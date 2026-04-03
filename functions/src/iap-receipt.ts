/**
 * verifyIapReceipt — callable Cloud Function
 *
 * Validates an Apple App Store or Google Play purchase receipt and activates
 * the user's subscription in Firestore.
 *
 * The Flutter app calls this after a successful in_app_purchase transaction.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import * as crypto from "crypto";

const db = () => getFirestore();

// ── Product ID → plan mapping ───────────────────────────────────────────────
const PRODUCT_PLAN_MAP: Record<string, {plan: string; tier: string; durationDays: number}> = {
  revvo_growth_monthly: {plan: "growth_monthly", tier: "growth", durationDays: 30},
  revvo_growth_yearly: {plan: "growth_yearly", tier: "growth", durationDays: 365},
};

export const verifyIapReceipt = onCall(
  {
    region: "us-central1",
    maxInstances: 20,
    invoker: "public",
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;

    const platform = request.data?.platform as string | undefined;
    const productId = request.data?.product_id as string | undefined;
    const purchaseToken = request.data?.purchase_token as string | undefined;
    const transactionId = request.data?.transaction_id as string | undefined;

    if (!platform || !productId || !purchaseToken) {
      throw new HttpsError(
        "invalid-argument",
        "Missing required fields: platform, product_id, purchase_token"
      );
    }

    const productInfo = PRODUCT_PLAN_MAP[productId];
    if (!productInfo) {
      throw new HttpsError(
        "invalid-argument",
        `Unknown product: ${productId}`
      );
    }

    // ── Verify receipt with the respective store ──────────────────────
    let verified = false;
    let storeData: Record<string, unknown> = {};

    if (platform === "ios") {
      const result = await verifyAppleReceipt(purchaseToken, productId);
      verified = result.verified;
      storeData = result.data;
    } else if (platform === "android") {
      const result = await verifyGoogleReceipt(purchaseToken, productId);
      verified = result.verified;
      storeData = result.data;
    } else {
      throw new HttpsError("invalid-argument", `Unsupported platform: ${platform}`);
    }

    // ── Log the IAP attempt ──────────────────────────────────────────
    await db().collection("payment_logs").add({
      user_id: uid,
      plan: productInfo.plan,
      platform,
      product_id: productId,
      transaction_id: transactionId ?? null,
      success: verified,
      source: "iap",
      store_data: storeData,
      created_at: FieldValue.serverTimestamp(),
    });

    if (!verified) {
      logger.warn("verifyIapReceipt: verification failed", {uid, platform, productId});
      throw new HttpsError("permission-denied", "Receipt verification failed");
    }

    // ── Idempotency: skip if this receipt was already processed ──────
    if (transactionId) {
      const dup = await db().collection("payment_logs")
        .where("transaction_id", "==", transactionId)
        .where("success", "==", true)
        .limit(2)
        .get();
      if (dup.size > 1) {
        logger.warn("verifyIapReceipt: duplicate receipt — returning current status", {transactionId});
        const userSnap = await db().collection("users").doc(uid).get();
        const userData = userSnap.data();
        return {
          status: userData?.subscription_status ?? "active",
          tier: userData?.subscription_tier ?? productInfo.tier,
          plan: userData?.subscription_plan ?? productInfo.plan,
          expires_at: (userData?.subscription_expires_at as Timestamp)?.toMillis() ?? Date.now(),
        };
      }
    }

    // ── Activate subscription ────────────────────────────────────────
    // If user already has an active subscription, extend from current expiry.
    const userDoc = await db().collection("users").doc(uid).get();
    let baseDate = new Date();
    if (userDoc.exists) {
      const data = userDoc.data()!;
      const currentExpiry = data.subscription_expires_at as Timestamp | undefined;
      if (
        currentExpiry &&
        data.subscription_status === "active" &&
        currentExpiry.toDate() > baseDate
      ) {
        baseDate = currentExpiry.toDate();
      }
    }

    const expiresAt = new Date(baseDate);
    expiresAt.setDate(expiresAt.getDate() + productInfo.durationDays);

    await db()
      .collection("users")
      .doc(uid)
      .set(
        {
          subscription_tier: productInfo.tier,
          subscription_status: "active",
          subscription_plan: productInfo.plan,
          subscription_expires_at: Timestamp.fromDate(expiresAt),
          last_payment_at: FieldValue.serverTimestamp(),
          last_iap_platform: platform,
          last_iap_transaction_id: transactionId ?? null,
          payment_source: "iap",
        },
        {merge: true}
      );

    logger.info("verifyIapReceipt: subscription activated", {
      uid,
      platform,
      tier: productInfo.tier,
      plan: productInfo.plan,
      expiresAt: expiresAt.toISOString(),
    });

    return {
      status: "active",
      tier: productInfo.tier,
      plan: productInfo.plan,
      expires_at: expiresAt.getTime(),
    };
  }
);

// ────────────────────────────────────────────────────────────────────────────
// Apple JWS cryptographic verification
// ────────────────────────────────────────────────────────────────────────────

/**
 * Cryptographically verifies an Apple StoreKit 2 JWS (signed transaction).
 *
 * 1. Extracts the x5c certificate chain from the JWS header.
 * 2. Verifies each certificate is signed by the next in the chain.
 * 3. Verifies the root certificate is self-signed and issued by Apple Inc.
 * 4. Verifies the JWS signature using the leaf certificate's public key.
 */
