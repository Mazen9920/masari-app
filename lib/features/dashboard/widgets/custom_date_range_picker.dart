import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../providers/dashboard_state_provider.dart';

/// Result from the date-range sheet.
/// Either a preset [period] or a [customRange].
class DateRangeResult {
  final DashboardPeriod? period;
  final DateTimeRange? customRange;
  const DateRangeResult.preset(DashboardPeriod p)
      : period = p,
        customRange = null;
  const DateRangeResult.custom(DateTimeRange r)
      : period = null,
        customRange = r;
}

/// Shopify-style date range bottom sheet.
Future<DateRangeResult?> showDateRangeSheet(
  BuildContext context, {
  required DashboardPeriod currentPeriod,
  DashboardDateRange? currentRange,
}) {
  return showModalBottomSheet<DateRangeResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DateRangeSheet(
      currentPeriod: currentPeriod,
      currentRange: currentRange,
    ),
  );
}

class _DateRangeSheet extends StatefulWidget {
  final DashboardPeriod currentPeriod;
  final DashboardDateRange? currentRange;

  const _DateRangeSheet({
    required this.currentPeriod,
    this.currentRange,
  });

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

enum _SheetView { list, calendar }

class _DateRangeSheetState extends State<_DateRangeSheet> {
  _SheetView _view = _SheetView.list;

  // Calendar state
  late DateTime _focusedMonth;
  DateTime? _calStart;
  DateTime? _calEnd;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    if (widget.currentPeriod == DashboardPeriod.custom &&
        widget.currentRange != null) {
      _calStart = widget.currentRange!.start;
      _calEnd = widget.currentRange!.end;
    }
  }

  /// The preset periods shown in the list (excluding custom).
  static const _presets = [
    DashboardPeriod.today,
    DashboardPeriod.yesterday,
    DashboardPeriod.last7Days,
    DashboardPeriod.last30Days,
    DashboardPeriod.last90Days,
    DashboardPeriod.last365Days,
    DashboardPeriod.lastMonth,
    DashboardPeriod.last12Months,
    DashboardPeriod.lastYear,
    DashboardPeriod.weekToDate,
    DashboardPeriod.monthToDate,
    DashboardPeriod.quarterToDate,
    DashboardPeriod.yearToDate,
  ];

  void _selectPreset(DashboardPeriod p) {
    HapticFeedback.selectionClick();
    Navigator.pop(context, DateRangeResult.preset(p));
  }

