import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
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
    Icons.shopping_cart_rounded,
    Icons.restaurant_rounded,
    Icons.directions_car_rounded,
    Icons.campaign_rounded,
    Icons.flight_rounded,
    Icons.home_rounded,
    Icons.pets_rounded,
    Icons.medical_services_rounded,
    Icons.school_rounded,
    Icons.fitness_center_rounded,
    Icons.movie_rounded,
    Icons.more_horiz_rounded,
  ];

  static const _colors = [
    Color(0xFF1B4F72), // navy
    Color(0xFFE67E22), // orange
    Color(0xFF27AE60), // green
    Color(0xFF9B59B6), // purple
    Color(0xFFC0392B), // red
    Color(0xFFF1C40F), // yellow
    Color(0xFF34495E), // dark grey
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category.name);
    _isExpense = true; // default
    _budgetController = TextEditingController(text: '6,000');

    // match current icon/color to available palette
    _selectedIconIndex = _icons.indexWhere((ic) => ic == widget.category.icon);
    if (_selectedIconIndex < 0) _selectedIconIndex = 3; // fallback

    _selectedColorIndex =
        _colors.indexWhere((c) => c.value == widget.category.color.value);
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

    final color = _colors[_selectedColorIndex];
    final updated = CategoryData(
      name: name,
      icon: _icons[_selectedIconIndex],
      color: color,
      bgColor: color.withValues(alpha: 0.1),
    );

    ref
        .read(categoriesProvider.notifier)
        .updateCategory(widget.category.name, updated);
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(updated);
  }

  // ── Delete ──────────────────────────────────────────
  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Category',
          style: AppTypography.h3
              .copyWith(fontWeight: FontWeight.w700, color: AppColors.danger),
        ),
        content: Text(
          'Are you sure you want to delete "${widget.category.name}"? This action cannot be undone.',
          style: AppTypography.bodySmall
              .copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.textTertiary)),
          ),
          ElevatedButton(
            onPressed: () {
              ref
                  .read(categoriesProvider.notifier)
                  .removeCategory(widget.category.name);
              HapticFeedback.mediumImpact();
              Navigator.pop(ctx); // dialog
              Navigator.pop(context); // edit screen
              Navigator.pop(context); // detail screen back to list
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
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
                    const SizedBox(height: 20),
                    _buildBudgetCard(),
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
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ),
          const Spacer(),
          Text(
            'Edit Category',
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
              'Save',
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
            label: 'CATEGORY NAME',
            child: TextField(
              controller: _nameController,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryNavy,
              ),
              decoration: const InputDecoration(
                hintText: 'e.g. Groceries',
                hintStyle: TextStyle(
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
            label: 'TYPE',
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _typeTab('Expense', true),
                  _typeTab('Income', false),
                ],
              ),
            ),
            showBorder: true,
          ),

          // ── Icon picker ──
          _field(
            label: 'ICON',
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
            label: 'COLOR',
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
  //  BUDGET CARD
  // ═══════════════════════════════════════════════════
  Widget _buildBudgetCard() {
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
          // toggle row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFEFF6FF),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded,
                      size: 18, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Enable Monthly Budget',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _hasBudget = !_hasBudget);
                  },
                  child: AnimatedContainer(
                    duration: 200.ms,
                    width: 48,
                    height: 26,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(50),
                      color: _hasBudget
                          ? AppColors.primaryNavy
                          : const Color(0xFFCCCCCC),
                    ),
                    child: AnimatedAlign(
                      duration: 200.ms,
                      alignment: _hasBudget
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // budget input
          AnimatedCrossFade(
            duration: 250.ms,
            crossFadeState:
                _hasBudget ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFB),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LIMIT AMOUNT',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _budgetController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'EGP',
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 0, minHeight: 0),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: AppColors.borderLight),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            BorderSide(color: AppColors.borderLight),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: AppColors.primaryNavy, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Reset every month',
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
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
        'Delete Category',
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
  Widget _typeTab(String label, bool isExpenseTab) {
    final isSelected = _isExpense == isExpenseTab;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _isExpense = isExpenseTab);
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
