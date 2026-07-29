/**
 * weekly-digest.ts — Monday-morning summary plus the data-health checks.
 *
 * Two jobs in one weekly pass:
 *
 *  1. **The digest** (S13/S14) — how last week actually went, plus capital
 *     sitting still in stock nobody is buying.
 *  2. **Integrity nudges** (N1–N4) — the class of quiet bookkeeping decay that
 *     this project spent a long session unpicking by hand: sales with no COGS,
 *     goods received but never billed, cash drifting away from the ledger, and
 *     duplicate entries. Caught at a week old they are a two-minute fix; found
 *     at year-end they are an archaeology project.
 *
 * It also refreshes the rolling baselines other alerts compare against, and
 * prunes expired dedup keys.
 */

import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {notifyUser} from "../notify.js";
import {computeClosingCash, parseTxnDate, round2} from "../cash-engine.js";
import {loadAlertState, pruneFired, saveAlertState, shouldFire, markFired} from "./alert-state.js";

const db = () => getFirestore();

/** Ignore dead-stock noise below this value. */
const DEAD_CAPITAL_FLOOR = 1000;
/** Days without a sale before stock counts as dead. */
const DEAD_DAYS = 30;
/** Only look this far back for sales missing their COGS entry. */
const COGS_LOOKBACK_DAYS = 90;

const num = (v: unknown): number => (typeof v === "number" ? v : Number(v) || 0);
const money = (n: number): string => Math.round(n).toLocaleString("en-US");

