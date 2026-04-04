/**
 * Revvo Billing — Paymob webhook + subscription validation
 *
 * Uses Paymob's built-in Subscription Module for recurring billing.
 * Paymob handles card tokenization, auto-deductions, retries, and reminders.
 *
 * Exports:
 *  - paymobWebhook        (onRequest)  — POST endpoint for Paymob payment callbacks
 *  - validateSubscriptions (onSchedule) — daily 03:00 UTC, expires lapsed subscriptions
 *  - getSubscriptionStatus (onCall)     — app calls to refresh subscription state
 *  - cancelSubscription    (onCall)     — voluntary downgrade (not Paymob cancel)
 *  - sendPreExpiryReminders(onSchedule) — 3d/1d pre-expiry notifications
 *  - toggleAutoRenew       (onCall)     — enable/disable auto-renew in our DB
 *  - removePaymentMethod   (onCall)     — removes saved card info from our DB
 */

import {onRequest} from "firebase-functions/v2/https";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, FieldValue, Timestamp} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";
import * as crypto from "crypto";
import * as logger from "firebase-functions/logger";
import {notifyUser} from "./notify.js";

const db = () => getFirestore();

// ── Paymob secrets ───────────────────────────────────────────────────────────
const paymobHmacSecret = defineSecret("PAYMOB_HMAC_SECRET");
const paymobSecretKey = defineSecret("PAYMOB_SECRET_KEY");
const paymobApiKey = defineSecret("PAYMOB_API_KEY");

// ── Plan durations in days ──────────────────────────────────────────────────
const PLAN_DURATION_DAYS: Record<string, number> = {
  growth_monthly: 30,
  growth_yearly: 365,
  pro_monthly: 30,
  pro_yearly: 365,
};

// ── Grace period before downgrade (days) ────────────────────────────────────
const GRACE_PERIOD_DAYS = 3;

// ── Subscription status constants ───────────────────────────────────────────
type SubscriptionStatus = "active" | "grace_period" | "expired" | "free";

// ────────────────────────────────────────────────────────────────────────────
// 1. Paymob Webhook — receives POST from Paymob after payment attempt
// ────────────────────────────────────────────────────────────────────────────

/**
 * Paymob HMAC transaction callback fields (sorted alphabetically).
 * See: https://docs.paymob.com/docs/transaction-callbacks
 */
const HMAC_FIELDS = [
  "amount_cents",
  "created_at",
  "currency",
  "error_occured",
  "has_parent_transaction",
  "id",
  "integration_id",
  "is_3d_secure",
  "is_auth",
  "is_capture",
  "is_refunded",
  "is_standalone_payment",
  "is_voided",
  "order.id",
  "owner",
  "pending",
  "source_data.pan",
  "source_data.sub_type",
  "source_data.type",
  "success",
];

/** Resolve a dotted field path on an object (e.g. "order.id"). */
function resolveField(obj: Record<string, unknown>, key: string): unknown {
  const parts = key.split(".");
  let val: unknown = obj;
  for (const p of parts) {
    val = (val as Record<string, unknown>)?.[p];
  }
  return val;
}

/**
 * Stringify a value the way Paymob's Python backend does: str(value).
 * Python: str(True)="True", str(False)="False", str(None)="None", str(50)="50".
 */
function pyStr(val: unknown): string {
  if (val === true) return "True";
  if (val === false) return "False";
  if (val === null || val === undefined) return "";
  return String(val);
}

/**
 * Compute HMAC-SHA512 for Paymob transaction callback using Python-style
 * boolean stringification (True/False) which matches Paymob's backend.
 */
function computePaymobHmac(
  obj: Record<string, unknown>,
  secret: string
): string {
  const concatenated = HMAC_FIELDS
    .map((key) => pyStr(resolveField(obj, key)))
    .join("");
  return crypto
    .createHmac("sha512", secret)
    .update(concatenated)
    .digest("hex");
}

/**
 * Fallback: compute HMAC with lowercase booleans (true/false) for backward
 * compatibility with older Paymob Accept API responses.
 */
function computePaymobHmacLower(
  obj: Record<string, unknown>,
  secret: string
): string {
  const concatenated = HMAC_FIELDS
    .map((key) => String(resolveField(obj, key) ?? ""))
    .join("");
  return crypto
    .createHmac("sha512", secret)
    .update(concatenated)
    .digest("hex");
}

