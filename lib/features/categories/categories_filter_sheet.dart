import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';

/// Filter/sort options returned from the bottom sheet.
class CategoryFilterResult {
  final CategorySortBy sortBy;
  final String dateRange;
  final bool hideEmpty;
  final bool showOverBudget;
  final Set<String> categoryTypes;

  const CategoryFilterResult({
    this.sortBy = CategorySortBy.highestAmount,
    this.dateRange = 'This Month',
    this.hideEmpty = false,
    this.showOverBudget = false,
    this.categoryTypes = const {},
  });
}

enum CategorySortBy { highestAmount, mostTransactions, lowestAmount, nameAZ }

/// Show the categories filter bottom sheet. Returns null if dismissed.
Future<CategoryFilterResult?> showCategoriesFilterSheet(
  BuildContext context, {
  CategoryFilterResult? current,
}) {
  return showModalBottomSheet<CategoryFilterResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategoriesFilterSheet(initial: current),
  );
}

class _CategoriesFilterSheet extends StatefulWidget {
  final CategoryFilterResult? initial;

  const _CategoriesFilterSheet({this.initial});

  @override
  State<_CategoriesFilterSheet> createState() => _CategoriesFilterSheetState();
}

class _CategoriesFilterSheetState extends State<_CategoriesFilterSheet> {
  late CategorySortBy _sortBy;
  late String _dateRange;
  late bool _hideEmpty;
  late bool _showOverBudget;
  late Set<String> _categoryTypes;

  static const _sortOptions = [
    ('Highest Amount', CategorySortBy.highestAmount),
    ('Most Transactions', CategorySortBy.mostTransactions),
    ('Lowest Amount', CategorySortBy.lowestAmount),
    ('Name (A-Z)', CategorySortBy.nameAZ),
  ];

  static const _dateOptions = ['This Month', 'Last Month', 'Quarter to Date', 'Custom'];
  static const _typeOptions = ['Operational', 'Marketing', 'Fixed Costs', 'Variable'];

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _sortBy = init?.sortBy ?? CategorySortBy.highestAmount;
    _dateRange = init?.dateRange ?? 'This Month';
    _hideEmpty = init?.hideEmpty ?? false;
    _showOverBudget = init?.showOverBudget ?? false;
    _categoryTypes = Set.from(init?.categoryTypes ?? {'Operational', 'Variable'});
  }

  void _apply() {
    HapticFeedback.mediumImpact();
    Navigator.pop(
      context,
      CategoryFilterResult(
        sortBy: _sortBy,
        dateRange: _dateRange,
        hideEmpty: _hideEmpty,
        showOverBudget: _showOverBudget,
        categoryTypes: _categoryTypes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          _buildHeader(),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSortSection(),
                  _divider(),
                  _buildDateSection(),
                  _divider(),
                  _buildStatusSection(),
                  _divider(),
                  _buildTypesSection(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // Apply button
          _buildApplyButton(),
        ],
      ),
    ).animate().slideY(begin: 0.1, end: 0, duration: 300.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Filter & Sort',
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Divider(color: AppColors.borderLight.withValues(alpha: 0.5), height: 1),
    );
  }

  // ─── Sort By ───
  Widget _buildSortSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sort By',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        ...List.generate(_sortOptions.length, (i) {
          final (label, value) = _sortOptions[i];
          final isSelected = _sortBy == value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _sortBy = value);
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? AppColors.accentOrange : const Color(0xFFCCC),
                        width: 2,
                      ),
                      color: isSelected ? AppColors.accentOrange : Colors.transparent,
                    ),
                    child: isSelected
                        ? Center(
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // ─── Date Range ───
  Widget _buildDateSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Date Range',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 3.0,
          children: _dateOptions.map((label) {
            final isSelected = _dateRange == label;
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _dateRange = label);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.accentOrange.withValues(alpha: 0.05) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? AppColors.accentOrange : AppColors.borderLight,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppTypography.labelSmall.copyWith(
                          color: isSelected ? AppColors.accentOrange : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (label == 'Custom') ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 14,
                          color: isSelected ? AppColors.accentOrange : AppColors.textSecondary,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Category Status ───
  Widget _buildStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category Status',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        _toggleRow('Hide Empty Categories', _hideEmpty, (v) => setState(() => _hideEmpty = v)),
        const SizedBox(height: 16),
        _toggleRow('Show Only Over Budget', _showOverBudget, (v) => setState(() => _showOverBudget = v)),
      ],
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: (v) {
            HapticFeedback.lightImpact();
            onChanged(v);
          },
          activeColor: AppColors.accentOrange,
        ),
      ],
    );
  }

  // ─── Category Types ───
  Widget _buildTypesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Category Types',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _typeOptions.map((type) {
            final isSelected = _categoryTypes.contains(type);
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  if (isSelected) {
                    _categoryTypes.remove(type);
                  } else {
                    _categoryTypes.add(type);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryNavy : Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: isSelected ? AppColors.primaryNavy : AppColors.borderLight,
                  ),
                ),
                child: Text(
                  type,
                  style: AppTypography.labelSmall.copyWith(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ─── Apply Button ───
  Widget _buildApplyButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentOrange.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _apply,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentOrange,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              'Apply Filters',
              style: AppTypography.labelLarge.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
