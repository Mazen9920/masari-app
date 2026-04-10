/**
 * Revvo Cloud Functions — v2.2.0
 *
 * 1. processRecurringTransactions — scheduled daily, creates transaction docs
 *    for overdue recurring transactions and advances their next_due_date.
 *
 * 2. onSupplierDeleted — Firestore trigger that cascade-deletes related
 *    purchases, payments, goods receipts, and supplier-tagged transactions
 *    when a supplier is removed.
 *
 * 3. purgeExpiredShopifyData — scheduled daily, deletes:
 *    - shopify_webhook_queue entries processed > 30 days ago
 *    - shopify_sync_log entries created > 90 days ago
 *    This enforces the data retention policy required by Shopify's
 *    protected customer data access requirements.
 */

import {setGlobalOptions} from "firebase-functions";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentDeleted, onDocumentCreated} from "firebase-functions/v2/firestore";
import {initializeApp} from "firebase-admin/app";
import {getFirestore, FieldValue, WriteBatch} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {notifyUser} from "./notify.js";

// ── Shopify (Phases 3–5) ───────────────────────────────────
export {shopifyAuthStart} from "./shopify-auth.js";
export {storeAuthCallback} from "./shopify-auth.js";
export {storeWebhook} from "./shopify-webhooks.js";
export {processShopifyWebhook, backfillFulfillmentStatus, refreshShopifyOrder, refreshAllShopifyOrders, reconcileShopifyOrders} from "./shopify-processor.js";
export {shopifyProxy} from "./shopify-proxy.js";
export {shopifyHealthCheck} from "./shopify-health.js";
export {shopifyDisconnect} from "./shopify-disconnect.js";

// ── Account Management ─────────────────────────────────────
export {deleteUserData} from "./delete-user-data.js";

// ── Admin Dashboard ────────────────────────────────────────
export {adminListUsers, adminUpdateUser, adminGetUser, adminResetPassword, adminDisableUser} from "./admin.js";

// ── Admin Analytics ────────────────────────────────────────
export {getRevenueMetrics, getSubscriptionMetrics, computeDailyMetrics} from "./analytics.js";

// ── Billing & Subscriptions ────────────────────────────────
export {paymobWebhook, validateSubscriptions, getSubscriptionStatus, cancelSubscription, sendPreExpiryReminders, toggleAutoRenew, removePaymentMethod, getPaymentHistory} from "./billing.js";
export {createPaymentIntent} from "./paymob-order.js";
export {setupSubscriptionPlans, getPaymobSubscription, suspendSubscription, resumeSubscription, cancelPaymobSubscription} from "./paymob-subscription.js";
export {verifyIapReceipt} from "./iap-receipt.js";

initializeApp();
const db = getFirestore();

setGlobalOptions({maxInstances: 10, region: "us-central1"});

/** Max operations per Firestore batch (Firestore limit is 500). */
const BATCH_LIMIT = 250;

/**
 * Commits the current batch if it has reached the limit and returns a fresh
 * batch. Otherwise returns the same batch.
 * @param {WriteBatch} batch  The current Firestore write batch.
 * @param {number} count  Number of operations in the batch so far.
 * @return {object} Fresh or same batch with count.
 */
async function flushIfNeeded(
  batch: WriteBatch,
  count: number,
): Promise<{batch: WriteBatch; count: number}> {
  if (count >= BATCH_LIMIT) {
    await batch.commit();
    return {batch: db.batch(), count: 0};
  }
  return {batch, count};
}

// ═══════════════════════════════════════════════════════════
// 0. New Sale Notification — triggers on any new sale doc
// ═══════════════════════════════════════════════════════════