export const paymobWebhook = onRequest(
  {
    region: "us-central1",
    maxInstances: 10,
    invoker: "public",
    secrets: [paymobHmacSecret, paymobSecretKey, paymobApiKey],
  },
  async (req, res) => {
    // Only accept POST
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    try {
      const body = req.body;

      // Debug: log top-level body keys and subscription-related fields
      logger.info("paymobWebhook: body keys", {
        keys: Object.keys(body).join(", "),
        hasObj: !!body.obj,
        hasTransaction: !!body.transaction,
        subscription_id: body.subscription_id ?? "none",
      });

      // ── Card/subscription data callback (separate payload format) ────
      // Paymob sends a second POST with {subscription_data, card_data,
      // transaction_id, trigger_type, hmac} after the main transaction.
      // Handle this BEFORE HMAC verification since the payload has no
      // transaction fields to verify against.
      const subscriptionData = body.subscription_data as Record<string, unknown> | undefined;
      const cardData = body.card_data as Record<string, unknown> | undefined;
      const callbackTxId = body.transaction_id as number | undefined;

      if ((subscriptionData || cardData) && !body.transaction && !body.obj) {
        logger.info("paymobWebhook: card/subscription data callback", {
          trigger_type: body.trigger_type ?? "none",
          transaction_id: callbackTxId ?? "none",
          subscription_data: subscriptionData ? JSON.stringify(subscriptionData).substring(0, 500) : "none",
          card_data: cardData ? JSON.stringify(cardData).substring(0, 500) : "none",
        });

        // Verify by matching transaction_id to an existing payment_log
        if (callbackTxId) {
          const txStr = String(callbackTxId);
          const logSnap = await db().collection("payment_logs")
            .where("paymob_transaction_id", "==", txStr)
            .where("success", "==", true)
            .limit(1)
            .get();

          if (!logSnap.empty) {
            const logDoc = logSnap.docs[0].data();
            const uid = logDoc.user_id as string;

            const updateFields: Record<string, unknown> = {};

            const subId = (subscriptionData as Record<string, unknown> | undefined)?.id as number | undefined;
            if (subId) {
              updateFields.paymob_subscription_id = subId;
              updateFields.paymob_subscription_state = (subscriptionData as Record<string, unknown>).state ?? "active";
              updateFields.paymob_auto_renew = true;
            }

            const token = (cardData as Record<string, unknown> | undefined)?.token as string | undefined;
            if (token) {
              updateFields.paymob_card_token_internal = token;
            }

            if (Object.keys(updateFields).length > 0) {
              await db().collection("users").doc(uid).set(updateFields, {merge: true});
              logger.info("paymobWebhook: saved subscription/card data", {
                uid,
                subscriptionId: subId ?? "none",
                hasCardToken: !!token,
              });
            }
          } else {
            logger.warn("paymobWebhook: card/sub callback — no matching payment_log", {
              transaction_id: callbackTxId,
            });
          }
        }

        res.status(200).send("OK — card/subscription data processed");
        return;
      }

      // ── Transaction callback handling ────────────────────────────────
      // Intention API sends {transaction: {...}, hmac: "..."} at top level.
      // Legacy Accept API sends {obj: {...}}.
      const obj = body.obj ?? body.transaction ?? body;

      // ── HMAC verification ────────────────────────────────────────────
      const receivedHmac =
        (req.query.hmac as string) ||
        (req.headers["hmac"] as string) ||
        (req.headers["x-paymob-hmac"] as string) ||
        (body.hmac as string);

      if (!receivedHmac) {
        logger.warn("paymobWebhook: missing HMAC");
        res.status(401).send("Missing HMAC");
        return;
      }

      const hmacSecret = paymobHmacSecret.value().trim();
      const received = String(receivedHmac);

      // ── Try multiple HMAC computation methods ────────────────────────
      // Paymob's Python backend uses str(True)="True", str(False)="False"
      // which differs from JavaScript's String(true)="true".
      let hmacValid = false;
      let matchedMethod = "";

      // Method 1: Python-style booleans (True/False) — Intention API
      const pyHmac = computePaymobHmac(obj, hmacSecret);
      if (received.length === pyHmac.length) {
        hmacValid = crypto.timingSafeEqual(
          Buffer.from(received), Buffer.from(pyHmac)
        );
        if (hmacValid) matchedMethod = "python-style";
      }

      // Method 2: JavaScript-style booleans (true/false) — legacy Accept API
      if (!hmacValid) {
        const jsHmac = computePaymobHmacLower(obj, hmacSecret);
        if (received.length === jsHmac.length) {
          hmacValid = crypto.timingSafeEqual(
            Buffer.from(received), Buffer.from(jsHmac)
          );
          if (hmacValid) matchedMethod = "js-style";
        }
      }

      // Method 3: Raw body HMAC (some Paymob integrations)
      if (!hmacValid) {
        const rawBody = typeof req.rawBody === "string"
          ? req.rawBody
          : req.rawBody?.toString("utf8") ?? "";
        const rawBodyHmac = crypto
          .createHmac("sha512", hmacSecret)
          .update(rawBody)
          .digest("hex");
        if (received.length === rawBodyHmac.length) {
          hmacValid = crypto.timingSafeEqual(
            Buffer.from(received), Buffer.from(rawBodyHmac)
          );
          if (hmacValid) matchedMethod = "raw-body";
        }
      }

      if (hmacValid) {
        logger.info("paymobWebhook: HMAC verified", {method: matchedMethod});
      } else {
        // HMAC field-based verification failed — Paymob's Intention API v1
        // uses a different HMAC computation than the legacy Accept API docs.
        // Fallback: verify the transaction directly with Paymob's legacy API.
        const txId = obj.id ?? body.transaction?.id;
        if (txId) {
          try {
            // Step 1: Get auth token via legacy API
            const apiKey = paymobApiKey.value().trim();
            const authRes = await fetch(
              "https://accept.paymob.com/api/auth/tokens",
              {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({api_key: apiKey}),
              }
            );

            if (authRes.ok) {
              const authData = await authRes.json() as Record<string, unknown>;
              const authToken = authData.token as string;

              // Step 2: Retrieve transaction details
              const verifyRes = await fetch(
                `https://accept.paymob.com/api/acceptance/transactions/${txId}`,
                {headers: {"Authorization": `Bearer ${authToken}`}}
              );

              if (verifyRes.ok) {
                const verifyData = await verifyRes.json() as Record<string, unknown>;
                // Confirm the amount and success status match
                const verifiedSuccess = verifyData.success === true || verifyData.success === "true";
                const verifiedAmount = Number(verifyData.amount_cents ?? 0);
                const webhookAmount = Number(obj.amount_cents ?? 0);
                if (
                  verifiedSuccess === (obj.success === true || obj.success === "true") &&
                  verifiedAmount === webhookAmount
                ) {
                  hmacValid = true;
                  matchedMethod = "api-verification";
                  logger.info("paymobWebhook: verified via Paymob API", {
                    txId: String(txId),
                    amount: verifiedAmount,
                    success: verifiedSuccess,
                  });
                } else {
                  logger.warn("paymobWebhook: API verification data mismatch", {
                    txId: String(txId),
                    webhookSuccess: String(obj.success),
                    apiSuccess: String(verifyData.success),
                    webhookAmount: webhookAmount,
                    apiAmount: verifiedAmount,
                  });
                }
              } else {
                logger.warn("paymobWebhook: API transaction lookup failed", {
                  txId: String(txId),
                  status: verifyRes.status,
                });
              }
            } else {
              logger.warn("paymobWebhook: API auth token request failed", {
                status: authRes.status,
              });
            }
          } catch (verifyErr) {
            logger.error("paymobWebhook: API verification error", verifyErr);
          }
        }

        if (!hmacValid) {
          logger.warn("paymobWebhook: HMAC mismatch and API verification failed", {
            receivedPrefix: received.substring(0, 8),
            pyHmacPrefix: pyHmac.substring(0, 8),
          });
          res.status(401).send("Invalid HMAC");
          return;
        }
      }

      // ── Extract payment data ─────────────────────────────────────────
      const success = obj.success === true || obj.success === "true";
      const amountCents = Number(obj.amount_cents ?? 0);
      const currency = String(obj.currency ?? "EGP");
      const paymobOrderId = String(obj.order?.id ?? "");
      const transactionId = String(obj.id ?? "");
      const apiSource = String(obj.api_source ?? "");

      // Intention API uses special_reference for merchant_order_id
      const intention = body.intention as Record<string, unknown> | undefined;
      const orderObj = obj.order as Record<string, unknown> | undefined;
      const merchantOrderId = String(
        intention?.special_reference ??
        orderObj?.merchant_order_id ??
        obj.merchant_order_id ??
        ""
      );

      // Parse uid and plan from merchant_order_id.
      // Format: "{uid}_{plan}_{timestamp}"
      const separatorIdx = merchantOrderId.indexOf("_");
      if (!merchantOrderId || separatorIdx === -1) {
        // Paymob sometimes sends extra callbacks (3DS verification, etc.)
        // with no merchant_order_id — acknowledge without processing.
        logger.info("paymobWebhook: callback without merchant_order_id — skipping", {
          merchantOrderId: merchantOrderId || "(empty)",
          transactionId: String(obj.id ?? ""),
        });
        res.status(200).send("OK — no merchant_order_id");
        return;
      }

      const uid = merchantOrderId.substring(0, separatorIdx);
      const rest = merchantOrderId.substring(separatorIdx + 1);
      const knownPlans = Object.keys(PLAN_DURATION_DAYS).sort(
        (a, b) => b.length - a.length
      );
      const plan = knownPlans.find((p) => rest.startsWith(p)) ?? rest;

      if (!uid || !plan) {
        logger.error("paymobWebhook: missing uid or plan", {uid, plan});
        res.status(400).send("Missing uid or plan");
        return;
      }

      // ── Log the payment attempt ──────────────────────────────────────
      await db().collection("payment_logs").add({
        user_id: uid,
        plan,
        success,
        amount_cents: amountCents,
        currency,
        paymob_order_id: paymobOrderId,
        paymob_transaction_id: transactionId,
        merchant_order_id: merchantOrderId,
        api_source: apiSource,
        is_renewal: apiSource === "SUBSCRIPTION",
        created_at: FieldValue.serverTimestamp(),
      });

      if (!success) {
        logger.info("paymobWebhook: payment failed", {uid, plan, transactionId, apiSource});

        // If renewal failed, notify user
        if (apiSource === "SUBSCRIPTION") {
          await notifyUser(
            uid,
            "Renewal Payment Issue",
            "We had trouble charging your card. Paymob will retry automatically.",
            {type: "auto_renewal_retry", plan},
            "billing"
          );
        }

        res.status(200).send("Payment failure recorded");
        return;
      }

      // ── Idempotency: skip if this transaction was already processed ──
      const existingTx = await db().collection("payment_logs")
        .where("paymob_transaction_id", "==", transactionId)
        .where("success", "==", true)
        .limit(2)
        .get();
      if (existingTx.size > 1) {
        logger.warn("paymobWebhook: duplicate transaction — skipping", {transactionId});
        res.status(200).send("Duplicate — already processed");
        return;
      }

      // ── Determine tier and expiry ────────────────────────────────────
      const durationDays = PLAN_DURATION_DAYS[plan];
      if (!durationDays) {
        logger.error("paymobWebhook: unknown plan", {plan});
        res.status(400).send("Unknown plan");
        return;
      }

      const tier = plan.split("_")[0];

      // Stack expiry if user already has active time remaining
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
      expiresAt.setDate(expiresAt.getDate() + durationDays);

      // ── Extract card info from transaction source_data ────────────────
      const sourceData = obj.source_data as Record<string, unknown> | undefined;
      const cardLast4 = (sourceData?.pan as string)?.slice(-4) || "";
      const cardBrand = (sourceData?.sub_type as string) || "";

      // ── Extract card token from intention.card_tokens ─────────────────
      // Paymob Unified Checkout stores tokenized card info in intention.card_tokens
      const cardTokens = intention?.card_tokens as Array<Record<string, unknown>> | undefined;
      let cardToken: string | undefined;
      if (Array.isArray(cardTokens) && cardTokens.length > 0) {
        cardToken = cardTokens[0].token as string | undefined;
      }

      logger.info("paymobWebhook: card & subscription data", {
        hasSourceData: !!sourceData,
        cardLast4: cardLast4 || "(empty)",
        cardBrand: cardBrand || "(empty)",
        hasCardTokens: Array.isArray(cardTokens),
        cardTokensLength: cardTokens?.length ?? 0,
        cardToken: cardToken ? `${cardToken.substring(0, 8)}...` : "(none)",
        cardDetail: intention?.card_detail ? JSON.stringify(intention.card_detail) : "(none)",
      });

      // ── Extract subscription ID from webhook body ─────────────────────
      // Paymob sends subscription info in the body for subscription-related txns
      let subscriptionId = body.subscription_id as number | undefined;

      // ── If no subscription yet, create one manually via Paymob API ────
      // The subscription_plan_id in the intention should auto-create, but if
      // Paymob didn't, we create it ourselves using the card token.
      if (!subscriptionId && cardToken && apiSource !== "SUBSCRIPTION") {
        try {
          const configDoc = await db()
            .collection("paymob_config")
            .doc("subscription_plans")
            .get();
          const planId = configDoc.data()?.[plan] as number | undefined;

          if (planId) {
            const apiKey = paymobApiKey.value().trim();
            const authRes = await fetch("https://accept.paymob.com/api/auth/tokens", {
              method: "POST",
              headers: {"Content-Type": "application/json"},
              body: JSON.stringify({api_key: apiKey}),
            });
            const authData = await authRes.json() as {token?: string};

            if (authData.token) {
              const subRes = await fetch(
                "https://accept.paymob.com/api/acceptance/subscriptions",
                {
                  method: "POST",
                  headers: {
                    "Authorization": `Bearer ${authData.token}`,
                    "Content-Type": "application/json",
                  },
                  body: JSON.stringify({
                    plan_id: planId,
                    card_token: cardToken,
                  }),
                }
              );
              const subData = await subRes.json() as Record<string, unknown>;
              const newSubId = subData.id as number | undefined;

              if (newSubId) {
                subscriptionId = newSubId;
                logger.info("paymobWebhook: subscription created manually", {
                  uid, subscriptionId: newSubId, planId, state: subData.state,
                });
              } else {
                logger.warn("paymobWebhook: subscription creation response", {
                  uid, planId, status: subRes.status,
                  response: JSON.stringify(subData).substring(0, 500),
                });
              }
            }
          } else {
            logger.warn("paymobWebhook: no planId in Firestore for", {plan});
          }
        } catch (subErr) {
          logger.error("paymobWebhook: subscription creation error", subErr);
        }
      }

      // Build user doc update
      const userUpdate: Record<string, unknown> = {
        subscription_tier: tier,
        subscription_status: "active" as SubscriptionStatus,
        subscription_plan: plan,
        subscription_expires_at: Timestamp.fromDate(expiresAt),
        last_payment_at: FieldValue.serverTimestamp(),
        last_paymob_order_id: paymobOrderId,
        last_paymob_transaction_id: transactionId,
        payment_source: "paymob",
        paymob_auto_renew: true, // Subscription module handles renewals
      };

      if (cardLast4) {
        userUpdate.paymob_card_last4 = cardLast4;
        userUpdate.paymob_card_brand = cardBrand;
      }

      if (subscriptionId) {
        userUpdate.paymob_subscription_id = subscriptionId;
        userUpdate.paymob_subscription_state = "active";
      }

      // ── Update user document ─────────────────────────────────────────
      await db()
        .collection("users")
        .doc(uid)
        .set(userUpdate, {merge: true});

      logger.info("paymobWebhook: subscription activated", {
        uid,
        tier,
        plan,
        expiresAt: expiresAt.toISOString(),
        apiSource,
        isRenewal: apiSource === "SUBSCRIPTION",
        subscriptionId,
      });

      // ── Notify user ──────────────────────────────────────────────────
      const isRenewal = apiSource === "SUBSCRIPTION";
      await notifyUser(
        uid,
        isRenewal ? "Subscription Renewed ✓" : "Payment Confirmed ✓",
        isRenewal
          ? `Your ${tier.charAt(0).toUpperCase() + tier.slice(1)} subscription has been automatically renewed until ${expiresAt.toLocaleDateString("en-US", {year: "numeric", month: "long", day: "numeric"})}.`
          : `Your ${tier.charAt(0).toUpperCase() + tier.slice(1)} subscription is active until ${expiresAt.toLocaleDateString("en-US", {year: "numeric", month: "long", day: "numeric"})}.`,
        {type: isRenewal ? "auto_renewal_success" : "payment_success", plan},
        "billing"
      );

      res.status(200).send("OK");
    } catch (err) {
      logger.error("paymobWebhook: unhandled error", err);
      res.status(500).send("Internal error");
    }
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 2. Validate Subscriptions — scheduled daily at 03:00 UTC
// ────────────────────────────────────────────────────────────────────────────
export const validateSubscriptions = onSchedule(
  {
    schedule: "0 3 * * *",
    timeZone: "UTC",
    region: "us-central1",
    maxInstances: 1,
    timeoutSeconds: 300,
  },
  async () => {
    const now = Timestamp.now();
    const graceThreshold = new Date();
    graceThreshold.setDate(graceThreshold.getDate() - GRACE_PERIOD_DAYS);
    const graceTs = Timestamp.fromDate(graceThreshold);

    // ── Phase 1: Move active → grace_period if expired ─────────────
    const activeExpired = await db()
      .collection("users")
      .where("subscription_status", "==", "active")
      .where("subscription_expires_at", "<", now)
      .get();

    let movedToGrace = 0;
    for (const doc of activeExpired.docs) {
      const data = doc.data();
      const expiresAt = data.subscription_expires_at as Timestamp;

      if (expiresAt.toDate() < graceThreshold) {
        // Already past grace period — downgrade immediately
        await doc.ref.update({
          subscription_tier: "launch",
          subscription_status: "expired" as SubscriptionStatus,
        });
        await notifyUser(
          doc.id,
          "Subscription Expired",
          "Your subscription has ended. Renew to keep Growth features.",
          {type: "subscription_expired"},
          "billing"
        );
      } else {
        // Within grace period — warn but keep tier
        await doc.ref.update({
          subscription_status: "grace_period" as SubscriptionStatus,
        });
        await notifyUser(
          doc.id,
          "Subscription Expiring",
          "Your subscription expires soon. Renew to avoid losing access.",
          {type: "subscription_grace"},
          "billing"
        );
        movedToGrace++;
      }
    }

    // ── Phase 2: Downgrade grace_period → expired if past grace ────
    const graceExpired = await db()
      .collection("users")
      .where("subscription_status", "==", "grace_period")
      .where("subscription_expires_at", "<", graceTs)
      .get();

    let downgraded = 0;
    for (const doc of graceExpired.docs) {
      await doc.ref.update({
        subscription_tier: "launch",
        subscription_status: "expired" as SubscriptionStatus,
      });
      await notifyUser(
        doc.id,
        "Subscription Expired",
        "Your grace period has ended. Renew to restore Growth features.",
        {type: "subscription_expired"},
        "billing"
      );
      downgraded++;
    }

    logger.info("validateSubscriptions complete", {
      activeExpiredChecked: activeExpired.size,
      movedToGrace,
      downgraded,
    });
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 3. Get Subscription Status — callable from the app to refresh state
// ────────────────────────────────────────────────────────────────────────────
export const getSubscriptionStatus = onCall(
  {region: "us-central1", maxInstances: 20, invoker: "public"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;

    const userDoc = await db().collection("users").doc(uid).get();
    if (!userDoc.exists) {
      return {
        subscription_tier: "launch",
        subscription_status: "free" as SubscriptionStatus,
        subscription_plan: null,
        subscription_expires_at: null,
      };
    }

    const data = userDoc.data()!;
    const tier = (data.subscription_tier as string) ?? "launch";
    const status = (data.subscription_status as string) ?? "free";
    const plan = (data.subscription_plan as string) ?? null;
    const expiresAt = data.subscription_expires_at as Timestamp | null;
    const paymentSource = (data.payment_source as string) ?? null;
    const cardLast4 = (data.paymob_card_last4 as string) ?? null;
    const cardBrand = (data.paymob_card_brand as string) ?? null;
    const autoRenew = (data.paymob_auto_renew as boolean) ?? false;

    // If active but expired, do an on-the-fly check
    if (
      status === "active" &&
      expiresAt &&
      expiresAt.toDate() < new Date()
    ) {
      const graceThreshold = new Date();
      graceThreshold.setDate(graceThreshold.getDate() - GRACE_PERIOD_DAYS);

      if (expiresAt.toDate() < graceThreshold) {
        // Past grace — downgrade
        await userDoc.ref.update({
          subscription_tier: "launch",
          subscription_status: "expired" as SubscriptionStatus,
        });
        return {
          subscription_tier: "launch",
          subscription_status: "expired",
          subscription_plan: plan,
          subscription_expires_at: expiresAt.toMillis(),
          payment_source: paymentSource,
          paymob_card_last4: cardLast4,
          paymob_card_brand: cardBrand,
          paymob_auto_renew: autoRenew,
        };
      } else {
        // In grace period
        await userDoc.ref.update({
          subscription_status: "grace_period" as SubscriptionStatus,
        });
        return {
          subscription_tier: tier,
          subscription_status: "grace_period",
          subscription_plan: plan,
          subscription_expires_at: expiresAt.toMillis(),
          payment_source: paymentSource,
          paymob_card_last4: cardLast4,
          paymob_card_brand: cardBrand,
          paymob_auto_renew: autoRenew,
        };
      }
    }

    return {
      subscription_tier: tier,
      subscription_status: status,
      subscription_plan: plan,
      subscription_expires_at: expiresAt?.toMillis() ?? null,
      payment_source: paymentSource,
      paymob_card_last4: cardLast4,
      paymob_card_brand: cardBrand,
      paymob_auto_renew: autoRenew,
    };
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 4. Cancel Subscription — voluntary downgrade
// ────────────────────────────────────────────────────────────────────────────
const ALLOWED_TIERS = ["launch", "growth"] as const;

export const cancelSubscription = onCall(
  {region: "us-central1", maxInstances: 20, invoker: "public"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;
    const targetTier = (request.data?.target_tier as string) ?? "launch";

    // Validate target — only downgrades to launch or growth are allowed
    if (!ALLOWED_TIERS.includes(targetTier as typeof ALLOWED_TIERS[number])) {
      throw new HttpsError("invalid-argument", `Invalid target tier: ${targetTier}`);
    }

    // Verify this is actually a downgrade (not an upgrade)
    const TIER_ORDER: Record<string, number> = {launch: 0, growth: 1, pro: 2};
    const userDoc = await db().collection("users").doc(uid).get();
    const currentTier = (userDoc.data()?.subscription_tier as string) ?? "launch";
    if (TIER_ORDER[targetTier] >= (TIER_ORDER[currentTier] ?? 0)) {
      // Not a downgrade — deny
      throw new HttpsError("permission-denied", "Can only downgrade, not upgrade via this endpoint");
    }

    const newStatus: SubscriptionStatus = targetTier === "launch" ? "free" : "active";

    // Write via Admin SDK — bypasses Firestore security rules that protect
    // subscription fields from client-side modification.
    await db()
      .collection("users")
      .doc(uid)
      .set(
        {
          subscription_tier: targetTier,
          subscription_status: newStatus,
        },
        {merge: true}
      );

    logger.info("cancelSubscription: user downgraded", {uid, from: currentTier, to: targetTier});

    return {
      subscription_tier: targetTier,
      subscription_status: newStatus,
    };
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 5. Pre-Expiry Reminders — daily at 10:00 UTC
//    Sends FCM notifications 3 days and 1 day before subscription expiry.
//    (Renewals are now handled automatically by Paymob's Subscription Module)
// ────────────────────────────────────────────────────────────────────────────
export const sendPreExpiryReminders = onSchedule(
  {
    schedule: "0 10 * * *",
    timeZone: "UTC",
    region: "us-central1",
    maxInstances: 1,
    timeoutSeconds: 120,
  },
  async () => {
    const now = new Date();
    let sent = 0;

    // ── 3-day reminder ─────────────────────────────────────────────
    const threeDayStart = new Date(now);
    threeDayStart.setDate(threeDayStart.getDate() + 3);
    threeDayStart.setHours(0, 0, 0, 0);
    const threeDayEnd = new Date(threeDayStart);
    threeDayEnd.setDate(threeDayEnd.getDate() + 1);

    const threeDayUsers = await db()
      .collection("users")
      .where("subscription_status", "==", "active")
      .where("subscription_expires_at", ">=", Timestamp.fromDate(threeDayStart))
      .where("subscription_expires_at", "<", Timestamp.fromDate(threeDayEnd))
      .get();

    for (const doc of threeDayUsers.docs) {
      const data = doc.data();
      const autoRenew = data.paymob_auto_renew === true;
      const paymentSource = data.payment_source as string | undefined;

      // Don't nag auto-renew users with an active subscription — they'll be charged automatically
      if (autoRenew && paymentSource === "paymob" && data.paymob_subscription_id) {
        continue;
      }

      await notifyUser(
        doc.id,
        "Subscription Expiring in 3 Days",
        paymentSource === "iap"
          ? "Your subscription renews automatically through the App Store / Google Play."
          : "Renew now to keep your Growth features.",
        {type: "pre_expiry_3d"},
        "billing"
      );
      sent++;
    }

    // ── 1-day reminder ─────────────────────────────────────────────
    const oneDayStart = new Date(now);
    oneDayStart.setDate(oneDayStart.getDate() + 1);
    oneDayStart.setHours(0, 0, 0, 0);
    const oneDayEnd = new Date(oneDayStart);
    oneDayEnd.setDate(oneDayEnd.getDate() + 1);

    const oneDayUsers = await db()
      .collection("users")
      .where("subscription_status", "==", "active")
      .where("subscription_expires_at", ">=", Timestamp.fromDate(oneDayStart))
      .where("subscription_expires_at", "<", Timestamp.fromDate(oneDayEnd))
      .get();

    for (const doc of oneDayUsers.docs) {
      const data = doc.data();
      const autoRenew = data.paymob_auto_renew === true;
      const paymentSource = data.payment_source as string | undefined;

      if (autoRenew && paymentSource === "paymob" && data.paymob_subscription_id) {
        continue;
      }

      await notifyUser(
        doc.id,
        "Subscription Expires Tomorrow",
        paymentSource === "iap"
          ? "Your subscription renews automatically through the App Store / Google Play."
          : "Renew today to avoid losing access to Growth features.",
        {type: "pre_expiry_1d"},
        "billing"
      );
      sent++;
    }

    logger.info("sendPreExpiryReminders complete", {sent});
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 7. Toggle Auto-Renew — callable from the app dashboard
// ────────────────────────────────────────────────────────────────────────────
export const toggleAutoRenew = onCall(
  {region: "us-central1", maxInstances: 20, invoker: "public"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;
    const enabled = request.data?.enabled;

    if (typeof enabled !== "boolean") {
      throw new HttpsError("invalid-argument", "enabled must be a boolean");
    }

    const userDoc = await db().collection("users").doc(uid).get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "User not found");
    }

    const data = userDoc.data()!;
    const paymentSource = data.payment_source as string | undefined;
    const subscriptionId = data.paymob_subscription_id as number | undefined;
    const cardLast4 = data.paymob_card_last4 as string | undefined;

    // Can only enable auto-renew if paying via Paymob with either an active
    // subscription or a saved card (subscription_id may arrive via a delayed
    // second callback from Paymob).
    if (enabled && paymentSource !== "paymob") {
      throw new HttpsError(
        "failed-precondition",
        "Auto-renew requires a Paymob payment method"
      );
    }
    if (enabled && !subscriptionId && !cardLast4) {
      throw new HttpsError(
        "failed-precondition",
        "Auto-renew requires a saved card or active Paymob subscription"
      );
    }

    await userDoc.ref.update({
      paymob_auto_renew: enabled,
      ...(enabled ? {paymob_renewal_attempts: 0} : {}),
    });

    logger.info("toggleAutoRenew", {uid, enabled});

    return {paymob_auto_renew: enabled};
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 8. Remove Payment Method — callable from the app dashboard
//    Removes saved card info, disables auto-renew, and cancels the Paymob
//    subscription so no further recurring charges occur.
// ────────────────────────────────────────────────────────────────────────────
export const removePaymentMethod = onCall(
  {
    region: "us-central1",
    maxInstances: 20,
    invoker: "public",
    secrets: [paymobApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;

    const userDoc = await db().collection("users").doc(uid).get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "User not found");
    }

    const data = userDoc.data()!;
    if (!data.paymob_card_last4) {
      return {removed: false, reason: "no_saved_card"};
    }

    // Cancel Paymob subscription if one exists
    const subscriptionId = data.paymob_subscription_id as number | undefined;
    if (subscriptionId) {
      try {
        const apiKey = paymobApiKey.value().trim();
        const authRes = await fetch("https://accept.paymob.com/api/auth/tokens", {
          method: "POST",
          headers: {"Content-Type": "application/json"},
          body: JSON.stringify({api_key: apiKey}),
        });
        const authData = await authRes.json() as {token?: string};
        if (authData.token) {
          await fetch(
            `https://accept.paymob.com/api/acceptance/subscriptions/${subscriptionId}/cancel`,
            {
              method: "POST",
              headers: {"Authorization": `Bearer ${authData.token}`},
            }
          );
          logger.info("removePaymentMethod: Paymob subscription cancelled", {uid, subscriptionId});
        }
      } catch (err) {
        logger.warn("removePaymentMethod: failed to cancel Paymob subscription", {uid, subscriptionId, err});
      }
    }

    await userDoc.ref.update({
      paymob_card_last4: FieldValue.delete(),
      paymob_card_brand: FieldValue.delete(),
      paymob_subscription_id: FieldValue.delete(),
      paymob_subscription_state: FieldValue.delete(),
      paymob_auto_renew: false,
      paymob_renewal_attempts: 0,
    });

    logger.info("removePaymentMethod: card removed", {uid});

    return {removed: true};
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 9. Get Payment History — returns the user's last 50 payment log entries
// ────────────────────────────────────────────────────────────────────────────
export const getPaymentHistory = onCall(
  {region: "us-central1", maxInstances: 20, invoker: "public"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;

    const snap = await db()
      .collection("payment_logs")
      .where("user_id", "==", uid)
      .orderBy("created_at", "desc")
      .limit(50)
      .get();

    const entries = snap.docs.map((doc) => {
      const d = doc.data();
      const createdAt = d.created_at as Timestamp | undefined;
      return {
        id: doc.id,
        plan: d.plan ?? null,
        success: d.success ?? false,
        amount_cents: d.amount_cents ?? 0,
        currency: d.currency ?? "EGP",
        is_renewal: d.is_renewal ?? false,
        paymob_transaction_id: d.paymob_transaction_id ?? null,
        created_at: createdAt?.toMillis() ?? null,
      };
    });

    return {payments: entries};
  }
);
