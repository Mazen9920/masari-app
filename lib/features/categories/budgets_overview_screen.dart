import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/category_data.dart';
import 'category_detail_screen.dart';

/// Budget Overview — shows spending health across all categories.
class BudgetsOverviewScreen extends ConsumerWidget {
  const BudgetsOverviewScreen({super.key});

  // Simulated budgets per category (in a real app these would be persisted)
  static const _budgets = <String, double>{
    'Groceries': 5000,
    'Transport': 2000,
    'Entertainment': 1500,
    'Health': 3000,
    'Food & Dining': 4000,
    'Shopping': 3500,
    'Bills': 5000,
    'Coffee': 800,
    'Utilities': 3000,
    'Rent': 8000,
    'Education': 2500,
    'Marketing': 6000,
    'Office Supplies': 1000,
    'Travel': 4000,
    'Salaries': 25000,
    'Software': 2000,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final transactions = ref.watch(transactionsProvider);

    // Compute per-category spending this month
    final now = DateTime.now();
    final expenses = transactions.where(
      (t) => !t.isIncome && t.dateTime.month == now.month && t.dateTime.year == now.year,
    );

    final spendingMap = <String, double>{};
    for (final tx in expenses) {
      spendingMap[tx.category.name] = (spendingMap[tx.category.name] ?? 0) + tx.amount.abs();
    }

    // Build budget items only for categories that have budgets
    final items = <_BudgetItem>[];
    for (final cat in categories) {
      final budget = _budgets[cat.name];
      if (budget == null) continue;
      final spent = spendingMap[cat.name] ?? 0;
      items.add(_BudgetItem(category: cat, budget: budget, spent: spent));
    }

    // Sort: over-budget first, then by % used descending
    items.sort((a, b) {
      final aRatio = a.spent / a.budget;
      final bRatio = b.spent / b.budget;
      return bRatio.compareTo(aRatio);
    });

    // Totals
    final totalBudget = items.fold(0.0, (s, i) => s + i.budget);
    final totalSpent = items.fold(0.0, (s, i) => s + i.spent);
    final overBudgetCount = items.where((i) => i.spent > i.budget).length;
    final nearBudgetCount = items.where((i) => i.spent >= i.budget * 0.8 && i.spent <= i.budget).length;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Summary card ──
                    _SummaryCard(
                      totalBudget: totalBudget,
                      totalSpent: totalSpent,
                      overCount: overBudgetCount,
                      nearCount: nearBudgetCount,
                      safeCount: items.length - overBudgetCount - nearBudgetCount,
                    ).animate().fadeIn(duration: 300.ms),

                    const SizedBox(height: 20),

                    // ── Status chips ──
                    _StatusChips(
                      overCount: overBudgetCount,
                      nearCount: nearBudgetCount,
                      safeCount: items.length - overBudgetCount - nearBudgetCount,
                    ).animate().fadeIn(duration: 250.ms, delay: 50.ms),

                    const SizedBox(height: 20),

                    // ── Category budget cards ──
                    ...List.generate(items.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _BudgetCard(
                          item: items[i],
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CategoryDetailScreen(
                                    category: items[i].category),
                              ),
                            );
                          },
                        ).animate().fadeIn(
                              duration: 250.ms,
                              delay: (80 + i * 40).ms,
                            ),
                      );
                    }),
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

// ═══════════════════════════════════════════════════════
//  DATA CLASS
// ═══════════════════════════════════════════════════════
class _BudgetItem {
  final CategoryData category;
  final double budget;
  final double spent;

  const _BudgetItem({
    required this.category,
    required this.budget,
    required this.spent,
  });

  double get ratio => budget > 0 ? (spent / budget).clamp(0, 999) : 0;
  double get remaining => (budget - spent).clamp(0.0, double.infinity);
  bool get isOver => spent > budget;
  bool get isNear => !isOver && spent >= budget * 0.8;
  bool get isSafe => !isOver && !isNear;

  Color get statusColor {
    if (isOver) return const Color(0xFFDC2626);
    if (isNear) return const Color(0xFFD97706);
    return const Color(0xFF16A34A);
  }
}

