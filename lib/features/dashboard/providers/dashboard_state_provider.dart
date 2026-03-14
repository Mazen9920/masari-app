import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

enum DashboardPeriod {
  today,
  yesterday,
  last7Days,
  last30Days,
  last90Days,
  last365Days,
  lastMonth,
  last12Months,
  lastYear,
  weekToDate,
  monthToDate,
  quarterToDate,
  yearToDate,
  custom,
}

extension DashboardPeriodX on DashboardPeriod {
  /// Human-readable label shown in the bottom-sheet list.
  String get label => switch (this) {
        DashboardPeriod.today => 'Today',
        DashboardPeriod.yesterday => 'Yesterday',
        DashboardPeriod.last7Days =>  'Last 7 days',
        DashboardPeriod.last30Days =>  'Last 30 days',
        DashboardPeriod.last90Days =>  'Last 90 days',
        DashboardPeriod.last365Days =>  'Last 365 days',
        DashboardPeriod.lastMonth =>  'Last month',
        DashboardPeriod.last12Months =>  'Last 12 months',
        DashboardPeriod.lastYear =>  'Last year',
        DashboardPeriod.weekToDate =>  'Week to date',
        DashboardPeriod.monthToDate =>  'Month to date',
        DashboardPeriod.quarterToDate =>  'Quarter to date',
        DashboardPeriod.yearToDate =>  'Year to date',
        DashboardPeriod.custom => 'Custom',
      };

  /// Short label for the header button (e.g. "Today", "Last 7d").
  String get shortLabel => switch (this) {
        DashboardPeriod.today => 'Today',
        DashboardPeriod.yesterday => 'Yesterday',
        DashboardPeriod.last7Days =>  'Last 7 days',
        DashboardPeriod.last30Days =>  'Last 30 days',
        DashboardPeriod.last90Days =>  'Last 90 days',
        DashboardPeriod.last365Days =>  'Last 365 days',
        DashboardPeriod.lastMonth =>  'Last month',
        DashboardPeriod.last12Months =>  'Last 12 months',
        DashboardPeriod.lastYear =>  'Last year',
        DashboardPeriod.weekToDate =>  'Week to date',
        DashboardPeriod.monthToDate =>  'Month to date',
        DashboardPeriod.quarterToDate =>  'Quarter to date',
        DashboardPeriod.yearToDate =>  'Year to date',
        DashboardPeriod.custom => 'Custom',
      };

  /// Comparison label for stat cards ("vs yesterday", "vs prior 7 days", etc.).
  String get vsLabel => switch (this) {
        DashboardPeriod.today => 'vs yesterday',
        DashboardPeriod.yesterday => 'vs day before',
        DashboardPeriod.last7Days => 'vs prior 7 days',
        DashboardPeriod.last30Days => 'vs prior 30 days',
        DashboardPeriod.last90Days => 'vs prior 90 days',
        DashboardPeriod.last365Days => 'vs prior 365 days',
        DashboardPeriod.lastMonth => 'vs month before',
        DashboardPeriod.last12Months => 'vs prior 12 months',
        DashboardPeriod.lastYear => 'vs prior year',
        DashboardPeriod.weekToDate => 'vs last week',
        DashboardPeriod.monthToDate => 'vs last month',
        DashboardPeriod.quarterToDate => 'vs last quarter',
        DashboardPeriod.yearToDate => 'vs last year',
        DashboardPeriod.custom => 'vs prior period',
      };

  /// Bucketing strategy: hourly, daily, or monthly.
  BucketStrategy get bucketStrategy => switch (this) {
        DashboardPeriod.today || DashboardPeriod.yesterday => BucketStrategy.hourly,
        DashboardPeriod.last365Days ||
        DashboardPeriod.last12Months ||
        DashboardPeriod.lastYear ||
        DashboardPeriod.yearToDate =>
          BucketStrategy.monthly,
        _ => BucketStrategy.daily,
      };
}

enum BucketStrategy { hourly, daily, monthly }

class DashboardDateRange {
  final DateTime start;
  final DateTime _end;
  final bool isLive;
  final DateTime previousStart;
  final DateTime previousEnd;

  const DashboardDateRange({
    required this.start,
    required DateTime end,
    this.isLive = false,
    required this.previousStart,
    required this.previousEnd,
  }) : _end = end;

