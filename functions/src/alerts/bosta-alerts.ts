/**
 * bosta-alerts.ts — money-protection alerts built on delivery + cash data.
 *
 *  S2  repeat COD refuser  — event-driven, the highest-value alert here:
 *      catches a doomed shipment BEFORE the courier is paid for the trip.
 *  S3  cash crunch         — obligations falling due vs cash actually available
 *  S4  payout overdue      — money sitting at Bosta longer than it should
 *  S5  RTO spike           — refusals running above this business's norm
 *  S12 cashout gap         — a payout that doesn't match what was expected
 *
 * The RTO phone index is maintained by the nightly sync rather than joined on
 * demand: shipments carry no customer phone (only `sale_id`), so answering
 * "has this number refused before?" live would mean a shipments→sales join per
 * order. Instead the join runs once per RTO, into `rto_index/{uid}`, and the
 * order-time check is a single document read.
 */

import {getFirestore, Timestamp} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {notifyUser} from "../notify.js";
import {computeClosingCash, parseTxnDate, round2} from "../cash-engine.js";
import {maskPhone, normalizeEgPhone} from "./phone.js";
import {
  AlertState,
  COOLDOWN_HOURS,
  clearKey,
  markFired,
  shouldFire,
} from "./alert-state.js";

const db = () => getFirestore();

/** Bosta states meaning the parcel came back: 46 returned, 60 RTO. */
const RTO_STATES = [46, 60];
/** Days past the usual cadence before a payout counts as late. */
const PAYOUT_GRACE_DAYS = 8;
/** Horizon for the cash-crunch forecast. */
const OBLIGATION_DAYS = 14;
/** Share of pending COD assumed collectable (the rest is refused/returned). */
const AR_HAIRCUT = 0.8;
/** Refusals must exceed this multiple of the norm AND the floor below. */
const RTO_SPIKE_FACTOR = 1.5;
const RTO_SPIKE_FLOOR = 3;

const num = (v: unknown): number => (typeof v === "number" ? v : Number(v) || 0);
const money = (n: number): string => Math.round(n).toLocaleString("en-US");
const daysBetween = (a: Date, b: Date): number =>
  Math.floor((a.getTime() - b.getTime()) / 86400_000);

// ═══════════════════════════════════════════════════════════
//  RTO phone index (maintained during the nightly Bosta sync)
// ═══════════════════════════════════════════════════════════

/**
 * Folds newly-returned shipments into `rto_index/{uid}` so the order-time
 * check stays a single read. Shipments already counted are marked
 * `rto_indexed` and skipped, so this is cheap after the first (backfill) run.
 */
export async function updateRtoIndex(uid: string): Promise<number> {
  const snap = await db()
    .collection("bosta_shipments")
    .where("user_id", "==", uid)
    .where("state", "in", RTO_STATES)
    .get();

  const pending = snap.docs.filter((d) => d.data().rto_indexed !== true);
  if (pending.length === 0) return 0;

  // Resolve customer phones through the linked sale.
  const saleIds = [
    ...new Set(
      pending
        .map((d) => d.data().sale_id as string | undefined)
        .filter((s): s is string => !!s)
    ),
  ];
  const phoneBySale = new Map<string, string>();
  for (let i = 0; i < saleIds.length; i += 300) {
    const refs = saleIds
      .slice(i, i + 300)
      .map((id) => db().collection("sales").doc(id));
    const docs = await db().getAll(...refs);
    for (const doc of docs) {
      const phone = normalizeEgPhone(doc.data()?.customer_phone as string);
      if (phone) phoneBySale.set(doc.id, phone);
    }
  }

  const ref = db().collection("rto_index").doc(uid);
  const existing = (await ref.get()).data() ?? {};
  const phones = (existing.phones ?? {}) as Record<
    string,
    {count: number; last_rto_at: Timestamp; sample_tracking?: string}
  >;

  let added = 0;
  let batch = db().batch();
  let ops = 0;
  for (const doc of pending) {
    const d = doc.data();
    const phone = d.sale_id ? phoneBySale.get(d.sale_id as string) : undefined;
    if (phone) {
      const cur = phones[phone];
      const at = (d.bosta_created_at as Timestamp) ?? Timestamp.now();
      phones[phone] = {
        count: (cur?.count ?? 0) + 1,
        last_rto_at:
          cur && cur.last_rto_at && cur.last_rto_at.toMillis() > at.toMillis()
            ? cur.last_rto_at
            : at,
        sample_tracking: (d.tracking_number as string) ?? cur?.sample_tracking,
      };
      added++;
    }
    // Mark even unmatched shipments so they aren't re-examined every night.
    batch.update(doc.ref, {rto_indexed: true});
    if (++ops >= 400) {
      await batch.commit();
      batch = db().batch();
      ops = 0;
    }
  }
  if (ops > 0) await batch.commit();

  await ref.set(
    {phones, backfilled: true, updated_at: Timestamp.now()},
    {merge: true}
  );
  logger.info("updateRtoIndex", {uid, examined: pending.length, added});
  return added;
}