function verifyAppleJws(
  jwsString: string
): {verified: boolean; payload?: Record<string, unknown>; reason?: string} {
  try {
    const parts = jwsString.split(".");
    if (parts.length !== 3) {
      return {verified: false, reason: "not_jws_format"};
    }

    // Decode JWS header
    const headerB64 = parts[0].replace(/-/g, "+").replace(/_/g, "/");
    const header = JSON.parse(Buffer.from(headerB64, "base64").toString("utf-8"));

    const alg = header.alg as string;
    const x5c = header.x5c as string[] | undefined;

    if (!x5c || x5c.length < 2) {
      return {verified: false, reason: "missing_x5c_chain"};
    }

    // Build X509Certificate objects from the DER-encoded chain
    const certs = x5c.map((certB64) => {
      const pem =
        `-----BEGIN CERTIFICATE-----\n${certB64}\n-----END CERTIFICATE-----`;
      return new crypto.X509Certificate(pem);
    });

    // Verify chain: each certificate must be signed by the next one's key
    for (let i = 0; i < certs.length - 1; i++) {
      if (!certs[i].verify(certs[i + 1].publicKey)) {
        return {verified: false, reason: `chain_break_at_${i}`};
      }
    }

    // Root must be self-signed
    const rootCert = certs[certs.length - 1];
    if (!rootCert.verify(rootCert.publicKey)) {
      return {verified: false, reason: "root_not_self_signed"};
    }

    // Verify root certificate is Apple's Root CA G3 by SHA-256 fingerprint.
    // Obtained from: https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
    const APPLE_ROOT_CA_G3_FP =
      "63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79";
    if (rootCert.fingerprint256 !== APPLE_ROOT_CA_G3_FP) {
      logger.warn("Apple JWS: root cert fingerprint mismatch", {
        got: rootCert.fingerprint256,
      });
      return {verified: false, reason: "root_not_apple_pinned"};
    }

    // Verify JWS signature using the leaf certificate's public key
    const signingInput = `${parts[0]}.${parts[1]}`;
    const signatureB64url = parts[2];
    const signature = Buffer.from(
      signatureB64url.replace(/-/g, "+").replace(/_/g, "/"),
      "base64"
    );

    // Map JWS algorithm to Node.js hash
    const hashAlg = alg === "ES256" ? "SHA256" : "SHA384";
    const verifier = crypto.createVerify(hashAlg);
    verifier.update(signingInput);

    // JWS uses IEEE P1363 (raw R||S) encoding for ECDSA signatures
    const sigValid = verifier.verify(
      {key: certs[0].publicKey, dsaEncoding: "ieee-p1363"},
      signature
    );

    if (!sigValid) {
      return {verified: false, reason: "signature_invalid"};
    }

    // Decode payload
    const payloadB64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(Buffer.from(payloadB64, "base64").toString("utf-8"));

    return {verified: true, payload};
  } catch (err) {
    logger.error("verifyAppleJws error", err);
    return {verified: false, reason: `error: ${String(err)}`};
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Apple receipt verification
// ────────────────────────────────────────────────────────────────────────────

/**
 * Verifies an Apple App Store receipt.
 *
 * With StoreKit 2, the `purchaseToken` is a JWS (signed transaction).
 * We cryptographically verify the JWS signature against Apple's certificate
 * chain embedded in the x5c header, ensuring the chain roots to Apple Inc.
 *
 * For StoreKit 1, we use Apple's verifyReceipt endpoint (legacy path).
 */
async function verifyAppleReceipt(
  receiptData: string,
  expectedProductId: string
): Promise<{verified: boolean; data: Record<string, unknown>}> {
  try {
    // StoreKit 2: receiptData is a JWS (header.payload.signature)
    const parts = receiptData.split(".");
    if (parts.length === 3) {
      // Attempt cryptographic JWS verification
      const jwsResult = verifyAppleJws(receiptData);
      if (!jwsResult.verified || !jwsResult.payload) {
        logger.warn("Apple JWS verification failed", {reason: jwsResult.reason});
        return {verified: false, data: {reason: jwsResult.reason ?? "jws_verification_failed"}};
      }

      const payload = jwsResult.payload;
      const productId = payload.productId ?? payload.product_id;
      const expiresDate = payload.expiresDate ?? payload.expires_date_ms;

      if (productId !== expectedProductId) {
        logger.warn("Apple receipt: product mismatch", {
          expected: expectedProductId,
          got: productId,
        });
        return {verified: false, data: {reason: "product_mismatch"}};
      }

      return {
        verified: true,
        data: {
          product_id: productId,
          transaction_id: payload.transactionId ?? payload.original_transaction_id,
          expires_date: expiresDate,
          environment: payload.environment,
        },
      };
    }

    // Legacy StoreKit 1: receiptData is base64-encoded receipt
    // Validate with Apple's verifyReceipt endpoint
    const verifyUrl = "https://buy.itunes.apple.com/verifyReceipt";
    const response = await fetch(verifyUrl, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({"receipt-data": receiptData}),
    });
    const result = await response.json() as Record<string, unknown>;

    // Status 0 = valid receipt
    if (result.status === 0) {
      return {verified: true, data: result};
    }

    // Status 21007 = sandbox receipt sent to production — retry with sandbox
    if (result.status === 21007) {
      const sandboxUrl = "https://sandbox.itunes.apple.com/verifyReceipt";
      const sandboxRes = await fetch(sandboxUrl, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({"receipt-data": receiptData}),
      });
      const sandboxResult = await sandboxRes.json() as Record<string, unknown>;
      return {
        verified: sandboxResult.status === 0,
        data: sandboxResult,
      };
    }

    return {verified: false, data: result};
  } catch (err) {
    logger.error("Apple receipt verification error", err);
    return {verified: false, data: {error: String(err)}};
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Google Play receipt verification
// ────────────────────────────────────────────────────────────────────────────

/**
 * Verifies a Google Play purchase.
 *
 * Uses the Google Play Developer API via the Firebase service account
 * (which has androidpublisher access if configured in Google Cloud Console).
 *
 * The `purchaseToken` is the token from Google Play Billing.
 */
async function verifyGoogleReceipt(
  purchaseToken: string,
  productId: string
): Promise<{verified: boolean; data: Record<string, unknown>}> {
  try {
    // Use Google Auth Library to get an access token from the default service account
    const {GoogleAuth} = await import("google-auth-library");
    const auth = new GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/androidpublisher"],
    });
    const client = await auth.getClient();
    const accessToken = (await client.getAccessToken()).token;

    if (!accessToken) {
      logger.error("Google receipt: could not obtain access token — rejecting");
      return {
        verified: false,
        data: {reason: "service_account_not_configured"},
      };
    }

    // Android package name — must match your app's applicationId
    const packageName = "com.revvo.app";
    const url =
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/subscriptions/${productId}/tokens/${purchaseToken}`;

    const response = await fetch(url, {
      headers: {Authorization: `Bearer ${accessToken}`},
    });
    const result = await response.json() as Record<string, unknown>;

    if (response.ok) {
      // Check payment state: 0 = pending, 1 = received, 2 = free trial, 3 = deferred
      const paymentState = result.paymentState as number | undefined;
      const verified = paymentState === 1 || paymentState === 2;
      return {verified, data: result};
    }

    logger.warn("Google receipt verification failed", {status: response.status, result});
    return {verified: false, data: result};
  } catch (err) {
    logger.error("Google receipt verification error", err);
    return {
      verified: false,
      data: {error: String(err)},
    };
  }
}
