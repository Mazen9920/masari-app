import '../models/transaction_model.dart';
import 'money_utils.dart';
import 'report_constants.dart';

/// Whether [t] should be counted as a cash movement for CF-user cash balance.
///
/// Excludes:
///  - ALL sale-linked accrual entries (revenue/shipping/COGS with saleId) —
///    both positive (original booking) AND negative (refund/cancellation reversal).
///    Cash reality for COD is captured entirely through Bosta cashouts.
///  - Bosta daily shipping estimates / reconciliation txns
/// Includes:
///  - cat_supplier_payment (real cash even though excludeFromPL)
///  - financing categories (loans, equity, withdrawals)
///  - all other non-excludeFromPL transactions
bool isCfUserCashTransaction(Transaction t) {
  // COGS is an accrual expense, NEVER a cash movement (the cash was the
  // inventory purchase / supplier payment). Exclude it regardless of sale_id —
  // unlinked/migrated COGS entries with no sale_id would otherwise leak in as a
  // phantom cash outflow and double-count the inventory spend.
  if (t.categoryId == 'cat_cogs') return false;
  // Accrued-expense recognition is a non-cash accrual (Dr expense, Cr liability);
  // the cash moves later via cat_accrued_payment.
  if (t.categoryId == 'cat_accrued_expense') return false;
  // Exclude ALL sale-linked accrual entries — positive AND negative.
  // Cash comes from Bosta cashouts, not from accrual entries.
  if (t.saleId != null && saleTxnCats.contains(t.categoryId)) {
    return false;
  }
  // Exclude Bosta daily shipping estimates / reconciliation txns.
  if (t.id.startsWith('bosta_est_daily_') ||
      t.id.startsWith('bosta_rec_daily_')) {
    return false;
  }
  if (t.categoryId == 'cat_supplier_payment') return true;
  // Capitalized manufacturing labor: real cash outflow even though excluded
  // from P&L (it reaches P&L as COGS when the finished good sells).
  if (t.categoryId == 'cat_manufacturing_cost') return true;
  // Payment-gateway settlement: real bank inflow even though excluded from P&L
  // (the revenue was already recognized at the sale; this is the receivable →
  // cash swap).
  if (t.categoryId == 'cat_gateway_settlement') return true;
  // Settling an accrued expense: real cash outflow, excluded from P&L (the cost
  // was already recognized when accrued).
  if (t.categoryId == 'cat_accrued_payment') return true;
  if (plExcludedCats.contains(t.categoryId)) return true;
  return !t.excludeFromPL;
}

/// Whether [t] should be counted as a cash movement for non-CF-user balance.
///
/// Excludes positive sale-linked accrual entries (replaced by sale.amountPaid).
/// Includes cat_supplier_payment and all non-excludeFromPL transactions.
bool isNonCfUserCashTransaction(Transaction t) {
  // COGS is an accrual expense, never a cash movement (see CF-user note).
  if (t.categoryId == 'cat_cogs') return false;
  if (t.categoryId == 'cat_accrued_expense') return false;
  if (t.saleId != null &&
      saleTxnCats.contains(t.categoryId) &&
      t.amount >= 0) {
    return false;
  }
  if (t.categoryId == 'cat_supplier_payment') return true;
  if (t.categoryId == 'cat_manufacturing_cost') return true;
  if (t.categoryId == 'cat_gateway_settlement') return true;
  if (t.categoryId == 'cat_accrued_payment') return true;
  return !t.excludeFromPL;
}

/// The signed cash impact of [t] on the running balance, or null if [t] is not
/// a cash movement (and should be skipped entirely).
///
/// This is the **single source of truth** that combines the include filter with
/// the income sign. Every screen that totals cash MUST use this (directly or via
/// [computeClosingCash]) so the Balance Sheet, Cash Flow statement, and Cash &
/// Bank dashboard can never drift apart. Income is determined by
/// `Transaction.isIncome` (amount > 0), NOT the stored is_income flag.
double? cashImpact(Transaction t, {required bool isCfUser}) {
  final include = isCfUser
      ? isCfUserCashTransaction(t)
      : isNonCfUserCashTransaction(t);
  if (!include) return null;
  return t.isIncome ? t.amount.abs() : -t.amount.abs();
}

/// Computes the closing cash balance up to [asOf].
///
/// This is the **single source of truth** for the "Cash & Bank" line on
/// both the Cash Flow Statement and the Balance Sheet.
///
/// For CF users (Bosta-integrated): cash = openingCash + cashouts + eligible txns.
/// For non-CF users: cash = openingCash + sale.amountPaid + eligible txns.
double computeClosingCash({
  required double openingCash,
  required List<Transaction> transactions,
  required DateTime asOf,
  required bool isCfUser,
  /// Actual cash received from Bosta cashouts (CF user).
  double totalCashouts = 0,
  /// Actual cash received from customers (non-CF user).
  double cashFromSales = 0,
}) {
  final double txnCashFlow = transactions
      .where((t) => !t.dateTime.isAfter(asOf))
      .fold<double>(
        0.0,
        (sum, t) => sum + (cashImpact(t, isCfUser: isCfUser) ?? 0),
      );

  final double externalCash = isCfUser ? totalCashouts : cashFromSales;
  return roundMoney(openingCash + externalCash + txnCashFlow);
}
