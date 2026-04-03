/**
 * Paymob Subscription Module — Plan & subscription management
 *
 * Uses Paymob's built-in Subscription Module for recurring billing.
 * Paymob handles card tokenization, auto-deductions, retries, and reminders.
 *
 * Architecture:
 *  1. Create subscription plans (one per pricing tier) — done once via setupSubscriptionPlans
 *  2. Customer subscribes via Intention API with subscription_plan_id
 *  3. Paymob auto-charges recurring payments via MOTO integration
 *  4. Webhook receives subscription events
 *
 * Exports:
 *  - setupSubscriptionPlans  (onCall) — creates/updates plans in Paymob
 *  - getPaymobSubscription   (onCall) — fetches subscription details from Paymob
 *  - suspendSubscription      (onCall) — pauses a subscription  
 *  - resumeSubscription       (onCall) — resumes a paused subscription
 *  - cancelPaymobSubscription (onCall) — permanently cancels a subscription
 */

import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

const db = () => getFirestore();

const paymobApiKey = defineSecret("PAYMOB_API_KEY");
const paymobIntegrationId = defineSecret("PAYMOB_INTEGRATION_ID");

// ── Webhook URL for subscription events ─────────────────────────────────────
const WEBHOOK_URL = "https://us-central1-massari-574ff.cloudfunctions.net/paymobWebhook";

/** Verify the caller has admin: true custom claim */
function assertAdmin(request: CallableRequest) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
  if (!(request.auth.token as Record<string, unknown>).admin) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
}

// ── Plan definitions ────────────────────────────────────────────────────────
// Each plan maps to a Paymob subscription plan with specific billing terms.
// amount_cents here is the RENEWAL amount (not the initial payment).
interface PlanDef {
  name: string;
  frequency: number; // 7=weekly, 30=monthly, 360=annual
  amount_cents: number;
  plan_type: string;
  reminder_days: number;
  retrial_days: number;
}

const PLAN_DEFINITIONS: Record<string, PlanDef> = {
  growth_monthly: {
    name: "Revvo Growth Monthly",
    frequency: 30,
    amount_cents: 50, // TODO: TEST PRICE 0.50 EGP — revert to 24900
    plan_type: "rent",
    reminder_days: 3,
    retrial_days: 2,
  },
  growth_yearly: {
    name: "Revvo Growth Yearly",
    frequency: 360,
    amount_cents: 50, // TODO: TEST PRICE 0.50 EGP — revert to 239000
    plan_type: "rent",
    reminder_days: 7,
    retrial_days: 3,
  },
};

// ── Helper: get Paymob auth token ───────────────────────────────────────────
async function getPaymobAuthToken(apiKey: string): Promise<string> {
  const res = await fetch("https://accept.paymob.com/api/auth/tokens", {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({api_key: apiKey}),
  });
  if (!res.ok) throw new Error(`Paymob auth failed: ${res.status}`);
  const data = await res.json() as {token?: string};
  if (!data.token) throw new Error("Paymob auth: no token returned");
  return data.token;
}

