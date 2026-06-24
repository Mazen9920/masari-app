import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/models/sale_model.dart';
import '../../../shared/utils/report_constants.dart';
import '../providers/dashboard_state_provider.dart';
import '../providers/dashboard_data_provider.dart';

enum _Metric { sales, expenses, profit, orders }

enum _SalesView { graph, breakdown }

/// Series keys for the Shopify-style sales breakdown view.
enum _BreakdownSeries { grossSales, discounts, returns, netSales }

class _BreakdownData {
  final List<double> grossSales;
  final List<double> discounts;
  final List<double> returns;
  final List<double> netSales;
  const _BreakdownData({
    required this.grossSales,
    required this.discounts,
    required this.returns,
    required this.netSales,
  });

  static _BreakdownData empty(int n) => _BreakdownData(
        grossSales: List.filled(n, 0.0),
        discounts: List.filled(n, 0.0),
        returns: List.filled(n, 0.0),
        netSales: List.filled(n, 0.0),
      );
}

/// Advanced Shopify-style analytics chart with metric toggling,
/// period-aware data, touch tooltips, and comparison line.
class AnalyticsChart extends ConsumerStatefulWidget {
  const AnalyticsChart({super.key});

  @override
  ConsumerState<AnalyticsChart> createState() => _AnalyticsChartState();
}

class _AnalyticsChartState extends ConsumerState<AnalyticsChart> {
  _Metric _selected = _Metric.sales;
  _SalesView _salesView = _SalesView.graph;
  bool _showComparison = false;