export const onSaleCreated = onDocumentCreated(
  {document: "sales/{saleId}"},
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const userId = data.user_id as string | undefined;
    if (!userId) return;

    // Skip Shopify sales — they already send their own notification
    if (data.external_source === "shopify") return;

    const customerName = data.customer_name as string | undefined;
    const total = Number(data.items?.reduce(
      (sum: number, item: Record<string, unknown>) =>
        sum + (Number(item.unit_price ?? 0) * Number(item.quantity ?? 0)),
      0
    ) ?? 0);
    const taxAmount = Number(data.tax_amount ?? 0);
    const discountAmount = Number(data.discount_amount ?? 0);
    const shippingCost = Number(data.shipping_cost ?? 0);
    const saleTotal = total - discountAmount + taxAmount + shippingCost;

    const orderNumber = data.order_number as number | undefined;
    const orderLabel = orderNumber ? `#${orderNumber}` : "";
    const customerLabel = customerName ? ` from ${customerName}` : "";

    await notifyUser(
      userId,
      `New Sale ${orderLabel}`.trim(),
      `Sale${customerLabel} recorded — ${saleTotal.toFixed(2)} ${data.currency ?? ""}`.trim(),
      {type: "sale_created", sale_id: event.params.saleId},
      "sales"
    );
  }
);

// ═══════════════════════════════════════════════════════════
// 1. Process Recurring Transactions — runs every day at 01:00 UTC
// ═══════════════════════════════════════════════════════════

export const processRecurringTransactions = onSchedule(
  {
    schedule: "every day 01:00",
    timeZone: "UTC",
  },
  async () => {
    const now = new Date();
    logger.info("Processing recurring transactions", {now: now.toISOString()});

    // Find all active recurring transactions that are overdue
    const snapshot = await db
      .collection("recurring_transactions")
      .where("is_active", "==", true)
      .where("next_due_date", "<=", now.toISOString())
      .get();

    if (snapshot.empty) {
      logger.info("No overdue recurring transactions found");
      return;
    }

    let batch = db.batch();
    let opsInBatch = 0;
    let count = 0;

    for (const doc of snapshot.docs) {
      const data = doc.data();

      // Create a real transaction from this recurring entry
      const txRef = db.collection("transactions").doc();
      batch.set(txRef, {
        user_id: data.user_id,
        title: data.title,
        amount: data.is_income ?
          Math.abs(data.amount) :
          -Math.abs(data.amount),
        category_id: data.category || (data.is_income ? "cat_income" : "cat_other"),
        date_time: now.toISOString(),
        note: `Auto-created from recurring: ${data.title}`,
        created_at: FieldValue.serverTimestamp(),
      });
      opsInBatch++;

      // Advance the next_due_date
      const nextDate = advanceDate(
        new Date(data.next_due_date),
        data.frequency as string
      );

      batch.update(doc.ref, {
        next_due_date: nextDate.toISOString(),
        updated_at: FieldValue.serverTimestamp(),
      });
      opsInBatch++;
      count++;

      // Flush if batch is getting large
      const flushed = await flushIfNeeded(batch, opsInBatch);
      batch = flushed.batch;
      opsInBatch = flushed.count;
    }

    if (opsInBatch > 0) {
      await batch.commit();
    }

    // Notify users about auto-created transactions
    const userCounts = new Map<string, number>();
    for (const doc of snapshot.docs) {
      const uid = doc.data().user_id as string;
      userCounts.set(uid, (userCounts.get(uid) || 0) + 1);
    }
    for (const [uid, n] of userCounts) {
      await notifyUser(
        uid,
        "Recurring Transactions",
        `${n} recurring transaction${n === 1 ? " was" : "s were"} auto-created today.`,
        {type: "recurring_created", count: String(n)},
        "recurring"
      );
    }

    logger.info(`Processed ${count} recurring transactions`);
  }
);

/**
 * Computes the next due date based on frequency.
 * Advances past "now" if the date is still in the past
 * after one step.
 * @param {Date} date - The current due date.
 * @param {string} frequency - weekly, monthly, or yearly.
 * @return {Date} The next future due date.
 */
function advanceDate(date: Date, frequency: string): Date {
  const now = new Date();
  let d = new Date(date);

  do {
    switch (frequency) {
    case "daily":
      d = new Date(d.getTime() + 1 * 24 * 60 * 60 * 1000);
      break;
    case "weekly":
      d = new Date(d.getTime() + 7 * 24 * 60 * 60 * 1000);
      break;
    case "monthly":
      d = new Date(d.getFullYear(), d.getMonth() + 1, d.getDate());
      break;
    case "yearly":
      d = new Date(d.getFullYear() + 1, d.getMonth(), d.getDate());
      break;
    default:
      // Fallback: treat unknown frequencies as monthly
      d = new Date(d.getFullYear(), d.getMonth() + 1, d.getDate());
    }
  } while (d <= now);

  return d;
}

