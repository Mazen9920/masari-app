import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/category_data.dart';
import '../../l10n/app_localizations.dart';
import 'category_detail_screen.dart';

/// Budget Overview — shows spending health + income targets.
class BudgetsOverviewScreen extends ConsumerWidget {
  const BudgetsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final categories = categoriesAsync.value ?? [];
    final transactions = ref.watch(transactionsProvider).value ?? [];
    final l10n = AppLocalizations.of(context)!;

    final now = DateTime.now();

    // ── Per-category spending (expenses) this month ──
    final spendingMap = <String, double>{};
    for (final tx in transactions) {
      if (!tx.isIncome &&
          tx.dateTime.month == now.month &&
          tx.dateTime.year == now.year) {
        spendingMap[tx.categoryId] =
            (spendingMap[tx.categoryId] ?? 0) + tx.amount.abs();
      }
    }

    // ── Per-category earnings (income) this month ──
    final earningsMap = <String, double>{};
    for (final tx in transactions) {
      if (tx.isIncome &&
          tx.dateTime.month == now.month &&
          tx.dateTime.year == now.year) {
        earningsMap[tx.categoryId] =
            (earningsMap[tx.categoryId] ?? 0) + tx.amount.abs();
      }
    }

    // ── Build expense budget items (budgetable expense categories) ──
    final expenseItems = <_BudgetItem>[];
    for (final cat in categories) {
      if (!cat.isBudgetable || !cat.isExpense) continue;
      final budget = cat.budgetLimit;
      if (budget == null || budget <= 0) continue;
      expenseItems.add(_BudgetItem(
        category: cat,
        budget: budget,
        spent: spendingMap[cat.id] ?? 0,
      ));
    }
    expenseItems.sort((a, b) {
      final aR = a.spent / a.budget;
      final bR = b.spent / b.budget;
      return bR.compareTo(aR);
    });

    // ── Build income target items (budgetable income categories) ──
    final incomeItems = <_BudgetItem>[];
    for (final cat in categories) {
      if (!cat.isBudgetable || cat.isExpense) continue;
      final target = cat.budgetLimit;
      if (target == null || target <= 0) continue;
      incomeItems.add(_BudgetItem(
        category: cat,
        budget: target,
        spent: earningsMap[cat.id] ?? 0,
      ));
    }
    incomeItems.sort((a, b) {
      final aR = a.ratio;
      final bR = b.ratio;
      return bR.compareTo(aR);
    });

    // ── Expense totals ──
    final totalBudget = expenseItems.fold(0.0, (s, i) => s + i.budget);
    final totalSpent = expenseItems.fold(0.0, (s, i) => s + i.spent);
    final overCount = expenseItems.where((i) => i.isOver).length;
    final nearCount = expenseItems.where((i) => i.isNear).length;
    final safeCount = expenseItems.length - overCount - nearCount;

