/**
 * createPaymentIntent — callable Cloud Function
 *
 * Creates a Paymob payment intention via the Intention API (v1) and returns
 * the unified checkout URL. Uses Paymob Subscription Module — the intention
 * includes a subscription_plan_id so Paymob automatically:
 *   - Tokenizes the card via 3DS
 *   - Creates the subscription
 *   - Handles all future recurring charges via MOTO integration
 *
 * Required secrets:
 *  - PAYMOB_SECRET_KEY       (Intention API auth)
 *  - PAYMOB_PUBLIC_KEY       (unified checkout URL)
 *  - PAYMOB_INTEGRATION_ID   (3DS card integration for initial payment)
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

const db = () => getFirestore();

const paymobSecretKey = defineSecret("PAYMOB_SECRET_KEY");
const paymobPublicKey = defineSecret("PAYMOB_PUBLIC_KEY");
const paymobIntegrationId = defineSecret("PAYMOB_INTEGRATION_ID");

// ── Plan pricing ────────────────────────────────────────────────────────────
// Initial payment amount in cents. When use_transaction_amount is false on the
// plan, this is just the enrollment charge; renewals use the plan's amount_cents.
const PLAN_PRICES: Record<string, {amount_cents: number; currency: string}> = {
  growth_monthly: {amount_cents: 50, currency: "EGP"}, // TODO: TEST PRICE 0.50 EGP — revert to 24900
  growth_yearly: {amount_cents: 50, currency: "EGP"}, // TODO: TEST PRICE 0.50 EGP — revert to 239000
};

export const createPaymentIntent = onCall(
  {
    region: "us-central1",
    maxInstances: 20,
    invoker: "public",
    secrets: [paymobSecretKey, paymobPublicKey, paymobIntegrationId],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }
    const uid = request.auth.uid;
    const plan = request.data?.plan as string | undefined;

    if (!plan || !PLAN_PRICES[plan]) {
      throw new HttpsError(
        "invalid-argument",
        `Invalid plan. Choose one of: ${Object.keys(PLAN_PRICES).join(", ")}`
      );
    }

    const {amount_cents, currency} = PLAN_PRICES[plan];

    // Fetch user email for billing data
    const userDoc = await db().collection("users").doc(uid).get();
    const email = userDoc.data()?.email as string || request.auth.token.email;
    if (!email) {
      throw new HttpsError("failed-precondition", "User account has no email address. Please update your profile.");
    }
    const name = userDoc.data()?.business_name as string || "Revvo User";
    const firstName = name.split(" ")[0] || "User";
    const lastName = name.split(" ").slice(1).join(" ") || ".";

    try {
      const merchantOrderId = `${uid}_${plan}_${Date.now()}`;
      const integrationId = Number(paymobIntegrationId.value());
      const secretKey = paymobSecretKey.value().trim();

      // ── Fetch subscription_plan_id from Firestore config ───────────
      const configDoc = await db()
        .collection("paymob_config")
        .doc("subscription_plans")
        .get();
      const subscriptionPlanId = configDoc.data()?.[plan] as number | undefined;

      if (!subscriptionPlanId) {
        logger.error("createPaymentIntent: no subscription plan configured for", {plan});
        throw new HttpsError(
          "failed-precondition",
          `Subscription plan not configured for ${plan}. Run setupSubscriptionPlans first.`
        );
      }

      // ── Intention API (v1) — with subscription_plan_id ─────────────
      const intentionBody: Record<string, unknown> = {
        amount: amount_cents, // Intention API uses cents (integer)
        currency,
        payment_methods: [integrationId],
        subscription_plan_id: subscriptionPlanId,
        billing_data: {
          email,
          first_name: firstName,
          last_name: lastName,
          phone_number: "NA",
          apartment: "NA",
          floor: "NA",
          street: "NA",
          building: "NA",
          shipping_method: "NA",
          postal_code: "NA",
          city: "NA",
          country: "EG",
          state: "NA",
        },
        special_reference: merchantOrderId,
        notification_url: "https://us-central1-massari-574ff.cloudfunctions.net/paymobWebhook",
        redirection_url: "https://revvo-app.com/payment-complete",
        items: [
          {
            name: `Revvo ${plan.replace("_", " ")} subscription`,
            amount: amount_cents,
            quantity: 1,
          },
        ],
      };

      const intentionRes = await fetch(
        "https://accept.paymob.com/v1/intention/",
        {
          method: "POST",
          headers: {
            "Authorization": `Token ${secretKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(intentionBody),
        }
      );

      const intentionData = await intentionRes.json() as Record<string, unknown>;
      const clientSecret = intentionData.client_secret as string | undefined;

      logger.info("createPaymentIntent: intention response", {
        id: intentionData.id,
        hasClientSecret: !!clientSecret,
        subscription_plan_id: subscriptionPlanId,
        subscription: intentionData.subscription ?? "none",
        status: intentionRes.status,
      });

      if (!clientSecret) {
        logger.error("Paymob intention response:", JSON.stringify(intentionData));
        throw new Error("Paymob intention creation failed — no client_secret");
      }

      // ── Build unified checkout URL ─────────────────────────────────
      const publicKey = paymobPublicKey.value().trim();
      const checkoutUrl =
        `https://accept.paymob.com/unifiedcheckout/?publicKey=${publicKey}&clientSecret=${clientSecret}`;

      logger.info("createPaymentIntent: success", {
        uid,
        plan,
        merchantOrderId,
        intentionId: intentionData.id,
      });

      return {
        iframe_url: checkoutUrl, // keep same key name for Flutter backward compat
        client_secret: clientSecret,
        public_key: publicKey,
      };
    } catch (err) {
      logger.error("createPaymentIntent: failed", err);
      throw new HttpsError("internal", "Failed to create payment intent");
    }
  }
);