// ────────────────────────────────────────────────────────────────────────────
// 1. Setup Subscription Plans — creates plans in Paymob and stores IDs
//    Call this once (or when pricing changes) from an admin context.
// ────────────────────────────────────────────────────────────────────────────
export const setupSubscriptionPlans = onCall(
  {
    region: "us-central1",
    maxInstances: 5,
    invoker: "public",
    secrets: [paymobApiKey, paymobIntegrationId],
  },
  async (request) => {
    assertAdmin(request);
    const uid = request.auth!.uid;
    logger.info("setupSubscriptionPlans: called by", {uid});

    const apiKey = paymobApiKey.value().trim();
    const integrationId = Number(paymobIntegrationId.value().trim());
    const authToken = await getPaymobAuthToken(apiKey);

    const results: Record<string, unknown> = {};

    for (const [planKey, def] of Object.entries(PLAN_DEFINITIONS)) {
      // Check if plan already exists in our config
      const configDoc = await db()
        .collection("paymob_config")
        .doc("subscription_plans")
        .get();
      const existingPlanId = configDoc.data()?.[planKey] as number | undefined;

      if (existingPlanId) {
        // Update existing plan
        const updateRes = await fetch(
          `https://accept.paymob.com/api/acceptance/subscription-plans/${existingPlanId}`,
          {
            method: "PUT",
            headers: {
              "Authorization": `Bearer ${authToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              amount_cents: def.amount_cents,
              integration: integrationId,
            }),
          }
        );
        const updateData = await updateRes.json();
        results[planKey] = {action: "updated", id: existingPlanId, response: updateData};
        logger.info(`setupSubscriptionPlans: updated ${planKey}`, {id: existingPlanId});
      } else {
        // Create new plan
        const createRes = await fetch(
          "https://accept.paymob.com/api/acceptance/subscription-plans",
          {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${authToken}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              frequency: def.frequency,
              name: def.name,
              amount_cents: def.amount_cents,
              integration: integrationId,
              webhook_url: WEBHOOK_URL,
              use_transaction_amount: false,
              is_active: true,
              plan_type: def.plan_type,
              reminder_days: def.reminder_days,
              retrial_days: def.retrial_days,
              number_of_deductions: null, // unlimited
            }),
          }
        );

        if (!createRes.ok) {
          const errText = await createRes.text();
          logger.error(`setupSubscriptionPlans: create failed for ${planKey}`, {
            status: createRes.status,
            body: errText,
          });
          results[planKey] = {action: "error", status: createRes.status, body: errText};
          continue;
        }

        const createData = await createRes.json() as {id?: number};
        if (!createData.id) {
          results[planKey] = {action: "error", body: createData};
          continue;
        }

        // Store plan ID in Firestore config
        await db()
          .collection("paymob_config")
          .doc("subscription_plans")
          .set({[planKey]: createData.id}, {merge: true});

        results[planKey] = {action: "created", id: createData.id, response: createData};
        logger.info(`setupSubscriptionPlans: created ${planKey}`, {id: createData.id});
      }
    }

    return {plans: results};
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 2. Get Subscription Details — fetches from Paymob API
// ────────────────────────────────────────────────────────────────────────────
export const getPaymobSubscription = onCall(
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
    const subscriptionId = userDoc.data()?.paymob_subscription_id as number | undefined;

    if (!subscriptionId) {
      return {subscription: null};
    }

    const apiKey = paymobApiKey.value().trim();
    const authToken = await getPaymobAuthToken(apiKey);

    const res = await fetch(
      `https://accept.paymob.com/api/acceptance/subscriptions/${subscriptionId}`,
      {headers: {"Authorization": `Bearer ${authToken}`}}
    );

    if (!res.ok) {
      logger.warn("getPaymobSubscription: fetch failed", {subscriptionId, status: res.status});
      return {subscription: null, error: `Fetch failed: ${res.status}`};
    }

    const data = await res.json();
    return {subscription: data};
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 3. Suspend Subscription — pauses billing
// ────────────────────────────────────────────────────────────────────────────
export const suspendSubscription = onCall(
  {
    region: "us-central1",
    maxInstances: 10,
    invoker: "public",
    secrets: [paymobApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const uid = request.auth.uid;
    const userDoc = await db().collection("users").doc(uid).get();
    const subscriptionId = userDoc.data()?.paymob_subscription_id as number | undefined;

    if (!subscriptionId) {
      throw new HttpsError("not-found", "No active subscription found");
    }

    const apiKey = paymobApiKey.value().trim();
    const authToken = await getPaymobAuthToken(apiKey);

    const res = await fetch(
      `https://accept.paymob.com/api/acceptance/subscriptions/${subscriptionId}/suspend`,
      {
        method: "POST",
        headers: {"Authorization": `Bearer ${authToken}`},
      }
    );

    if (!res.ok) {
      const errText = await res.text();
      logger.error("suspendSubscription: failed", {subscriptionId, status: res.status, body: errText});
      throw new HttpsError("internal", "Failed to suspend subscription");
    }

    const data = await res.json() as {state?: string};

    await userDoc.ref.update({
      subscription_status: "suspended",
      paymob_subscription_state: data.state ?? "suspended",
    });

    logger.info("suspendSubscription: success", {uid, subscriptionId});
    return {state: data.state};
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 4. Resume Subscription — resumes billing
// ────────────────────────────────────────────────────────────────────────────
export const resumeSubscription = onCall(
  {
    region: "us-central1",
    maxInstances: 10,
    invoker: "public",
    secrets: [paymobApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const uid = request.auth.uid;
    const userDoc = await db().collection("users").doc(uid).get();
    const subscriptionId = userDoc.data()?.paymob_subscription_id as number | undefined;

    if (!subscriptionId) {
      throw new HttpsError("not-found", "No active subscription found");
    }

    const apiKey = paymobApiKey.value().trim();
    const authToken = await getPaymobAuthToken(apiKey);

    const res = await fetch(
      `https://accept.paymob.com/api/acceptance/subscriptions/${subscriptionId}/resume`,
      {
        method: "POST",
        headers: {"Authorization": `Bearer ${authToken}`},
      }
    );

    if (!res.ok) {
      const errText = await res.text();
      logger.error("resumeSubscription: failed", {subscriptionId, status: res.status, body: errText});
      throw new HttpsError("internal", "Failed to resume subscription");
    }

    const data = await res.json() as {state?: string};

    await userDoc.ref.update({
      subscription_status: "active",
      paymob_subscription_state: data.state ?? "active",
    });

    logger.info("resumeSubscription: success", {uid, subscriptionId});
    return {state: data.state};
  }
);

// ────────────────────────────────────────────────────────────────────────────
// 5. Cancel Subscription — permanent, cannot be undone
// ────────────────────────────────────────────────────────────────────────────
export const cancelPaymobSubscription = onCall(
  {
    region: "us-central1",
    maxInstances: 10,
    invoker: "public",
    secrets: [paymobApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required");
    }

    const uid = request.auth.uid;
    const userDoc = await db().collection("users").doc(uid).get();
    const subscriptionId = userDoc.data()?.paymob_subscription_id as number | undefined;

    if (!subscriptionId) {
      throw new HttpsError("not-found", "No active subscription found");
    }

    const apiKey = paymobApiKey.value().trim();
    const authToken = await getPaymobAuthToken(apiKey);

    const res = await fetch(
      `https://accept.paymob.com/api/acceptance/subscriptions/${subscriptionId}/cancel`,
      {
        method: "POST",
        headers: {"Authorization": `Bearer ${authToken}`},
      }
    );

    if (!res.ok) {
      const errText = await res.text();
      logger.error("cancelPaymobSubscription: failed", {subscriptionId, status: res.status, body: errText});
      throw new HttpsError("internal", "Failed to cancel subscription");
    }

    const data = await res.json() as {state?: string};

    // Downgrade user — they keep access until current billing period ends
    await userDoc.ref.update({
      paymob_subscription_state: data.state ?? "canceled",
      paymob_auto_renew: false,
    });

    logger.info("cancelPaymobSubscription: success", {uid, subscriptionId});
    return {state: data.state};
  }
);
