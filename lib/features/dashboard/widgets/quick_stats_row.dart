import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../providers/dashboard_state_provider.dart';

/// Horizontal scrolling row of stat cards: Revenue, Expenses, Net Profit.
class QuickStatsRow extends ConsumerWidget {
  const QuickStatsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = ref.watch(dashboardStateProvider);
    final range = ds.range;
    final currency = ref.watch(appSettingsProvider).currency;
    final fmt = NumberFormat.compactCurrency(symbol: '$currency ');

    final allTxns = ref.watch(transactionsProvider).value ?? [];

    // Categories excluded from P&L (CF investing activities / BS only)
    const plExcludedCats = {'cat_investments'};

    bool inPL(t) => !t.excludeFromPL && !plExcludedCats.contains(t.categoryId);

    // Current period
    final curTxns = allTxns
        .where((t) =>
            inPL(t) &&
            !t.dateTime.isBefore(range.start) &&
            !t.dateTime.isAfter(range.end))
        .toList();

    // Previous period
    final prevTxns = allTxns
        .where((t) =>
            inPL(t) &&
            !t.dateTime.isBefore(range.previousStart) &&
            !t.dateTime.isAfter(range.previousEnd))
        .toList();

    // Revenue (accrual basis — operating income only)
    final curRevenue = curTxns
        .where((t) => t.isIncome)
        .fold<double>(0, (sum, t) => sum + t.amount.abs());
    final prevRevenue = prevTxns
        .where((t) => t.isIncome)
        .fold<double>(0, (sum, t) => sum + t.amount.abs());
    final revenuePct = prevRevenue > 0
        ? ((curRevenue - prevRevenue) / prevRevenue * 100)
        : (curRevenue > 0 ? 100.0 : 0.0);

    // Expenses (negative amounts = expenses)
    final curExpenses = curTxns
        .where((t) => !t.isIncome)
        .fold<double>(0, (sum, t) => sum + t.amount.abs());
    final prevExpenses = prevTxns
        .where((t) => !t.isIncome)
        .fold<double>(0, (sum, t) => sum + t.amount.abs());
    final expensesPct = prevExpenses > 0
        ? ((curExpenses - prevExpenses) / prevExpenses * 100)
        : (curExpenses > 0 ? 100.0 : 0.0);

    // Net Profit
    final curProfit = curRevenue - curExpenses;
    final prevProfit = prevRevenue - prevExpenses;
    final profitPct = prevProfit.abs() > 0
        ? ((curProfit - prevProfit) / prevProfit.abs() * 100)
        : (curProfit > 0 ? 100.0 : (curProfit < 0 ? -100.0 : 0.0));

    final vsLabel = ds.period.vsLabel;

    return SizedBox(
      height: 120,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _StatCard(
            label: 'Revenue',
            amount: fmt.format(curRevenue),
            change: '${revenuePct >= 0 ? '+' : ''}${revenuePct.toStringAsFixed(1)}% $vsLabel',
            changePositive: revenuePct >= 0,
            icon: Icons.trending_up_rounded,
            accentColor: AppColors.success,
          ),
          const SizedBox(width: 12),
          _StatCard(
            label: 'Expenses',
            amount: fmt.format(curExpenses),
            change: '${expensesPct >= 0 ? '+' : ''}${expensesPct.toStringAsFixed(1)}% $vsLabel',
            changePositive: expensesPct <= 0, // lower expenses = positive
            icon: Icons.trending_down_rounded,
            accentColor: AppColors.danger,
          ),
          const SizedBox(width: 12),
          _StatCard(
            label: 'Net Profit',
            amount: fmt.format(curProfit),
            change: curProfit >= 0
                ? '${profitPct >= 0 ? '+' : ''}${profitPct.toStringAsFixed(1)}% $vsLabel'
                : 'Loss $vsLabel',
            changePositive: curProfit >= 0 && profitPct >= 0,
            icon: Icons.monetization_on_rounded,
            accentColor: AppColors.accentOrange,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String amount;
  final String change;
  final bool changePositive;
  final IconData icon;
  final Color accentColor;

  const _StatCard({
    required this.label,
    required this.amount,
    required this.change,
    required this.changePositive,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top colored bar
          Container(
            width: double.infinity,
            height: 3,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Icon + label row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Amount
          Text(
            amount,
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 2),
          // Change
          Text(
            change,
            style: AppTypography.captionSmall.copyWith(
              color: changePositive ? AppColors.success : AppColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
