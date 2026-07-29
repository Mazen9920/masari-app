/**
 * cash-engine.ts — server-side mirror of `lib/shared/utils/cf_engine.dart`.
 *
 * ⚠ PARITY CONTRACT: this file and cf_engine.dart must agree to the pound.
 * Any category rule changed in one MUST be changed in the other, or the
 * cash-crunch alert will quote a balance the app never shows. There is a
 * parity check in the Phase-4 verification script; run it after any edit.
 *
 * Cash for a CF (Bosta) user is:
 *     openingCash + cashouts within the books window + Σ transaction impact
 *
 * The subtleties that took a full reconciliation session to pin down:
 *  - COD sale revenue is NOT cash; the money arrives via Bosta cashouts, so
 *    sale-linked revenue/shipping/COGS rows are excluded.
 *  - A cashout TRANSACTION is only cash when it is NOT flagged
 *    exclude_from_pl: flagged ones mirror a payout already counted in the
 *    cashout total (double-count), unflagged ones are payouts the sync missed
 *    and are the only record of that money.
 *  - Gateway fees and "P adjustment" write-offs never touched the bank.
 *  - `date_time` is a Timestamp from the app but an ISO STRING from
 *    processRecurringTransactions, so both shapes must parse.
 */

import {getFirestore, Timestamp} from "firebase-admin/firestore";

const db = () => getFirestore();

/** Non-operating categories — balance-sheet movements, still real cash. */
const PL_EXCLUDED = new Set([
  "cat_investments",
  "cat_loan_received",
  "cat_loan_repayment",
  "cat_equity_injection",
  "cat_owner_withdrawal",
  "cat_salary_payment",
  "cat_asset_sale",
  "cat_bosta_cashout",
  "cat_gateway_settlement",
  "cat_accrued_payment",
  "cat_supplier_payment",
  "cat_manufacturing_cost",
]);

/** Accrual entries written against a sale. */
const SALE_TXN_CATS = new Set(["cat_sales_revenue", "cat_cogs", "cat_shipping"]);

const num = (v: unknown): number => (typeof v === "number" ? v : Number(v) || 0);
export const round2 = (n: number): number => Math.round(n * 100) / 100;

/** Parses either a Firestore Timestamp or an ISO string. */
export function parseTxnDate(v: unknown): Date | null {
  if (!v) return null;
  if (v instanceof Timestamp) return v.toDate();
  if (typeof v === "string") {
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  const secs = (v as {_seconds?: number})?._seconds;
  if (typeof secs === "number") return new Date(secs * 1000);
  return null;
}

/**
 * Whether [t] moves cash for a CF user. Mirrors isCfUserCashTransaction()
 * in cf_engine.dart — the ORDER of these checks is load-bearing (the cashout
 * rule must precede the PL_EXCLUDED catch-all).
 */
export function isCashTransaction(id: string, t: Record<string, unknown>): boolean {
  const c = t.category_id as string;
  if (c === "cat_cogs") return false;
  if (c === "cat_accrued_expense") return false;
  if (c === "cat_d_paymob") return false;
  if (c === "cat_gateway_fees") return false;
  if (t.sale_id && SALE_TXN_CATS.has(c)) return false;
  if (id.startsWith("bosta_est_daily_") || id.startsWith("bosta_rec_daily_")) {
    return false;
  }
  if (c === "cat_bosta_cashout") return t.exclude_from_pl !== true;
  if (c === "cat_supplier_payment") return true;
  if (c === "cat_manufacturing_cost") return true;
  if (c === "cat_gateway_settlement") return true;
  if (c === "cat_accrued_payment") return true;
  if (PL_EXCLUDED.has(c)) return true;
  return t.exclude_from_pl !== true;
}

export interface CashPosition {
  closingCash: number;
  openingCash: number;
  cashouts: number;
  txnFlow: number;
  asOf: Date;
}

/** Last instant of [d]'s day — the app reports cash as of end-of-period. */
export function endOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
}

/**
 * Computes closing cash for [uid] as of [asOf], honouring the books-start
 * cutover (cashouts before the start date are represented by the opening
 * balance, not counted again).
 *
 * [asOf] defaults to the END of today, matching the app: a transaction dated
 * later today (a payment booked at 18:00, say) is part of today's balance.
 * Using the current instant instead silently dropped it and produced a
 * balance the app never shows.
 */
export async function computeClosingCash(
  uid: string,
  asOf: Date = endOfDay(new Date())
): Promise<CashPosition> {
  const bsDoc = await db().collection("balance_sheet").doc(uid).get();
  const bs = bsDoc.data() ?? {};
  const openingCash = num(bs.opening_cash_balance);
  const startKey = String(bs.books_start_date ?? "").substring(0, 10);
  const asOfKey = asOf.toISOString().substring(0, 10);

  // Bosta cashouts inside [booksStart, asOf] — compared as YYYY-MM-DD so a
  // same-day payout counts regardless of its timestamp.
  const coSnap = await db()
    .collection("bosta_cashouts")
    .where("user_id", "==", uid)
    .get();
  let cashouts = 0;
  coSnap.forEach((doc) => {
    const ds = String(doc.data().transaction_date ?? "").substring(0, 10);
    if (!ds) return;
    if (startKey && ds < startKey) return;
    if (ds > asOfKey) return;
    cashouts += num(doc.data().amount);
  });

  const txSnap = await db()
    .collection("transactions")
    .where("user_id", "==", uid)
    .get();
  let txnFlow = 0;
  txSnap.forEach((doc) => {
    const t = doc.data();
    const d = parseTxnDate(t.date_time ?? t.date);
    if (!d || d > asOf) return;
    if (!isCashTransaction(doc.id, t)) return;
    txnFlow += num(t.amount);
  });

  return {
    closingCash: round2(openingCash + cashouts + txnFlow),
    openingCash,
    cashouts: round2(cashouts),
    txnFlow: round2(txnFlow),
    asOf,
  };
}
