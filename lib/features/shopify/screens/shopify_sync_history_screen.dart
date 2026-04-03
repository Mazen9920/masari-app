import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/repositories/shopify_sync_log_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../providers/shopify_sync_log_provider.dart';
import '../../../shared/utils/safe_pop.dart';
import '../../../l10n/app_localizations.dart';

/// Shows the Shopify sync log — every action (order import, inventory
/// push/pull, webhook) is logged and browsable here.
class ShopifySyncHistoryScreen extends ConsumerWidget {
  const ShopifySyncHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncLogs = ref.watch(shopifySyncLogProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, ref),
            Expanded(
              child: asyncLogs.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primaryNavy),
                ),
                error: (e, _) => Center(
                  child: Text(
                     AppLocalizations.of(context)!.shopifyFailedLoadSyncHistory('$e'),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),
                data: (logs) {
                  if (logs.isEmpty) return _buildEmpty(context);
                  return RefreshIndicator(
                    color: AppColors.primaryNavy,
                    onRefresh: () => ref
                        .read(shopifySyncLogProvider.notifier)
                        .refresh(),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      padding:
                          const EdgeInsets.fromLTRB(16, 8, 16, 40),
                      itemCount: logs.length,
                      itemBuilder: (ctx, i) {
                        return _LogTile(entry: logs[i])
                            .animate()
                            .fadeIn(
                              duration: 200.ms,
                              delay: (i.clamp(0, 20) * 20).ms,
                            );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            color: AppColors.primaryNavy,
          ),
          const Spacer(),
          Text(
             l10n.shopifySyncHistoryLabel,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.textSecondary, size: 22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onSelected: (val) {
              if (val == 'clear') {
                _confirmClear(context, ref);
              } else if (val == 'refresh') {
                ref.read(shopifySyncLogProvider.notifier).refresh();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'refresh',
                child: Text(l10n.refresh),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Text(l10n.clearAllLogs),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history_rounded,
              size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 16),
          Text(
             l10n.shopifyNoSyncHistory,
            style: AppTypography.h3.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
             l10n.shopifyNoSyncHistoryMessage,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.clearSyncHistory),
        content: Text(
             l10n.shopifyClearLogsMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(shopifySyncLogProvider.notifier).clearAll();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(l10n.clear),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  LOG TILE
// ═══════════════════════════════════════════════════════════

class _LogTile extends StatelessWidget {
  final ShopifySyncLogEntry entry;

  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isError = entry.status == 'error';
    final isSkipped = entry.status == 'skipped';
    final statusColor = isError
        ? AppColors.danger
        : isSkipped
            ? AppColors.warning
            : AppColors.success;
    final statusIcon = isError
        ? Icons.error_outline_rounded
        : isSkipped
            ? Icons.skip_next_rounded
            : Icons.check_circle_outline_rounded;

    final timeFmt = DateFormat( 'MMM dd, HH:mm');
    final directionLabel = entry.direction == 'shopify_to_masari'
        ? l10n.shopifyDirectionToRevvo
        : entry.direction == 'masari_to_shopify'
            ? l10n.shopifyDirectionToShopify
            : entry.direction;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError
              ? AppColors.danger.withValues(alpha: 0.2)
              : AppColors.borderLight.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 18, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _actionLabel(l10n, entry.action),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  entry.status.toUpperCase(),
                  style: AppTypography.captionSmall.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.swap_horiz_rounded,
                  size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Text(
                directionLabel,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.access_time_rounded,
                  size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Text(
                timeFmt.format(entry.createdAt),
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (entry.error != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onLongPress: () {
                HapticFeedback.lightImpact();
                Clipboard.setData(
                    ClipboardData(text: entry.error!));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.errorCopiedToClipboard),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: Text(
                entry.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.danger,
                  fontSize: 11,
                ),
              ),
            ),
          ],
          // Reference IDs
          if (entry.shopifyOrderId != null ||
              entry.revvoSaleId != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (entry.shopifyOrderId != null)
                  l10n.shopifyRefId(entry.shopifyOrderId!),
                if (entry.revvoSaleId != null)
                  l10n.shopifySaleRef(entry.revvoSaleId!.substring(0, 8)),
              ].join(' · '),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _actionLabel(AppLocalizations l10n, String action) {
    switch (action) {
      case 'order_import':
        return l10n.shopifyActionOrderImported;
      case 'order_updated':
        return l10n.shopifyActionOrderUpdated;
      case 'order_cancelled':
        return l10n.shopifyActionOrderCancelled;
      case 'order_push':
        return l10n.shopifyActionOrderPush;
      case 'inventory_pull':
        return l10n.shopifyActionInventoryPull;
      case 'inventory_push':
        return l10n.shopifyActionInventoryPush;
      case 'product_update':
        return l10n.shopifyActionProductUpdated;
      case 'inventory_level_update':
        return l10n.shopifyActionStockLevelUpdate;
      case 'refund_processed':
        return l10n.shopifyActionRefundProcessed;
      default:
        return action.replaceAll('_', ' ');
    }
  }
}
