import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/category_data.dart';
import '../../l10n/app_localizations.dart';

/// Shows the "Quick Categorize" bottom sheet for uncategorized transactions.
Future<int> showCategorizeTransactionsSheet(
  BuildContext context,
  List<Transaction> uncategorized,
) async {
  final result = await showModalBottomSheet<int>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategorizeTransactionsSheet(uncategorized: uncategorized),
  );
  return result ?? 0;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sheet Widget
// ─────────────────────────────────────────────────────────────────────────────

class _CategorizeTransactionsSheet extends ConsumerStatefulWidget {
  final List<Transaction> uncategorized;

  const _CategorizeTransactionsSheet({required this.uncategorized});

  @override
  ConsumerState<_CategorizeTransactionsSheet> createState() =>
      _CategorizeTransactionsSheetState();
}

class _CategorizeTransactionsSheetState
    extends ConsumerState<_CategorizeTransactionsSheet> {
  // Map from transaction ID → chosen category ID
  late final Map<String, String> _selectedCategories;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Start with null-like value; we track which ones have been assigned
    _selectedCategories = {
      for (final t in widget.uncategorized) t.id: t.categoryId,
    };
  }

  int get _assignedCount =>
      _selectedCategories.values
          .where((id) => id != 'cat_uncategorized')
          .length;

  Future<void> _saveAll() async {
    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);

    int saved = 0;
    for (final tx in widget.uncategorized) {
      final newCategoryId = _selectedCategories[tx.id];
      if (newCategoryId != null &&
          newCategoryId != 'cat_uncategorized') {
        final updated = tx.copyWith(categoryId: newCategoryId);
        await ref.read(transactionsProvider.notifier).updateTransaction(updated);
        saved++;
      }
    }

    if (mounted) context.pop(saved);
  }

  void _pickCategory(String txId, bool isExpense) {
    HapticFeedback.lightImpact();
    // Same source as add_transaction_screen: categoriesProvider only
    final categories = (ref.read(categoriesProvider).value ?? [])
        .where((c) => c.isExpense == isExpense && c.name != 'Uncategorized')
        .toList();

    showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CategoryPickerSheet(
        categories: categories,
        selectedId: _selectedCategories[txId],
      ),
    ).then((picked) {
      if (picked != null) {
        setState(() => _selectedCategories[txId] = picked);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: EdgeInsets.only(top: 80, bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle ──
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.borderLight,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // ── Header ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.categorizeTransactions,
                        style: AppTypography.h2.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.nTransactionsNeedCategory(widget.uncategorized.length),
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Progress badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _assignedCount == widget.uncategorized.length
                        ? AppColors.success.withValues(alpha: 0.12)
                        : AppColors.primaryNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    '$_assignedCount / ${widget.uncategorized.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _assignedCount == widget.uncategorized.length
                          ? AppColors.success
                          : AppColors.primaryNavy,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: AppColors.borderLight.withValues(alpha: 0.5),
          ),

          // ── Transaction list ──
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: widget.uncategorized.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: 20,
                endIndent: 20,
                color: AppColors.borderLight.withValues(alpha: 0.4),
              ),
              itemBuilder: (ctx, i) {
                final tx = widget.uncategorized[i];
                final chosenId = _selectedCategories[tx.id];
                final chosen = chosenId != null
                    ? CategoryData.findById(chosenId)
                    : null;
                final isAssigned =
                    chosen != null && chosen.name != 'Uncategorized';

                return _TransactionCategoryRow(
                  transaction: tx,
                  chosenCategory: isAssigned ? chosen : null,
                  onPickCategory: () =>
                      _pickCategory(tx.id, tx.amount < 0),
                ).animate().fadeIn(duration: 250.ms, delay: (i * 40).ms);
              },
            ),
          ),

          Divider(
            height: 1,
            color: AppColors.borderLight.withValues(alpha: 0.5),
          ),

          // ── Action buttons ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _isSaving ? null : () => context.pop(0),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(
                            color: AppColors.borderLight.withValues(alpha: 0.8)),
                      ),
                      child: Text(
                         l10n.cancelLabel,
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed:
                          (_isSaving || _assignedCount == 0) ? null : _saveAll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryNavy,
                        disabledBackgroundColor:
                            AppColors.primaryNavy.withValues(alpha: 0.4),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                               l10n.saveNChanges(_assignedCount),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Single transaction row inside the sheet
// ─────────────────────────────────────────────────────────────────────────────

class _TransactionCategoryRow extends ConsumerWidget {
  final Transaction transaction;
  final CategoryData? chosenCategory;
  final VoidCallback onPickCategory;

  const _TransactionCategoryRow({
    required this.transaction,
    required this.chosenCategory,
    required this.onPickCategory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
      final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(appSettingsProvider).currency;
    final dateLabel = DateFormat( 'MMM d').format(transaction.dateTime);
    final amountLabel =
        '$currency ${NumberFormat('#,##0').format(transaction.amount.abs())}';
    final isExpense = transaction.amount < 0;

    return InkWell(
      onTap: onPickCategory,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            // Category icon / placeholder
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: chosenCategory != null
                    ? Color(chosenCategory!.bgColorValue)
                    : AppColors.accentOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                chosenCategory?.iconData ?? Icons.help_outline_rounded,
                size: 20,
                color: chosenCategory != null
                    ? Color(chosenCategory!.colorValue)
                    : AppColors.accentOrange,
              ),
            ),
            const SizedBox(width: 12),

            // Title + date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.title,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateLabel,
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Amount
            Text(
              amountLabel,
              style: AppTypography.labelMedium.copyWith(
                color: isExpense ? AppColors.danger : AppColors.success,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),

            const SizedBox(width: 10),

            // Category chip / picker button
            GestureDetector(
              onTap: onPickCategory,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: chosenCategory != null
                      ? Color(chosenCategory!.bgColorValue)
                      : AppColors.accentOrange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: chosenCategory != null
                        ? Color(chosenCategory!.colorValue)
                            .withValues(alpha: 0.3)
                        : AppColors.accentOrange.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chosenCategory?.localizedName(l10n) ?? l10n.setCategory,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: chosenCategory != null
                            ? Color(chosenCategory!.colorValue)
                            : AppColors.accentOrange,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 14,
                      color: chosenCategory != null
                          ? Color(chosenCategory!.colorValue)
                          : AppColors.accentOrange,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Category picker mini-sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryPickerSheet extends StatelessWidget {
  final List<CategoryData> categories;
  final String? selectedId;

  const _CategoryPickerSheet({
    required this.categories,
    this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
               'Choose a Category',
              style: AppTypography.h2.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.1,
              ),
              itemCount: categories.length,
              itemBuilder: (ctx, i) {
                final cat = categories[i];
                final isSelected = cat.id == selectedId;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    context.pop(cat.id);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Color(cat.colorValue).withValues(alpha: 0.15)
                          : Color(cat.bgColorValue),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? Color(cat.colorValue)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          cat.iconData,
                          size: 26,
                          color: Color(cat.colorValue),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          cat.localizedName(AppLocalizations.of(context)!),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
  }
}
