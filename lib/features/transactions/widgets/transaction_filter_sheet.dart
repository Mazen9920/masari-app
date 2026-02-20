import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../shared/models/transaction_model.dart';
import '../../../shared/models/category_data.dart';

/// Filter bottom sheet for transactions.
/// Returns a [TransactionFilter] when "Apply Filters" is tapped.
class TransactionFilterSheet extends StatefulWidget {
  final TransactionFilter initialFilter;

  const TransactionFilterSheet({
    super.key,
    required this.initialFilter,
  });

  @override
  State<TransactionFilterSheet> createState() => _TransactionFilterSheetState();
}

class _TransactionFilterSheetState extends State<TransactionFilterSheet> {
  late TransactionType _selectedType;
  late RangeValues _amountRange;
  late Set<String> _selectedCategories;

  // Categories displayed in filter
  static final _filterCategories = [
    CategoryData.findByName('Food & Dining'),
    CategoryData.findByName('Shopping'),
    CategoryData.findByName('Transport'),
    CategoryData.findByName('Utilities'),
    CategoryData.findByName('Entertainment'),
    CategoryData.findByName('Health'),
    CategoryData.findByName('Groceries'),
    CategoryData.findByName('Bills'),
    CategoryData.findByName('Rent'),
    CategoryData.findByName('Education'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialFilter.type;
    _amountRange = widget.initialFilter.amountRange;
    _selectedCategories = Set.from(widget.initialFilter.selectedCategories);
  }

  void _reset() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedType = TransactionType.all;
      _amountRange = const RangeValues(0, 10000);
      _selectedCategories.clear();
    });
  }

  void _apply() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(
      TransactionFilter(
        type: _selectedType,
        amountRange: _amountRange,
        selectedCategories: _selectedCategories,
      ),
    );
  }

  int get _activeFilterCount {
    int count = 0;
    if (_selectedType != TransactionType.all) count++;
    if (_amountRange != const RangeValues(0, 10000)) count++;
    count += _selectedCategories.length;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filter Transactions',
                  style: AppTypography.h2.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                GestureDetector(
                  onTap: _reset,
                  child: Text(
                    'Reset',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.accentOrange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Container(height: 1, color: AppColors.borderLight.withOpacity(0.5)),

          // Scrollable content
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20, 20, 20, 100 + bottomPadding),
              children: [
                _buildTypeSelector(),
                const SizedBox(height: 28),
                _buildAmountRange(),
                const SizedBox(height: 28),
                _buildCategoryList(),
              ],
            ),
          ),

          // Sticky apply button
          Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPadding),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: AppColors.borderLight.withOpacity(0.5)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  shadowColor: AppColors.accentOrange.withOpacity(0.3),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Apply Filters',
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    if (_activeFilterCount > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$_activeFilterCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  TYPE SELECTOR (All / Income / Expense)
  // ═══════════════════════════════════════════════════
  Widget _buildTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Transaction Type'),
        const SizedBox(height: 10),
        Container(
          height: 46,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.backgroundLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: TransactionType.values.map((type) {
              final isSelected = _selectedType == type;
              final label = switch (type) {
                TransactionType.all => 'All',
                TransactionType.income => 'Income',
                TransactionType.expense => 'Expense',
              };
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedType = type);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: AppTypography.labelMedium.copyWith(
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  AMOUNT RANGE SLIDER
  // ═══════════════════════════════════════════════════
  Widget _buildAmountRange() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionLabel('Amount Range'),
            Text(
              '\$${_amountRange.start.toInt()} - \$${_amountRange.end.toInt() >= 10000 ? '10k+' : _amountRange.end.toInt().toString()}',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.accentOrange,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.accentOrange,
            inactiveTrackColor: AppColors.borderLight,
            thumbColor: Colors.white,
            overlayColor: AppColors.accentOrange.withOpacity(0.1),
            thumbShape: _CustomThumbShape(),
            trackHeight: 4,
            rangeThumbShape: _CustomRangeThumbShape(),
          ),
          child: RangeSlider(
            values: _amountRange,
            min: 0,
            max: 10000,
            divisions: 100,
            onChanged: (values) {
              setState(() => _amountRange = values);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '\$0',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '\$10k+',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  CATEGORY LIST
  // ═══════════════════════════════════════════════════
  Widget _buildCategoryList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Category'),
        const SizedBox(height: 12),
        ...List.generate(_filterCategories.length, (index) {
          final cat = _filterCategories[index];
          final isChecked = _selectedCategories.contains(cat.name);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (isChecked) {
                    _selectedCategories.remove(cat.name);
                  } else {
                    _selectedCategories.add(cat.name);
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isChecked
                      ? AppColors.accentOrange.withOpacity(0.04)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isChecked
                        ? AppColors.accentOrange.withOpacity(0.25)
                        : AppColors.borderLight,
                    width: isChecked ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Icon
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isChecked ? Colors.white : AppColors.backgroundLight,
                        boxShadow: isChecked
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 4,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        cat.icon,
                        size: 20,
                        color: isChecked
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Name
                    Expanded(
                      child: Text(
                        cat.name,
                        style: AppTypography.labelMedium.copyWith(
                          color: isChecked
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight: isChecked
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),

                    // Checkbox
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isChecked
                            ? AppColors.accentOrange
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: isChecked
                              ? AppColors.accentOrange
                              : AppColors.textTertiary.withOpacity(0.4),
                          width: 2,
                        ),
                      ),
                      child: isChecked
                          ? const Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.captionSmall.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
        fontSize: 11,
      ),
    );
  }
}

// Custom range slider thumb
class _CustomRangeThumbShape extends RangeSliderThumbShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(24, 24);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool? isDiscrete,
    bool? isEnabled,
    bool? isOnTop,
    bool? isPressed,
    required SliderThemeData sliderTheme,
    TextDirection? textDirection,
    Thumb? thumb,
  }) {
    final canvas = context.canvas;

    // Shadow
    canvas.drawCircle(
      center + const Offset(0, 1),
      12,
      Paint()
        ..color = Colors.black.withOpacity(0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // White circle
    canvas.drawCircle(
      center,
      12,
      Paint()..color = Colors.white,
    );

    // Orange border
    canvas.drawCircle(
      center,
      12,
      Paint()
        ..color = AppColors.accentOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }
}

// Custom single slider thumb (used for consistency)
class _CustomThumbShape extends SliderComponentShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(24, 24);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;

    canvas.drawCircle(
      center + const Offset(0, 1),
      12,
      Paint()
        ..color = Colors.black.withOpacity(0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    canvas.drawCircle(center, 12, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      12,
      Paint()
        ..color = AppColors.accentOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }
}
