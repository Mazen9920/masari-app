import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/models/category_data.dart';

class EditCategoryScreen extends ConsumerStatefulWidget {
  final CategoryData category;

  const EditCategoryScreen({super.key, required this.category});

  @override
  ConsumerState<EditCategoryScreen> createState() =>
      _EditCategoryScreenState();
}

class _EditCategoryScreenState extends ConsumerState<EditCategoryScreen> {
  late final TextEditingController _nameController;
  late bool _isExpense;
  late int _selectedIconIndex;
  late int _selectedColorIndex;
  bool _hasBudget = true;
  late final TextEditingController _budgetController;

  // ── icons & colours identical to the add-sheet ──────────
  static const _icons = [
    Icons.star_rounded,
    Icons.shopping_bag_rounded,
    Icons.restaurant_rounded,
    Icons.commute_rounded,
    Icons.grid_view_rounded,
    Icons.work_rounded,
    Icons.campaign_rounded,
    Icons.flight_rounded,
    Icons.home_rounded,
    Icons.fitness_center_rounded,
  ];

  static const _colors = [
    Color(0xFFEF4444), // red
    Color(0xFFF97316), // orange
    Color(0xFFFBBF24), // amber
    Color(0xFF22C55E), // green
    Color(0xFF14B8A6), // teal
    Color(0xFF3B82F6), // blue
    Color(0xFF6366F1), // indigo
    Color(0xFF8B5CF6), // purple
    Color(0xFFEC4899), // pink
    Color(0xFF64748B), // slate
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.name);
    _isExpense = widget.category.isExpense;
    _hasBudget = widget.category.budgetLimit != null;
    _budgetController = TextEditingController(text: widget.category.budgetLimit?.toStringAsFixed(0) ?? '');

    // match current icon/color to available palette
    _selectedIconIndex = _icons.indexWhere((i) => i == widget.category.iconData);
    if (_selectedIconIndex < 0) _selectedIconIndex = 3; // fallback

