import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../providers/shopify_connection_provider.dart';
import '../providers/shopify_sync_provider.dart';
import '../../../l10n/app_localizations.dart';

/// Persistent badge/indicator for the Management Hub.
///
/// - Green dot = connected, syncing animation, red = error
/// - Last sync time: "Last sync: 2 min ago"
/// - Tap → goes to Shopify settings screen
class ShopifySyncStatusWidget extends ConsumerWidget {
  const ShopifySyncStatusWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isConnected = ref.watch(isShopifyConnectedProvider);
    if (!isConnected) return const SizedBox.shrink();

    final asyncConn = ref.watch(shopifyConnectionProvider);
    final syncStatus = ref.watch(shopifySyncProvider);
    final conn = asyncConn.value;

    if (conn == null) return const SizedBox.shrink();

    // Determine status display
    Color dotColor;
    String statusText;

    if (syncStatus.isSyncing) {
      dotColor = AppColors.secondaryBlue;
      statusText = syncStatus.message ?? l10n.shopifySyncingStatus;
    } else if (conn.hasError) {
      dotColor = AppColors.danger;
      statusText = l10n.connectionError;
    } else {
      dotColor = AppColors.success;
      statusText = _lastSyncText(l10n, conn.lastOrderSyncAt);
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push(AppRoutes.shopify);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: dotColor.withValues(alpha: 0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Shopify icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF96BF48), Color(0xFF5E8E3E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.shopping_bag_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                     l10n.shopifyConnectedTo(conn.shopName),
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusText,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),

            // Status dot with optional animation
            if (syncStatus.isSyncing)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: dotColor,
                ),
              )
            else
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),

            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 250.ms);
  }

  String _lastSyncText(AppLocalizations l10n, DateTime? lastSync) {
    if (lastSync == null) return l10n.shopifyConnectedLabel;

    final diff = DateTime.now().difference(lastSync);
    if (diff.inMinutes < 1) return l10n.shopifyLastSyncJustNow;
    if (diff.inMinutes < 60) return l10n.shopifyLastSyncMinAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.shopifyLastSyncHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.shopifyLastSyncDaysAgo(diff.inDays);
    return l10n.shopifyLastSyncTime(DateFormat('MMM dd').format(lastSync));
  }
}
