/**
 * anomaly-alerts.ts — event- and silence-driven alerts.
 *
 *  S10 no-orders  — treats SILENCE as the signal. For a store that normally
 *      takes an order every couple of hours, a long quiet stretch during
 *      trading hours usually means checkout or the Shopify sync is broken,
 *      not that customers went away. Nothing else in the app notices this,
 *      because "nothing happened" produces no document to react to.
 *  S11 margin erosion — fires the moment a goods receipt lands at a higher
 *      unit cost than the stock it joins, so a supplier price rise is caught
 *      at receipt instead of at month-end.
 */

import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {notifyUser} from "../notify.js";
import {
  COOLDOWN_HOURS,
  loadAlertState,
  markFired,
  saveAlertState,
  shouldFire,
} from "./alert-state.js";

const db = () => getFirestore();

/** Never cry "no orders" before this many hours, however busy the store. */
const MIN_SILENCE_HOURS = 24;
/** Silence must also exceed this multiple of the usual gap between orders. */
const SILENCE_FACTOR = 3;
/** Cost increase that counts as erosion rather than noise. */
const COST_JUMP_PCT = 10;

const num = (v: unknown): number => (typeof v === "number" ? v : Number(v) || 0);
const money = (n: number): string => Math.round(n).toLocaleString("en-US");

// ═══════════════════════════════════════════════════════════
//  S10 — order silence
// ═══════════════════════════════════════════════════════════

/**
 * Users whose orders arrive automatically (Shopify or Bosta connected).
 * Silence only means something when orders are supposed to flow on their own;
 * for a purely manual shop, a quiet day is just a quiet day.
 */
async function usersWithOrderPipelines(): Promise<Set<string>> {
  const uids = new Set<string>();
  const [shopify, bosta] = await Promise.all([
    db().collection("shopify_connections").get(),
    db().collection("bosta_connections").where("status", "==", "active").get(),
  ]);
  shopify.forEach((d) => {
    const uid = (d.data().user_id as string) ?? d.id;
    if (uid) uids.add(uid);
  });
  bosta.forEach((d) => uids.add(d.id));
  return uids;
}

export async function checkOrderSilence(uid: string, now = new Date()): Promise<void> {
  const state = await loadAlertState(uid);
  const updates: Record<string, unknown> = {};

  const latest = await db()
    .collection("sales")
    .where("user_id", "==", uid)
    .orderBy("date", "desc")
    .limit(1)
    .get();
  if (latest.empty) return; // never sold anything — nothing to compare against

  const last = (latest.docs[0].data().date as Timestamp)?.toDate();
  if (!last) return;

  const silentHours = (now.getTime() - last.getTime()) / 3600_000;
  // Median gap is refreshed weekly; fall back to a day until it exists.
  const median = num(state.baselines?.median_order_gap_hours) || 24;
  const threshold = Math.max(MIN_SILENCE_HOURS, median * SILENCE_FACTOR);

  if (silentHours < threshold) return;
  if (!shouldFire(state, "no_orders", now)) return;
  markFired(state, updates, "no_orders", COOLDOWN_HOURS.noOrders, now);
  await saveAlertState(uid, updates);

  await notifyUser(
    uid,
    "",
    "",
    {type: "no_orders"},
    "insights",
    {
      msg: {
        type: "no_orders",
        params: {
          hours: String(Math.floor(silentHours)),
          median: String(Math.round(median)),
        },
      },
    }
  );
  logger.info("orderSilence", {uid, silentHours: Math.round(silentHours)});
}

export const noOrdersMonitor = onSchedule(
  {
    schedule: "0 */4 * * *",
    timeZone: "Africa/Cairo",
    region: "us-central1",
    maxInstances: 1,
    timeoutSeconds: 300,
  },
  async () => {
    const uids = await usersWithOrderPipelines();
    for (const uid of uids) {
      try {
        await checkOrderSilence(uid);
      } catch (err) {
        logger.error("noOrdersMonitor: user failed", {uid, err});
      }
    }
    logger.info("noOrdersMonitor: complete", {checked: uids.size});
  }
);

// ═══════════════════════════════════════════════════════════
//  S11 — margin erosion on goods receipt
// ═══════════════════════════════════════════════════════════

export const onGoodsReceiptCreated = onDocumentCreated(
  {document: "goods_receipts/{receiptId}"},
  async (event) => {
    const receipt = event.data?.data();
    if (!receipt) return;
    const uid = receipt.user_id as string | undefined;
    if (!uid) return;

    const items = (receipt.items ?? []) as Record<string, unknown>[];
    if (items.length === 0) return;

    // Compare each received line against the cost already carried for that
    // variant. The product doc still holds the PRE-receipt cost when this
    // trigger runs, which is exactly the comparison we want.
    const worst = {
      pct: 0,
      productId: "",
      name: "",
      oldCost: 0,
      newCost: 0,
      price: 0,
    };

    for (const item of items) {
      const productId = item.product_id as string | undefined;
      const newCost = num(item.unit_cost);
      if (!productId || newCost <= 0) continue;

      const snap = await db().collection("products").doc(productId).get();
      const p = snap.data();
      if (!p) continue;
      const variantId = item.variant_id as string | undefined;
      const variants = (p.variants ?? []) as Record<string, unknown>[];
      const variant =
        variants.find((v) => v.id === variantId) ?? variants[0] ?? {};

      const oldCost = num(variant.cost_price);
      if (oldCost <= 0) continue; // nothing to compare — first ever purchase

      const pct = ((newCost - oldCost) / oldCost) * 100;
      if (pct > worst.pct) {
        worst.pct = pct;
        worst.productId = productId;
        worst.name = String(item.product_name ?? p.name ?? "");
        worst.oldCost = oldCost;
        worst.newCost = newCost;
        worst.price = num(variant.selling_price);
      }
    }

    if (worst.pct < COST_JUMP_PCT) return;

    // Margin at the CURRENT selling price, i.e. what this costs if the price
    // isn't changed.
    const margin =
      worst.price > 0
        ? ((worst.price - worst.newCost) / worst.price) * 100
        : 0;

    await notifyUser(
      uid,
      "",
      "",
      {
        type: "margin_erosion",
        product_id: worst.productId,
        receipt_id: event.params.receiptId,
      },
      "low_stock",
      {
        msg: {
          type: "margin_erosion",
          params: {
            product: worst.name,
            newCost: money(worst.newCost),
            oldCost: money(worst.oldCost),
            pct: worst.pct.toFixed(0),
            margin: margin.toFixed(0),
          },
        },
      }
    );
    logger.info("marginErosion", {uid, product: worst.name, pct: worst.pct});
  }
);