// ═══════════════════════════════════════════════════════════
// 2. Cascade Delete — remove related purchases, payments,
//    goods receipts and supplier-tagged transactions when a
//    supplier document is deleted.
// ═══════════════════════════════════════════════════════════

export const onSupplierDeleted = onDocumentDeleted(
  "suppliers/{supplierId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const userId = data.user_id as string;
    const supplierId = event.params.supplierId;

    logger.info("Supplier deleted, cascading", {userId, supplierId});

    // Gather all related documents
    const [purchases, payments, receipts, transactions] = await Promise.all([
      db.collection("purchases")
        .where("user_id", "==", userId)
        .where("supplier_id", "==", supplierId)
        .get(),
      db.collection("payments")
        .where("user_id", "==", userId)
        .where("supplier_id", "==", supplierId)
        .get(),
      db.collection("goods_receipts")
        .where("user_id", "==", userId)
        .where("supplier_id", "==", supplierId)
        .get(),
      db.collection("transactions")
        .where("user_id", "==", userId)
        .where("supplier_id", "==", supplierId)
        .get(),
    ]);

    const allDocs = [
      ...purchases.docs,
      ...payments.docs,
      ...receipts.docs,
      ...transactions.docs,
    ];

    if (allDocs.length === 0) {
      logger.info("No related documents to cascade-delete");
      return;
    }

    // Chunk-delete in batches of BATCH_LIMIT
    let batch = db.batch();
    let opsInBatch = 0;

    for (const doc of allDocs) {
      batch.delete(doc.ref);
      opsInBatch++;

      const flushed = await flushIfNeeded(batch, opsInBatch);
      batch = flushed.batch;
      opsInBatch = flushed.count;
    }

    if (opsInBatch > 0) {
      await batch.commit();
    }

    logger.info(
      `Cascade deleted ${purchases.size} purchases, ` +
      `${payments.size} payments, ${receipts.size} goods receipts, ` +
      `${transactions.size} transactions for supplier ${supplierId}`
    );
  }
);

// ═══════════════════════════════════════════════════════════
// 3. Purge Expired Shopify Data — runs daily at 02:00 UTC
//
// Retention policy (Shopify protected customer data compliance):
//   • shopify_webhook_queue: delete entries processed > 30 days ago.
//     Unprocessed entries (processed_at == null) are never deleted here
//     so the processor can always retry them.
//   • shopify_sync_log: delete entries created > 90 days ago.
// ═══════════════════════════════════════════════════════════

export const purgeExpiredShopifyData = onSchedule(
  {
    schedule: "every day 02:00",
    timeZone: "UTC",
  },
  async () => {
    const now = new Date();

    // ── Webhook queue: processed entries older than 30 days ──
    const webhookCutoff = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
    const webhookSnap = await db
      .collection("shopify_webhook_queue")
      .where("processed_at", "!=", null)
      .where("processed_at", "<=", webhookCutoff)
      .get();

    // ── Sync log: entries older than 90 days ──────────────
    const logCutoff = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000);
    const logSnap = await db
      .collection("shopify_sync_log")
      .where("created_at", "<=", logCutoff)
      .get();

    const allExpired = [...webhookSnap.docs, ...logSnap.docs];

    if (allExpired.length === 0) {
      logger.info("purgeExpiredShopifyData: nothing to delete");
      return;
    }

    let batch = db.batch();
    let opsInBatch = 0;

    for (const doc of allExpired) {
      batch.delete(doc.ref);
      opsInBatch++;
      const flushed = await flushIfNeeded(batch, opsInBatch);
      batch = flushed.batch;
      opsInBatch = flushed.count;
    }

    if (opsInBatch > 0) await batch.commit();

    logger.info(
      `purgeExpiredShopifyData: deleted ${webhookSnap.size} webhook queue ` +
      `entries (>30 days) and ${logSnap.size} sync log entries (>90 days)`
    );
  }
);
