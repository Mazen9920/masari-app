/**
 * Shopify Webhook Receiver — Cloud Function
 *
 * Single HTTPS endpoint that receives ALL Shopify webhook POSTs.
 * Validates HMAC, identifies the owning user, and queues the payload
 * to `shopify_webhook_queue` for async processing.
 *
 * Design: respond 200 as fast as possible (Shopify requires &lt; 5 s).
 */

import {onRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getFirestore, FieldValue, QuerySnapshot} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {createHmac, timingSafeEqual} from "crypto";

// ── Secrets ────────────────────────────────────────────────

const shopifyApiSecret = defineSecret("SHOPIFY_API_SECRET");

// ── Helpers ────────────────────────────────────────────────

/**
 * Lazy Firestore accessor.
 * @return {FirebaseFirestore.Firestore} Firestore instance.
 */
function getDb() {
  return getFirestore();
}

/**
 * Verifies the X-Shopify-Hmac-Sha256 header against the raw
 * request body using the Shopify API secret.
 * @param {Buffer} rawBody  The raw request body bytes.
 * @param {string} hmacHeader  Value of X-Shopify-Hmac-Sha256.
 * @param {string} secret  The Shopify API secret.
 * @return {boolean} Whether the HMAC is valid.
 */
function verifyWebhookHmac(
  rawBody: Buffer,
  hmacHeader: string,
  secret: string,
): boolean {
  const computed = createHmac("sha256", secret)
    .update(rawBody)
    .digest("base64");
  try {
    return timingSafeEqual(
      Buffer.from(computed, "utf8"),
      Buffer.from(hmacHeader, "utf8"),
    );
  } catch {
    return false; // length mismatch
  }
}

// ═══════════════════════════════════════════════════════════
// shopifyWebhook — receives all Shopify webhook POSTs
// ═══════════════════════════════════════════════════════════

export const storeWebhook = onRequest(
  {
    secrets: [shopifyApiSecret],
    region: "us-central1",
  },
  async (req, res) => {
    // Only POST is valid
    if (req.method !== "POST") {
      res.status(405).send("Method not allowed");
      return;
    }

    const hmacHeader = req.headers[
      "x-shopify-hmac-sha256"
    ] as string | undefined;
    const topic = req.headers[
      "x-shopify-topic"
    ] as string | undefined;
    const shopDomain = req.headers[
      "x-shopify-shop-domain"
    ] as string | undefined;
    const webhookId = req.headers[
      "x-shopify-webhook-id"
    ] as string | undefined;

    if (!hmacHeader || !topic || !shopDomain) {
      res.status(400).send("Missing Shopify headers");
      return;
    }

    // ── 1. Validate HMAC ──────────────────────────────────
    const rawBody = (req as unknown as {rawBody: Buffer}).rawBody;
    if (
      !rawBody ||
      !verifyWebhookHmac(rawBody, hmacHeader, shopifyApiSecret.value().trim())
    ) {
      logger.warn("Webhook HMAC invalid", {topic, shopDomain});
      res.status(401).send("HMAC verification failed");
      return;
    }

    // ── 2. Look up ALL users that own this shop ──────────
    const db = getDb();

    // Compliance webhooks (shop/redact, customers/*) may arrive after
    // the app was uninstalled, so we must also find disconnected
    // connections; other topics still require an active connection.
    const complianceTopics = new Set([
      "customers/data_request",
      "customers/redact",
      "shop/redact",
    ]);
    const isCompliance = complianceTopics.has(topic);

    let connSnap: QuerySnapshot;
    if (isCompliance) {
      connSnap = await db
        .collection("shopify_connections")
        .where("shop_domain", "==", shopDomain)
        .get();
    } else {
      connSnap = await db
        .collection("shopify_connections")
        .where("shop_domain", "==", shopDomain)
        .where("status", "==", "active")
        .get();
    }

    if (connSnap.empty) {
      // No connection for this shop — 200 to stop retries
      if (isCompliance) {
        logger.info("Compliance webhook for unknown shop — acknowledged", {
          shopDomain, topic,
        });
      } else {
        logger.warn("No active connection for shop", {shopDomain, topic});
      }
      res.status(200).send("OK");
      return;
    }

    if (connSnap.size > 1) {
      logger.warn("Multiple users connected to same shop", {
        shopDomain,
        topic,
        userCount: connSnap.size,
        userIds: connSnap.docs.map((d) => d.data().user_id),
      });
    }

    // ── 3. Queue the webhook payload ──────────────────────
    let payload: Record<string, unknown>;
    try {
      payload = typeof req.body === "string" ?
        JSON.parse(req.body) :
        req.body;
    } catch {
      logger.error("Invalid JSON body", {topic, shopDomain});
      res.status(400).send("Invalid JSON");
      return;
    }

    // Queue webhook for EVERY user that owns this shop.
    // Uses Shopify's webhook ID + userId as doc ID to prevent
    // duplicates from retries while ensuring each user gets a copy.
    const batch = db.batch();
    for (const doc of connSnap.docs) {
      const userId = doc.data().user_id as string;
      const queueDocId = webhookId ?
        `wh_${webhookId}_${userId}` :
        undefined;
      const queueRef = queueDocId ?
        db.collection("shopify_webhook_queue").doc(queueDocId) :
        db.collection("shopify_webhook_queue").doc();

      batch.set(queueRef, {
        user_id: userId,
        topic: topic,
        shop_domain: shopDomain,
        payload: payload,
        processed_at: null,
        created_at: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    // ── 4. Respond 200 immediately ────────────────────────
    const userIds = connSnap.docs.map((d) => d.data().user_id);
    logger.info("Webhook queued", {userIds, topic, shopDomain});
    res.status(200).send("OK");
  },
);
