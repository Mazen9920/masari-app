import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';

/// The type of financial period selected.
enum FinancialPeriodType { monthEnd, yearEnd }

/// Result from the financial period sheet.
class FinancialPeriodResult {
  final FinancialPeriodType type;
  final DateTimeRange range;
  final String label;

  const FinancialPeriodResult({
    required this.type,
    required this.range,
    required this.label,
  });
}

/// Shows a bottom sheet with Month End / Year End period selector.
Future<FinancialPeriodResult?> showFinancialPeriodSheet(
  BuildContext context, {
  FinancialPeriodResult? current,
}) {
  return showModalBottomSheet<FinancialPeriodResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _FinancialPeriodSheet(current: current),
  );
}

class _FinancialPeriodSheet extends StatefulWidget {
  final FinancialPeriodResult? current;
  const _FinancialPeriodSheet({this.current});

  @override
  State<_FinancialPeriodSheet> createState() => _FinancialPeriodSheetState();
}

class _FinancialPeriodSheetState extends State<_FinancialPeriodSheet> {
  late FinancialPeriodType _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.current?.type ?? FinancialPeriodType.monthEnd;
  }

  /// Generate month-end items: current month going back 24 months.
  List<_PeriodItem> _buildMonths() {
    final now = DateTime.now();
    final items = <_PeriodItem>[];
    for (var i = 0; i < 24; i++) {
      final m = DateTime(now.year, now.month - i);
      final isCurrentMonth = m.year == now.year && m.month == now.month;
      final start = DateTime(m.year, m.month, 1);
      final end = isCurrentMonth
          ? DateTime(now.year, now.month, now.day, 23, 59, 59)
          : DateTime(m.year, m.month + 1, 0, 23, 59, 59); // last day of month
      final label = DateFormat('MMMM yyyy').format(m);
      items.add(_PeriodItem(
        label: label,
        range: DateTimeRange(start: start, end: end),
        type: FinancialPeriodType.monthEnd,
      ));
    }
    return items;
  }

  /// Generate year-end items: current year going back 5 years.
  List<_PeriodItem> _buildYears() {
    final now = DateTime.now();
    final items = <_PeriodItem>[];
    for (var i = 0; i < 6; i++) {
      final year = now.year - i;
      final isCurrentYear = year == now.year;
      final start = DateTime(year, 1, 1);
      final end = isCurrentYear
          ? DateTime(now.year, now.month, now.day, 23, 59, 59)
          : DateTime(year, 12, 31, 23, 59, 59);
      items.add(_PeriodItem(
        label: '$year',
        range: DateTimeRange(start: start, end: end),
        type: FinancialPeriodType.yearEnd,
      ));
    }
    return items;
  }

  void _select(_PeriodItem item) {
    HapticFeedback.selectionClick();
    Navigator.pop(
      context,
      FinancialPeriodResult(
        type: item.type,
        range: item.range,
        label: item.label,
      ),
    );
  }

  bool _isActive(_PeriodItem item) {
    final c = widget.current;
    if (c == null) return false;
    return c.type == item.type && c.label == item.label;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).viewPadding.bottom;
    final items =
        _tab == FinancialPeriodType.monthEnd ? _buildMonths() : _buildYears();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
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
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
            child: Text(
              'Select Period',
              style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
            ),
          ),
          // Segmented control
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(3),
              child: Row(
                children: [
                  _buildTab('Month End', FinancialPeriodType.monthEnd),
                  _buildTab('Year End', FinancialPeriodType.yearEnd),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: AppColors.dividerLight),
          // List
          Flexible(
            child: ListView.separated(
              padding: EdgeInsets.only(bottom: bottomPad + 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: AppColors.dividerLight,
              ),
              itemBuilder: (_, i) {
                final item = items[i];
                final active = _isActive(item);
                return InkWell(
                  onTap: () => _select(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.label,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (active)
                          const Icon(Icons.check_rounded,
                              color: AppColors.textPrimary, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, FinancialPeriodType type) {
    final isActive = _tab == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _tab = type);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: isActive ? AppColors.textPrimary : AppColors.textTertiary,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _PeriodItem {
  final String label;
  final DateTimeRange range;
  final FinancialPeriodType type;
  const _PeriodItem({
    required this.label,
    required this.range,
    required this.type,
  });
}
