import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../core/navigation/app_router.dart';
import '../providers/dashboard_state_provider.dart';
import '../../../shared/models/sale_model.dart';
import '../../../l10n/app_localizations.dart';

/// Shows top 5 products by revenue in the selected period.
class TopProductsCard extends ConsumerWidget {
  const TopProductsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final dashState = ref.watch(dashboardStateProvider);
    final range = dashState.range;
    final salesAsync = ref.watch(salesProvider);
    final sales = salesAsync.value ?? [];
    final currency = ref.watch(appSettingsProvider).currency;
    final fmt = NumberFormat.compactCurrency(symbol: '$currency ');

    // Aggregate revenue & quantity by product across sales in the period
    final revenueByProduct = <String, double>{};
    final qtyByProduct = <String, double>{};
    final nameByProduct = <String, String>{};

    for (final sale in sales) {
      if (sale.date.isBefore(range.start) || sale.date.isAfter(range.end)) {
        continue;
      }
      if (sale.orderStatus == OrderStatus.cancelled) continue;
      for (final item in sale.items) {
        final key = item.productId ?? item.productName;
        revenueByProduct[key] =
            (revenueByProduct[key] ?? 0) + item.lineTotal;
        qtyByProduct[key] = (qtyByProduct[key] ?? 0) + item.quantity;
        nameByProduct[key] = item.productName;
      }
    }

    // Sort by revenue descending, take top 5
    final sorted = revenueByProduct.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sorted.take(5).toList();

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.emoji_events_rounded,
                        size: 18, color: AppColors.accentOrange),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.topProducts,
                    style: AppTypography.h3.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () => context.push(AppRoutes.inventory),
                child: Text(
                  l10n.viewAll,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.accentOrange,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (top5.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                   l10n.noSalesInPeriod,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            )
          else
            ...List.generate(top5.length, (i) {
              final entry = top5[i];
              final name = nameByProduct[entry.key] ?? 'Unknown';
              final qty = qtyByProduct[entry.key] ?? 0;
              final revenue = entry.value;
              final maxRevenue = top5.first.value;
              final barFraction =
                  maxRevenue > 0 ? (revenue / maxRevenue) : 0.0;

              return Padding(
                padding: EdgeInsets.only(bottom: i < top5.length - 1 ? 12 : 0),
                child: _ProductRow(
                  rank: i + 1,
                  name: name,
                  quantity: qty,
                  revenue: fmt.format(revenue),
                  barFraction: barFraction,
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final int rank;
  final String name;
  final double quantity;
  final String revenue;
  final double barFraction;

  const _ProductRow({
    required this.rank,
    required this.name,
    required this.quantity,
    required this.revenue,
    required this.barFraction,
  });

  Color get _rankColor {
    switch (rank) {
      case 1:
        return AppColors.accentOrange;
      case 2:
        return AppColors.secondaryBlue;
      case 3:
        return AppColors.success;
      default:
        return AppColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            // Rank badge
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: _rankColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '#$rank',
                  style: AppTypography.captionSmall.copyWith(
                    color: _rankColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Name + qty
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${quantity.toStringAsFixed(quantity.truncateToDouble() == quantity ? 0 : 1)} units',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            // Revenue
            Text(
              revenue,
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: barFraction.clamp(0, 1),
            minHeight: 4,
            backgroundColor: AppColors.borderLight,
            valueColor: AlwaysStoppedAnimation(
              _rankColor.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }
}
