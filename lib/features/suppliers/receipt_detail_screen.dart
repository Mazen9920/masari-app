import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../shared/models/goods_receipt_model.dart';
import '../../shared/models/purchase_model.dart';
import '../../shared/utils/safe_pop.dart';

/// Full-page detail screen for a single goods receipt.
/// Supports viewing details, editing, and deleting — all
/// synced back to inventory, purchase, and supplier.
class ReceiptDetailScreen extends ConsumerWidget {
  final GoodsReceipt receipt;
  const ReceiptDetailScreen({super.key, required this.receipt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0.00', 'en');
    final dateFmt = DateFormat('MMM dd, yyyy');

    // Watch live receipt data
    final receipts = ref.watch(goodsReceiptsProvider);
    final live = receipts.firstWhere(
      (r) => r.id == receipt.id,
      orElse: () => receipt,
    );

    // Look up linked purchase
    final purchases = ref.watch(purchasesProvider);
    final linkedPurchase = live.purchaseId != null
        ? purchases.cast<Purchase?>().firstWhere(
              (p) => p!.id == live.purchaseId,
              orElse: () => null,
            )
        : null;

    final statusColors = _statusColors(live.status);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, live, ref, currency),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Hero card ──
                    _buildHeroCard(live, currency, fmt, dateFmt, statusColors)
                        .animate()
                        .fadeIn(duration: 250.ms),
                    const SizedBox(height: 16),

                    // ── Linked PO ──
                    if (linkedPurchase != null) ...[
                      _buildLinkedPO(context, live, linkedPurchase, currency, fmt)
                          .animate()
                          .fadeIn(duration: 250.ms, delay: 60.ms),
                      const SizedBox(height: 16),
                    ],

                    // ── Items ──
                    _buildItemsList(live, currency, fmt)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 120.ms),

