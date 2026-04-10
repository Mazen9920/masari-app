import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../providers/dashboard_data_provider.dart';
import '../../../l10n/app_localizations.dart';

/// Card showing Gross Margin %, Net Margin %, and COGS Ratio
/// computed from sales in the selected period.
class ProfitMarginsCard extends ConsumerWidget {
  const ProfitMarginsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dashData = ref.watch(dashboardDataProvider).value;
    final cur = dashData?.currentMetrics ?? const PeriodMetrics();
    final currency = ref.watch(appSettingsProvider).currency;

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
             l10n.totalIncomeLabel(fmt.format(cur.revenue)),
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),

          _MarginRow(
            label: l10n.grossMargin,
            percentage: cur.grossMarginPct,
            color: cur.grossMarginPct >= 0
                ? AppColors.success
                : AppColors.danger,
          ),
          const SizedBox(height: 14),
          _MarginRow(
            label: l10n.netMargin,
            percentage: cur.netMarginPct,
            color: cur.netMarginPct >= 0
                ? AppColors.secondaryBlue
                : AppColors.danger,
          ),
          const SizedBox(height: 14),
          _MarginRow(
            label: l10n.cogsRatio,
            percentage: cur.cogsRatioPct,
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
    final isNegative = percentage < 0;
    final displayColor = isNegative && !invertColor ? AppColors.danger : color;
    final barValue = percentage.abs().clamp(0.0, 100.0);
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
                color: displayColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: barValue / 100,
            minHeight: 6,
            backgroundColor: displayColor.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation(displayColor),
          ),
        ),
      ],
    );
  }
}
