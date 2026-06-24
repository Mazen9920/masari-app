import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../shared/models/category_data.dart';
import '../../../shared/models/transaction_model.dart';
import '../../../l10n/app_localizations.dart';

/// A single contributing line in a P&L category drill-down.
class CategoryBreakdownEntry {
  final Transaction transaction;

  /// The value this transaction contributed to the P&L figure (already
  /// sign-normalised the same way the P&L computed the category total, so the
  /// sum of [contribution] across entries equals the figure the user tapped).
  final double contribution;

  const CategoryBreakdownEntry({
    required this.transaction,
    required this.contribution,
  });
}

/// Shows an accurate, focused drill-down of the transactions that make up a
/// single P&L category figure for the selected period. The header total is
/// guaranteed to reconcile with the number tapped in the breakdown.
Future<void> showCategoryBreakdownSheet({
  required BuildContext context,
  required String title,
  required String periodLabel,
  required List<CategoryBreakdownEntry> entries,
  required double total,
  required String currency,
  required Color accent,
  required bool isExpenseSection,
  required ValueChanged<Transaction> onTapTransaction,
  required ValueChanged<Transaction> onEditTransaction,
  VoidCallback? onExport,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategoryBreakdownSheet(
      title: title,
      periodLabel: periodLabel,
      entries: entries,
      total: total,
      currency: currency,
      accent: accent,
      isExpenseSection: isExpenseSection,
      onTapTransaction: onTapTransaction,
      onEditTransaction: onEditTransaction,
      onExport: onExport,
    ),
  );
}

class _CategoryBreakdownSheet extends StatefulWidget {
  final String title;
  final String periodLabel;
  final List<CategoryBreakdownEntry> entries;
  final double total;
  final String currency;
  final Color accent;
  final bool isExpenseSection;
  final ValueChanged<Transaction> onTapTransaction;
  final ValueChanged<Transaction> onEditTransaction;
  final VoidCallback? onExport;

  const _CategoryBreakdownSheet({
    required this.title,
    required this.periodLabel,
    required this.entries,
    required this.total,
    required this.currency,
    required this.accent,
    required this.isExpenseSection,
    required this.onTapTransaction,
    required this.onEditTransaction,
    required this.onExport,
  });

  @override
  State<_CategoryBreakdownSheet> createState() => _CategoryBreakdownSheetState();
}

class _CategoryBreakdownSheetState extends State<_CategoryBreakdownSheet> {
  String _query = '';

  void _showRowActions(Transaction t) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.backgroundLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: Text(l10n.transactionDetail),
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onTapTransaction(t);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.edit),
                onTap: () {
                  Navigator.of(ctx).pop();
                  widget.onEditTransaction(t);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = NumberFormat('#,##0.##');
    final dateFmt = DateFormat('d MMM yyyy');

    // Sort by contribution magnitude (largest first) for a practical view.
    final sorted = [...widget.entries]
      ..sort((a, b) => b.contribution.abs().compareTo(a.contribution.abs()));

    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? sorted
        : sorted.where((e) {
            final t = e.transaction;
            final name = CategoryData.findById(t.categoryId)
                .localizedName(l10n)
                .toLowerCase();
            return t.title.toLowerCase().contains(q) ||
                (t.note?.toLowerCase().contains(q) ?? false) ||
                name.contains(q);
          }).toList();

    final visibleTotal =
        visible.fold<double>(0, (sum, e) => sum + e.contribution);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.backgroundLight,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Grabber
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: widget.accent, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.title,
                            style: AppTypography.sectionTitle
                                .copyWith(fontSize: 17),
                          ),
                        ),
                        if (widget.onExport != null)
                          IconButton(
                            icon: const Icon(Icons.ios_share_rounded, size: 20),
                            tooltip: l10n.exportCsv,
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              final export = widget.onExport!;
                              Navigator.of(context).pop();
                              export();
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 22),
                          onPressed: () => Navigator.of(context).pop(),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.periodLabel,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.total.toUpperCase(),
                                style: AppTypography.badge.copyWith(
                                  fontSize: 10,
                                  color: AppColors.textTertiary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.currency} ${fmt.format(widget.total)}',
                                style: AppTypography.metric.copyWith(
                                  fontSize: 24,
                                  color: widget.isExpenseSection
                                      ? AppColors.danger
                                      : AppColors.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: widget.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${widget.entries.length} ${l10n.transactions}',
                            style: AppTypography.labelSmall
                                .copyWith(color: widget.accent),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Search (only worth showing for longer lists)
              if (widget.entries.length > 8)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: l10n.searchTransactions,
                      prefixIcon:
                          const Icon(Icons.search_rounded, size: 20),
                      filled: true,
                      fillColor: AppColors.surfaceLight,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              const Divider(height: 1),
              // List
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          l10n.noTransactionsFound,
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: EdgeInsets.only(
                            top: 4,
                            bottom:
                                MediaQuery.of(context).viewPadding.bottom + 24),
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const Divider(
                            height: 1, indent: 64, endIndent: 16),
                        itemBuilder: (context, i) {
                          final entry = visible[i];
                          final t = entry.transaction;
                          final cat = CategoryData.findById(t.categoryId);
                          final isNegative = entry.contribution < 0;
                          final amountColor = widget.isExpenseSection
                              ? (isNegative
                                  ? AppColors.success // reversal reduces expense
                                  : AppColors.danger)
                              : (isNegative
                                  ? AppColors.danger // refund reduces revenue
                                  : AppColors.success);
                          return InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onTapTransaction(t);
                            },
                            onLongPress: () {
                              HapticFeedback.mediumImpact();
                              _showRowActions(t);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color:
                                          widget.accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(cat.iconData,
                                        size: 18, color: widget.accent),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          t.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AppTypography.bodySmall
                                              .copyWith(
                                                  color:
                                                      AppColors.textPrimary,
                                                  fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dateFmt.format(t.dateTime),
                                          style: AppTypography.labelSmall
                                              .copyWith(
                                                  color:
                                                      AppColors.textTertiary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${widget.currency} ${fmt.format(entry.contribution.abs())}',
                                    style: AppTypography.labelSmall
                                        .copyWith(color: amountColor),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // Filtered subtotal footer (when searching)
              if (q.isNotEmpty && visible.isNotEmpty)
                Container(
                  padding: EdgeInsets.fromLTRB(
                      20, 10, 20, 10 + MediaQuery.of(context).padding.bottom),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceLight,
                    border: Border(
                        top: BorderSide(color: AppColors.dividerLight, width: 1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${visible.length} / ${widget.entries.length}',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      Text(
                        '${widget.currency} ${fmt.format(visibleTotal)}',
                        style: AppTypography.labelSmall
                            .copyWith(color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