    // ── Income totals ──
    final totalTarget = incomeItems.fold(0.0, (s, i) => s + i.budget);
    final totalEarned = incomeItems.fold(0.0, (s, i) => s + i.spent);
    final metCount = incomeItems.where((i) => i.spent >= i.budget).length;
    final onTrackIncCount =
        incomeItems.where((i) => i.spent >= i.budget * 0.5 && i.spent < i.budget).length;
    final belowCount = incomeItems.length - metCount - onTrackIncCount;

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
                    // ═══ EXPENSE BUDGETS SECTION ═══
                    if (expenseItems.isNotEmpty) ...[
                      _SummaryCard(
                        totalBudget: totalBudget,
                        totalSpent: totalSpent,
                        overCount: overCount,
                        nearCount: nearCount,
                        safeCount: safeCount,
                        currency: currency,
                      ).animate().fadeIn(duration: 300.ms),

                      const SizedBox(height: 16),

                      _StatusChips(
                        overCount: overCount,
                        nearCount: nearCount,
                        safeCount: safeCount,
                      ).animate().fadeIn(duration: 250.ms, delay: 50.ms),

                      const SizedBox(height: 16),

                      ...List.generate(expenseItems.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _BudgetCard(
                            item: expenseItems[i],
                            currency: currency,
                            isIncome: false,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CategoryDetailScreen(
                                      category: expenseItems[i].category),
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

                    if (expenseItems.isEmpty) ...[
                      _EmptySection(
                        icon: Icons.receipt_long_rounded,
                        label: l10n.noBudgetsSet,
                        color: const Color(0xFFE67E22),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // ═══ INCOME TARGETS SECTION ═══
                    _SectionTitle(
                      icon: Icons.trending_up_rounded,
                      title: l10n.incomeTargets,
                      color: const Color(0xFF16A34A),
                    ).animate().fadeIn(duration: 250.ms, delay: 100.ms),

                    const SizedBox(height: 12),

                    if (incomeItems.isNotEmpty) ...[
                      _IncomeSummaryCard(
                        totalTarget: totalTarget,
                        totalEarned: totalEarned,
                        metCount: metCount,
                        onTrackCount: onTrackIncCount,
                        belowCount: belowCount,
                        currency: currency,
                      ).animate().fadeIn(duration: 300.ms, delay: 120.ms),

                      const SizedBox(height: 16),

                      _IncomeStatusChips(
                        metCount: metCount,
                        onTrackCount: onTrackIncCount,
                        belowCount: belowCount,
                      ).animate().fadeIn(duration: 250.ms, delay: 150.ms),

                      const SizedBox(height: 16),

                      ...List.generate(incomeItems.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _BudgetCard(
                            item: incomeItems[i],
                            currency: currency,
                            isIncome: true,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CategoryDetailScreen(
                                      category: incomeItems[i].category),
                                ),
                              );
                            },
                          ).animate().fadeIn(
                                duration: 250.ms,
                                delay: (180 + i * 40).ms,
                              ),
                        );
                      }),
                    ],

