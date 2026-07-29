/**
 * daily-alerts.ts — the once-a-day scan that turns Revvo's data into the
 * handful of things actually worth interrupting someone for.
 *
 * Runs 09:15 Africa/Cairo, after the nightly Bosta sync (21:59 UTC) has
 * refreshed delivery/cashout data, so every figure it reads is current.
 *
 * Design notes that matter:
 *  - **Ranked, not exhaustive.** RPE has 114 of 157 variants sitting at or
 *    below their reorder point; listing them daily is noise. Items are scored
 *    by how soon they run out RELATIVE to their supplier's lead time, and only
 *    the genuinely urgent ones are named.
 *  - **Velocity beats thresholds.** A static reorder point can't tell a
 *    fast-mover from dead stock. Units/day over the last 28 days does.
 *  - **Accrued payable, not due dates.** No purchase in the live data carries
 *    a due_date, so a due-date reminder would never fire; what's real is value
 *    RECEIVED but not paid.
 *  - Every alert is deduped through `notification_state` and re-arms when the
 *    condition resolves.
 */

import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {notifyUser} from "../notify.js";
import {
  AlertState,
  COOLDOWN_HOURS,
  clearKey,
  loadAlertState,
  markFired,
  saveAlertState,
  shouldFire,
} from "./alert-state.js";
import {
  cashCrunchAlert,
  cashoutGapAlert,
  payoutOverdueAlert,
  rtoSpikeAlert,
} from "./bosta-alerts.js";

const db = () => getFirestore();

/** One per-user alert check. */
type AlertStep = (
  uid: string,
  state: AlertState,
  updates: Record<string, unknown>,
  now: Date
) => Promise<void>;

/** Days of stock cover below which an item is "order now". */
const URGENCY_BUFFER_DAYS = 3;
/** Sales window used for the units/day estimate. */
const VELOCITY_DAYS = 28;
/** Supplier lead time assumed when the supplier record doesn't state one. */
const DEFAULT_LEAD_DAYS = 7;
const num = (v: unknown): number => (typeof v === "number" ? v : Number(v) || 0);
const round2 = (n: number): number => Math.round(n * 100) / 100;
const money = (n: number): string =>
  Math.round(n).toLocaleString("en-US");

interface VariantNeed {
  key: string; // productId:variantId
  productId: string;
  label: string;
  stock: number;
  velocity: number; // units/day
  daysOfCover: number;
  leadDays: number;
  slack: number; // daysOfCover − leadDays (negative = already late)
}

/**
 * Units sold per variant over the velocity window, keyed `productId:variantId`
 * (falling back to `productId:` when a line has no variant, as manual and
 * legacy sales often don't). Cancelled orders are excluded.
 */
async function salesVelocity(uid: string, since: Date): Promise<Map<string, number>> {
  const snap = await db()
    .collection("sales")
    .where("user_id", "==", uid)
    .where("date", ">=", Timestamp.fromDate(since))
    .get();

  const units = new Map<string, number>();
  snap.forEach((doc) => {
    const s = doc.data();
    if (s.order_status === 4 || s.order_status === "cancelled") return;
    for (const item of (s.items ?? []) as Record<string, unknown>[]) {
      const pid = (item.product_id as string) ?? "";
      if (!pid) continue;
      const vid = (item.variant_id as string) ?? "";
      const key = `${pid}:${vid}`;
      units.set(key, (units.get(key) ?? 0) + num(item.quantity));
    }
  });
  return units;
}

