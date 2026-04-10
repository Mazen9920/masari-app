import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/dashboard_state_provider.dart';
import '../providers/dashboard_data_provider.dart';

/// Horizontal scrolling row of stat cards: Revenue, Expenses, Net Profit.
class QuickStatsRow extends ConsumerWidget {
  const QuickStatsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ds = ref.watch(dashboardStateProvider);
    final currency = ref.watch(appSettingsProvider).currency;
    final fmt = NumberFormat.compactCurrency(symbol: '$currency ');

    final dashData = ref.watch(dashboardDataProvider).value;
    final cur = dashData?.currentMetrics ?? const PeriodMetrics();
    final prev = dashData?.previousMetrics ?? const PeriodMetrics();

    final revenuePct = prev.revenue.abs() > 0
        ? ((cur.revenue - prev.revenue) / prev.revenue.abs() * 100)
        : (cur.revenue > 0 ? 100.0 : 0.0);

    final expensesPct = prev.expenses > 0
        ? ((cur.expenses - prev.expenses) / prev.expenses * 100)
        : (cur.expenses > 0 ? 100.0 : 0.0);

    final profitPct = prev.netProfit.abs() > 0
        ? ((cur.netProfit - prev.netProfit) / prev.netProfit.abs() * 100)
        : (cur.netProfit > 0 ? 100.0 : (cur.netProfit < 0 ? -100.0 : 0.0));

    final l10n = AppLocalizations.of(context)!;
    final vsLabel = ds.period.localizedVsLabel(l10n);

    return SizedBox(
      height: 120,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _StatCard(
            label: l10n.revenue,
            amount: fmt.format(cur.revenue),
            change: '${revenuePct >= 0 ? '+' : ''}${revenuePct.toStringAsFixed(1)}% $vsLabel',
            changePositive: revenuePct >= 0,
            icon: Icons.trending_up_rounded,
            accentColor: AppColors.success,
          ),
          const SizedBox(width: 12),
          _StatCard(
            label: l10n.expenses,
            amount: fmt.format(cur.expenses),
            change: '${expensesPct >= 0 ? '+' : ''}${expensesPct.toStringAsFixed(1)}% $vsLabel',
            changePositive: expensesPct <= 0, // lower expenses = positive
            icon: Icons.trending_down_rounded,
            accentColor: AppColors.danger,
          ),
          const SizedBox(width: 12),
          _StatCard(
            label: l10n.netProfit,
            amount: fmt.format(cur.netProfit),
            change: cur.netProfit >= 0
                ? '${profitPct >= 0 ? '+' : ''}${profitPct.toStringAsFixed(1)}% $vsLabel'
                : '${l10n.lossLabel} $vsLabel',
            changePositive: cur.netProfit >= 0 && profitPct >= 0,
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