    _selectedColorIndex = _colors.indexWhere((c) => c.toARGB32() == widget.category.displayColor.toARGB32());
    if (_selectedColorIndex < 0) _selectedColorIndex = 0;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  // ── Save ────────────────────────────────────────────
  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }

    double? budgetLimit;
    if (_hasBudget) {
      final budgetText = _budgetController.text.trim().replaceAll(',', '');
      if (budgetText.isNotEmpty) {
        budgetLimit = double.tryParse(budgetText);
        if (budgetLimit == null || budgetLimit <= 0) {
          HapticFeedback.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.invalidBudgetAmount)),
          );
          return;
        }
        if (budgetLimit > 10000000) {
          HapticFeedback.heavyImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.budgetExceedsMax)),
          );
          return;
        }
      }
    }

    final color = _colors[_selectedColorIndex];
    final selectedIcon = _icons[_selectedIconIndex];
    final updated = CategoryData(
      id: widget.category.id,
      userId: widget.category.userId,
      name: name,
      iconName: CategoryDataUIExt.iconNameFromData(selectedIcon),
      colorValue: color.toARGB32(),
      bgColorValue: color.withValues(alpha: 0.1).toARGB32(),
      isExpense: _isExpense,
      budgetLimit: budgetLimit,
      createdAt: widget.category.createdAt,
      updatedAt: DateTime.now(),
    );

    ref
        .read(categoriesProvider.notifier)
        .updateCategory(updated);
    HapticFeedback.mediumImpact();
    context.pop(updated);
  }

  // ── Delete ──────────────────────────────────────────
  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          AppLocalizations.of(context)!.deleteCategory,
          style: AppTypography.h3
              .copyWith(fontWeight: FontWeight.w700, color: AppColors.danger),
        ),
        content: Text(
          AppLocalizations.of(context)!.deleteCategoryConfirm(widget.category.name),
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.cancel,
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.textTertiary)),
          ),
          ElevatedButton(
            onPressed: () {
              ref
                  .read(categoriesProvider.notifier)
                  .removeCategory(widget.category.id);
              HapticFeedback.mediumImpact();
              Navigator.pop(ctx); // dialog
              // Navigate safely back to categories list
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) context.go(AppRoutes.categories);
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
                child: Column(
                  children: [
                    _buildHeroPreview(),
                    const SizedBox(height: 28),
                    _buildConfigCard(),
                    const SizedBox(height: 28),
                    _buildDeleteButton(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  HEADER – Cancel / Title / Save
  // ═══════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: () => context.pop(),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ),
          const Spacer(),
          Text(
            AppLocalizations.of(context)!.editCategory,
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _save,
            child: Text(
              AppLocalizations.of(context)!.save,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.accentOrange,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  HERO ICON PREVIEW
  // ═══════════════════════════════════════════════════
  Widget _buildHeroPreview() {
    final color = _colors[_selectedColorIndex];
    final icon = _icons[_selectedIconIndex];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: 250.ms,
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(icon, size: 40, color: Colors.white),
        ),
        Positioned(
          bottom: -2,
          right: -2,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                ),
              ],
            ),
            child: const Icon(Icons.edit_rounded,
                size: 13, color: AppColors.textTertiary),
          ),
        ),
      ],
    ).animate().scale(duration: 300.ms, begin: const Offset(0.8, 0.8));
  }

  // ═══════════════════════════════════════════════════
  //  CONFIGURATION CARD
  // ═══════════════════════════════════════════════════
  Widget _buildConfigCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Name ──
          _field(
            label: AppLocalizations.of(context)!.categoryName.toUpperCase(),
            child: TextField(
              controller: _nameController,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryNavy,
              ),
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.egGroceries,
                hintStyle: const TextStyle(
                    color: AppColors.textTertiary, fontWeight: FontWeight.w400),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            showBorder: true,
          ),

          // ── Type toggle ──
          _field(
            label: AppLocalizations.of(context)!.type.toUpperCase(),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _typeTab(AppLocalizations.of(context)!.expense, true),
                  _typeTab(AppLocalizations.of(context)!.income, false),
                ],
              ),
            ),
            showBorder: true,
          ),

          // ── Monthly Limit (expense only) ──
          if (_isExpense)
          _field(
            label: AppLocalizations.of(context)!.monthlyLimit.toUpperCase(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppLocalizations.of(context)!.enableMonthlyBudget,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                    Switch.adaptive(
                      value: _hasBudget,
                      onChanged: (v) {
                        HapticFeedback.lightImpact();
                        setState(() => _hasBudget = v);
                      },
                      activeTrackColor: AppColors.primaryNavy,
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 250),
                  crossFadeState: _hasBudget ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                  firstChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      TextField(
                        controller: _budgetController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryNavy,
                        ),
                        decoration: InputDecoration(
                          hintText: '${ref.watch(appSettingsProvider).currency} 0,000',
                          hintStyle: TextStyle(
                            color: AppColors.textTertiary, 
                            fontWeight: FontWeight.w400,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 12, color: AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.budgetAlertHint,
                              style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  secondChild: const SizedBox.shrink(),
                ),
              ],
            ),
            showBorder: true,
          ),

          // ── Icon picker ──
          _field(
            label: AppLocalizations.of(context)!.icon.toUpperCase(),
            child: GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: List.generate(_icons.length, (i) {
                final isSelected = _selectedIconIndex == i;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedIconIndex = i);
                  },
                  child: AnimatedContainer(
                    duration: 200.ms,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? AppColors.primaryNavy.withValues(alpha: 0.1)
                          : Colors.transparent,
                      border: isSelected
                          ? Border.all(color: AppColors.primaryNavy, width: 2)
                          : null,
                    ),
                    child: Icon(
                      _icons[i],
                      size: 24,
                      color: isSelected
                          ? AppColors.primaryNavy
                          : AppColors.textTertiary,
                    ),
                  ),
                );
              }),
            ),
            showBorder: true,
          ),

          // ── Color picker ──
          _field(
            label: AppLocalizations.of(context)!.color.toUpperCase(),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              children: List.generate(_colors.length, (i) {
                final isSelected = _selectedColorIndex == i;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedColorIndex = i);
                  },
                  child: AnimatedContainer(
                    duration: 200.ms,
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _colors[i],
                      border: isSelected
                          ? Border.all(color: _colors[i], width: 3)
                          : null,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: _colors[i].withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check_rounded,
                            size: 16, color: Colors.white)
                        : null,
                  ),
                );
              }),
            ),
            showBorder: false,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 50.ms);
  }

  // ═══════════════════════════════════════════════════
  //  DELETE BUTTON
  // ═══════════════════════════════════════════════════
  Widget _buildDeleteButton() {
    return TextButton.icon(
      onPressed: _confirmDelete,
      icon: const Icon(Icons.delete_outline_rounded,
          size: 20, color: AppColors.danger),
      label: Text(
        AppLocalizations.of(context)!.deleteCategory,
        style: AppTypography.labelMedium.copyWith(
          color: AppColors.danger,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 150.ms);
  }

  // ═══════════════════════════════════════════════════
  //  REUSABLE HELPERS
  // ═══════════════════════════════════════════════════

  // Field wrapper inside config card
  Widget _field({
    required String label,
    required Widget child,
    required bool showBorder,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: showBorder
            ? Border(
                bottom: BorderSide(
                    color: AppColors.borderLight.withValues(alpha: 0.5)))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  // Type tab
  void _onTypeChanged(bool newIsExpense) {
    if (_isExpense && !newIsExpense && _hasBudget) {
      // Clear budget when switching from expense to income
      setState(() {
        _isExpense = newIsExpense;
        _hasBudget = false;
        _budgetController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.budgetRemovedNotice)),
      );
    } else {
      setState(() => _isExpense = newIsExpense);
    }
  }

  Widget _typeTab(String label, bool isExpenseTab) {
    final isSelected = _isExpense == isExpenseTab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          _onTypeChanged(isExpenseTab);
        },
        child: AnimatedContainer(
          duration: 200.ms,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: isSelected
                    ? AppColors.primaryNavy
                    : AppColors.textTertiary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