// ═══════════════════════════════════════════════════════
//  HEADER
// ═══════════════════════════════════════════════════════
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryNavy,
          ),
          Expanded(
            child: Text(
              'Budget Overview',
              style: AppTypography.h2.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primaryNavy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              _monthName(),
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _monthName() {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final now = DateTime.now();
    return '${months[now.month - 1]} ${now.year}';
  }
}

// ═══════════════════════════════════════════════════════
//  SUMMARY CARD
// ═══════════════════════════════════════════════════════
class _SummaryCard extends StatelessWidget {
  final double totalBudget;
  final double totalSpent;
  final int overCount;
  final int nearCount;
  final int safeCount;

  const _SummaryCard({
    required this.totalBudget,
    required this.totalSpent,
    required this.overCount,
    required this.nearCount,
    required this.safeCount,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = totalBudget > 0 ? totalSpent / totalBudget : 0.0;
    final remaining = (totalBudget - totalSpent).clamp(0.0, double.infinity);
    final isOver = totalSpent > totalBudget;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOver
              ? [const Color(0xFFDC2626), const Color(0xFFEF4444)]
              : [AppColors.primaryNavy, const Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: (isOver ? const Color(0xFFDC2626) : AppColors.primaryNavy)
                .withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Monthly Budget',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  isOver ? 'Over Budget' : '${(ratio * 100).toInt()}% Used',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Spent / Total
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'EGP ${_fmt(totalSpent)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '/ EGP ${_fmt(totalBudget)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: LinearProgressIndicator(
              value: ratio.clamp(0, 1).toDouble(),
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(
                Colors.white.withValues(alpha: 0.9),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Remaining
          Text(
            isOver
                ? 'Over by EGP ${_fmt(totalSpent - totalBudget)}'
                : 'EGP ${_fmt(remaining)} remaining',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  STATUS CHIPS
// ═══════════════════════════════════════════════════════
class _StatusChips extends StatelessWidget {
  final int overCount;
  final int nearCount;
  final int safeCount;

  const _StatusChips({
    required this.overCount,
    required this.nearCount,
    required this.safeCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _chip(Icons.error_rounded, '$overCount Over', const Color(0xFFDC2626),
            const Color(0xFFFEF2F2)),
        const SizedBox(width: 8),
        _chip(Icons.warning_rounded, '$nearCount Near', const Color(0xFFD97706),
            const Color(0xFFFFFBEB)),
        const SizedBox(width: 8),
        _chip(Icons.check_circle_rounded, '$safeCount Safe',
            const Color(0xFF16A34A), const Color(0xFFF0FDF4)),
      ],
    );
  }

  Widget _chip(IconData icon, String label, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  BUDGET CARD
// ═══════════════════════════════════════════════════════
class _BudgetCard extends StatelessWidget {
  final _BudgetItem item;
  final VoidCallback onTap;

  const _BudgetCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final progressRatio = item.ratio.clamp(0, 1).toDouble();
    final percentText = '${(item.ratio * 100).toInt()}%';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: item.isOver
                  ? const Color(0xFFDC2626).withValues(alpha: 0.2)
                  : AppColors.borderLight.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              // Top row
              Row(
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: item.category.bgColor,
                    ),
                    child: Icon(item.category.icon,
                        size: 20, color: item.category.color),
                  ),
                  const SizedBox(width: 12),
                  // Name + amounts
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.category.name,
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'EGP ${_fmt(item.spent)} / ${_fmt(item.budget)}',
                          style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Percent + status
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        percentText,
                        style: TextStyle(
                          color: item.statusColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.isOver
                            ? 'Over'
                            : item.isNear
                                ? 'Near limit'
                                : 'On track',
                        style: TextStyle(
                          color: item.statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: LinearProgressIndicator(
                  value: progressRatio,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation(item.statusColor),
                ),
              ),
              if (item.isOver) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 13, color: item.statusColor),
                    const SizedBox(width: 4),
                    Text(
                      'Over by EGP ${_fmt(item.spent - item.budget)}',
                      style: TextStyle(
                        color: item.statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  FORMAT HELPER
// ═══════════════════════════════════════════════════════
String _fmt(double v) {
  if (v >= 1000) {
    final whole = v.toInt();
    final parts = <String>[];
    var n = whole;
    while (n >= 1000) {
      parts.insert(0, (n % 1000).toString().padLeft(3, '0'));
      n ~/= 1000;
    }
    parts.insert(0, n.toString());
    return parts.join(',');
  }
  return v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
}
