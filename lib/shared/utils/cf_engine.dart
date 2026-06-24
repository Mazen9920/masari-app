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
  if (plExcludedCats.contains(t.categoryId)) return true;
  return !t.excludeFromPL;
}

/// Whether [t] should be counted as a cash movement for non-CF-user balance.
///
/// Excludes positive sale-linked accrual entries (replaced by sale.amountPaid).
/// Includes cat_supplier_payment and all non-excludeFromPL transactions.
bool isNonCfUserCashTransaction(Transaction t) {
  if (t.saleId != null &&
      saleTxnCats.contains(t.categoryId) &&
      t.amount >= 0) {
    return false;
  }
  if (t.categoryId == 'cat_supplier_payment') return true;
  return !t.excludeFromPL;
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
  final filter = isCfUser ? isCfUserCashTransaction : isNonCfUserCashTransaction;

  final double txnCashFlow = transactions
      .where((t) => !t.dateTime.isAfter(asOf))
      .where(filter)
      .fold<double>(
        0.0,
        (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs()),
      );

  final double externalCash = isCfUser ? totalCashouts : cashFromSales;
  return roundMoney(openingCash + externalCash + txnCashFlow);
}