  @override
  Widget build(BuildContext context) {
    final ds = ref.watch(dashboardStateProvider);
    final range = ds.range;
    final currency = ref.watch(appSettingsProvider).currency;

    final dashData = ref.watch(dashboardDataProvider).value;
    final allSales = dashData?.sales ?? [];
    final allTxns = dashData?.transactions ?? [];

    // Filter to current period
    final curSales = allSales
        .where((s) =>
            !s.date.isBefore(range.start) && !s.date.isAfter(range.end))
        .toList();
    final prevSales = allSales
        .where((s) =>
            !s.date.isBefore(range.previousStart) &&
            !s.date.isAfter(range.previousEnd))
        .toList();

    final curTxns = allTxns
        .where((t) =>
            !t.excludeFromPL &&
            !plExcludedCats.contains(t.categoryId) &&
            !t.dateTime.isBefore(range.start) &&
            !t.dateTime.isAfter(range.end))
        .toList();
    final prevTxns = allTxns
        .where((t) =>
            !t.excludeFromPL &&
            !plExcludedCats.contains(t.categoryId) &&
            !t.dateTime.isBefore(range.previousStart) &&
            !t.dateTime.isAfter(range.previousEnd))
        .toList();

    // Build time buckets
    final strategy = ds.period.effectiveBucketStrategy(range);
    final buckets = _buildBuckets(range.start, range.end, strategy);
    final prevBuckets =
        _buildBuckets(range.previousStart, range.previousEnd, strategy);

    // Sales metric supports two views: classic line chart or text breakdown.
    final isBreakdown =
        _selected == _Metric.sales && _salesView == _SalesView.breakdown;

    final curBreakdown = isBreakdown
        ? _aggregateBreakdown(buckets, curSales, curTxns, strategy)
        : _BreakdownData.empty(buckets.length);
    final prevBreakdown = isBreakdown
        ? _aggregateBreakdown(prevBuckets, prevSales, prevTxns, strategy)
        : _BreakdownData.empty(prevBuckets.length);

    final curData = isBreakdown
        ? curBreakdown.netSales
        : _aggregate(
            buckets, curSales, curTxns, range.start, _selected, strategy);
    final prevData = isBreakdown
        ? prevBreakdown.netSales
        : _aggregate(prevBuckets, prevSales, prevTxns, range.previousStart,
            _selected, strategy);

    // Summary value
    final totalCur = curData.fold<double>(0, (a, b) => a + b);
    final totalPrev = prevData.fold<double>(0, (a, b) => a + b);
    final changePct = totalPrev.abs() > 0
        ? ((totalCur - totalPrev) / totalPrev.abs() * 100)
        : (totalCur > 0 ? 100.0 : 0.0);

    final fmt = _selected == _Metric.orders
        ? NumberFormat('#,##0')
        : NumberFormat.compactCurrency(symbol: '$currency ');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Header ───
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.of(context)!.analytics,
                style: AppTypography.h3.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              // Right-side controls: view switcher (sales only) + compare.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selected == _Metric.sales) ...[
                    _ViewSwitcher(
                      salesView: _salesView,
                      onChanged: (v) => setState(() => _salesView = v),
                    ),
                    const SizedBox(width: 8),
                  ],
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showComparison = !_showComparison),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _showComparison
                            ? AppColors.primaryNavy.withValues(alpha: 0.08)
                            : AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _showComparison
                              ? AppColors.primaryNavy.withValues(alpha: 0.2)
                              : AppColors.borderLight,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.compare_arrows_rounded,
                            size: 14,
                            color: _showComparison
                                ? AppColors.primaryNavy
                                : AppColors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            AppLocalizations.of(context)!.compareLabel,
                            style: AppTypography.captionSmall.copyWith(
                              color: _showComparison
                                  ? AppColors.primaryNavy
                                  : AppColors.textTertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                fmt.format(totalCur),
                style: AppTypography.h1.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                ),
              ),
              const SizedBox(width: 8),
              _ChangeBadge(changePct: changePct),
            ],
          ),
          const SizedBox(height: 16),

          // ─── Metric Tabs ───
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
            children: _Metric.values.map((m) {
              final sel = m == _selected;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _selected = m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel
                          ? _metricColor(m).withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: sel
                          ? Border.all(
                              color: _metricColor(m).withValues(alpha: 0.3))
                          : null,
                    ),
                    child: Text(
                      _metricLabel(m),
                      style: AppTypography.captionSmall.copyWith(
                        color: sel ? _metricColor(m) : AppColors.textTertiary,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // ─── Chart / Breakdown ───
          if (isBreakdown)
            _buildBreakdownList(curBreakdown, prevBreakdown, currency)
          else
            SizedBox(
              height: 200,
              child: _buildChart(curData, prevData, buckets, strategy),
            ),
        ],
      ),
    );
  }

  Widget _buildChart(List<double> curData, List<double> prevData,
      List<DateTime> buckets, BucketStrategy strategy) {
    if (curData.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.noDataForPeriod,
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.textTertiary),
        ),
      );
    }

    final color = _metricColor(_selected);
    final allPoints = [...curData, if (_showComparison) ...prevData];
    final rawMax = allPoints.fold<double>(0, (a, b) => a > b ? a : b);
    final rawMin = allPoints.fold<double>(0, (a, b) => a < b ? a : b);
    final safeMaxY = rawMax == 0 ? 1.0 : rawMax * 1.15;
    final safeMinY = rawMin >= 0 ? 0.0 : rawMin * 1.15;
    final yRange = safeMaxY - safeMinY;

    final curSpots = List.generate(
        curData.length, (i) => FlSpot(i.toDouble(), curData[i]));
    final prevSpots = _showComparison
        ? List.generate(
            prevData.length, (i) => FlSpot(i.toDouble(), prevData[i]))
        : <FlSpot>[];

    return LineChart(
      LineChartData(
        minY: safeMinY,
        maxY: safeMaxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yRange / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.borderLight,
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: yRange / 4,
              getTitlesWidget: (value, _) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  _shortNum(value),
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: _bottomInterval(buckets.length),
              getTitlesWidget: (value, _) {
                final i = value.toInt();
                if (i < 0 || i >= buckets.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _bucketLabel(buckets[i], strategy),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.primaryNavy,
            tooltipBorderRadius: BorderRadius.circular(8),
            getTooltipItems: (spots) {
              return spots.map((spot) {
                final isCur = spot.barIndex == 0;
                return LineTooltipItem(
                  _selected == _Metric.orders
                      ? spot.y.toInt().toString()
                      : NumberFormat.compact().format(spot.y),
                  TextStyle(
                    color: isCur ? Colors.white : Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              }).toList();
            },
          ),
          handleBuiltInTouches: true,
        ),
        lineBarsData: [
          // Current period
          LineChartBarData(
            spots: curSpots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: color,
            barWidth: 2.5,
            dotData: FlDotData(
              show: curData.length <= 12,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 3,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: color,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  color.withValues(alpha: 0.2),
                  color.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          // Previous period (comparison)
          if (_showComparison && prevSpots.isNotEmpty)
            LineChartBarData(
              spots: prevSpots.length > curSpots.length
                  ? prevSpots.sublist(0, curSpots.length)
                  : prevSpots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: AppColors.textTertiary.withValues(alpha: 0.4),
              barWidth: 1.5,
              dashArray: [6, 4],
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ─── Helpers ───

  static Color _metricColor(_Metric m) {
    switch (m) {
      case _Metric.sales:
        return AppColors.success;
      case _Metric.expenses:
        return AppColors.danger;
      case _Metric.profit:
        return AppColors.accentOrange;
      case _Metric.orders:
        return AppColors.secondaryBlue;
    }
  }

  String _metricLabel(_Metric m) {
    final l10n = AppLocalizations.of(context)!;
    switch (m) {
      case _Metric.sales:
        return l10n.salesMetric;
      case _Metric.expenses:
        return l10n.expenses;
      case _Metric.profit:
        return l10n.profitMetric;
      case _Metric.orders:
        return l10n.ordersMetric;
    }
  }

  static Color _seriesColor(_BreakdownSeries s) {
    switch (s) {
      case _BreakdownSeries.grossSales:
        return AppColors.secondaryBlue;
      case _BreakdownSeries.discounts:
        return AppColors.accentOrange;
      case _BreakdownSeries.returns:
        return AppColors.danger;
      case _BreakdownSeries.netSales:
        return AppColors.success;
    }
  }

  String _seriesLabel(_BreakdownSeries s) {
    switch (s) {
      case _BreakdownSeries.grossSales:
        return 'Gross sales';
      case _BreakdownSeries.discounts:
        return 'Discounts';
      case _BreakdownSeries.returns:
        return 'Returns';
      case _BreakdownSeries.netSales:
        return 'Net sales';
    }
  }

  /// Shopify-style row list: label | amount | change-vs-previous badge.
  Widget _buildBreakdownList(
    _BreakdownData cur,
    _BreakdownData prev,
    String currency,
  ) {
    double sum(List<double> xs) => xs.fold(0.0, (a, b) => a + b);

    final curVals = {
      _BreakdownSeries.grossSales: sum(cur.grossSales),
      _BreakdownSeries.discounts: sum(cur.discounts),
      _BreakdownSeries.returns: sum(cur.returns),
      _BreakdownSeries.netSales: sum(cur.netSales),
    };
    final prevVals = {
      _BreakdownSeries.grossSales: sum(prev.grossSales),
      _BreakdownSeries.discounts: sum(prev.discounts),
      _BreakdownSeries.returns: sum(prev.returns),
      _BreakdownSeries.netSales: sum(prev.netSales),
    };

    final money = NumberFormat.currency(symbol: '$currency ', decimalDigits: 2);

    Widget row(_BreakdownSeries s, {required bool zebra, required bool emphasize}) {
      final label = _seriesLabel(s);
      final color = _seriesColor(s);
      final curV = curVals[s]!;
      final prevV = prevVals[s]!;
      final isDeduction =
          s == _BreakdownSeries.discounts || s == _BreakdownSeries.returns;
      final display = isDeduction ? -curV : curV;
      final formatted = isDeduction
          ? '-${money.format(curV)}'
          : money.format(curV);

      double? changePct;
      if (prevV.abs() > 0) {
        changePct = (curV - prevV) / prevV.abs() * 100;
      } else if (curV.abs() > 0) {
        changePct = 100.0;
      }

      // For deductions, growth is "bad" — invert sign for badge color semantics.
      final badgePct = (changePct == null)
          ? null
          : (isDeduction ? -changePct : changePct);

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: zebra ? AppColors.backgroundLight : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodySmall.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              formatted,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
            if (_showComparison && badgePct != null) ...[
              const SizedBox(width: 8),
              _ChangeBadge(changePct: badgePct),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        row(_BreakdownSeries.grossSales, zebra: false, emphasize: false),
        row(_BreakdownSeries.discounts, zebra: true, emphasize: false),
        row(_BreakdownSeries.returns, zebra: false, emphasize: false),
        row(_BreakdownSeries.netSales, zebra: true, emphasize: true),
      ],
    );
  }

  static String _shortNum(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  static double _bottomInterval(int count) {
    if (count <= 7) return 1;
    if (count <= 14) return 2;
    if (count <= 31) return 5;
    return (count / 6).ceilToDouble();
  }

  static String _bucketLabel(DateTime d, BucketStrategy strategy) {
    switch (strategy) {
      case BucketStrategy.hourly:
        return DateFormat('HH:mm').format(d);
      case BucketStrategy.daily:
        // Show "EEE" for short ranges (≤7 days), otherwise day number
        return DateFormat('d').format(d);
      case BucketStrategy.monthly:
        return DateFormat('MMM').format(d);
    }
  }
}

// ─── Time bucketing ───

List<DateTime> _buildBuckets(
    DateTime start, DateTime end, BucketStrategy strategy) {
  final buckets = <DateTime>[];
  switch (strategy) {
    case BucketStrategy.hourly:
      var cursor = DateTime(start.year, start.month, start.day);
      while (!cursor.isAfter(end)) {
        buckets.add(cursor);
        cursor = cursor.add(const Duration(hours: 1));
      }
    case BucketStrategy.daily:
      var cursor = DateTime(start.year, start.month, start.day);
      final endDay = DateTime(end.year, end.month, end.day);
      while (!cursor.isAfter(endDay)) {
        buckets.add(cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
    case BucketStrategy.monthly:
      var cursor = DateTime(start.year, start.month, 1);
      while (!cursor.isAfter(end)) {
        buckets.add(cursor);
        cursor = DateTime(cursor.year, cursor.month + 1, 1);
      }
  }
  return buckets;
}

List<double> _aggregate(
  List<DateTime> buckets,
  List<dynamic> sales,
  List<dynamic> txns,
  DateTime rangeStart,
  _Metric metric,
  BucketStrategy strategy,
) {
  if (buckets.isEmpty) return [];
  final values = List.filled(buckets.length, 0.0);
  final lastIdx = buckets.length - 1;

  // O(1) bucket lookup instead of O(n) reverse scan.
  int bucketIndex(DateTime d) {
    int idx;
    switch (strategy) {
      case BucketStrategy.hourly:
        idx = d.difference(buckets.first).inHours;
      case BucketStrategy.daily:
        final dDay = DateTime(d.year, d.month, d.day);
        final startDay = DateTime(
            buckets.first.year, buckets.first.month, buckets.first.day);
        idx = dDay.difference(startDay).inDays;
      case BucketStrategy.monthly:
        idx = (d.year - buckets.first.year) * 12 +
            d.month -
            buckets.first.month;
    }
    return idx.clamp(0, lastIdx);
  }

  switch (metric) {
    case _Metric.sales:
      // Transaction-based Net Sales = Σ signed (cat_sales_revenue + cat_shipping)
      // txns, bucketed by txn date. Positive = sale/shipping income, negative =
      // refund or cancellation reversal. This nets out cancelled orders and
      // matches Shopify "Total sales" exactly (sale[] docs can drift from txns).
      for (final t in txns) {
        final amount = (t as dynamic).amount as double;
        final catId = (t as dynamic).categoryId as String;
        if (catId == 'cat_sales_revenue' || catId == 'cat_shipping') {
          final idx = bucketIndex((t as dynamic).dateTime as DateTime);
          if (idx >= 0 && idx < values.length) {
            values[idx] += amount;
          }
        }
      }
      break;
    case _Metric.expenses:
      for (final t in txns) {
        final amount = (t as dynamic).amount as double;
        final catId = (t as dynamic).categoryId as String;
        final idx = bucketIndex((t as dynamic).dateTime as DateTime);
        if (idx >= 0 && idx < values.length) {
          if (catId == 'cat_cogs') {
            // COGS: negative = cost, positive = reversal (reduces expenses)
            values[idx] -= amount;
          } else if (amount < 0 &&
              catId != 'cat_sales_revenue' &&
              catId != 'cat_shipping') {
            values[idx] += amount.abs();
          }
        }
      }
      break;
    case _Metric.profit:
      // Revenue minus expenses. Refunds/reversals reduce revenue, COGS reversals reduce expenses.
      for (final t in txns) {
        final amount = (t as dynamic).amount as double;
        final catId = (t as dynamic).categoryId as String;
        final idx = bucketIndex((t as dynamic).dateTime as DateTime);
        if (idx >= 0 && idx < values.length) {
          if (catId == 'cat_cogs') {
            // COGS: negative = expense, positive = reversal (reduces expense)
            values[idx] += amount; // +(-X) subtracts cost, +(+X) adds back reversal
          } else if (catId == 'cat_sales_revenue' ||
              catId == 'cat_shipping') {
            // Signed: positive = revenue, negative = refund
            values[idx] += amount;
          } else if (amount > 0) {
            values[idx] += amount; // other income
          } else {
            values[idx] += amount; // other expense (negative)
          }
        }
      }
      break;
    case _Metric.orders:
      // Match Shopify's order count which includes cancelled orders.
      for (final s in sales) {
        final idx = bucketIndex((s as Sale).date);
        if (idx >= 0 && idx < values.length) {
          values[idx] += 1;
        }
      }
      break;
  }

  return values;
}

/// Shopify-style sales breakdown:
///   Gross Sales  — sum of sale subtotals (line items × price, before discounts)
///   Discounts    — sum of discount amounts on sales
///   Returns      — absolute value of negative `cat_sales_revenue` transactions (refunds)
///   Net Sales    — Gross Sales − Discounts − Returns
///
/// Shopify-style sales breakdown. Mirrors Shopify Admin's Sales report:
///   Gross   = Σ qty × unit_price for every sale (cancelled included)
///   Discounts = Σ discount_amount for every sale
///   Returns = Σ |negative cat_sales_revenue txns| (partial refunds + full
///             cancellation reversals) dated in bucket
///   Net     = Gross − Discounts − Returns
_BreakdownData _aggregateBreakdown(
  List<DateTime> buckets,
  List<dynamic> sales,
  List<dynamic> txns,
  BucketStrategy strategy,
) {
  if (buckets.isEmpty) return _BreakdownData.empty(0);
  final n = buckets.length;
  final gross = List.filled(n, 0.0);
  final discounts = List.filled(n, 0.0);
  final returns = List.filled(n, 0.0);
  final lastIdx = n - 1;

  int bucketIndex(DateTime d) {
    int idx;
    switch (strategy) {
      case BucketStrategy.hourly:
        idx = d.difference(buckets.first).inHours;
      case BucketStrategy.daily:
        final dDay = DateTime(d.year, d.month, d.day);
        final startDay = DateTime(
            buckets.first.year, buckets.first.month, buckets.first.day);
        idx = dDay.difference(startDay).inDays;
      case BucketStrategy.monthly:
        idx = (d.year - buckets.first.year) * 12 +
            d.month -
            buckets.first.month;
    }
    return idx.clamp(0, lastIdx);
  }

  for (final s in sales) {
    final sale = s as Sale;
    // Include cancelled sales in Gross/Discounts (no shipping).
    final idx = bucketIndex(sale.date);
    if (idx >= 0 && idx < n) {
      gross[idx] += sale.subtotal;
      discounts[idx] += sale.discountAmount;
    }
  }

  // Returns: revenue refund-event txns only (no shipping).
  // Includes `*_reversal` txns so fully cancelled/voided orders are removed
  // from Net Sales (otherwise cancelled orders are double-counted in Gross).
  for (final t in txns) {
    final amount = (t as dynamic).amount as double;
    final catId = (t as dynamic).categoryId as String;
    if (catId != 'cat_sales_revenue') continue;
    if (amount >= 0) continue;
    final idx = bucketIndex((t as dynamic).dateTime as DateTime);
    if (idx >= 0 && idx < n) {
      returns[idx] += amount.abs();
    }
  }

  final net = List<double>.generate(
      n, (i) => gross[i] - discounts[i] - returns[i]);

  return _BreakdownData(
    grossSales: gross,
    discounts: discounts,
    returns: returns,
    netSales: net,
  );
}

class _ChangeBadge extends StatelessWidget {
  final double changePct;
  const _ChangeBadge({required this.changePct});

  @override
  Widget build(BuildContext context) {
    final up = changePct >= 0;
    final color = up ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            '${changePct.abs().toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented icon toggle between chart view and text breakdown view.
class _ViewSwitcher extends StatelessWidget {
  final _SalesView salesView;
  final ValueChanged<_SalesView> onChanged;
  const _ViewSwitcher({required this.salesView, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget segment(_SalesView v, IconData icon) {
      final sel = salesView == v;
      return GestureDetector(
        onTap: () => onChanged(v),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: sel
                ? AppColors.primaryNavy.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 16,
            color: sel ? AppColors.primaryNavy : AppColors.textTertiary,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(_SalesView.graph, Icons.show_chart_rounded),
          segment(_SalesView.breakdown, Icons.format_list_bulleted_rounded),
        ],
      ),
    );
  }
}
