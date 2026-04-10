import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/transaction_model.dart';
import '../../../shared/models/sale_model.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../shared/utils/report_constants.dart';
import 'dashboard_state_provider.dart';

/// Pre-computed summary metrics for a single period.
class PeriodMetrics {
  final double revenue;
  final double expenses;
  final double salesRevenue;
  final double totalCogs;
  final int orderCount;

  const PeriodMetrics({
    this.revenue = 0,
    this.expenses = 0,
    this.salesRevenue = 0,
    this.totalCogs = 0,
    this.orderCount = 0,
  });

  double get netProfit => revenue - expenses;
  double get grossProfit => salesRevenue - totalCogs;
  double get grossMarginPct =>
      salesRevenue > 0 ? grossProfit / salesRevenue * 100 : 0;
  double get netMarginPct => revenue > 0 ? netProfit / revenue * 100 : 0;
  double get cogsRatioPct =>
      salesRevenue > 0 ? totalCogs / salesRevenue * 100 : 0;
}

/// Pre-fetched dashboard data covering [previousStart .. end]
/// with pre-computed metrics so widgets skip redundant iteration.
class DashboardData {
  final List<Transaction> transactions;
  final List<Sale> sales;
  final PeriodMetrics currentMetrics;
  final PeriodMetrics previousMetrics;

  const DashboardData({
    required this.transactions,
    required this.sales,
    required this.currentMetrics,
    required this.previousMetrics,
  });

  static const empty = DashboardData(
    transactions: [],
    sales: [],
    currentMetrics: PeriodMetrics(),
    previousMetrics: PeriodMetrics(),
  );
}

class DashboardDataNotifier extends AsyncNotifier<DashboardData> {
  @override
  Future<DashboardData> build() async {
    // Survive tab switches — data stays warm in memory.
    ref.keepAlive();

    final ds = ref.watch(dashboardStateProvider);
    return _fetchAndCompute(ds.range);
  }

  Future<DashboardData> _fetchAndCompute(DashboardDateRange range) async {
    final queryStart = range.previousStart;
    final queryEnd = range.end;

    final txnRepo = ref.read(transactionRepositoryProvider);
    final saleRepo = ref.read(saleRepositoryProvider);

    final results = await Future.wait([
      txnRepo.getTransactionsInRange(start: queryStart, end: queryEnd),
      saleRepo.getSalesInRange(start: queryStart, end: queryEnd),
    ]);

    final txns = results[0].data as List<Transaction>? ?? [];
    final sales = results[1].data as List<Sale>? ?? [];

    final currentMetrics =
        _computeMetrics(txns, sales, range.start, range.end);
    final previousMetrics =
        _computeMetrics(txns, sales, range.previousStart, range.previousEnd);

    return DashboardData(
      transactions: txns,
      sales: sales,
      currentMetrics: currentMetrics,
      previousMetrics: previousMetrics,
    );
  }

  static PeriodMetrics _computeMetrics(
    List<Transaction> allTxns,
    List<Sale> allSales,
    DateTime start,
    DateTime end,
  ) {
    double revenue = 0;
    double expenses = 0;

    for (final t in allTxns) {
      if (t.excludeFromPL || plExcludedCats.contains(t.categoryId)) continue;
      if (t.dateTime.isBefore(start) || t.dateTime.isAfter(end)) continue;
      if (t.categoryId == 'cat_cogs') {
        // COGS: negative = cost, positive = reversal from cancelled order
        expenses -= t.amount; // -(-X)=+X for cost, -(+X)=-X for reversal
      } else if (t.categoryId == 'cat_sales_revenue' ||
          t.categoryId == 'cat_shipping') {
        // Signed: positive = income, negative = refund/reversal
        revenue += t.amount;
      } else if (t.isIncome) {
        revenue += t.amount.abs();
      } else {
        expenses += t.amount.abs();
      }
    }

    double salesRevenue = 0;
    double totalCogs = 0;
    int orderCount = 0;

    for (final s in allSales) {
      if (s.orderStatus == OrderStatus.cancelled) continue;
      if (s.date.isBefore(start) || s.date.isAfter(end)) continue;
      salesRevenue += s.netRevenue;
      totalCogs += s.totalCogs;
      orderCount++;
    }

    return PeriodMetrics(
      revenue: revenue,
      expenses: expenses,
      salesRevenue: salesRevenue,
      totalCogs: totalCogs,
      orderCount: orderCount,
    );
  }

  /// Refresh without flashing a loading spinner.
  /// Old data stays visible while the new fetch runs.
  Future<void> refresh() async {
    final range = ref.read(dashboardStateProvider).range;
    try {
      final newData = await _fetchAndCompute(range);
      state = AsyncData(newData);
    } catch (_) {
      // On error keep previous data visible.
      if (!state.hasValue) rethrow;
    }
  }
}

final dashboardDataProvider =
    AsyncNotifierProvider<DashboardDataNotifier, DashboardData>(
  DashboardDataNotifier.new,
);
