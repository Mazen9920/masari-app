import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../providers/dashboard_state_provider.dart';

enum _Metric { sales, expenses, profit, orders }

/// Advanced Shopify-style analytics chart with metric toggling,
/// period-aware data, touch tooltips, and comparison line.
class AnalyticsChart extends ConsumerStatefulWidget {
  const AnalyticsChart({super.key});

  @override
  ConsumerState<AnalyticsChart> createState() => _AnalyticsChartState();
}

class _AnalyticsChartState extends ConsumerState<AnalyticsChart> {
  _Metric _selected = _Metric.sales;
  bool _showComparison = false;

  @override
  Widget build(BuildContext context) {
    final ds = ref.watch(dashboardStateProvider);
    final range = ds.range;
    final currency = ref.watch(appSettingsProvider).currency;

    final allSales = ref.watch(salesProvider).value ?? [];
    final allTxns = ref.watch(transactionsProvider).value ?? [];

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
            !t.dateTime.isBefore(range.start) &&
            !t.dateTime.isAfter(range.end))
        .toList();
    final prevTxns = allTxns
        .where((t) =>
            !t.excludeFromPL &&
            !t.dateTime.isBefore(range.previousStart) &&
            !t.dateTime.isAfter(range.previousEnd))
        .toList();

    // Build time buckets
    final buckets = _buildBuckets(range.start, range.end, ds.period);
    final prevBuckets =
        _buildBuckets(range.previousStart, range.previousEnd, ds.period);

    final curData =
        _aggregate(buckets, curSales, curTxns, range.start, _selected);
    final prevData =
        _aggregate(prevBuckets, prevSales, prevTxns, range.previousStart, _selected);

    // Summary value
    final totalCur = curData.fold<double>(0, (a, b) => a + b);
    final totalPrev = prevData.fold<double>(0, (a, b) => a + b);
    final changePct = totalPrev > 0
        ? ((totalCur - totalPrev) / totalPrev * 100)
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Analytics',
                    style: AppTypography.h3.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
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
                ],
              ),
              // Compare toggle
              GestureDetector(
                onTap: () => setState(() => _showComparison = !_showComparison),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                        'Compare',
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
          const SizedBox(height: 16),

          // ─── Metric Tabs ───
          Row(
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
          const SizedBox(height: 20),

          // ─── Chart ───
          SizedBox(
            height: 200,
            child: _buildChart(curData, prevData, buckets, ds.period),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<double> curData, List<double> prevData,
      List<DateTime> buckets, DashboardPeriod period) {
    if (curData.isEmpty) {
      return Center(
        child: Text(
          'No data for this period',
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.textTertiary),
        ),
      );
    }

    final color = _metricColor(_selected);
    final maxY = [...curData, if (_showComparison) ...prevData]
        .fold<double>(0, (a, b) => a > b ? a : b);
    final safeMaxY = maxY == 0 ? 1.0 : maxY * 1.15;

    final curSpots = List.generate(
        curData.length, (i) => FlSpot(i.toDouble(), curData[i]));
    final prevSpots = _showComparison
        ? List.generate(
            prevData.length, (i) => FlSpot(i.toDouble(), prevData[i]))
        : <FlSpot>[];

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: safeMaxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: safeMaxY / 4,
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
              interval: safeMaxY / 4,
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
                    _bucketLabel(buckets[i], period),
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

  static String _metricLabel(_Metric m) {
    switch (m) {
      case _Metric.sales:
        return 'Sales';
      case _Metric.expenses:
        return 'Expenses';
      case _Metric.profit:
        return 'Profit';
      case _Metric.orders:
        return 'Orders';
    }
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

  static String _bucketLabel(DateTime d, DashboardPeriod period) {
    switch (period.bucketStrategy) {
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
    DateTime start, DateTime end, DashboardPeriod period) {
  final buckets = <DateTime>[];
  switch (period.bucketStrategy) {
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
) {
  if (buckets.isEmpty) return [];
  final values = List.filled(buckets.length, 0.0);

  int bucketIndex(DateTime d) {
    for (int i = buckets.length - 1; i >= 0; i--) {
      if (!d.isBefore(buckets[i])) return i;
    }
    return 0;
  }

  switch (metric) {
    case _Metric.sales:
      // Use income transactions — same source as the Revenue stat card
      for (final t in txns) {
        if ((t as dynamic).isIncome as bool) {
          final idx = bucketIndex((t as dynamic).dateTime as DateTime);
          if (idx >= 0 && idx < values.length) {
            values[idx] += ((t as dynamic).amount as double).abs();
          }
        }
      }
      break;
    case _Metric.expenses:
      for (final t in txns) {
        if ((t as dynamic).amount < 0) {
          final idx = bucketIndex((t as dynamic).dateTime as DateTime);
          if (idx >= 0 && idx < values.length) {
            values[idx] += ((t as dynamic).amount as double).abs();
          }
        }
      }
      break;
    case _Metric.profit:
      // Revenue (income txns) minus expenses (negative txns)
      for (final t in txns) {
        final amount = (t as dynamic).amount as double;
        final isIncome = (t as dynamic).isIncome as bool;
        final idx = bucketIndex((t as dynamic).dateTime as DateTime);
        if (idx >= 0 && idx < values.length) {
          if (isIncome) {
            values[idx] += amount.abs(); // add revenue
          } else {
            values[idx] -= amount.abs(); // subtract expense
          }
        }
      }
      break;
    case _Metric.orders:
      for (final s in sales) {
        final idx = bucketIndex((s as dynamic).date as DateTime);
        if (idx >= 0 && idx < values.length) {
          values[idx] += 1;
        }
      }
      break;
  }

  return values;
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
