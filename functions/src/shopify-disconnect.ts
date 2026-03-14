/**
 * Shopify Disconnect — Cloud Function
 *
 * Called when a user disconnects their Shopify integration.
 * Unregisters all webhooks and clears the encrypted access token
 * from Firestore.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getFirestore, FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {createDecipheriv} from "crypto";

const tokenEncryptionKey = defineSecret("SHOPIFY_TOKEN_ENCRYPTION_KEY");

const SHOPIFY_API_VERSION = "2024-01";

/**
 * Lazy Firestore accessor.
 * @return {FirebaseFirestore.Firestore} The Firestore instance.
 */
function getDb() {
  return getFirestore();
}

/**
 * Decrypts a token previously encrypted with AES-256-GCM.
 * @param {string} encryptedStr  "iv:tag:ciphertext" (base64).
 * @param {string} key  32-byte hex key (64 chars).
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

export const shopifyDisconnect = onCall(
  {
    secrets: [tokenEncryptionKey],
    region: "us-central1",
    timeoutSeconds: 60,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const uid = request.auth.uid;

    const connDoc = await getDb()
      .collection("shopify_connections")
      .doc(uid)
      .get();

    if (!connDoc.exists) {
      throw new HttpsError(
        "not-found",
        "No Shopify connection found"
      );
    }

    const conn = connDoc.data();
    if (!conn) {
      throw new HttpsError(
        "not-found",
        "No Shopify connection data"
      );
    }

    const shopDomain = conn.shop_domain as string;
    const encryptedToken = conn.access_token as string | undefined;
    const webhookIds = conn.webhook_ids as
      Record<string, string> | undefined;

    // ── 1. Unregister webhooks ─────────────────────────────
    if (encryptedToken && webhookIds) {
      try {
        const accessToken = decrypt(
          encryptedToken,
          tokenEncryptionKey.value().trim()
        );

        const deletePromises = Object.entries(webhookIds).map(
          async ([topic, webhookId]) => {
            try {
              const url =
                `https://${shopDomain}/admin/api/` +
                `${SHOPIFY_API_VERSION}/webhooks/${webhookId}.json`;

              const res = await fetch(url, {
                method: "DELETE",
                headers: {
                  "X-Shopify-Access-Token": accessToken,
                },
              });

              if (res.ok || res.status === 404) {
                logger.info(`Webhook unregistered: ${topic}`, {
                  webhookId,
                });
              } else {
                logger.warn(
                  `Failed to unregister webhook: ${topic}`,
                  {webhookId, status: res.status}
                );
              }
            } catch (err) {
              logger.warn(`Error unregistering webhook: ${topic}`, {
                webhookId,
                error: String(err),
              });
            }
          }
        );

        await Promise.all(deletePromises);
      } catch (err) {
        logger.error("Failed to decrypt token for webhook cleanup", {
          uid,
          error: String(err),
        });
      }
    }

    // ── 2. Clear connection data in Firestore ──────────────
    await connDoc.ref.update({
      status: "disconnected",
      access_token: null,
      webhook_ids: null,
      setup_completed: false,
      disconnected_at: FieldValue.serverTimestamp(),
      updated_at: FieldValue.serverTimestamp(),
    });

    logger.info("Shopify disconnected", {uid, shopDomain});

    return {success: true, message: "Shopify integration disconnected"};
  }
);
