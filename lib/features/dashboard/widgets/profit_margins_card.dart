import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../providers/dashboard_state_provider.dart';
import '../../../l10n/app_localizations.dart';

/// Card showing Gross Margin %, Net Margin %, and COGS Ratio
/// computed from sales in the selected period.
class ProfitMarginsCard extends ConsumerWidget {
  const ProfitMarginsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dashState = ref.watch(dashboardStateProvider);
    final range = dashState.range;
    final salesAsync = ref.watch(salesProvider);
    final sales = salesAsync.value ?? [];
    final currency = ref.watch(appSettingsProvider).currency;

    // Filter sales in the selected period
    final periodSales = sales.where((s) {
      return !s.date.isBefore(range.start) && !s.date.isAfter(range.end);
    }).toList();

    double totalRevenue = 0;
    double totalCogs = 0;

    for (final sale in periodSales) {
      totalRevenue += sale.netRevenue;
      totalCogs += sale.totalCogs;
    }

    final grossProfit = totalRevenue - totalCogs;
    final grossMargin =
        totalRevenue > 0 ? (grossProfit / totalRevenue * 100) : 0.0;
    final cogsRatio =
        totalRevenue > 0 ? (totalCogs / totalRevenue * 100) : 0.0;

    // Net margin: P&L income - expenses (investments excluded from P&L)
    const plExcludedCats = {'cat_investments'};
    final transactionsAsync = ref.watch(transactionsProvider);
    final transactions = transactionsAsync.value ?? [];
    double totalIncome = 0;
    double totalExpenses = 0;
    for (final tx in transactions) {
      if (tx.excludeFromPL || plExcludedCats.contains(tx.categoryId)) continue;
      if (!tx.dateTime.isBefore(range.start) &&
          !tx.dateTime.isAfter(range.end)) {
        if (tx.isIncome) {
          totalIncome += tx.amount.abs();
        } else {
          totalExpenses += tx.amount.abs();
        }
      }
    }
    final netProfit = totalIncome - totalExpenses;
    final netMargin =
        totalIncome > 0 ? (netProfit / totalIncome * 100) : 0.0;

    final fmt = NumberFormat.compactCurrency(symbol: '$currency ');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.pie_chart_rounded,
                    size: 18, color: AppColors.success),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.profitMargins,
                style: AppTypography.h3.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
             'Revenue: ${fmt.format(totalIncome)}',
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          _MarginRow(
            label: l10n.grossMargin,
            percentage: grossMargin,
            color: AppColors.success,
          ),
          const SizedBox(height: 14),
          _MarginRow(
            label: l10n.netMargin,
            percentage: netMargin,
            color: netMargin >= 0
                ? AppColors.secondaryBlue
                : AppColors.danger,
          ),
          SizedBox(height: 14),
          _MarginRow(
            label: l10n.cogsRatio,
            percentage: cogsRatio,
            color: AppColors.accentOrange,
            invertColor: true,
          ),
        ],
      ),
    );
  }
}

class _MarginRow extends StatelessWidget {
  final String label;
  final double percentage;
  final Color color;
  final bool invertColor;

  const _MarginRow({
    required this.label,
    required this.percentage,
    required this.color,
    this.invertColor = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final clamped = percentage.clamp(0.0, 100.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${percentage.toStringAsFixed(1)}%',
              style: AppTypography.labelLarge.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: clamped / 100,
            minHeight: 6,
            backgroundColor: color.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