/** Inventory alert: what to reorder, ranked by urgency against lead time. */
async function inventoryAlerts(
  uid: string,
  state: AlertState,
  updates: Record<string, unknown>,
  now: Date
): Promise<void> {
  const [products, suppliers, velocityMap] = await Promise.all([
    db().collection("products").where("user_id", "==", uid).get(),
    db().collection("suppliers").where("user_id", "==", uid).get(),
    salesVelocity(uid, new Date(now.getTime() - VELOCITY_DAYS * 86400_000)),
  ]);

  // Products reference their supplier by NAME, not id.
  const leadByName = new Map<string, number>();
  suppliers.forEach((d) => {
    const s = d.data();
    const name = String(s.name ?? "").toLowerCase().trim();
    if (name) leadByName.set(name, num(s.lead_time_days) || DEFAULT_LEAD_DAYS);
  });

  const needs: VariantNeed[] = [];
  products.forEach((doc) => {
    const p = doc.data();
    const leadDays =
      leadByName.get(String(p.supplier ?? "").toLowerCase().trim()) ??
      DEFAULT_LEAD_DAYS;

    for (const v of (p.variants ?? []) as Record<string, unknown>[]) {
      const stock = num(v.current_stock);
      const reorder = num(v.reorder_point) || 10;
      const vid = (v.id as string) ?? "";
      // Velocity may be recorded against the variant or (legacy) the product.
      const velocity =
        ((velocityMap.get(`${doc.id}:${vid}`) ?? 0) +
          (vid ? 0 : velocityMap.get(`${doc.id}:`) ?? 0)) /
        VELOCITY_DAYS;

      // A slow/dead item below its reorder point is not urgent — it's dead
      // capital, reported by the weekly digest instead.
      if (velocity <= 0) continue;
      if (stock > reorder && stock / velocity > leadDays + URGENCY_BUFFER_DAYS) {
        // Comfortably covered; make sure a previous alert re-arms.
        clearKey(state, updates, `stockout:${doc.id}:${vid}`);
        continue;
      }

      const optionValues = (v.option_values ?? {}) as Record<string, string>;
      const variantName = Object.values(optionValues).join(" / ");
      const daysOfCover = velocity > 0 ? stock / velocity : Infinity;
      needs.push({
        key: `${doc.id}:${vid}`,
        productId: doc.id,
        label: variantName ? `${p.name} (${variantName})` : String(p.name ?? ""),
        stock,
        velocity,
        daysOfCover,
        leadDays,
        slack: daysOfCover - leadDays,
      });
    }
  });

  if (needs.length === 0) return;

  // Most negative slack first — those are already past the point of no return.
  needs.sort((a, b) => a.slack - b.slack);
  const urgent = needs.filter((n) => n.slack <= URGENCY_BUFFER_DAYS);
  if (urgent.length === 0) return;

  // Fire only when at least one urgent item is outside its cooldown, so a
  // long-running shortage doesn't re-notify every morning.
  const fresh = urgent.filter((n) =>
    shouldFire(state, `stockout:${n.key}`, now)
  );
  if (fresh.length === 0) return;

  const worst = urgent[0];
  for (const n of urgent) {
    markFired(state, updates, `stockout:${n.key}`, COOLDOWN_HOURS.stockoutForecast, now);
  }

  await notifyUser(
    uid,
    "",
    "",
    {
      type: "stockout_forecast",
      product_id: worst.productId,
      count: String(urgent.length),
    },
    "low_stock",
    {
      msg: {
        type: "stockout_forecast",
        params: {
          worst: worst.label,
          days: String(Math.max(0, Math.floor(worst.daysOfCover))),
          supplier: "your supplier",
          lead: String(worst.leadDays),
          count: String(urgent.length),
        },
      },
    }
  );
  logger.info("dailyAlerts: stockout", {uid, urgent: urgent.length});
}

/** Accrued expenses that are due within a week or already overdue. */
async function accruedAlerts(
  uid: string,
  state: AlertState,
  updates: Record<string, unknown>,
  now: Date
): Promise<void> {
  const snap = await db()
    .collection("accrued_expenses")
    .doc(uid)
    .collection("items")
    .get();

  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const due: {name: string; amount: number; overdue: boolean; id: string}[] = [];

  snap.forEach((doc) => {
    const a = doc.data();
    if (a.status === "settled") return;
    const outstanding = num(a.amount);
    if (outstanding <= 0.01) {
      clearKey(state, updates, `accrued_due:${doc.id}`);
      return;
    }
    const raw = a.due_date as string | undefined;
    if (!raw) return; // no deadline → nothing to remind about
    const d = new Date(raw);
    const days = Math.round((d.getTime() - today.getTime()) / 86400_000);
    if (days > 7) {
      clearKey(state, updates, `accrued_due:${doc.id}`);
      return;
    }
    due.push({
      name: String(a.name ?? ""),
      amount: outstanding,
      overdue: days < 0,
      id: doc.id,
    });
  });

  const fresh = due.filter((d) => shouldFire(state, `accrued_due:${d.id}`, now));
  if (fresh.length === 0) return;

  due.sort((a, b) => b.amount - a.amount);
  const total = due.reduce((s, d) => s + d.amount, 0);
  for (const d of due) {
    markFired(state, updates, `accrued_due:${d.id}`, COOLDOWN_HOURS.dueReminder, now);
  }

  await notifyUser(
    uid,
    "",
    "",
    {type: "accrued_due", count: String(due.length)},
    "payment_reminders",
    {
      msg: {
        type: "accrued_due",
        params: {
          count: String(due.length),
          total: money(total),
          worst: due[0].name,
          status: due[0].overdue ? "overdue" : "due soon",
        },
      },
    }
  );
}