// ═══════════════════════════════════════════════════════════
//  S2 + S15 — checks that run the moment an order is created
// ═══════════════════════════════════════════════════════════

/**
 * Warns when a new order comes from a number that has refused delivery
 * before, and celebrates a customer's 4th order. Safe to call on every sale;
 * it exits quickly when there's no phone.
 */
export async function checkNewSaleAlerts(
  uid: string,
  saleId: string,
  sale: Record<string, unknown>
): Promise<void> {
  const phone = normalizeEgPhone(sale.customer_phone as string);
  if (!phone) return;

  // ── S2 repeat refuser ──
  try {
    const idx = (await db().collection("rto_index").doc(uid).get()).data();
    const entry = (idx?.phones ?? {})[phone] as
      | {count: number; last_rto_at?: Timestamp}
      | undefined;
    if (entry && entry.count > 0) {
      const last = entry.last_rto_at?.toDate();
      await notifyUser(
        uid,
        "",
        "",
        {type: "repeat_refuser", sale_id: saleId, phone: maskPhone(phone)},
        "deliveries",
        {
          msg: {
            type: "repeat_refuser",
            params: {
              phone: maskPhone(phone),
              count: String(entry.count),
              last: last ? last.toISOString().substring(0, 10) : "—",
            },
          },
        }
      );
      logger.info("repeat refuser flagged", {uid, saleId, count: entry.count});
    }
  } catch (err) {
    logger.error("checkNewSaleAlerts: refuser check failed", {uid, err});
  }

  // ── S15 VIP (4th order) ──
  try {
    const agg = await db()
      .collection("sales")
      .where("user_id", "==", uid)
      .where("customer_phone", "==", sale.customer_phone as string)
      .count()
      .get();
    if (agg.data().count === 4) {
      await notifyUser(
        uid,
        "",
        "",
        {type: "vip_customer", sale_id: saleId},
        "insights",
        {
          msg: {
            type: "vip_customer",
            params: {
              name: String(sale.customer_name ?? maskPhone(phone)),
              n: "4",
            },
          },
        }
      );
    }
  } catch (err) {
    logger.error("checkNewSaleAlerts: vip check failed", {uid, err});
  }
}

// ═══════════════════════════════════════════════════════════
//  Scheduled steps (called from dailyAlertsScan)
// ═══════════════════════════════════════════════════════════

/** S4 — Bosta holding collected COD longer than the usual payout cadence. */
export async function payoutOverdueAlert(
  uid: string,
  state: AlertState,
  updates: Record<string, unknown>,
  now: Date
): Promise<void> {
  const conn = (await db().collection("bosta_connections").doc(uid).get()).data();
  if (!conn || conn.status !== "active") return;

  const pending = num(conn.cf_pending_ar);
  const key = "payout_overdue";
  const lastRaw = conn.cf_last_cashout_date as string | undefined;
  if (pending <= 0 || !lastRaw) {
    clearKey(state, updates, key);
    return;
  }
  const days = daysBetween(now, new Date(lastRaw));
  if (days <= PAYOUT_GRACE_DAYS) {
    clearKey(state, updates, key);
    return;
  }
  if (!shouldFire(state, key, now)) return;
  markFired(state, updates, key, COOLDOWN_HOURS.payoutOverdue, now);

  await notifyUser(
    uid,
    "",
    "",
    {type: "payout_overdue"},
    "payment_reminders",
    {
      msg: {
        type: "payout_overdue",
        params: {pending: money(pending), days: String(days)},
      },
    }
  );
}

