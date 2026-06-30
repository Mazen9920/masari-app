import '../../shared/models/sale_model.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/utils/money_utils.dart';

/// COGS integrity helpers — pure, testable. Used by the COGS dashboard to make
/// sure cost of goods sold is fully and accurately recorded.

/// A sale that booked revenue but captured no cost on the sale record itself.
/// (Cancelled orders are ignored.) Prefer [findOrdersMissingCogs], which checks
/// the authoritative `cat_cogs` ledger rather than `sale.totalCogs` (the latter
/// is 0 for imported/historical sales whose item cost wasn't captured).
bool saleIsMissingCogs(Sale s) =>
    s.orderStatus != OrderStatus.cancelled &&
    s.netRevenue > 0 &&
    s.totalCogs <= 0;

/// Sale ids that have a non-zero `cat_cogs` ledger entry.
Set<String> saleIdsWithLedgerCogs(List<Transaction> txns) {
  final ids = <String>{};
  for (final t in txns) {
    if (t.categoryId == 'cat_cogs' &&
        t.saleId != null &&
        t.amount.abs() > 0.001) {
      ids.add(t.saleId!);
    }
  }
  return ids;
}

/// Orders that booked revenue but have NO cost recorded in the ledger — the
/// real "missing COGS" set (ledger-authoritative, no false positives from
/// sales whose item cost wasn't captured but whose COGS was still posted).
List<Sale> findOrdersMissingCogs(List<Sale> sales, List<Transaction> txns) {
  final withCogs = saleIdsWithLedgerCogs(txns);
  return sales
      .where((s) =>
          s.orderStatus != OrderStatus.cancelled &&
          s.netRevenue > 0 &&
          !withCogs.contains(s.id))
      .toList();
}

/// Total COGS posted to the ledger within [start]..[end] (signed: a normal cost
/// is negative, a cancellation reversal is positive). Authoritative period COGS.
double periodLedgerCogs(List<Transaction> txns, DateTime start, DateTime end) {
  return roundMoney(txns
      .where((t) => t.categoryId == 'cat_cogs')
      .where((t) => !t.dateTime.isBefore(start) && !t.dateTime.isAfter(end))
      .fold<double>(0, (a, t) => a - t.amount));
}

/// Net sales revenue posted to the ledger within [start]..[end] (signed:
/// refunds/reversals are negative).
double periodLedgerRevenue(List<Transaction> txns, DateTime start, DateTime end) {
  return roundMoney(txns
      .where((t) => t.categoryId == 'cat_sales_revenue')
      .where((t) => !t.dateTime.isBefore(start) && !t.dateTime.isAfter(end))
      .fold<double>(0, (a, t) => a + t.amount));
}

/// Reconciliation between COGS implied by sales and COGS actually posted to the
/// ledger as `cat_cogs` transactions. They should match to the cent.
class CogsRecon {
  /// Σ `sale.totalCogs` over non-cancelled sales.
  final double salesCogs;

  /// Σ |amount| of `cat_cogs` ledger transactions.
  final double recordedCogs;

  const CogsRecon(this.salesCogs, this.recordedCogs);

  double get diff => roundMoney(salesCogs - recordedCogs);
  bool get matches => diff.abs() < 1.0;
}

CogsRecon reconcileCogs(List<Sale> sales, List<Transaction> txns) {
  final liveIds = sales
      .where((s) => s.orderStatus != OrderStatus.cancelled)
      .map((s) => s.id)
      .toSet();
  final salesCogs = roundMoney(sales
      .where((s) => s.orderStatus != OrderStatus.cancelled)
      .fold<double>(0.0, (a, s) => a + s.totalCogs));
  // Apples-to-apples: ledger COGS posted FOR those same non-cancelled orders
  // only. Excludes cancelled-order entries (cost + reversal) and unlinked /
  // migration COGS — so the check reads ~0 for clean data and lights up only for
  // genuine per-order cost mismatches, not for cancellations. (`-amount`: a cost
  // is negative, so this yields a positive COGS figure.)
  final recordedCogs = roundMoney(txns
      .where((t) =>
          t.categoryId == 'cat_cogs' &&
          t.saleId != null &&
          liveIds.contains(t.saleId))
      .fold<double>(0.0, (a, t) => a - t.amount));
  return CogsRecon(salesCogs, recordedCogs);
}
