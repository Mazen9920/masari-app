import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_providers.dart';
import '../../transactions/transaction_detail_screen.dart';
import '../../transactions/transactions_list_screen.dart';

/// Recent transactions section with "View All" header and transaction cards.
class RecentTransactions extends ConsumerWidget {
  const RecentTransactions({super.key});

  // Sample data — replace with real data from backend
  static final List<TransactionItem> _transactions = [
    TransactionItem(
      title: 'AWS Web Services',
      subtitle: 'Today, 9:41 AM',
      amount: -1200.00,
      icon: Icons.dns_rounded,
      iconBgColor: AppColors.backgroundLight,
      iconColor: AppColors.textSecondary,
      category: 'Software/Infrastructure',
    ),
    TransactionItem(
      title: 'Client Payment',
      subtitle: 'Yesterday, 4:20 PM',
      amount: 4500.00,
      icon: Icons.account_balance_rounded,
      iconBgColor: const Color(0xFFF0FDF4), // green-50
      iconColor: AppColors.success,
      category: 'Income',
    ),
    TransactionItem(
      title: 'Office Rent',
      subtitle: 'Oct 24, 10:00 AM',
      amount: -3000.00,
      icon: Icons.domain_rounded,
      iconBgColor: AppColors.accentOrange.withOpacity(0.08),
      iconColor: AppColors.accentOrange,
      category: 'Rent',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTransactions = ref.watch(transactionsProvider);
    final recentTransactions = allTransactions.take(5).toList();
    return Column(
      children: [
        // Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Transactions',
              style: AppTypography.h3.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const TransactionsListScreen(showBackButton: true),
                  ),
                );
              },
              child: Text(
                'View All',
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
          recentTransactions.length > 5 ? 5 : recentTransactions.length,
          (index) {
            final tx = recentTransactions[index];
            final item = TransactionItem(
              title: tx.title,
              subtitle: tx.formattedTime,
              amount: tx.amount,
              icon: tx.category.icon,
              iconBgColor: tx.category.bgColor,
              iconColor: tx.category.color,
              category: tx.category.name,
            );
            return Padding(
              padding: EdgeInsets.only(
                bottom: index < recentTransactions.length - 1 ? 10 : 0,
              ),
              child: _TransactionCard(item: item),
            );
          },
        ),
      ],
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final TransactionItem item;
  const _TransactionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final isIncome = item.amount > 0;
    final formattedAmount =
        '${isIncome ? '+' : '-'}EGP ${item.amount.abs().toStringAsFixed(0)}';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TransactionDetailScreen(transaction: item),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight.withOpacity(0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.015),
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
                  color: item.iconColor.withOpacity(0.15),
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