                    if (incomeItems.isEmpty)
                      _EmptySection(
                        icon: Icons.trending_up_rounded,
                        label: l10n.noTargetsSet,
                        color: const Color(0xFF16A34A),
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

  /// Income-specific status color: gray → blue → green.
  Color get incomeStatusColor {
    if (spent >= budget) return const Color(0xFF16A34A); // met
    if (spent >= budget * 0.5) return const Color(0xFF3B82F6); // on track
    return const Color(0xFF94A3B8); // below
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
              AppLocalizations.of(context)!.budgetOverview,
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
    final now = DateTime.now();
    return DateFormat.yMMM().format(now);
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
  final String currency;

  const _SummaryCard({
    required this.totalBudget,
    required this.totalSpent,
    required this.overCount,
    required this.nearCount,
    required this.safeCount,
    required this.currency,
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
                AppLocalizations.of(context)!.monthlyBudgetLabel,
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
                  isOver ? AppLocalizations.of(context)!.overBudget : AppLocalizations.of(context)!.nPercentUsed((ratio * 100).toInt()),
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
                '$currency ${_fmt(totalSpent)}',
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
                  '/ $currency ${_fmt(totalBudget)}',
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
                ? AppLocalizations.of(context)!.overBy(currency, _fmt(totalSpent - totalBudget))
                : AppLocalizations.of(context)!.amountRemaining(currency, _fmt(remaining)),
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
        _chip(Icons.error_rounded, '$overCount ${AppLocalizations.of(context)!.overStatus}', const Color(0xFFDC2626),
            const Color(0xFFFEF2F2)),
        const SizedBox(width: 8),
        _chip(Icons.warning_rounded, '$nearCount ${AppLocalizations.of(context)!.nearStatus}', const Color(0xFFD97706),
            const Color(0xFFFFFBEB)),
        const SizedBox(width: 8),
        _chip(Icons.check_circle_rounded, '$safeCount ${AppLocalizations.of(context)!.safeStatus}',
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
  final String currency;
  final bool isIncome;
  final VoidCallback onTap;

  const _BudgetCard({
    required this.item,
    required this.currency,
    required this.isIncome,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progressRatio = item.ratio.clamp(0, 1).toDouble();
    final percentText = '${(item.ratio * 100).toInt()}%';
    final statusColor = isIncome ? item.incomeStatusColor : item.statusColor;

    // Income-specific border highlight when met
    final borderColor = isIncome
        ? (item.spent >= item.budget
            ? const Color(0xFF16A34A).withValues(alpha: 0.3)
            : AppColors.borderLight.withValues(alpha: 0.4))
        : (item.isOver
            ? const Color(0xFFDC2626).withValues(alpha: 0.2)
            : AppColors.borderLight.withValues(alpha: 0.4));

    // Status text
    final statusText = isIncome
        ? (item.spent >= item.budget
            ? l10n.metStatus
            : item.spent >= item.budget * 0.5
                ? l10n.onTrackStatus
                : l10n.belowStatus)
        : (item.isOver
            ? l10n.overStatus
            : item.isNear
                ? l10n.nearLimitStatus
                : l10n.onTrackStatus);

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
            border: Border.all(color: borderColor),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: item.category.displayBgColor,
                    ),
                    child: Icon(item.category.iconData,
                        size: 20, color: item.category.displayColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.category.localizedName(l10n),
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$currency ${_fmt(item.spent)} / ${_fmt(item.budget)}',
                          style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        percentText,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: LinearProgressIndicator(
                  value: progressRatio,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFF1F5F9),
                  valueColor: AlwaysStoppedAnimation(statusColor),
                ),
              ),
              // Expense: over-budget warning; Income: target met badge
              if (!isIncome && item.isOver) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 13, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      l10n.overBy(currency, _fmt(item.spent - item.budget)),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              if (isIncome && item.spent >= item.budget) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 13, color: const Color(0xFF16A34A)),
                    const SizedBox(width: 4),
                    Text(
                      l10n.targetMetBadge,
                      style: const TextStyle(
                        color: Color(0xFF16A34A),
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
//  SECTION TITLE
// ═══════════════════════════════════════════════════════
class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: AppTypography.h2.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
//  INCOME SUMMARY CARD
// ═══════════════════════════════════════════════════════
class _IncomeSummaryCard extends StatelessWidget {
  final double totalTarget;
  final double totalEarned;
  final int metCount;
  final int onTrackCount;
  final int belowCount;
  final String currency;

  const _IncomeSummaryCard({
    required this.totalTarget,
    required this.totalEarned,
    required this.metCount,
    required this.onTrackCount,
    required this.belowCount,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ratio = totalTarget > 0 ? totalEarned / totalTarget : 0.0;
    final isMet = totalEarned >= totalTarget && totalTarget > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isMet
              ? [const Color(0xFF16A34A), const Color(0xFF22C55E)]
              : [const Color(0xFF1E3A5F), const Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: (isMet ? const Color(0xFF16A34A) : const Color(0xFF1E3A5F))
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
                l10n.monthlyTargetLabel,
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  isMet
                      ? l10n.targetMetBadge
                      : l10n.nPercentUsed((ratio * 100).toInt()),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$currency ${_fmt(totalEarned)}',
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
                  '/ $currency ${_fmt(totalTarget)}',
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
          Text(
            l10n.earnedOf(
              '$currency ${_fmt(totalEarned)}',
              '$currency ${_fmt(totalTarget)}',
            ),
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
//  INCOME STATUS CHIPS
// ═══════════════════════════════════════════════════════
class _IncomeStatusChips extends StatelessWidget {
  final int metCount;
  final int onTrackCount;
  final int belowCount;

  const _IncomeStatusChips({
    required this.metCount,
    required this.onTrackCount,
    required this.belowCount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        _chip(Icons.check_circle_rounded, '$metCount ${l10n.metStatus}',
            const Color(0xFF16A34A), const Color(0xFFF0FDF4)),
        const SizedBox(width: 8),
        _chip(Icons.trending_up_rounded,
            '$onTrackCount ${l10n.onTrackStatus}',
            const Color(0xFF3B82F6), const Color(0xFFEFF6FF)),
        const SizedBox(width: 8),
        _chip(Icons.trending_down_rounded, '$belowCount ${l10n.belowStatus}',
            const Color(0xFF94A3B8), const Color(0xFFF8FAFC)),
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
//  EMPTY SECTION PLACEHOLDER
// ═══════════════════════════════════════════════════════
class _EmptySection extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _EmptySection({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: color.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
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