/** S5 — refusals running above this business's own 28-day norm. */
export async function rtoSpikeAlert(
  uid: string,
  state: AlertState,
  updates: Record<string, unknown>,
  now: Date
): Promise<void> {
  const since = new Date(now.getTime() - 28 * 86400_000);
  const snap = await db()
    .collection("bosta_shipments")
    .where("user_id", "==", uid)
    .where("bosta_created_at", ">=", Timestamp.fromDate(since))
    .select("state", "bosta_created_at")
    .get();

  if (snap.size < 20) return; // too little traffic for a rate to mean anything

  const weekAgo = new Date(now.getTime() - 7 * 86400_000);
  let total28 = 0;
  let rto28 = 0;
  let total7 = 0;
  let rto7 = 0;
  snap.forEach((doc) => {
    const d = doc.data();
    const isRto = RTO_STATES.includes(num(d.state));
    total28++;
    if (isRto) rto28++;
    const created = (d.bosta_created_at as Timestamp)?.toDate();
    if (created && created >= weekAgo) {
      total7++;
      if (isRto) rto7++;
    }
  });

  if (total7 === 0) return;
  const rate7 = (rto7 / total7) * 100;
  const baseline =
    num(state.baselines?.rto_rate_28d) || (total28 > 0 ? (rto28 / total28) * 100 : 0);

  // Keep the rolling baseline fresh regardless of whether we alert.
  updates["baselines.rto_rate_28d"] = round2(
    total28 > 0 ? (rto28 / total28) * 100 : 0
  );

  const key = "rto_spike";
  if (rto7 < RTO_SPIKE_FLOOR || baseline <= 0 || rate7 <= baseline * RTO_SPIKE_FACTOR) {
    clearKey(state, updates, key);
    return;
  }
  if (!shouldFire(state, key, now)) return;
  markFired(state, updates, key, COOLDOWN_HOURS.rtoSpike, now);

  await notifyUser(
    uid,
    "",
    "",
    {type: "rto_spike"},
    "deliveries",
    {
      msg: {
        type: "rto_spike",
        params: {
          count: String(rto7),
          rate: rate7.toFixed(1),
          baseline: baseline.toFixed(1),
        },
      },
    }
  );
}

/**
 * S3 — obligations falling due in the next fortnight vs cash actually
 * available (bank + gateway/COD money realistically collectable).
 */
