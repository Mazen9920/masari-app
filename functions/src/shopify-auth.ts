/**
 * Shopify OAuth Flow — Cloud Functions
 *
 * shopifyAuthStart  — onCall: app sends userId + shopDomain, returns OAuth URL.
 * shopifyAuthCallback — onRequest: Shopify redirects here after user approves.
 *   Validates HMAC + nonce, exchanges code for token, encrypts token,
 *   stores connection, registers webhooks.
 */

import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {
  randomBytes,
  createCipheriv,
  createDecipheriv,
  createHmac,
  timingSafeEqual,
} from "crypto";

// ── Secrets (Firebase Secret Manager) ──────────────────────

const shopifyApiKey = defineSecret("SHOPIFY_API_KEY");
const shopifyApiSecret = defineSecret("SHOPIFY_API_SECRET");

/**
 * 32-byte hex key (64 hex chars) used for AES-256-GCM encryption of
 * the Shopify access token at rest.
 */
const tokenEncryptionKey = defineSecret("SHOPIFY_TOKEN_ENCRYPTION_KEY");

// ── Constants ──────────────────────────────────────────────

/**
 * Lazy Firestore accessor — avoids calling getFirestore() at import time.
 * @return {FirebaseFirestore.Firestore} The Firestore instance.
 */
function getDb() {
  return getFirestore();
}

const SHOPIFY_API_VERSION = "2024-01";

const SHOPIFY_SCOPES = [
  "read_orders",
  "write_orders",
  "read_products",
  "write_products",
  "read_inventory",
  "write_inventory",
  "read_locations",
].join(",");

const WEBHOOK_TOPICS = [
  "orders/create",
  "orders/updated",
  "orders/cancelled",
  "products/update",
  "products/create",
  "inventory_levels/update",
  "app/uninstalled",
];

/** Gen 2 Cloud Run URLs for onRequest functions. */
const CALLBACK_URL =
  "https://shopifyauthcallback-colliwyzpa-uc.a.run.app";
const WEBHOOK_URL =
  "https://shopifywebhook-colliwyzpa-uc.a.run.app";

// ── Encryption helpers ─────────────────────────────────────

/**
 * Encrypts `text` with AES-256-GCM.
 * @param {string} text  The plaintext (Shopify access token).
 * @param {string} key   A 32-byte hex key (64 chars).
 * @return {string} "iv:tag:ciphertext" (base-64 segments).
 */
