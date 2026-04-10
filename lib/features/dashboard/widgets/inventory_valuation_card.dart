import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../l10n/app_localizations.dart';

/// Card showing total inventory cost value, retail value,
/// potential profit, and total SKU count.
class InventoryValuationCard extends ConsumerWidget {
  const InventoryValuationCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final inventoryAsync = ref.watch(filteredInventoryProvider);
    final products = inventoryAsync.value ?? [];
    final currency = ref.watch(appSettingsProvider).currency;
    final fmt = NumberFormat.compactCurrency(symbol: '$currency ');

    double totalCost = 0;
    double totalRetail = 0;
    int totalSkus = 0;

    for (final product in products) {
      totalCost += product.totalCostValue;
      totalRetail += product.totalValue;
      totalSkus += product.variants.length;
    }

    final potentialProfit = totalRetail - totalCost;

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
                  color: AppColors.secondaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warehouse_rounded,
                    size: 18, color: AppColors.secondaryBlue),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.inventoryValuation,
                style: AppTypography.h3.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 2x2 grid
          Row(
            children: [
              Expanded(
                child: _ValuationTile(
                  label: l10n.costValue,
                  value: fmt.format(totalCost),
                  icon: Icons.payments_rounded,
                  color: AppColors.danger,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ValuationTile(
                  label: l10n.retailValue,
                  value: fmt.format(totalRetail),
                  icon: Icons.sell_rounded,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ValuationTile(
                  label: l10n.potentialProfit,
                  value: fmt.format(potentialProfit),
                  icon: Icons.trending_up_rounded,
                  color: AppColors.accentOrange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ValuationTile(
                  label: l10n.totalSkus,
                  value: totalSkus.toString(),
                  icon: Icons.category_rounded,
                  color: AppColors.secondaryBlue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValuationTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ValuationTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