  /// For live periods (Today, Last 7 days, etc.) always returns
  /// [DateTime.now()] so that newly-added data falls within the range.
  DateTime get end => isLive ? DateTime.now() : _end;

  String get formattedRange {
    final f = DateFormat( 'MMM d');
    if (start.year != end.year) {
      final ff = DateFormat( 'MMM d, yyyy');
      return '${ff.format(start)} – ${ff.format(end)}';
    }
    return '${f.format(start)} – ${f.format(end)}';
  }
}

class DashboardState {
  final DashboardPeriod period;
  final DashboardDateRange range;

  const DashboardState({required this.period, required this.range});

  static DashboardDateRange _computeRange(DashboardPeriod period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime start;
    DateTime end = now;
    bool isLive = true;

    switch (period) {
      case DashboardPeriod.today:
        start = today;
      case DashboardPeriod.yesterday:
        start = today.subtract(const Duration(days: 1));
        end = DateTime(today.year, today.month, today.day)
            .subtract(const Duration(microseconds: 1));
        isLive = false;
      case DashboardPeriod.last7Days:
        start = today.subtract(const Duration(days: 6));
      case DashboardPeriod.last30Days:
        start = today.subtract(const Duration(days: 29));
      case DashboardPeriod.last90Days:
        start = today.subtract(const Duration(days: 89));
      case DashboardPeriod.last365Days:
        start = today.subtract(const Duration(days: 364));
      case DashboardPeriod.lastMonth:
        start = DateTime(now.year, now.month - 1, 1);
        end = DateTime(now.year, now.month, 0, 23, 59, 59);
        isLive = false;
      case DashboardPeriod.last12Months:
        start = DateTime(now.year - 1, now.month, now.day);
      case DashboardPeriod.lastYear:
        start = DateTime(now.year - 1, 1, 1);
        end = DateTime(now.year - 1, 12, 31, 23, 59, 59);
        isLive = false;
      case DashboardPeriod.weekToDate:
        final weekday = now.weekday; // Mon=1
        start = DateTime(now.year, now.month, now.day - weekday + 1);
      case DashboardPeriod.monthToDate:
        start = DateTime(now.year, now.month, 1);
      case DashboardPeriod.quarterToDate:
        final qMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        start = DateTime(now.year, qMonth, 1);
      case DashboardPeriod.yearToDate:
        start = DateTime(now.year, 1, 1);
      case DashboardPeriod.custom:
        // Should never be called — use setCustomRange instead
        start = DateTime(now.year, now.month, 1);
        isLive = false;
    }

    // Compute previous period as mirror of same duration
    final duration = end.difference(start);
    final prevEnd = start.subtract(const Duration(microseconds: 1));
    final prevStart = start.subtract(duration.isNegative
        ? const Duration(days: 1)
        : duration + const Duration(microseconds: 1));

    return DashboardDateRange(
      start: start,
      end: end,
      isLive: isLive,
      previousStart: prevStart,
      previousEnd: prevEnd,
    );
  }

  static DashboardDateRange _computeCustomRange(DateTime start, DateTime end) {
    final duration = end.difference(start);
    final prevEnd = start.subtract(const Duration(microseconds: 1));
    final prevStart = start.subtract(duration);
    return DashboardDateRange(
      start: start,
      end: end,
      previousStart: prevStart,
      previousEnd: prevEnd,
    );
  }

  factory DashboardState.fromPeriod(DashboardPeriod period) {
    return DashboardState(period: period, range: _computeRange(period));
  }

  factory DashboardState.customRange(DateTime start, DateTime end) {
    return DashboardState(
      period: DashboardPeriod.custom,
      range: _computeCustomRange(start, end),
    );
  }
}

class DashboardStateNotifier extends Notifier<DashboardState> {
  @override
  DashboardState build() =>
      DashboardState.fromPeriod(DashboardPeriod.today);

  void setPeriod(DashboardPeriod period) {
    if (period == DashboardPeriod.custom) return;
    state = DashboardState.fromPeriod(period);
  }

  void setCustomRange(DateTime start, DateTime end) {
    state = DashboardState.customRange(start, end);
  }
}

final dashboardStateProvider =
    NotifierProvider<DashboardStateNotifier, DashboardState>(
  DashboardStateNotifier.new,
);