  void _onCalDayTap(DateTime day) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_calStart == null || _calEnd != null) {
        _calStart = day;
        _calEnd = null;
      } else {
        if (day.isBefore(_calStart!)) {
          _calEnd = _calStart;
          _calStart = day;
        } else {
          _calEnd = day;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
            child: Row(
              children: [
                Text(
                  'Date range',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (_view == _SheetView.calendar)
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                    color: AppColors.textSecondary,
                    onPressed: () => setState(() => _view = _SheetView.list),
                  ),
              ],
            ),
          ),
          if (_view == _SheetView.list) ...[
            // Subtitle
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.currentPeriod == DashboardPeriod.custom &&
                          widget.currentRange != null
                      ? widget.currentRange!.formattedRange
                      : widget.currentPeriod.label,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
          const Divider(height: 1, color: AppColors.dividerLight),
          // Body
          Flexible(
            child: _view == _SheetView.list
                ? _buildListView(bottomPad)
                : _buildCalendarView(bottomPad),
          ),
        ],
      ),
    );
  }

  // ─── List View ────────────────────────────────────────────

  Widget _buildListView(double bottomPad) {
    return ListView(
      padding: EdgeInsets.only(bottom: bottomPad + 16),
      children: [
        // "Fixed dates" row → opens calendar
        _buildActionTile(
          icon: Icons.calendar_today_rounded,
          title: 'Fixed dates',
          subtitle: _calStart != null && _calEnd != null
              ? '${DateFormat('MMM d').format(_calStart!)} – ${DateFormat('MMM d').format(_calEnd!)}'
              : null,
          onTap: () => setState(() => _view = _SheetView.calendar),
          trailing: const Icon(Icons.chevron_right_rounded,
              color: AppColors.textTertiary, size: 22),
        ),
        const Divider(height: 1, indent: 56, color: AppColors.dividerLight),
        // Preset periods
        ..._presets.map((p) {
          final isActive = widget.currentPeriod == p;
          return Column(
            children: [
              _buildPresetTile(p, isActive),
              const Divider(
                  height: 1, indent: 20, endIndent: 20, color: AppColors.dividerLight),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildPresetTile(DashboardPeriod p, bool isActive) {
    return InkWell(
      onTap: () => _selectPreset(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                p.label,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (isActive)
              const Icon(Icons.check_rounded,
                  color: AppColors.textPrimary, size: 20),
          ],
        ),
      ),
    );
  }

  // ─── Calendar View ────────────────────────────────────────

  Widget _buildCalendarView(double bottomPad) {
    return Column(
      children: [
        // Range display
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _calStart != null && _calEnd != null
                  ? '${DateFormat('MMM d, yyyy').format(_calStart!)} – ${DateFormat('MMM d, yyyy').format(_calEnd!)}'
                  : _calStart != null
                      ? '${DateFormat('MMM d, yyyy').format(_calStart!)} – Select end'
                      : 'Select start date',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.secondaryBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        // Month nav
        _buildMonthNav(),
        // Weekday header
        _buildWeekdayHeader(),
        // Grid
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildCalendarGrid(),
          ),
        ),
        // Apply button
        _buildApplyBar(bottomPad),
      ],
    );
  }

  Widget _buildMonthNav() {
    final label = DateFormat('MMMM yyyy').format(_focusedMonth);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _navButton(Icons.chevron_left_rounded, () {
            setState(() {
              _focusedMonth = DateTime(
                _focusedMonth.year,
                _focusedMonth.month - 1,
              );
            });
          }),
          Text(label,
              style: AppTypography.labelLarge
                  .copyWith(color: AppColors.textPrimary)),
          _navButton(Icons.chevron_right_rounded, () {
            final now = DateTime.now();
            final next = DateTime(
              _focusedMonth.year,
              _focusedMonth.month + 1,
            );
            if (!next.isAfter(DateTime(now.year, now.month + 1))) {
              setState(() => _focusedMonth = next);
            }
          }),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 20),
      ),
    );
  }

  Widget _buildWeekdayHeader() {
    const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: days
            .map((d) => Expanded(
                  child: Center(
                    child: Text(d,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        )),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final year = _focusedMonth.year;
    final month = _focusedMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final firstWeekday = DateTime(year, month, 1).weekday % 7; // Sun = 0
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final cells = <Widget>[];

    for (int i = 0; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }

    for (int d = 1; d <= daysInMonth; d++) {
      final day = DateTime(year, month, d);
      final isFuture = day.isAfter(today);
      final isStart = _calStart != null && _sameDay(day, _calStart!);
      final isEnd = _calEnd != null && _sameDay(day, _calEnd!);
      final inRange = _inRange(day);
      final isTodayMark = _sameDay(day, today);

      cells.add(GestureDetector(
        onTap: isFuture ? null : () => _onCalDayTap(day),
        child: _DayCell(
          day: d,
          isStart: isStart,
          isEnd: isEnd,
          inRange: inRange,
          isToday: isTodayMark,
          isFuture: isFuture,
        ),
      ));
    }

    final rows = <Widget>[];
    for (int i = 0; i < cells.length; i += 7) {
      final end = (i + 7 > cells.length) ? cells.length : i + 7;
      final rowCells = List<Widget>.from(cells.sublist(i, end));
      while (rowCells.length < 7) {
        rowCells.add(const SizedBox());
      }
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: rowCells.map((c) => Expanded(child: c)).toList()),
      ));
    }
    return Column(children: rows);
  }

  Widget _buildApplyBar(double bottomPad) {
    final canApply = _calStart != null && _calEnd != null;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, bottomPad + 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.dividerLight)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: canApply
              ? () {
                  HapticFeedback.mediumImpact();
                  Navigator.pop(
                    context,
                    DateRangeResult.custom(
                      DateTimeRange(start: _calStart!, end: _calEnd!),
                    ),
                  );
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryNavy,
            disabledBackgroundColor: AppColors.borderLight,
            foregroundColor: Colors.white,
            disabledForegroundColor: AppColors.textTertiary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Apply',
            style: AppTypography.labelLarge.copyWith(
              color: canApply ? Colors.white : AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  // helpers
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _inRange(DateTime day) {
    if (_calStart == null || _calEnd == null) return false;
    return day.isAfter(_calStart!.subtract(const Duration(days: 1))) &&
        day.isBefore(_calEnd!.add(const Duration(days: 1)));
  }
}

// ─── Day Cell ─────────────────────────────────────────────

class _DayCell extends StatelessWidget {
  final int day;
  final bool isStart;
  final bool isEnd;
  final bool inRange;
  final bool isToday;
  final bool isFuture;

  const _DayCell({
    required this.day,
    required this.isStart,
    required this.isEnd,
    required this.inRange,
    required this.isToday,
    required this.isFuture,
  });

  @override
  Widget build(BuildContext context) {
    final isEndpoint = isStart || isEnd;

    // Range band
    Color? bandColor;
    BorderRadius? bandRadius;
    if (inRange && !isEndpoint) {
      bandColor = AppColors.primaryNavy.withValues(alpha: 0.07);
    } else if (isStart && !isEnd) {
      bandColor = AppColors.primaryNavy.withValues(alpha: 0.07);
      bandRadius = const BorderRadius.horizontal(left: Radius.circular(20));
    } else if (isEnd && !isStart) {
      bandColor = AppColors.primaryNavy.withValues(alpha: 0.07);
      bandRadius = const BorderRadius.horizontal(right: Radius.circular(20));
    }

    // Circle
    BoxDecoration? circle;
    if (isEndpoint) {
      circle = const BoxDecoration(
        color: AppColors.primaryNavy,
        shape: BoxShape.circle,
      );
    }

    // Text
    Color textColor;
    FontWeight weight = FontWeight.w400;
    if (isFuture) {
      textColor = AppColors.textTertiary.withValues(alpha: 0.4);
    } else if (isEndpoint) {
      textColor = Colors.white;
      weight = FontWeight.w700;
    } else if (isToday) {
      textColor = AppColors.secondaryBlue;
      weight = FontWeight.w700;
    } else if (inRange) {
      textColor = AppColors.primaryNavy;
      weight = FontWeight.w600;
    } else {
      textColor = AppColors.textPrimary;
    }

    return SizedBox(
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (bandColor != null)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                    color: bandColor, borderRadius: bandRadius),
              ),
            ),
          Container(
            width: 36,
            height: 36,
            decoration: circle,
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: AppTypography.bodySmall.copyWith(
                color: textColor,
                fontWeight: weight,
                fontSize: 14,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