                    // ── Notes ──
                    if (live.notes != null && live.notes!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildNotesCard(live)
                          .animate()
                          .fadeIn(duration: 250.ms, delay: 180.ms),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomSheet: _buildBottomActions(context, live, ref, currency),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════════

  Widget _buildHeader(
      BuildContext context, GoodsReceipt r, WidgetRef ref, String currency) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            iconSize: 26,
            color: AppColors.textSecondary,
          ),
          Expanded(
            child: Center(
              child: Text(
                'Receipt Details',
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded,
                color: AppColors.textSecondary, size: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (v) {
              if (v == 'edit') {
                context.pushNamed('EditReceiptScreen', extra: {'receipt': r});
              } else if (v == 'delete') {
                _confirmDelete(context, r, ref, currency);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_rounded, size: 18),
                    SizedBox(width: 8),
                    Text('Edit Receipt'),
                  ])),
              const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_rounded,
                        size: 18, color: Color(0xFFDC2626)),
                    SizedBox(width: 8),
                    Text('Delete Receipt',
                        style: TextStyle(color: Color(0xFFDC2626))),
                  ])),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  HERO CARD
  // ═══════════════════════════════════════════════════════

  Widget _buildHeroCard(GoodsReceipt r, String currency, NumberFormat fmt,
      DateFormat dateFmt, (Color, Color) statusColors) {
    final itemNames =
        r.items.map((i) => i.productName).take(3).join(', ');
    final overflow = r.items.length > 3
        ? ' +${r.items.length - 3} more'
        : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.4)),
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
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFF3E8FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.inventory_2_rounded,
                    color: Color(0xFF7C3AED), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$itemNames$overflow',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${r.supplierName} · ${dateFmt.format(r.date)}',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColors.$1,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.statusLabel,
                  style: TextStyle(
                    color: statusColors.$2,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Summary row
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text('Total Cost',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        '$currency ${fmt.format(r.totalCost)}',
                        style: const TextStyle(
                          color: Color(0xFF7C3AED),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text('Items',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        r.totalReceived.toStringAsFixed(0),
                        style: const TextStyle(
                          color: Color(0xFF7C3AED),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: const Color(0xFF7C3AED).withValues(alpha: 0.2),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text('Fulfilment',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        '${r.fulfilmentPct.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          color: Color(0xFF7C3AED),
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  LINKED PO
  // ═══════════════════════════════════════════════════════

  Widget _buildLinkedPO(BuildContext context, GoodsReceipt r,
      Purchase purchase, String currency, NumberFormat fmt) {
    final poLabel = purchase.referenceNo.isNotEmpty
        ? 'PO #${purchase.referenceNo}'
        : 'PO – ${purchase.items.map((i) => i.name).take(2).join(', ')}';

    return GestureDetector(
      onTap: () {
        final suppliers =
            ProviderScope.containerOf(context).read(suppliersProvider).value ??
                [];
        final supplier = suppliers.cast<dynamic>().firstWhere(
              (s) => s.id == purchase.supplierId,
              orElse: () => null,
            );
        if (supplier != null) {
          context.pushNamed('PurchaseDetailScreen',
              extra: {'supplier': supplier, 'purchase': purchase});
        }
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: AppColors.borderLight.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFFF5F3FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shopping_cart_rounded,
                  color: Color(0xFF8B5CF6), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    poLabel,
                    style: TextStyle(
                      color: AppColors.primaryNavy,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Total: $currency ${fmt.format(purchase.total)} · ${purchase.items.length} item${purchase.items.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  ITEMS LIST
  // ═══════════════════════════════════════════════════════

  Widget _buildItemsList(
      GoodsReceipt r, String currency, NumberFormat fmt) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items Received',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < r.items.length; i++) ...[
            _buildItemRow(r.items[i], currency, fmt),
            if (i < r.items.length - 1)
              Divider(
                  height: 16,
                  color: AppColors.borderLight.withValues(alpha: 0.3)),
          ],
        ],
      ),
    );
  }

  Widget _buildItemRow(
      ReceiptItem item, String currency, NumberFormat fmt) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: TextStyle(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Received ${item.receivedQty.toStringAsFixed(0)} of ${item.orderedQty.toStringAsFixed(0)} · $currency ${fmt.format(item.unitCost)} ea',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Text(
          '$currency ${fmt.format(item.lineTotal)}',
          style: const TextStyle(
            color: Color(0xFF7C3AED),
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  NOTES
  // ═══════════════════════════════════════════════════════

  Widget _buildNotesCard(GoodsReceipt r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Notes',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            r.notes!,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  BOTTOM ACTIONS
  // ═══════════════════════════════════════════════════════

  Widget _buildBottomActions(
      BuildContext context, GoodsReceipt r, WidgetRef ref, String currency) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => context.pushNamed('EditReceiptScreen',
                  extra: {'receipt': r}),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Edit Receipt',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _confirmDelete(context, r, ref, currency),
            child: Container(
              width: 54,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete_rounded,
                  color: Color(0xFFDC2626), size: 22),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  DELETE
  // ═══════════════════════════════════════════════════════

  void _confirmDelete(
      BuildContext context, GoodsReceipt r, WidgetRef ref, String currency) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Receipt'),
        content: const Text(
          'This will delete the receipt and reverse the inventory stock adjustment. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(); // close dialog

              // Reverse inventory adjustments
              final products = ref.read(inventoryProvider).value ?? [];
              for (final item in r.items) {
                if (item.receivedQty > 0) {
                  String? pid = item.productId;
                  if (pid == null) {
                    final match = products.cast<dynamic>().firstWhere(
                          (p) =>
                              p.name.toString().toLowerCase() ==
                              item.productName.toLowerCase(),
                          orElse: () => null,
                        );
                    pid = match?.id as String?;
                  }
                  if (pid != null) {
                    ref.read(inventoryProvider.notifier).adjustStock(
                          pid,
                          item.variantId ?? '${pid}_v0',
                          -item.receivedQty.toInt(),
                          'Receipt deleted – reversal',
                          valuationMethod: ref.read(appSettingsProvider).valuationMethod,
                        );
                  }
                }
              }

              // Reverse linked purchase's receivedQty
              if (r.purchaseId != null) {
                final purchases = ref.read(purchasesProvider);
                final pIdx =
                    purchases.indexWhere((p) => p.id == r.purchaseId);
                if (pIdx >= 0) {
                  final purchase = purchases[pIdx];
                  final updatedItems = purchase.items.map((pi) {
                    final matched = r.items.where((ri) =>
                        ri.productName.toLowerCase() ==
                        pi.name.toLowerCase());
                    if (matched.isNotEmpty) {
                      final removedQty = matched.first.receivedQty.toInt();
                      return pi.copyWith(
                          receivedQty:
                              (pi.receivedQty - removedQty).clamp(0, pi.qty));
                    }
                    return pi;
                  }).toList();
                  ref.read(purchasesProvider.notifier).updatePurchase(
                        purchase.copyWith(items: updatedItems),
                      );
                }
              }

              // Delete the receipt itself
              ref.read(goodsReceiptsProvider.notifier).removeReceipt(r.id);

              context.safePop(); // go back

              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Receipt deleted'),
                backgroundColor: AppColors.danger,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ));
            },
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════

  (Color, Color) _statusColors(ReceiptStatus status) {
    switch (status) {
      case ReceiptStatus.confirmed:
        return (const Color(0xFFDCFCE7), const Color(0xFF166534));
      case ReceiptStatus.rejected:
        return (const Color(0xFFFEE2E2), const Color(0xFFDC2626));
      case ReceiptStatus.pending:
        return (const Color(0xFFF3E8FF), const Color(0xFF7C3AED));
    }
  }
}
