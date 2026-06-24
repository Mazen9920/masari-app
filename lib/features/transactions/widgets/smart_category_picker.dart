import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../shared/models/category_data.dart';
import '../../../l10n/app_localizations.dart';

/// Opens a smart, searchable category picker. Returns the selected category id,
/// or null if dismissed. Supports creating a brand-new category inline by
/// typing a name that doesn't match any existing one.
Future<String?> showSmartCategoryPicker({
  required BuildContext context,
  required bool isExpense,
  String? selectedId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SmartCategoryPicker(
      isExpense: isExpense,
      selectedId: selectedId,
    ),
  );
}

class _SmartCategoryPicker extends ConsumerStatefulWidget {
  final bool isExpense;
  final String? selectedId;

  const _SmartCategoryPicker({
    required this.isExpense,
    this.selectedId,
  });

  @override
  ConsumerState<_SmartCategoryPicker> createState() =>
      _SmartCategoryPickerState();
}

class _SmartCategoryPickerState extends ConsumerState<_SmartCategoryPicker> {
  String _query = '';
  bool _creating = false;

  List<CategoryData> _sortedCategories() {
    final l10n = AppLocalizations.of(context)!;
    final cats = (ref.watch(categoriesProvider).value ?? [])
        .where((c) =>
            c.isExpense == widget.isExpense &&
            c.name != 'Uncategorized' &&
            !c.isSystemLocked)
        .toList();

    // Smart sort: most-used first, but push accrual/system cats to the end.
    const pinToEnd = {'cat_cogs', 'cat_shipping', 'cat_sales_revenue'};
    final transactions = ref.read(transactionsProvider).value ?? [];
    final usage = <String, int>{};
    for (final t in transactions) {
      usage[t.categoryId] = (usage[t.categoryId] ?? 0) + 1;
    }
    cats.sort((a, b) {
      final aPin = pinToEnd.contains(a.id) ? 1 : 0;
      final bPin = pinToEnd.contains(b.id) ? 1 : 0;
      if (aPin != bPin) return aPin - bPin;
      return (usage[b.id] ?? 0).compareTo(usage[a.id] ?? 0);
    });

    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return cats;
    return cats
        .where((c) =>
            c.localizedName(l10n).toLowerCase().contains(q) ||
            c.name.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _createCategory(String name) async {
    if (_creating) return;
    setState(() => _creating = true);
    final l10n = AppLocalizations.of(context)!;

    // Reuse an existing category with the same name (case-insensitive) instead
    // of creating a duplicate.
    final all = <CategoryData>[
      ...CategoryData.all,
      ...CategoryData.customCategories,
    ];
    final existing = all
        .where((c) => c.name.toLowerCase() == name.toLowerCase())
        .firstOrNull;
    if (existing != null) {
      if (mounted) Navigator.of(context).pop(existing.id);
      return;
    }

    final catId = 'cat_${DateTime.now().millisecondsSinceEpoch}';
    final newCat = CategoryData(
      id: catId,
      userId: '',
      name: name,
      iconName: 'grid_view',
      colorValue: 0xFF9E9E9E,
      bgColorValue: 0xFFF5F5F5,
      isExpense: widget.isExpense,
    );
    await ref.read(categoriesProvider.notifier).addCategory(newCat);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${l10n.createCategory}: $name')),
    );
    Navigator.of(context).pop(catId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cats = _sortedCategories();
    final q = _query.trim();
    final hasExact = cats.any(
        (c) => c.localizedName(l10n).toLowerCase() == q.toLowerCase());
    final showCreate = q.isNotEmpty && !hasExact;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const SizedBox(width: 36),
                      Expanded(
                        child: Text(
                          l10n.selectCategory,
                          textAlign: TextAlign.center,
                          style: AppTypography.h2.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.close_rounded, size: 22),
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Search field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    autofocus: false,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l10n.searchCategoriesHint,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: AppColors.backgroundLight,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Create-new tile (when the typed name has no exact match)
                if (showCreate)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: InkWell(
                      onTap: _creating ? null : () => _createCategory(q),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.accentOrange.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.accentOrange.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.accentOrange
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: _creating
                                  ? const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.accentOrange),
                                    )
                                  : const Icon(Icons.add_rounded,
                                      size: 20, color: AppColors.accentOrange),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${l10n.createCategory}: "$q"',
                                style: AppTypography.labelMedium.copyWith(
                                  color: AppColors.accentOrange,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Divider(height: 1, color: AppColors.borderLight),
                // Category list
                Expanded(
                  child: cats.isEmpty && !showCreate
                      ? Center(
                          child: Text(
                            l10n.noResultsFound,
                            style: AppTypography.labelMedium
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: cats.length,
                          itemBuilder: (ctx, i) {
                            final cat = cats[i];
                            final isSelected = cat.id == widget.selectedId;
                            return InkWell(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                Navigator.of(context).pop(cat.id);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                color: isSelected
                                    ? Color(cat.colorValue)
                                        .withValues(alpha: 0.06)
                                    : null,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? Color(cat.colorValue)
                                                .withValues(alpha: 0.15)
                                            : Color(cat.bgColorValue),
                                        borderRadius: BorderRadius.circular(12),
                                        border: isSelected
                                            ? Border.all(
                                                color: Color(cat.colorValue),
                                                width: 1.5)
                                            : null,
                                      ),
                                      child: Icon(cat.iconData,
                                          size: 20,
                                          color: Color(cat.colorValue)),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        cat.localizedName(l10n),
                                        style:
                                            AppTypography.labelMedium.copyWith(
                                          color: AppColors.textPrimary,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(Icons.check_circle_rounded,
                                          size: 22,
                                          color: Color(cat.colorValue)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(child: const SizedBox(height: 8)),
              ],
            ),
          );
        },
      ),
    );
  }
}
