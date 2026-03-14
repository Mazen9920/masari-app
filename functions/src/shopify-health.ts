/**
 * Shopify Health Check — Scheduled Cloud Function
 *
 * Runs daily to verify all active Shopify connections are still valid.
 * Calls Shopify's shop.json endpoint for each active connection.
 * Marks connections as disconnected on 401/403 responses.
 */

import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineSecret} from "firebase-functions/params";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {
  createDecipheriv,
} from "crypto";

const tokenEncryptionKey = defineSecret("SHOPIFY_TOKEN_ENCRYPTION_KEY");

const SHOPIFY_API_VERSION = "2024-01";

const WEBHOOK_URL =
  "https://shopifywebhook-colliwyzpa-uc.a.run.app";

const REQUIRED_WEBHOOK_TOPICS = [
  "orders/create",
  "orders/updated",
  "orders/cancelled",
  "products/update",
  "products/create",
  "inventory_levels/update",
  "app/uninstalled",
];

/**
 * Lazy Firestore accessor.
 * @return {FirebaseFirestore.Firestore} The Firestore instance.
 */
function getDb() {
  return getFirestore();
}

/**
 * Decrypts a token previously encrypted with AES-256-GCM.
 * @param {string} encryptedStr  The encrypted payload ("iv:tag:data").
 * @param {string} key  32-byte hex key.
 * @return {string} The decrypted plaintext.
 */
function decrypt(encryptedStr: string, key: string): string {
  const [ivB64, tagB64, dataB64] = encryptedStr.split(":");
  const keyBuf = Buffer.from(key, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const decipher = createDecipheriv("aes-256-gcm", keyBuf, iv);
  decipher.setAuthTag(tag);
  return decipher.update(data).toString("utf8") + decipher.final("utf8");
}

/**
 * Ensures all required webhook topics are registered for a Shopify store.
 * Fetches existing webhooks, compares against REQUIRED_WEBHOOK_TOPICS,
 * and registers any missing ones.
 */
async function reconcileWebhooks(
  shopDomain: string,
  accessToken: string,
  doc: FirebaseFirestore.QueryDocumentSnapshot,
): Promise<void> {
  try {
    // Fetch existing webhooks from Shopify
    const listRes = await fetch(
      `https://${shopDomain}/admin/api/${SHOPIFY_API_VERSION}/webhooks.json`,
      {
        method: "GET",
        headers: {
          "Content-Type": "application/json",
          "X-Shopify-Access-Token": accessToken,
        },
      },
    );

    if (!listRes.ok) {
      logger.warn("Failed to list webhooks for reconciliation", {
        uid: doc.id,
        shopDomain,
        status: listRes.status,
      });
      return;
    }

    const body = (await listRes.json()) as {
      webhooks?: {id: number; topic: string; address: string}[];
    };
    const existing = body.webhooks ?? [];

    // Topics already registered pointing to our webhook URL
    const registeredTopics = new Set(
      existing
        .filter((w) => w.address === WEBHOOK_URL)
        .map((w) => w.topic),
    );

    const missing = REQUIRED_WEBHOOK_TOPICS.filter(
      (t) => !registeredTopics.has(t),
    );

    if (missing.length === 0) return;

    logger.info("Registering missing webhook topics", {
      uid: doc.id,
      shopDomain,
      missing,
    });

    const webhookIds: Record<string, string> =
      (doc.data().webhook_ids as Record<string, string>) ?? {};

    for (const topic of missing) {
      try {
        const whRes = await fetch(
          `https://${shopDomain}/admin/api/${SHOPIFY_API_VERSION}/webhooks.json`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "X-Shopify-Access-Token": accessToken,
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
          const whBody = (await whRes.json()) as {
            webhook: {id: number};
          };
          webhookIds[topic] = String(whBody.webhook.id);
          logger.info(`Webhook registered: ${topic}`, {
            uid: doc.id,
            id: whBody.webhook.id,
          });
        } else {
          const errText = await whRes.text();
          logger.warn(`Webhook registration failed: ${topic}`, {
            uid: doc.id,
            errText,
          });
        }
      } catch (whErr) {
        logger.warn(`Webhook error: ${topic}`, {uid: doc.id, whErr});
      }
    }

    // Persist updated webhook IDs
    await doc.ref.update({webhook_ids: webhookIds});
  } catch (err) {
    logger.error("Webhook reconciliation failed", {
      uid: doc.id,
      shopDomain,
      error: String(err),
    });
  }
}

export const shopifyHealthCheck = onSchedule(
  {
    schedule: "every day 06:00",
    timeZone: "UTC",
    secrets: [tokenEncryptionKey],
    region: "us-central1",
  },
  async () => {
    logger.info("Starting Shopify health check");

    // Find all active connections
    const snapshot = await getDb()
      .collection("shopify_connections")
      .where("status", "==", "active")
      .get();

    if (snapshot.empty) {
      logger.info("No active Shopify connections to check");
      return;
    }

    let healthy = 0;
    let unhealthy = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const shopDomain = data.shop_domain as string;
      const encryptedToken = data.access_token as string;

      if (!shopDomain || !encryptedToken) {
        logger.warn("Skipping connection missing domain/token", {
          uid: doc.id,
        });
        continue;
      }

      try {
        const accessToken = decrypt(
          encryptedToken,
          tokenEncryptionKey.value().trim()
        );

        const url =
          `https://${shopDomain}/admin/api/${SHOPIFY_API_VERSION}/shop.json`;

        const response = await fetch(url, {
          method: "GET",
          headers: {
            "Content-Type": "application/json",
            "X-Shopify-Access-Token": accessToken,
          },
        });

        if (response.status === 401 || response.status === 403) {
          // Token revoked or app uninstalled
          logger.warn("Shopify connection unhealthy — marking disconnected", {
            uid: doc.id,
            shopDomain,
            status: response.status,
          });

          await doc.ref.update({
            status: "disconnected",
            health_status: "unhealthy",
            health_check_at: FieldValue.serverTimestamp(),
            health_error:
              `HTTP ${response.status} — token revoked or app uninstalled`,
          });
          unhealthy++;
        } else if (response.ok) {
          // Connection is healthy — also ensure all webhooks are registered
          await reconcileWebhooks(shopDomain, accessToken, doc);

          await doc.ref.update({
            health_status: "healthy",
            health_check_at: FieldValue.serverTimestamp(),
            health_error: null,
          });
          healthy++;
        } else {
          // Unexpected status — log but don't disconnect
          logger.warn("Shopify health check unexpected status", {
            uid: doc.id,
            shopDomain,
            status: response.status,
          });

          await doc.ref.update({
            health_status: "degraded",
            health_check_at: FieldValue.serverTimestamp(),
            health_error: `HTTP ${response.status}`,
          });
        }
      } catch (err) {
        logger.error("Shopify health check error", {
          uid: doc.id,
          shopDomain,
          error: String(err),
        });

        await doc.ref.update({
          health_status: "degraded",
          health_check_at: FieldValue.serverTimestamp(),
          health_error: `Check failed: ${String(err)}`,
        });
      }
    }

    logger.info("Shopify health check complete", {
      total: snapshot.size,
      healthy,
      unhealthy,
    });
  }
);
