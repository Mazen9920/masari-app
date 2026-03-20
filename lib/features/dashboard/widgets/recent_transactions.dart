import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/navigation/app_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../shared/models/category_data.dart';
import '../../../shared/models/transaction_model.dart';

/// Recent transactions section with "View All" header and transaction cards.
class RecentTransactions extends ConsumerWidget {
  const RecentTransactions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTransactions = ref.watch(transactionsProvider).value ?? [];
    final currency = ref.watch(appSettingsProvider).currency;
    final recentTransactions = allTransactions
        .where((t) => t.saleId == null)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final display = recentTransactions.take(5).toList();
    return Column(
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppLocalizations.of(context)!.recentTransactions,
              style: AppTypography.h3.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            GestureDetector(
              onTap: () => context.go(AppRoutes.transactions),
              child: Text(
                AppLocalizations.of(context)!.viewAll,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.accentOrange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Transaction cards - Convert provider transactions to UI format
        ...List.generate(
          display.length,
          (index) {
            final tx = display[index];
            final cat = CategoryData.findById(tx.categoryId);
            final item = TransactionItem(
              title: tx.title,
              subtitle: tx.formattedTime,
              amount: tx.amount,
              icon: cat.iconData,
              iconBgColor: cat.displayBgColor,
              iconColor: cat.displayColor,
              category: cat.name,
            );
            return Padding(
              padding: EdgeInsets.only(
                bottom: index < display.length - 1 ? 10 : 0,
              ),
              child: _TransactionCard(item: item, transaction: tx, currency: currency),
            );
          },
        ),
      ],
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final TransactionItem item;
  final Transaction transaction;
  final String currency;
  const _TransactionCard({required this.item, required this.transaction, required this.currency});

  @override
  Widget build(BuildContext context) {
    final isIncome = item.amount > 0;
    final formattedAmount =
        '${isIncome ? '+' : '-'}$currency ${item.amount.abs().toStringAsFixed(0)}';

    return GestureDetector(
      onTap: () {
        context.push(
          AppRoutes.transactionDetail,
          extra: {'transaction': transaction},
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.015),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: item.iconBgColor,
                border: Border.all(
                  color: item.iconColor.withValues(alpha: 0.15),
                ),
              ),
              child: Icon(item.icon, color: item.iconColor, size: 22),
            ),
            const SizedBox(width: 14),

            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: AppTypography.labelLarge.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // Amount
            Text(
              formattedAmount,
              style: AppTypography.labelLarge.copyWith(
                color: isIncome ? AppColors.success : AppColors.textPrimary,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Data model for a transaction (shared across screens)
class TransactionItem {
  final String title;
  final String subtitle;
  final double amount;
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String category;

  const TransactionItem({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.category,
  });
}