/** Gateways sitting on money longer than their stated payout cycle. */
async function gatewayAlerts(
  uid: string,
  state: AlertState,
  updates: Record<string, unknown>,
  now: Date
): Promise<void> {
  const snap = await db()
    .collection("gateway_receivables")
    .doc(uid)
    .collection("items")
    .get();

  for (const doc of snap.docs) {
    const g = doc.data();
    const key = `gateway_overdue:${doc.id}`;
    const pending = num(g.pending_balance);
    const cycle = num(g.settlement_days);
    if (g.status !== "active" || pending <= 0.01 || cycle <= 0) {
      clearKey(state, updates, key);
      continue;
    }

    const settlements = (g.settlements ?? []) as Record<string, unknown>[];
    let lastMs = 0;
    for (const s of settlements) {
      const t = new Date(String(s.date ?? "")).getTime();
      if (!Number.isNaN(t) && t > lastMs) lastMs = t;
    }
    // Never settled → measure from when the account was created.
    if (lastMs === 0) lastMs = new Date(String(g.created_at ?? now)).getTime();
    const days = Math.floor((now.getTime() - lastMs) / 86400_000);

    if (days <= cycle) {
      clearKey(state, updates, key);
      continue;
    }
    if (!shouldFire(state, key, now)) continue;
    markFired(state, updates, key, COOLDOWN_HOURS.payoutOverdue, now);

    await notifyUser(
      uid,
      "",
      "",
      {type: "gateway_overdue", gateway_id: doc.id},
      "payment_reminders",
      {
        msg: {
          type: "gateway_overdue",
          params: {
            name: String(g.gateway_name ?? "Gateway"),
            pending: money(pending),
            days: String(days),
            cycle: String(cycle),
          },
        },
      }
    );
  }
}

/** Salaries still unpaid for the current month (only late in the month). */
async function salaryAlerts(
  uid: string,
  state: AlertState,
  updates: Record<string, unknown>,
  now: Date
): Promise<void> {
  if (now.getDate() < 25) return; // pointless to nag mid-month

  const snap = await db().collection("salaries").doc(uid).collection("items").get();
  const period = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
  let owed = 0;
  let count = 0;

  snap.forEach((doc) => {
    const s = doc.data();
    if (s.status !== "active") return;
    const monthly = num(s.monthly_salary);
    if (monthly <= 0) return;
    const paid = ((s.payments ?? []) as Record<string, unknown>[]).reduce((sum, p) => {
      const d = new Date(String(p.date ?? ""));
      const inMonth =
        d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth();
      return sum + (inMonth ? num(p.amount) : 0);
    }, 0);
    const remaining = round2(monthly - paid);
    if (remaining > 0.01) {
      owed += remaining;
      count++;
    }
  });

  const key = `salary_unpaid:${period}`;
  if (count === 0) {
    clearKey(state, updates, key);
    return;
  }
  if (!shouldFire(state, key, now)) return;
  markFired(state, updates, key, COOLDOWN_HOURS.dueReminder, now);

  await notifyUser(
    uid,
    "",
    "",
    {type: "salary_unpaid", period},
    "payment_reminders",
    {
      msg: {
        type: "salary_unpaid",
        params: {count: String(count), total: money(owed), month: period},
      },
    }
  );
}

/**
 * Supplier money owed for goods ALREADY RECEIVED.
 *
 * Deliberately not due-date based: no purchase in the live data sets one, so a
 * due-date reminder would be silent forever. Accrued payable is the honest
 * signal — value received minus paid, minus unapplied credits (the same rule
 * the app's supplier screens use).
 */