export async function cashCrunchAlert(
  uid: string,
  state: AlertState,
  updates: Record<string, unknown>,
  now: Date
): Promise<void> {
  const horizon = new Date(now.getTime() + OBLIGATION_DAYS * 86400_000);
  const horizonKey = horizon.toISOString().substring(0, 10);
  const monthKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;

  const [cash, conn, purchases, payments, accrued, salaries, loans] =
    await Promise.all([
      computeClosingCash(uid),
      db().collection("bosta_connections").doc(uid).get(),
      db().collection("purchases").where("user_id", "==", uid).get(),
      db().collection("payments").where("user_id", "==", uid).get(),
      db().collection("accrued_expenses").doc(uid).collection("items").get(),
      db().collection("salaries").doc(uid).collection("items").get(),
      db().collection("loans").doc(uid).collection("items").get(),
    ]);

  // ── Obligations ──
  // Supplier payables: value received but unpaid, net of unapplied credits
  // (the same rule the app's supplier screens use).
  const credits = new Map<string, number>();
  payments.forEach((doc) => {
    const p = doc.data();
    if (((p.applied_to_purchase_ids ?? []) as string[]).length > 0) return;
    const sid = String(p.supplier_id ?? "");
    credits.set(sid, (credits.get(sid) ?? 0) + num(p.amount));
  });
  const payableBySupplier = new Map<string, number>();
  purchases.forEach((doc) => {
    const p = doc.data();
    const received = ((p.items ?? []) as Record<string, unknown>[]).reduce(
      (s, i) => s + num(i.received_qty) * num(i.unit_price),
      0
    );
    const payable = Math.max(0, received - num(p.amount_paid));
    if (payable <= 0) return;
    const sid = String(p.supplier_id ?? "");
    payableBySupplier.set(sid, (payableBySupplier.get(sid) ?? 0) + payable);
  });
  let supplierDue = 0;
  for (const [sid, amount] of payableBySupplier) {
    supplierDue += Math.max(0, amount - (credits.get(sid) ?? 0));
  }

  let accruedDue = 0;
  accrued.forEach((doc) => {
    const a = doc.data();
    if (a.status === "settled") return;
    const due = String(a.due_date ?? "").substring(0, 10);
    // No due date → treat as payable within the horizon (it's already owed).
    if (due && due > horizonKey) return;
    accruedDue += num(a.amount);
  });

  let salaryDue = 0;
  salaries.forEach((doc) => {
    const s = doc.data();
    if (s.status !== "active") return;
    const paidThisMonth = ((s.payments ?? []) as Record<string, unknown>[]).reduce(
      (sum, p) => {
        const d = parseTxnDate(p.date);
        return sum +
          (d &&
          d.getFullYear() === now.getFullYear() &&
          d.getMonth() === now.getMonth()
            ? num(p.amount)
            : 0);
      },
      0
    );
    salaryDue += Math.max(0, num(s.monthly_salary) - paidThisMonth);
  });

  let loanDue = 0;
  loans.forEach((doc) => {
    const l = doc.data();
    if (l.status !== "active") return;
    // No stored schedule — a monthly instalment falls inside any 14-day window
    // roughly half the time; count it when the balance is still outstanding.
    const outstanding =
      num(l.total_disbursed) > 0
        ? num(l.total_disbursed) - num(l.total_paid)
        : num(l.principal_amount) - num(l.total_paid);
    if (outstanding <= 0) return;
    const term = num(l.term_months) || 12;
    loanDue += Math.min(outstanding, num(l.principal_amount) / term);
  });

  const obligations = round2(supplierDue + accruedDue + salaryDue + loanDue);

  // ── Available ──
  const c = conn.data() ?? {};
  const available = round2(
    cash.closingCash +
      num(c.cf_wallet_balance) +
      num(c.cf_pending_ar) * AR_HAIRCUT
  );

  const key = "cash_crunch";
  if (obligations <= available) {
    clearKey(state, updates, key);
    return;
  }
  if (!shouldFire(state, key, now)) return;
  markFired(state, updates, key, COOLDOWN_HOURS.cashCrunch, now);

  await notifyUser(
    uid,
    "",
    "",
    {type: "cash_crunch", month: monthKey},
    "payment_reminders",
    {
      msg: {
        type: "cash_crunch",
        params: {
          obligations: money(obligations),
          available: money(available),
          gap: money(obligations - available),
        },
      },
    }
  );
  logger.info("cashCrunch", {uid, obligations, available});
}

/** S12 — a payout that doesn't match the COD it was supposed to settle. */
export async function cashoutGapAlert(
  uid: string,
  state: AlertState,
  updates: Record<string, unknown>,
  now: Date
): Promise<void> {
  const since = new Date(now.getTime() - 3 * 86400_000)
    .toISOString()
    .substring(0, 10);
  const cashouts = await db()
    .collection("bosta_cashouts")
    .where("user_id", "==", uid)
    .get();

  for (const doc of cashouts.docs) {
    const c = doc.data();
    const day = String(c.transaction_date ?? "").substring(0, 10);
    if (!day || day < since) continue;
    const key = `cashout_gap:${doc.id}`;
    if (!shouldFire(state, key, now)) continue;

    // Expected = COD minus fees on shipments settled that day.
    const start = new Date(`${day}T00:00:00Z`);
    const end = new Date(`${day}T23:59:59Z`);
    const ships = await db()
      .collection("bosta_shipments")
      .where("user_id", "==", uid)
      .where("deposited_at", ">=", Timestamp.fromDate(start))
      .where("deposited_at", "<=", Timestamp.fromDate(end))
      .select("cod", "total_fees")
      .get();
    if (ships.empty) continue;

    let expected = 0;
    ships.forEach((s) => {
      expected += num(s.data().cod) - num(s.data().total_fees);
    });
    const actual = num(c.amount);
    const gap = actual - expected;
    const tolerance = Math.max(100, Math.abs(expected) * 0.05);
    if (Math.abs(gap) <= tolerance) continue;

    markFired(state, updates, key, 24 * 365, now); // per-cashout, effectively once
    await notifyUser(
      uid,
      "",
      "",
      {type: "cashout_gap", cashout_id: String(c.transaction_id ?? doc.id)},
      "payment_reminders",
      {
        msg: {
          type: "cashout_gap",
          params: {
            actual: money(actual),
            expected: money(expected),
            gap: money(Math.abs(gap)),
          },
        },
      }
    );
  }
}
