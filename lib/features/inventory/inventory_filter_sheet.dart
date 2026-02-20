import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';

/// Result returned from the filter sheet
class InventoryFilterResult {
  final int sortIndex; // 0=Stock Low→High, 1=High→Low, 2=A-Z, 3=Value High→Low
  final Set<String> statusFilters; // 'In Stock', 'Low Stock', 'Out of Stock'
  final Set<String> categories;
  final Set<String> suppliers;
  final double? minPrice;
  final double? maxPrice;

  const InventoryFilterResult({
    this.sortIndex = 0,
    this.statusFilters = const {},
    this.categories = const {},
    this.suppliers = const {},
    this.minPrice,
    this.maxPrice,
  });
}

Future<InventoryFilterResult?> showInventoryFilterSheet(
  BuildContext context, {
  InventoryFilterResult? initial,
}) {
  return showModalBottomSheet<InventoryFilterResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _InventoryFilterSheet(initial: initial),
  );
}

class _InventoryFilterSheet extends StatefulWidget {
  final InventoryFilterResult? initial;
  const _InventoryFilterSheet({this.initial});

  @override
  State<_InventoryFilterSheet> createState() => _InventoryFilterSheetState();
}

class _InventoryFilterSheetState extends State<_InventoryFilterSheet> {
  int _sortIndex = 0;
  final Set<String> _statusFilters = {};
  final Set<String> _categories = {};
  final Set<String> _suppliers = {};
  final _minPriceController = TextEditingController();
  final _maxPriceController = TextEditingController();

  static const _sortOptions = [
    'Stock: Low to High',
    'Stock: High to Low',
    'Name: A-Z',
    'Value: High to Low',
  ];

  static const _statusOptions = ['In Stock', 'Low Stock', 'Out of Stock'];

  static const _categoryOptions = [
    'Gym Gear',
    'Weights',
    'Yoga',
    'Supplements',
    'Accessories',
  ];

  static const _supplierOptions = [
    'IronFit',
    'HeavyLift',
    'ZenLife',
    'GymSupps',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _sortIndex = widget.initial!.sortIndex;
      _statusFilters.addAll(widget.initial!.statusFilters);
      _categories.addAll(widget.initial!.categories);
      _suppliers.addAll(widget.initial!.suppliers);
      if (widget.initial!.minPrice != null) {
        _minPriceController.text = widget.initial!.minPrice!.toStringAsFixed(0);
      }
      if (widget.initial!.maxPrice != null) {
        _maxPriceController.text = widget.initial!.maxPrice!.toStringAsFixed(0);
      }
    }
  }

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
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
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSortSection(),
                  _divider(),
                  _buildStatusSection(),
                  _divider(),
                  _buildCategorySection(),
                  _divider(),
                  _buildSupplierSection(),
                  _divider(),
                  _buildPriceRangeSection(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
          _buildBottomActions(),
        ],
      ),
    ).animate().slideY(begin: 0.1, end: 0, duration: 300.ms, curve: Curves.easeOutCubic);
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFDDDDDD),
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
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
                icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Divider(color: AppColors.borderLight.withValues(alpha: 0.5), height: 1),
    );
  }

  // ── Sort ────────────────────────────────────────────
  Widget _buildSortSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Sort By'),
        const SizedBox(height: 10),
        ...List.generate(_sortOptions.length, (i) {
          final isSelected = _sortIndex == i;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _sortIndex = i);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primaryNavy
                        : AppColors.borderLight,
                  ),
                  color: isSelected
                      ? AppColors.primaryNavy.withValues(alpha: 0.05)
                      : Colors.transparent,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _sortOptions[i],
                      style: AppTypography.labelMedium.copyWith(
                        color: isSelected
                            ? AppColors.primaryNavy
                            : AppColors.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryNavy
                              : AppColors.textTertiary,
                          width: isSelected ? 6 : 1.5,
                        ),
                      ),
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

  // ── Status ─────────────────────────────────────────
  Widget _buildStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Stock Status'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _statusOptions.map((status) {
            final isSelected = _statusFilters.contains(status);
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  isSelected
                      ? _statusFilters.remove(status)
                      : _statusFilters.add(status);
                });
              },
              child: AnimatedContainer(
                duration: 200.ms,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryNavy
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primaryNavy
                        : AppColors.borderLight,
                  ),
                ),
                child: Text(
                  status,
                  style: AppTypography.labelMedium.copyWith(
                    color:
                        isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Category ───────────────────────────────────────
  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Category'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _categoryOptions.map((cat) {
            final isSelected = _categories.contains(cat);
            return _buildChip(cat, isSelected, () {
              HapticFeedback.lightImpact();
              setState(() {
                isSelected
                    ? _categories.remove(cat)
                    : _categories.add(cat);
              });
            });
          }).toList(),
        ),
      ],
    );
  }

  // ── Supplier ───────────────────────────────────────
  Widget _buildSupplierSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Supplier'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _supplierOptions.map((sup) {
            final isSelected = _suppliers.contains(sup);
            return _buildChip(sup, isSelected, () {
              HapticFeedback.lightImpact();
              setState(() {
                isSelected
                    ? _suppliers.remove(sup)
                    : _suppliers.add(sup);
              });
            });
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primaryNavy : AppColors.borderLight,
          ),
          color: isSelected
              ? AppColors.primaryNavy.withValues(alpha: 0.05)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: isSelected
                    ? AppColors.primaryNavy
                    : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 4),
              Icon(Icons.close, size: 14, color: AppColors.primaryNavy),
            ],
          ],
        ),
      ),
    );
  }

  // ── Price Range ────────────────────────────────────
  Widget _buildPriceRangeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Price Range (EGP)'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _priceField(_minPriceController, 'Min', '0'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                width: 16,
                height: 1,
                color: AppColors.borderLight,
              ),
            ),
            Expanded(
              child: _priceField(_maxPriceController, 'Max', '10000'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _priceField(
      TextEditingController controller, String label, String hint) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTypography.captionSmall
            .copyWith(color: AppColors.textTertiary, fontSize: 11),
        hintText: hint,
        hintStyle: AppTypography.bodySmall
            .copyWith(color: AppColors.textTertiary),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primaryNavy, width: 1.5),
        ),
      ),
      style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.captionSmall.copyWith(
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
        fontSize: 11,
      ),
    );
  }

  // ── Bottom Actions ─────────────────────────────────
  Widget _buildBottomActions() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.pop(
                  context,
                  InventoryFilterResult(
                    sortIndex: _sortIndex,
                    statusFilters: Set.from(_statusFilters),
                    categories: Set.from(_categories),
                    suppliers: Set.from(_suppliers),
                    minPrice: double.tryParse(_minPriceController.text),
                    maxPrice: double.tryParse(_maxPriceController.text),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentOrange,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
              child: Text(
                'Apply Filters',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                _sortIndex = 0;
                _statusFilters.clear();
                _categories.clear();
                _suppliers.clear();
                _minPriceController.clear();
                _maxPriceController.clear();
              });
            },
            child: Text(
              'Reset All',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