/** ISO week key, e.g. 2026-W31 — a natural once-per-week dedup key. */
function isoWeek(d: Date): string {
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  const week = Math.ceil(((t.getTime() - yearStart.getTime()) / 86400_000 + 1) / 7);
  return `${t.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}

interface SaleLite {
  id: string;
  date: Date;
  revenue: number;
  cancelled: boolean;
  items: Record<string, unknown>[];
}

/** Loads sales in a window, flattened to what the digest needs. */
async function loadSales(uid: string, since: Date): Promise<SaleLite[]> {
  const snap = await db()
    .collection("sales")
    .where("user_id", "==", uid)
    .where("date", ">=", Timestamp.fromDate(since))
    .get();
  const out: SaleLite[] = [];
  snap.forEach((doc) => {
    const s = doc.data();
    const items = (s.items ?? []) as Record<string, unknown>[];
    const gross = items.reduce(
      (sum, i) => sum + num(i.unit_price) * num(i.quantity),
      0
    );
    out.push({
      id: doc.id,
      date: (s.date as Timestamp)?.toDate() ?? new Date(0),
      revenue:
        gross - num(s.discount_amount) + num(s.tax_amount) + num(s.shipping_cost),
      cancelled: s.order_status === 4 || s.order_status === "cancelled",
      items,
    });
  });
  return out;
}

/** N1 — sales with no COGS entry in the ledger (the authoritative check). */
async function missingCogs(uid: string, sales: SaleLite[]): Promise<{count: number; revenue: number}> {
  const cogsSnap = await db()
    .collection("transactions")
    .where("user_id", "==", uid)
    .where("category_id", "==", "cat_cogs")
    .get();
  const withCogs = new Set<string>();
  cogsSnap.forEach((d) => {
    const sid = d.data().sale_id as string | undefined;
    if (sid) withCogs.add(sid);
  });

  let count = 0;
  let revenue = 0;
  for (const s of sales) {
    if (s.cancelled || s.revenue <= 0) continue;
    if (withCogs.has(s.id)) continue;
    count++;
    revenue += s.revenue;
  }
  return {count, revenue: round2(revenue)};
}

/** N2 — goods received but never paid for and never even part-billed. */
async function receivedNotBilled(uid: string): Promise<{count: number; total: number}> {
  const snap = await db().collection("purchases").where("user_id", "==", uid).get();
  let count = 0;
  let total = 0;
  snap.forEach((doc) => {
    const p = doc.data();
    if (num(p.payment_status) !== 0) return; // 0 = unpaid
    const received = ((p.items ?? []) as Record<string, unknown>[]).reduce(
      (s, i) => s + num(i.received_qty) * num(i.unit_price),
      0
    );
    if (received <= 0) return;
    count++;
    total += received;
  });
  return {count, total: round2(total)};
}

/**
 * N4 — same amount, same category, same day, more than once.
 * Auto-generated rows (sale/bosta pipelines) legitimately repeat, so they are
 * excluded; this is aimed at human double-entry.
 */
async function duplicateTransactions(uid: string, since: Date): Promise<number> {
  const snap = await db().collection("transactions").where("user_id", "==", uid).get();
  const groups = new Map<string, number>();
  snap.forEach((doc) => {
    const t = doc.data();
    if (doc.id.startsWith("sale_") || doc.id.startsWith("bosta_")) return;
    if (t.sale_id) return;
    const d = parseTxnDate(t.date_time ?? t.date);
    if (!d || d < since) return;
    const key = [
      Math.round(num(t.amount) * 100),
      t.category_id ?? "",
      d.toISOString().substring(0, 10),
    ].join("|");
    groups.set(key, (groups.get(key) ?? 0) + 1);
  });
  let dupes = 0;
  for (const n of groups.values()) if (n > 1) dupes += n - 1;
  return dupes;
}

/** S14 — stock with value but no movement for a month. */
async function deadCapital(
  uid: string,
  sales: SaleLite[]
): Promise<{count: number; total: number; worst: string}> {
  const sold = new Set<string>();
  for (const s of sales) {
    if (s.cancelled) continue;
    for (const i of s.items) {
      const pid = i.product_id as string | undefined;
      if (pid) sold.add(`${pid}:${(i.variant_id as string) ?? ""}`);
    }
  }

  const products = await db().collection("products").where("user_id", "==", uid).get();
  const idle: {label: string; value: number}[] = [];
  products.forEach((doc) => {
    const p = doc.data();
    for (const v of (p.variants ?? []) as Record<string, unknown>[]) {
      const stock = num(v.current_stock);
      if (stock <= 0) continue;
      const key = `${doc.id}:${(v.id as string) ?? ""}`;
      if (sold.has(key)) continue;
      const value = stock * num(v.cost_price);
      if (value < DEAD_CAPITAL_FLOOR) continue;
      const opts = Object.values((v.option_values ?? {}) as Record<string, string>);
      idle.push({
        label: opts.length ? `${p.name} (${opts.join(" / ")})` : String(p.name ?? ""),
        value,
      });
    }
  });
  idle.sort((a, b) => b.value - a.value);
  return {
    count: idle.length,
    total: round2(idle.reduce((s, i) => s + i.value, 0)),
    worst: idle[0]?.label ?? "",
  };
}

/** Median hours between consecutive orders — feeds the silence detector. */
function medianOrderGapHours(sales: SaleLite[]): number {
  const times = sales
    .filter((s) => !s.cancelled)
    .map((s) => s.date.getTime())
    .sort((a, b) => a - b);
  if (times.length < 3) return 24;
  const gaps: number[] = [];
  for (let i = 1; i < times.length; i++) {
    gaps.push((times[i] - times[i - 1]) / 3600_000);
  }
  gaps.sort((a, b) => a - b);
  return round2(gaps[Math.floor(gaps.length / 2)]);
}

export async function runWeeklyDigestForUser(uid: string, now = new Date()): Promise<void> {
  const state = await loadAlertState(uid);
  const updates: Record<string, unknown> = {};
  const weekKey = `digest:${isoWeek(now)}`;
  if (!shouldFire(state, weekKey, now)) return;

  const prefs =
    ((await db().collection("users").doc(uid).get()).data()?.notification_prefs ??
      {}) as Record<string, boolean>;

  const weekAgo = new Date(now.getTime() - 7 * 86400_000);
  const twoWeeks = new Date(now.getTime() - 14 * 86400_000);
  const deadWindow = new Date(now.getTime() - DEAD_DAYS * 86400_000);
  const cogsWindow = new Date(now.getTime() - COGS_LOOKBACK_DAYS * 86400_000);

  const [recent, longSales, cogs, unbilled, dupes] = await Promise.all([
    loadSales(uid, twoWeeks),
    loadSales(uid, deadWindow),
    loadSales(uid, cogsWindow).then((s) => missingCogs(uid, s)),
    receivedNotBilled(uid),
    duplicateTransactions(uid, weekAgo),
  ]);

  // ── S13 trend ──
  const thisWeek = recent.filter((s) => !s.cancelled && s.date >= weekAgo);
  const lastWeek = recent.filter((s) => !s.cancelled && s.date < weekAgo);
  const revThis = round2(thisWeek.reduce((s, x) => s + x.revenue, 0));
  const revLast = round2(lastWeek.reduce((s, x) => s + x.revenue, 0));
  const trend = revLast > 0 ? ((revThis - revLast) / revLast) * 100 : 0;

  // ── S14 dead capital ──
  const dead = await deadCapital(uid, longSales);

  // ── N3 cash drift ──
  // A full recompute vs the app's own reconciled figure; a growing gap is the
  // early warning that unrecorded movements are piling up again.
  let driftNote = "";
  try {
    const pos = await computeClosingCash(uid, now);
    const prevDrift = num(state.baselines?.last_cash_drift);
    updates["baselines.last_cash_drift"] = pos.closingCash;
    if (prevDrift > 0) {
      const delta = round2(pos.closingCash - prevDrift);
      if (Math.abs(delta) > 0) {
        driftNote = `cash ${delta >= 0 ? "+" : ""}${money(delta)} vs last week`;
      }
    }
  } catch (err) {
    logger.error("weeklyDigest: cash drift failed", {uid, err});
  }

  // ── Baselines + housekeeping ──
  updates["baselines.median_order_gap_hours"] = medianOrderGapHours(recent);
  const bestDay = num(state.baselines?.best_day_revenue);
  const byDay = new Map<string, number>();
  for (const s of thisWeek) {
    const k = s.date.toISOString().substring(0, 10);
    byDay.set(k, (byDay.get(k) ?? 0) + s.revenue);
  }
  const topDay = Math.max(0, ...byDay.values());
  const isRecord = topDay > bestDay;
  if (isRecord) updates["baselines.best_day_revenue"] = round2(topDay);
  updates["baselines.last_week_revenue"] = revThis;
  pruneFired(state, updates, now);

  // ── Send: digest, integrity nudge, or both ──
  const integrityBits: string[] = [];
  if (cogs.count > 0) integrityBits.push(`${cogs.count} sales missing COGS`);
  if (unbilled.count > 0) {
    integrityBits.push(`${unbilled.count} received-not-paid (${money(unbilled.total)})`);
  }
  if (dupes > 0) integrityBits.push(`${dupes} possible duplicate entries`);

  const wantsDigest = prefs.weekly_digest !== false;
  const wantsIntegrity = prefs.data_integrity !== false;

  if (wantsDigest) {
    const extras: string[] = [];
    if (isRecord && topDay > 0) extras.push(`record day ${money(topDay)}`);
    if (dead.count > 0) {
      extras.push(`${money(dead.total)} idle stock`);
    }
    if (driftNote) extras.push(driftNote);
    if (integrityBits.length > 0 && !wantsIntegrity) {
      extras.push(integrityBits.join(", "));
    }

    await notifyUser(
      uid,
      "",
      "",
      {type: "weekly_digest", week: isoWeek(now)},
      "weekly_digest",
      {
        msg: {
          type: "weekly_digest",
          params: {
            business: "your store",
            revenue: money(revThis),
            trend: (trend >= 0 ? "+" : "") + trend.toFixed(0),
            orders: String(thisWeek.length),
            extra: extras.join(" · ") || "no issues flagged",
          },
        },
      }
    );
  }

  if (wantsIntegrity && integrityBits.length > 0) {
    await notifyUser(
      uid,
      "",
      "",
      {type: "integrity_nudge", week: isoWeek(now)},
      "data_integrity",
      {
        msg: {
          type: "integrity_nudge",
          params: {
            count: String(integrityBits.length),
            summary: integrityBits.join(" · "),
          },
        },
      }
    );
  }

  markFired(state, updates, weekKey, 24 * 6, now); // once per ISO week
  await saveAlertState(uid, updates);
  logger.info("weeklyDigest", {uid, revThis, integrity: integrityBits.length});
}

export const weeklyDigest = onSchedule(
  {
    schedule: "30 9 * * 1",
    timeZone: "Africa/Cairo",
    region: "us-central1",
    maxInstances: 1,
    timeoutSeconds: 540,
  },
  async () => {
    const users = await db().collection("users").get();
    let n = 0;
    for (const doc of users.docs) {
      try {
        await runWeeklyDigestForUser(doc.id);
        n++;
      } catch (err) {
        logger.error("weeklyDigest: user failed", {uid: doc.id, err});
      }
    }
    logger.info("weeklyDigest: complete", {users: n});
  }
);
