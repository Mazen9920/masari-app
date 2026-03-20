import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../providers/shopify_connection_provider.dart';

/// A banner that appears when the Shopify connection has an error/disconnected
/// status but the user has a Growth subscription (which includes Shopify).
///
/// Shows on screens like dashboard, sales list, etc.
class ShopifyReconnectBanner extends ConsumerWidget {
  const ShopifyReconnectBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAccess = ref.watch(hasShopifyAccessProvider);
    if (!hasAccess) return const SizedBox.shrink();

    final asyncConn = ref.watch(shopifyConnectionProvider);
    return asyncConn.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (conn) {
        if (conn == null) {
          // Has Growth tier but never connected → show setup CTA
          return _SetupBanner();
        }
        if (conn.isActive) return const SizedBox.shrink();
        // Disconnected or error → show reconnect
        return _ReconnectBanner(hasError: conn.hasError, shopName: conn.shopName);
      },
    );
  }
}

class _SetupBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.shopifyPurple.withValues(alpha: 0.08),
            AppColors.shopifyPurple.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.shopifyPurple.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.shopifyPurple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.store_rounded,
                color: AppColors.shopifyPurple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shopify integration ready',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.shopifyPurple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap to connect your store and start syncing.',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => context.push(AppRoutes.shopifySetupWizard),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.shopifyPurple,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Setup',
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReconnectBanner extends StatelessWidget {
  final bool hasError;
  final String shopName;

  const _ReconnectBanner({required this.hasError, required this.shopName});

  @override
  Widget build(BuildContext context) {
    final color = hasError ? AppColors.danger : AppColors.warning;
    final icon = hasError ? Icons.error_outline_rounded : Icons.link_off_rounded;
    final title = hasError ? 'Shopify connection error' : 'Shopify disconnected';
    final subtitle = hasError
        ? 'Re-authorize "$shopName" to resume syncing.'
        : '"$shopName" was disconnected. Reconnect to resume.';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.08),
            color.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelSmall.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => context.push(AppRoutes.shopifySetupWizard),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Fix',
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