export function encrypt(text: string, key: string): string {
  const keyBuf = Buffer.from(key, "hex");
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", keyBuf, iv);
  const encrypted = Buffer.concat([
    cipher.update(text, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return [
    iv.toString("base64"),
    tag.toString("base64"),
    encrypted.toString("base64"),
  ].join(":");
}

/**
 * Decrypts a string previously produced by {@link encrypt}.
 * @param {string} encryptedStr  The encrypted payload.
 * @param {string} key  The same 32-byte hex key used to encrypt.
 * @return {string} The original plaintext.
 */
export function decrypt(encryptedStr: string, key: string): string {
  const [ivB64, tagB64, dataB64] = encryptedStr.split(":");
  const keyBuf = Buffer.from(key, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const decipher = createDecipheriv("aes-256-gcm", keyBuf, iv);
  decipher.setAuthTag(tag);
  return decipher.update(data).toString("utf8") + decipher.final("utf8");
}

// ── HMAC verification ──────────────────────────────────────

/**
 * Verifies the `hmac` query-string parameter that Shopify
 * appends to the OAuth callback URL.
 * @param {Record<string, string>} query  Callback params.
 * @param {string} secret  Shopify API secret.
 * @return {boolean} Whether the HMAC is valid.
 */
function verifyShopifyHmac(
  query: Record<string, string>,
  secret: string,
): boolean {
  const hmac = query["hmac"];
  if (!hmac) return false;

  // Rebuild message from every param except `hmac` itself
  const message = Object.keys(query)
    .filter((k) => k !== "hmac")
    .sort()
    .map((k) => `${k}=${query[k]}`)
    .join("&");

  const computed = createHmac("sha256", secret)
    .update(message)
    .digest("hex");

  // Constant-time comparison
  return timingSafeEqual(
    Buffer.from(computed, "utf8"),
    Buffer.from(hmac, "utf8"),
  );
}

// ═══════════════════════════════════════════════════════════
// shopifyAuthStart — called by the Flutter app (onCall)
// ═══════════════════════════════════════════════════════════

export const shopifyAuthStart = onCall(
  {
    secrets: [shopifyApiKey],
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }

    const uid = request.auth.uid;

    // ── Tier check ─────────────────────────────────────────
    const userDoc = await getDb()
      .collection("users")
      .doc(uid)
      .get();
    const userTier = userDoc.data()?.subscription_tier as string | undefined;
    if (userTier !== "growth" && userTier !== "growthShopify" && userTier !== "pro") {
      throw new HttpsError(
        "permission-denied",
        "Shopify integration requires Growth plan or higher"
      );
    }

    const {shopDomain} = request.data as {shopDomain: string};

    if (!shopDomain || !shopDomain.includes(".myshopify.com")) {
      throw new HttpsError(
        "invalid-argument",
        "shopDomain must be a valid *.myshopify.com domain",
      );
    }

    // Cryptographic nonce for CSRF protection
    const nonce = randomBytes(24).toString("hex");

    // Store pending connection with nonce.
    // The state param sent to Shopify encodes userId + nonce so the
    // callback can do a direct doc lookup instead of a query.
    await getDb().collection("shopify_connections").doc(uid).set(
      {
        user_id: uid,
        shop_domain: shopDomain,
        nonce: nonce,
        status: "pending",
        created_at: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    const state = `${uid}:${nonce}`;
    const callbackUrl = CALLBACK_URL;

    const apiKey = shopifyApiKey.value().trim();
    if (!apiKey) {
      logger.error("SHOPIFY_API_KEY secret is missing/empty");
      throw new HttpsError(
        "failed-precondition",
        "Server is missing SHOPIFY_API_KEY secret",
      );
    }

    const oauthUrl =
      `https://${shopDomain}/admin/oauth/authorize` +
      `?client_id=${apiKey}` +
      `&scope=${SHOPIFY_SCOPES}` +
      `&redirect_uri=${encodeURIComponent(callbackUrl)}` +
      `&state=${state}`;

    logger.info("Shopify OAuth started", {
      uid,
      shopDomain,
      callbackUrl,
      apiKeyPrefix: apiKey.slice(0, 8),
    });
    return {oauthUrl};
  },
);

// ═══════════════════════════════════════════════════════════
// shopifyAuthCallback — Shopify redirects here (onRequest)
// ═══════════════════════════════════════════════════════════

export const shopifyAuthCallback = onRequest(
  {
    secrets: [shopifyApiKey, shopifyApiSecret, tokenEncryptionKey],
    region: "us-central1",
  },
  async (req, res) => {
    try {
      const query = req.query as Record<string, string>;
      const {code, state, shop} = query;

      // ── App landing page (no OAuth params) ─────────────
      // When a merchant clicks the app in Shopify admin,
      // Shopify loads this URL without code/state. Show a
      // friendly landing page instead of an error.
      if (!code || !state) {
        res.status(200).send(`
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport"
        content="width=device-width, initial-scale=1">
  <title>Masari Inventory</title>
  <style>
    body {
      font-family: system-ui, -apple-system, sans-serif;
      text-align: center;
      padding: 60px 24px;
      background: #fafafa;
      color: #1a1a1a;
    }
    .card {
      max-width: 460px;
      margin: 0 auto;
      background: #fff;
      border-radius: 16px;
      box-shadow: 0 2px 12px rgba(0,0,0,.08);
      padding: 40px 32px;
    }
    .logo {
      font-size: 2.5rem;
      margin-bottom: 4px;
    }
    h1 { font-size: 1.4rem; margin-bottom: 12px; }
    p  { color: #555; line-height: 1.6; }
    .steps {
      text-align: left;
      margin: 20px 0;
      padding: 0 16px;
    }
    .steps li {
      margin-bottom: 10px;
      color: #444;
    }
    .badge {
      display: inline-block;
      background: #5C6BC0;
      color: #fff;
      border-radius: 8px;
      padding: 10px 24px;
      font-weight: 600;
      margin-top: 16px;
      text-decoration: none;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">\uD83D\uDCE6</div>
    <h1>Masari Inventory</h1>
    <p>Manage your Shopify integration directly
       from the <strong>Masari</strong> mobile app.</p>
    <ol class="steps">
      <li>Open the <strong>Masari</strong> app on
          your phone</li>
      <li>Go to <strong>Manage &rarr;
          Shopify Integration</strong></li>
      <li>Tap <strong>Connect Store</strong> and
          follow the prompts</li>
    </ol>
    <p style="color:#888; font-size:0.9rem;">
      Your store is linked and syncing
      automatically once connected.</p>

    <a class="badge" href="masari://app">Open Masari</a>
  </div>
</body>
</html>
        `);
        return;
      }

      if (!shop) {
        res.status(400).send("Missing shop parameter");
        return;
      }

      // ── 1. Verify HMAC (prevents parameter tampering) ────
      const apiSecret = shopifyApiSecret.value().trim();
      if (!apiSecret) {
        logger.error("SHOPIFY_API_SECRET secret is missing/empty");
        res.status(500).send("Server misconfigured");
        return;
      }

      if (!verifyShopifyHmac(query, apiSecret)) {
        logger.warn("HMAC verification failed", {shop});
        res.status(403).send("HMAC verification failed");
        return;
      }

      // ── 2. Validate nonce ────────────────────────────────
      // State format: "userId:nonce"
      const sepIdx = state.indexOf(":");
      if (sepIdx < 1) {
        res.status(400).send("Invalid state parameter");
        return;
      }
      const userId = state.substring(0, sepIdx);
      const nonce = state.substring(sepIdx + 1);

      const docRef = getDb().collection("shopify_connections").doc(userId);
      const docSnap = await docRef.get();

      if (
        !docSnap.exists ||
        docSnap.data()?.nonce !== nonce ||
        docSnap.data()?.status !== "pending"
      ) {
        res.status(403).send("Invalid or expired nonce");
        return;
      }

      // Verify shop matches what the user initiated
      if (docSnap.data()?.shop_domain !== shop) {
        res.status(403).send("Shop domain mismatch");
        return;
      }

      // ── 3. Exchange code for permanent access token ──────
      const tokenResponse = await fetch(
        `https://${shop}/admin/oauth/access_token`,
        {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify({
            client_id: shopifyApiKey.value().trim(),
            client_secret: apiSecret,
            code,
          }),
        },
      );

      if (!tokenResponse.ok) {
        const errBody = await tokenResponse.text();
        logger.error("Token exchange failed", {
          status: tokenResponse.status, errBody,
        });
        res.status(502).send("Failed to exchange authorization code");
        return;
      }

      const tokenData = (await tokenResponse.json()) as {
        access_token: string;
        scope: string;
      };

      // ── 4. Encrypt the access token ──────────────────────
      const encryptedToken = encrypt(
        tokenData.access_token,
        tokenEncryptionKey.value().trim(),
      );

      // ── 5. Register Shopify webhooks ─────────────────────
      const webhookIds: Record<string, string> = {};
      for (const topic of WEBHOOK_TOPICS) {
        try {
          const whRes = await fetch(
            `https://${shop}/admin/api/${SHOPIFY_API_VERSION}/webhooks.json`,
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                "X-Shopify-Access-Token": tokenData.access_token,
              },
              body: JSON.stringify({
                webhook: {
                  topic,
                  address: WEBHOOK_URL,
                  format: "json",
                },
              }),
            },
          );

          if (whRes.ok) {
            const body = (await whRes.json()) as {
              webhook: {id: number};
            };
            webhookIds[topic] = String(body.webhook.id);
            logger.info(`Webhook registered: ${topic}`, {id: body.webhook.id});
          } else {
            const errText = await whRes.text();
            logger.warn(`Webhook registration failed: ${topic}`, {errText});
          }
        } catch (whErr) {
          logger.warn(`Webhook error: ${topic}`, {whErr});
        }
      }

      // ── 6. Save complete connection ──────────────────────
      // Full .set() (no merge) — replaces the pending doc entirely,
      // which also removes the temporary `nonce` field.
      await docRef.set({
        user_id: userId,
        shop_domain: shop,
        access_token: encryptedToken,
        scopes: tokenData.scope.split(","),
        sync_orders_enabled: true,
        sync_inventory_enabled: false,
        inventory_sync_direction: null,
        last_order_sync_at: null,
        last_inventory_sync_at: null,
        webhook_ids: webhookIds,
        import_from_date: null,
        connected_at: FieldValue.serverTimestamp(),
        status: "active",
        updated_at: FieldValue.serverTimestamp(),
      });

      logger.info("Shopify OAuth completed", {
        userId,
        shop,
        webhooks: Object.keys(webhookIds).length,
      });

      // ── 7. Return a success page the user can close ──────
      res.status(200).send(`
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Masari — Shopify Connected</title>
  <style>
    body {
      font-family: system-ui, -apple-system, sans-serif;
      text-align: center;
      padding: 80px 24px;
      background: #fafafa;
      color: #1a1a1a;
    }
    .card {
      max-width: 420px;
      margin: 0 auto;
      background: #fff;
      border-radius: 16px;
      box-shadow: 0 2px 12px rgba(0,0,0,.08);
      padding: 40px 32px;
    }
    h1 { font-size: 1.5rem; margin-bottom: 8px; }
    p  { color: #555; line-height: 1.5; }
  </style>
</head>
<body>
  <div class="card">
    <h1>&#9989; Shopify Connected!</h1>
    <p>Your store <strong>${shop}</strong> has been linked to Masari.</p>
    <p>You can close this window and return to the app.</p>
    <p style="margin-top: 18px;">
      <a class="badge" href="masari://app">Open Masari</a>
    </p>
  </div>
</body>
</html>
      `);
    } catch (error) {
      logger.error("shopifyAuthCallback error", {error});
      res.status(500).send("Internal server error");
    }
  },
);

// Re-export constants/helpers for use by future Cloud Functions
// (e.g., webhook handler, sync engine).
export {SHOPIFY_API_VERSION, tokenEncryptionKey};
