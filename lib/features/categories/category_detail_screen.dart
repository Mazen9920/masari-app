import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/category_data.dart';
import 'edit_category_screen.dart';

class CategoryDetailScreen extends ConsumerWidget {
  final CategoryData category;

  const CategoryDetailScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allTransactions = ref.watch(transactionsProvider);
    final categoryTx = allTransactions
        .where((t) => t.category.name == category.name)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    final totalSpend = categoryTx.fold(0.0, (sum, t) => sum + t.amount.abs());
    final budget = 6000.0; // placeholder budget
    final usedPercent = (totalSpend / budget * 100).clamp(0.0, 100.0).toInt();
    final remaining = (budget - totalSpend).clamp(0.0, double.infinity);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SpendCard(
                      category: category,
                      totalSpend: totalSpend,
                      budget: budget,
                      usedPercent: usedPercent,
                      remaining: remaining,
                      transactionCount: categoryTx.length,
                    ),
                    const SizedBox(height: 20),
                    _TrendChart(category: category),
                    const SizedBox(height: 24),
                    _TransactionsList(transactions: categoryTx),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryNavy,
          ),
          Expanded(
            child: Text(
              category.name,
              textAlign: TextAlign.center,
              style: AppTypography.h3.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EditCategoryScreen(category: category),
              ),
            );
          },
          icon: const Icon(Icons.edit_rounded),
          color: AppColors.primaryNavy,
        ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  SPEND CARD
// ═══════════════════════════════════════════════════════════
class _SpendCard extends StatelessWidget {
  final CategoryData category;
  final double totalSpend;
  final double budget;
  final int usedPercent;
  final double remaining;
  final int transactionCount;

  const _SpendCard({
    required this.category,
    required this.totalSpend,
    required this.budget,
    required this.usedPercent,
    required this.remaining,
    required this.transactionCount,
  });

  @override
  Widget build(BuildContext context) {
    final isNearLimit = usedPercent >= 80;
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: category.color.withValues(alpha: 0.12),
                ),
                child: Icon(category.icon, size: 22, color: category.color),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENT SPEND',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${months[now.month - 1]} ${now.year}',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Amount
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '\$${totalSpend.toStringAsFixed(0)}',
                style: AppTypography.h1.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/ ${budget.toStringAsFixed(0)}',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),
          Text(
            '$transactionCount transaction${transactionCount != 1 ? 's' : ''} this month',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),

          const SizedBox(height: 18),

          // Progress bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$usedPercent% Used',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isNearLimit ? AppColors.accentOrange : AppColors.primaryNavy,
                ),
              ),
              Text(
                '\$${remaining.toStringAsFixed(0)} Left',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: usedPercent / 100),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, value, __) {
                return SizedBox(
                  height: 8,
                  child: LinearProgressIndicator(
                    value: value,
                    backgroundColor: const Color(0xFFF0F1F3),
                    valueColor: AlwaysStoppedAnimation(
                      isNearLimit ? AppColors.accentOrange : AppColors.primaryNavy,
                    ),
                  ),
                );
              },
            ),
          ),

          if (isNearLimit) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.warning_rounded, size: 14, color: AppColors.accentOrange),
                const SizedBox(width: 4),
                Text(
                  'Approaching budget limit',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentOrange,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04, end: 0);
  }
}

// ═══════════════════════════════════════════════════════════
//  3-MONTH TREND CHART
// ═══════════════════════════════════════════════════════════
class _TrendChart extends StatelessWidget {
  final CategoryData category;

  const _TrendChart({required this.category});

  @override
  Widget build(BuildContext context) {
    // Simulated month data — will derive from transactions when backend arrives
    final data = [
      _MonthData('Dec', 4200, 0.6),
      _MonthData('Jan', 4900, 0.7),
      _MonthData('Feb', 5800, 0.85),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '3 Month Trend',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.asMap().entries.map((entry) {
                final i = entry.key;
                final d = entry.value;
                final isCurrent = i == data.length - 1;

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i > 0 ? 12 : 0,
                      right: i < data.length - 1 ? 12 : 0,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          d.amount.toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isCurrent ? AppColors.primaryNavy : AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: d.heightFraction),
                            duration: Duration(milliseconds: 600 + i * 150),
                            curve: Curves.easeOutCubic,
                            builder: (_, value, __) {
                              return FractionallySizedBox(
                                heightFactor: value,
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? AppColors.primaryNavy
                                        : AppColors.primaryNavy.withValues(alpha: 0.15 + i * 0.15),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(8),
                                    ),
                                    border: isCurrent
                                        ? Border.all(
                                            color: AppColors.primaryNavy.withValues(alpha: 0.1),
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          d.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: isCurrent ? AppColors.primaryNavy : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms);
  }
}

class _MonthData {
  final String label;
  final double amount;
  final double heightFraction;

  const _MonthData(this.label, this.amount, this.heightFraction);
}

// ═══════════════════════════════════════════════════════════
//  TRANSACTIONS LIST
// ═══════════════════════════════════════════════════════════
class _TransactionsList extends StatelessWidget {
  final List<Transaction> transactions;

  const _TransactionsList({required this.transactions});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Transactions',
          style: AppTypography.h3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        if (transactions.isEmpty)
          _buildEmpty()
        else
          ...transactions.asMap().entries.map((entry) {
            final i = entry.key;
            final tx = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TransactionTile(transaction: tx, index: i),
            );
          }),
      ],
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(32),
      width: double.infinity,
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 40,
            color: AppColors.textTertiary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'No transactions yet',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final int index;

  const _TransactionTile({required this.transaction, required this.index});

  String get _formattedDate {
    final d = transaction.dateTime;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: transaction.category.color.withValues(alpha: 0.08),
            ),
            child: Icon(
              transaction.category.icon,
              size: 20,
              color: transaction.category.color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formattedDate,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            transaction.isIncome
                ? '+\$${transaction.amount.abs().toStringAsFixed(0)}'
                : '-\$${transaction.amount.abs().toStringAsFixed(0)}',
            style: AppTypography.labelMedium.copyWith(
              color: transaction.isIncome ? AppColors.success : AppColors.danger,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(
          duration: 300.ms,
          delay: Duration(milliseconds: 50 * index),
        )
        .slideX(begin: 0.03, end: 0, duration: 300.ms, delay: Duration(milliseconds: 50 * index));
  }
}
