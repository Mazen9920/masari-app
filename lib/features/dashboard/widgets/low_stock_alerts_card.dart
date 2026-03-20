import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../core/navigation/app_router.dart';
import '../../../shared/models/product_model.dart';
import '../../../l10n/app_localizations.dart';

/// Shows products at or below reorder point, color-coded by urgency.
class LowStockAlertsCard extends ConsumerWidget {
  const LowStockAlertsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    // Respect the low-stock alerts setting
    final alertsEnabled = ref.watch(appSettingsProvider).lowStockAlerts;
    if (!alertsEnabled) return const SizedBox.shrink();

    final inventoryAsync = ref.watch(inventoryProvider);
    final products = inventoryAsync.value ?? [];

    // Collect all variants that are low/out-of-stock
    final alerts = <_StockAlert>[];
    for (final product in products) {
      for (final variant in product.variants) {
        if (variant.status == StockStatus.outOfStock ||
            variant.status == StockStatus.lowStock) {
          alerts.add(_StockAlert(
            productName: product.name,
            variantName: variant.optionValues.isNotEmpty
                ? variant.optionValues.values.join(' / ')
                : null,
            currentStock: variant.currentStock,
            reorderPoint: variant.reorderPoint,
            isOutOfStock: variant.status == StockStatus.outOfStock,
          ));
        }
      }
    }

    // Sort: out-of-stock first, then by stock ascending
    alerts.sort((a, b) {
      if (a.isOutOfStock != b.isOutOfStock) {
        return a.isOutOfStock ? -1 : 1;
      }
      return a.currentStock.compareTo(b.currentStock);
    });

    final shown = alerts.take(5).toList();
    final remaining = alerts.length - shown.length;

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
                      color: AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.warning_amber_rounded,
                        size: 18, color: AppColors.warning),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.lowStockAlerts,
                    style: AppTypography.h3.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (alerts.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${alerts.length}',
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
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
          const SizedBox(height: 14),

          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 36,
                        color: AppColors.success.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    Text(
                       l10n.allProductsWellStocked,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ...shown.map((alert) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _AlertRow(alert: alert),
                )),
            if (remaining > 0)
              Center(
                child: Text(
                  '+$remaining more items',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StockAlert {
  final String productName;
  final String? variantName;
  final int currentStock;
  final int reorderPoint;
  final bool isOutOfStock;

  const _StockAlert({
    required this.productName,
    this.variantName,
    required this.currentStock,
    required this.reorderPoint,
    required this.isOutOfStock,
  });
}

class _AlertRow extends StatelessWidget {
  final _StockAlert alert;

  const _AlertRow({required this.alert});

  @override
  Widget build(BuildContext context) {
      final l10n = AppLocalizations.of(context)!;
    final color = alert.isOutOfStock ? AppColors.danger : AppColors.warning;
    final label = alert.variantName != null
        ? '${alert.productName} — ${alert.variantName}'
        : alert.productName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(
            alert.isOutOfStock
                ? Icons.error_rounded
                : Icons.warning_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  alert.isOutOfStock
                      ? l10n.outOfStockStatus
                      : '${alert.currentStock} left (reorder at ${alert.reorderPoint})',
                  style: AppTypography.captionSmall.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
