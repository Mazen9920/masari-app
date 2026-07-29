/**
 * alert-state.ts — per-user dedup/cooldown state for smart alerts.
 *
 * Scheduled scans run daily, but a condition that stays true (stock stays low,
 * payout stays overdue) must not re-notify on every run. Each alert marks a
 * key in `notification_state/{uid}.fired` with an expiry; while the expiry is
 * in the future the alert is suppressed. When a scan observes the condition
 * RESOLVED it clears the key, so the alert re-arms immediately instead of
 * waiting out its cooldown — recovery is honest, suppression is not sticky.
 *
 * The document is server-only (no Firestore rules → default deny for clients).
 */

import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";

const db = () => getFirestore();

/** Hours before the same alert key may fire again while still true. */
export const COOLDOWN_HOURS = {
  lowStock: 7 * 24, // per variant
  stockoutForecast: 7 * 24, // per variant
  cashCrunch: 3 * 24,
  payoutOverdue: 3 * 24,
  rtoSpike: 7 * 24,
  dueReminder: 3 * 24, // S6-S9, per entity
  noOrders: 24,
  deadCapital: 30 * 24, // per product
} as const;

/** Entries whose cooldown expired longer ago than this are pruned weekly. */
const PRUNE_AFTER_DAYS = 90;

interface FiredEntry {
  at: Timestamp;
  until: Timestamp;
}

export interface AlertState {
  fired: Record<string, FiredEntry>;
  /** Incremental cash-engine cache (phase 4). */
  cash_cache?: {
    closing_cash: number;
    as_of: Timestamp;
    cashouts_through: string; // YYYY-MM-DD
  };
  /** Rolling baselines maintained by the weekly digest. */
  baselines?: {
    rto_rate_28d?: number;
    median_order_gap_hours?: number;
    best_day_revenue?: number;
    last_week_revenue?: number;
    last_cash_drift?: number;
  };
}

/** Loads the state doc, defaulting to empty on first contact. */
export async function loadAlertState(uid: string): Promise<AlertState> {
  const snap = await db().collection("notification_state").doc(uid).get();
  const data = (snap.data() ?? {}) as Partial<AlertState>;
  return {fired: data.fired ?? {}, cash_cache: data.cash_cache, baselines: data.baselines};
}

/** True when [key] has never fired or its cooldown has lapsed. */
export function shouldFire(state: AlertState, key: string, now: Date = new Date()): boolean {
  const entry = state.fired[key];
  if (!entry) return true;
  return entry.until.toDate() < now;
}

/**
 * Records that [key] fired, suppressing it for [cooldownHours]. Mutates the
 * in-memory state too so one scan pass sees its own marks.
 */
export function markFired(
  state: AlertState,
  updates: Record<string, unknown>,
  key: string,
  cooldownHours: number,
  now: Date = new Date()
): void {
  const at = Timestamp.fromDate(now);
  const until = Timestamp.fromDate(new Date(now.getTime() + cooldownHours * 3600_000));
  state.fired[key] = {at, until};
  updates[`fired.${key}`] = {at, until};
}

/** Clears [key] when its condition resolved, re-arming the alert. */
export function clearKey(
  state: AlertState,
  updates: Record<string, unknown>,
  key: string
): void {
  if (!state.fired[key]) return;
  delete state.fired[key];
  updates[`fired.${key}`] = FieldValue.delete();
}

/** Drops long-expired entries; returns how many were removed. */
export function pruneFired(
  state: AlertState,
  updates: Record<string, unknown>,
  now: Date = new Date()
): number {
  const cutoff = now.getTime() - PRUNE_AFTER_DAYS * 86400_000;
  let removed = 0;
  for (const [key, entry] of Object.entries(state.fired)) {
    if (entry.until.toDate().getTime() < cutoff) {
      clearKey(state, updates, key);
      removed++;
    }
  }
  return removed;
}

/**
 * Persists accumulated dot-path [updates] in one write. No-op when empty.
 * Uses set+merge so the first write creates the doc.
 */
export async function saveAlertState(
  uid: string,
  updates: Record<string, unknown>
): Promise<void> {
  if (Object.keys(updates).length === 0) return;
  const ref = db().collection("notification_state").doc(uid);
  // Dot-path keys require update(); fall back to set for a missing doc.
  try {
    await ref.update(updates);
  } catch {
    // Doc doesn't exist yet — expand "fired.x" paths into nested maps.
    const nested: Record<string, unknown> = {};
    for (const [path, value] of Object.entries(updates)) {
      const parts = path.split(".");
      let cur = nested;
      for (let i = 0; i < parts.length - 1; i++) {
        cur = (cur[parts[i]] ??= {}) as Record<string, unknown>;
      }
      const leaf = parts[parts.length - 1];
      // FieldValue.delete() is meaningless on a fresh doc — skip it.
      if (!(value instanceof FieldValue)) cur[leaf] = value;
    }
    await ref.set(nested, {merge: true});
  }
}