async function supplierAlerts(
  uid: string,
  state: AlertState,
  updates: Record<string, unknown>,
  now: Date
): Promise<void> {
  const [purchases, payments] = await Promise.all([
    db().collection("purchases").where("user_id", "==", uid).get(),
    db().collection("payments").where("user_id", "==", uid).get(),
  ]);

  const credits = new Map<string, number>();
  payments.forEach((doc) => {
    const p = doc.data();
    const applied = (p.applied_to_purchase_ids ?? []) as string[];
    if (applied.length > 0) return;
    const sid = String(p.supplier_id ?? "");
    credits.set(sid, (credits.get(sid) ?? 0) + num(p.amount));
  });

  const payableBySupplier = new Map<string, {name: string; amount: number}>();
  purchases.forEach((doc) => {
    const p = doc.data();
    const items = (p.items ?? []) as Record<string, unknown>[];
    const received = items.reduce(
      (s, i) => s + num(i.received_qty) * num(i.unit_price), 0);
    const payable = Math.max(0, received - num(p.amount_paid));
    if (payable <= 0.01) return;
    const sid = String(p.supplier_id ?? "");
    const cur = payableBySupplier.get(sid) ?? {
      name: String(p.supplier_name ?? "Supplier"),
      amount: 0,
    };
    cur.amount += payable;
    payableBySupplier.set(sid, cur);
  });

  const owing: {name: string; amount: number; id: string}[] = [];
  for (const [sid, v] of payableBySupplier) {
    const net = round2(v.amount - (credits.get(sid) ?? 0));
    const key = `supplier_due:${sid}`;
    if (net <= 0.01) {
      clearKey(state, updates, key);
      continue;
    }
    owing.push({name: v.name, amount: net, id: sid});
  }
  if (owing.length === 0) return;

  const fresh = owing.filter((o) => shouldFire(state, `supplier_due:${o.id}`, now));
  if (fresh.length === 0) return;

  owing.sort((a, b) => b.amount - a.amount);
  const total = owing.reduce((s, o) => s + o.amount, 0);
  for (const o of owing) {
    markFired(state, updates, `supplier_due:${o.id}`, COOLDOWN_HOURS.dueReminder, now);
  }

  await notifyUser(
    uid,
    "",
    "",
    {type: "supplier_due", count: String(owing.length)},
    "payment_reminders",
    {
      msg: {
        type: "supplier_due",
        params: {
          count: String(owing.length),
          total: money(total),
          worst: `${owing[0].name} ${money(owing[0].amount)}`,
        },
      },
    }
  );
}

/** Runs every per-user check, isolating failures so one user can't stop the run. */
export async function runDailyAlertsForUser(uid: string, now = new Date()): Promise<void> {
  const state = await loadAlertState(uid);
  const updates: Record<string, unknown> = {};

  // Sequential, each guarded: a step that throws must not abort the rest, and
  // must not become an unhandled rejection (which it would if every step were
  // started eagerly and awaited later).
  const steps: [string, AlertStep][] = Object.entries({
    inventory: inventoryAlerts,
    accrued: accruedAlerts,
    gateway: gatewayAlerts,
    salary: salaryAlerts,
    supplier: supplierAlerts,
    // Bosta / cash-derived steps run against data the nightly sync refreshed.
    payout: payoutOverdueAlert,
    rtoSpike: rtoSpikeAlert,
    cashCrunch: cashCrunchAlert,
    cashoutGap: cashoutGapAlert,
  });
  for (const [name, fn] of steps) {
    try {
      await fn(uid, state, updates, now);
    } catch (err) {
      logger.error("dailyAlerts: step failed", {uid, step: name, err});
    }
  }

  await saveAlertState(uid, updates);
}

export const dailyAlertsScan = onSchedule(
  {
    schedule: "15 9 * * *",
    timeZone: "Africa/Cairo",
    region: "us-central1",
    maxInstances: 1,
    timeoutSeconds: 540,
  },
  async () => {
    const users = await db().collection("users").get();
    let scanned = 0;
    for (const doc of users.docs) {
      try {
        await runDailyAlertsForUser(doc.id);
        scanned++;
      } catch (err) {
        logger.error("dailyAlertsScan: user failed", {uid: doc.id, err});
      }
    }
    logger.info("dailyAlertsScan: complete", {scanned});
  }
);
