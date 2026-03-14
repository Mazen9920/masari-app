import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/navigation/app_router.dart';
import '../../../l10n/app_localizations.dart';

/// Row of 4 quick action buttons: Record Sale, Add Expense, Add Product, Import.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _ActionButton(
            icon: Icons.point_of_sale_rounded,
            label: l10n.saleAction,
            color: AppColors.success,
            onTap: () => context.push('/sales/record'),
          ),
          _ActionButton(
            icon: Icons.receipt_long_rounded,
            label: l10n.expense,
            color: AppColors.danger,
            onTap: () => context.push(AppRoutes.addTransaction),
          ),
          _ActionButton(
            icon: Icons.inventory_2_rounded,
            label: l10n.product,
            color: AppColors.secondaryBlue,
            onTap: () => context.push(AppRoutes.inventory),
          ),
          _ActionButton(
            icon: Icons.cloud_download_rounded,
            label: l10n.importAction,
            color: AppColors.accentOrange,
            onTap: () => context.push(AppRoutes.shopifyImport),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: color.withValues(alpha: 0.2),
              ),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
