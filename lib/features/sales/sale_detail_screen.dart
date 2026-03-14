import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/services/shopify_sync_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../shared/models/sale_model.dart';
import '../shopify/providers/shopify_connection_provider.dart';
import '../shopify/widgets/shopify_badges.dart';
import '../../shared/utils/safe_pop.dart';
import 'widgets/edit_cogs_dialog.dart';

/// Order detail screen — view and manage a single sale/order.
class SaleDetailScreen extends ConsumerWidget {
  final Sale sale;

  const SaleDetailScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch for live updates
    final sales = ref.watch(salesProvider).value ?? [];
    final live = sales.firstWhere((s) => s.id == sale.id, orElse: () => sale);

    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0.00', 'en');
    final dateFmt = DateFormat('MMM dd, yyyy');

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, live, ref),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(salesProvider.notifier).refresh(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                child: Column(
                  children: [
                    _buildOrderStatusCard(context, live, ref)
                        .animate()
                        .fadeIn(duration: 250.ms),
                    if (live.externalSource == 'shopify') ...[                      const SizedBox(height: 14),
                      Builder(builder: (context) {
                        final conn = ref.watch(shopifyConnectionProvider).value;
                        return ShopifySaleBadge(
                          externalOrderId: live.externalOrderId,
                          shopDomain: conn?.shopDomain,
                        );
                      }).animate().fadeIn(duration: 250.ms, delay: 40.ms),
                    ],
                    const SizedBox(height: 14),
                    _buildSummaryCard(live, currency, fmt, dateFmt)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 60.ms),
                    // ── Zero-COGS alert ──
                    if (live.totalCogs == 0 &&
                        live.orderStatus != OrderStatus.cancelled &&
                        live.items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: _buildZeroCogsBanner(context, live, currency, ref),
                      ).animate().fadeIn(duration: 250.ms, delay: 90.ms),
                    const SizedBox(height: 14),
                    _buildItemsList(live, currency, fmt, ref)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 120.ms),
                    const SizedBox(height: 14),
                    _buildTotalsCard(context, live, currency, fmt, ref)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 180.ms),
                    const SizedBox(height: 14),
                    _buildPaymentInfo(context, live, ref)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 240.ms),
                    if (live.trackingNumber != null &&
                        live.trackingNumber!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildTrackingCard(context, live)
                          .animate()
                          .fadeIn(duration: 250.ms, delay: 280.ms),
                    ],
                    if (live.shippingAddress != null &&
                        live.shippingAddress!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildShippingCard(live)
                          .animate()
                          .fadeIn(duration: 250.ms, delay: 300.ms),
                    ],
                    if (live.notes != null && live.notes!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildNotesCard(live)
                          .animate()
                          .fadeIn(duration: 250.ms, delay: 340.ms),
                    ],
                  ],
                ),
              ),
              ),
            ),
          ],
        ),
      ),
      // Use a single bottomSheet widget to avoid framework assertions
      // when dynamically swapping between different widget trees.
      bottomSheet: _buildBottomSheet(context, live, ref, currency, fmt),
    );
  }

  /// Unified bottom sheet that switches content internally, avoiding
  /// the RenderFlex overflow & Duplicate GlobalKey issues that occur
  /// when Scaffold.bottomSheet toggles between two different widgets.
  Widget _buildBottomSheet(BuildContext context, Sale live, WidgetRef ref,
      String currency, NumberFormat fmt) {
    final isCancelled = live.orderStatus == OrderStatus.cancelled;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    // Use a SINGLE consistent Container so Scaffold never swaps between
    // structurally different widget trees — this prevents Duplicate
    // GlobalKeys, RenderFlex overflow, and wrong-build-scope assertions.
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
      decoration: BoxDecoration(
        color: isCancelled
            ? AppColors.danger.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(
            color: isCancelled
                ? AppColors.danger.withValues(alpha: 0.2)
                : AppColors.borderLight.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: isCancelled
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cancel_rounded,
                    size: 20,
                    color: AppColors.danger.withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Text(
                  'This order has been cancelled',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : _buildBottomActionsContent(context, live, ref, currency, fmt),
    );
  }

  // ── Header ──────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, Sale live, WidgetRef ref) {
    final isCancelled = live.orderStatus == OrderStatus.cancelled;

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
            iconSize: 24,
            color: AppColors.textSecondary,
          ),
          Expanded(
            child: Center(
              child: Text(
                'Order Details',
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (!isCancelled)
            PopupMenuButton<String>(
              icon:
                  Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
              onSelected: (v) {
                if (v == 'edit') {
                  context
                      .pushNamed('RecordSaleScreen', extra: {'sale': live});
                } else if (v == 'cancel') {
                  _confirmCancel(context, ref, live);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'edit', child: Text('Edit Order')),
                const PopupMenuItem(
                  value: 'cancel',
                  child: Text('Cancel Order',
                      style: TextStyle(color: AppColors.danger)),
                ),
              ],
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── Order Status Card ───────────────────────────────────

  Widget _buildOrderStatusCard(
      BuildContext context, Sale live, WidgetRef ref) {
    return _Card(
      children: [
        Row(
          children: [
            Icon(Icons.local_shipping_rounded,
                size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Order Status',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            _OrderStatusBadge(status: live.orderStatus),
          ],
        ),
        const SizedBox(height: 16),
        _buildStatusStepper(live.orderStatus),
        if (live.orderStatus != OrderStatus.cancelled &&
            live.orderStatus != OrderStatus.completed) ...[
          const SizedBox(height: 16),
          _buildStatusActions(context, live, ref),
        ],
      ],
    );
  }

  Widget _buildStatusStepper(OrderStatus current) {
    const steps = [
      (OrderStatus.pending, 'Pending', Icons.hourglass_empty_rounded),
      (OrderStatus.confirmed, 'Confirmed', Icons.check_circle_outline_rounded),
      (OrderStatus.processing, 'Processing', Icons.inventory_2_rounded),
      (OrderStatus.completed, 'Completed', Icons.done_all_rounded),
    ];

    if (current == OrderStatus.cancelled) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cancel_rounded, color: AppColors.danger, size: 20),
            const SizedBox(width: 8),
            Text(
              'This order has been cancelled',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.danger,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final currentIdx = steps.indexWhere((s) => s.$1 == current);

    return Row(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: i <= currentIdx
                      ? AppColors.success
                      : AppColors.borderLight.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: i <= currentIdx
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.borderLight.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: i <= currentIdx
                        ? AppColors.success
                        : AppColors.borderLight,
                    width: i == currentIdx ? 2 : 1,
                  ),
                ),
                child: Icon(
                  steps[i].$3,
                  size: 16,
                  color: i <= currentIdx
                      ? AppColors.success
                      : AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[i].$2,
                style: AppTypography.captionSmall.copyWith(
                  color: i <= currentIdx
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                  fontWeight:
                      i == currentIdx ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStatusActions(
      BuildContext context, Sale live, WidgetRef ref) {
    // Determine next status
    OrderStatus? next;
    String? nextLabel;
    IconData? nextIcon;

    switch (live.orderStatus) {
      case OrderStatus.pending:
        next = OrderStatus.confirmed;
        nextLabel = 'Confirm Order';
        nextIcon = Icons.check_circle_outline_rounded;
        break;
      case OrderStatus.confirmed:
        next = OrderStatus.processing;
        nextLabel = 'Start Processing';
        nextIcon = Icons.inventory_2_rounded;
        break;
      case OrderStatus.processing:
        next = OrderStatus.completed;
        nextLabel = 'Mark Completed';
        nextIcon = Icons.done_all_rounded;
        break;
      case OrderStatus.completed:
      case OrderStatus.cancelled:
        break;
    }

    if (next == null) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          HapticFeedback.mediumImpact();
          _changeStatus(ref, live, next!);
        },
        icon: Icon(nextIcon, size: 18),
        label: Text(nextLabel!),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.success,
          side: BorderSide(color: AppColors.success.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  void _changeStatus(WidgetRef ref, Sale live, OrderStatus newStatus) {
    final updated = live.copyWith(
      orderStatus: newStatus,
      updatedAt: DateTime.now(),
    );
    ref.read(salesProvider.notifier).updateSale(updated);

    // Revenue recognition: when confirmed/completed, ensure P&L includes the
    // sale transactions. When still pending, exclude from P&L (deferred revenue).
    final shouldExclude = newStatus == OrderStatus.pending;
    final transactions = ref.read(transactionsProvider).value ?? [];
    final transNotifier = ref.read(transactionsProvider.notifier);
    for (final tx in transactions) {
      if (tx.saleId == live.id && tx.excludeFromPL != shouldExclude) {
        transNotifier.updateTransaction(tx.copyWith(
          excludeFromPL: shouldExclude,
          updatedAt: DateTime.now(),
        ));
      }
    }
  }

  // ── Cancel Order ────────────────────────────────────────

  void _confirmCancel(BuildContext context, WidgetRef ref, Sale live) {
    final isShopifyOrder = live.externalSource == 'shopify' &&
        live.externalOrderId != null;
    final isPaid = live.paymentStatus == PaymentStatus.paid;

    // Block cancelling paid Shopify orders from Masari — user must cancel
    // on Shopify (which handles refund + fulfillment properly), and the
    // webhook will auto-sync the cancellation back to Masari.
    if (isShopifyOrder && isPaid) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot Cancel Here'),
          content: Text(
            'Shopify order #${live.shopifyOrderNumber ?? live.externalOrderId} '
            'is marked as paid.\n\n'
            'Paid orders must be cancelled directly on Shopify '
            '(which will handle the refund automatically).\n\n'
            'Once cancelled on Shopify, it will sync to Masari automatically.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Order'),
        content: Text(
          isShopifyOrder
              ? 'This sale is linked to Shopify order '
                  '#${live.shopifyOrderNumber ?? live.externalOrderId}.\n\n'
                  'Cancelling here will:\n'
                  '• Restore inventory stock locally\n'
                  '• Create reversal entries for revenue & COGS\n'
                  '• Mark the order as cancelled in Masari\n'
                  '• Cancel the order on Shopify automatically\n\n'
                  'This action cannot be undone.'
              : 'Are you sure you want to cancel this order?\n\n'
                  'This will:\n'
                  '• Restore inventory stock\n'
                  '• Create reversal entries for revenue & COGS\n'
                  '• Mark the order as cancelled\n\n'
                  'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Order'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _cancelOrder(context, ref, live);
            },
            child: Text(
              'Cancel Order',
              style: const TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelOrder(BuildContext context, WidgetRef ref, Sale live) async {
    HapticFeedback.heavyImpact();

    final now = DateTime.now();
    final isShopifyOrder = live.externalSource == 'shopify' &&
        live.externalOrderId != null;

    // 0) Cancel on Shopify first if linked — must succeed before local cancel
    if (isShopifyOrder) {
      final result = await ref
          .read(shopifyApiServiceProvider)
          .cancelOrder(orderId: live.externalOrderId!);

      if (!context.mounted) return;

      if (!result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Shopify cancel failed: ${result.error}'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ));
        return; // Don't proceed with local cancel if Shopify failed
      }
    }

    // 1) Restore stock for each sale item
    final valMethod = ref.read(appSettingsProvider).valuationMethod;
    for (final item in live.items) {
      if (item.productId != null && item.quantity > 0) {
        ref.read(inventoryProvider.notifier).adjustStock(
              item.productId!,
              item.variantId ?? '${item.productId}_v0',
              item.quantity.toInt(),
              'Order cancelled',
              valuationMethod: valMethod,
            );
      }
    }

    // 2) Create reversal entries for linked transactions (proper accounting)
    //    Original transactions are kept intact for audit trail.
    final transactions = ref.read(transactionsProvider).value ?? [];
    final transNotifier = ref.read(transactionsProvider.notifier);
    for (final tx in transactions) {
      if (tx.saleId == live.id && tx.amount != 0) {
        // Mark original as cancelled (audit trail — keep original amount)
        transNotifier.updateTransaction(tx.copyWith(
          title: '[Cancelled] ${tx.title}',
          excludeFromPL: true,
          updatedAt: now,
        ));

        // Create reversal entry with negated amount
        final reversalId =
            '${tx.id}_reversal_${now.millisecondsSinceEpoch}';
        transNotifier.addTransaction(tx.copyWith(
          id: reversalId,
          title: '[Reversal] ${tx.title}',
          amount: -tx.amount,
          dateTime: now,
          note: 'Auto-reversal for cancelled order ${live.id}',
          excludeFromPL: true,
          createdAt: now,
          updatedAt: now,
        ));
      }
    }

    // 3) Mark order as cancelled
    final cancelled = live.copyWith(
      orderStatus: OrderStatus.cancelled,
      updatedAt: now,
    );
    ref.read(salesProvider.notifier).updateSale(cancelled);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text(
          'Order cancelled — stock restored, reversal entries created'),
      backgroundColor: AppColors.primaryNavy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Summary ─────────────────────────────────────────────

  Widget _buildSummaryCard(
      Sale live, String currency, NumberFormat fmt, DateFormat dateFmt) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (live.paymentStatus) {
      case PaymentStatus.paid:
        statusColor = AppColors.success;
        statusLabel = 'Paid';
        statusIcon = Icons.check_circle_rounded;
        break;
      case PaymentStatus.refunded:
        statusColor = AppColors.danger;
        statusLabel = 'Refunded';
        statusIcon = Icons.money_off_rounded;
        break;
      case PaymentStatus.partial:
        statusColor = AppColors.warning;
        statusLabel = 'Partial';
        statusIcon = Icons.timelapse_rounded;
        break;
      case PaymentStatus.unpaid:
        statusColor = AppColors.danger;
        statusLabel = 'Unpaid';
        statusIcon = Icons.money_off_rounded;
        break;
    }

    return _Card(children: [
      Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: live.orderStatus == OrderStatus.cancelled
                  ? AppColors.danger.withValues(alpha: 0.08)
                  : const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              live.orderStatus == OrderStatus.cancelled
                  ? Icons.cancel_rounded
                  : Icons.shopping_bag_rounded,
              size: 26,
              color: live.orderStatus == OrderStatus.cancelled
                  ? AppColors.danger
                  : const Color(0xFF10B981),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  live.shopifyOrderNumber != null
                      ? 'Shopify #${live.shopifyOrderNumber}'
                      : live.customerName ?? 'Walk-in Customer',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (live.shopifyOrderNumber != null &&
                    live.customerName != null) ...[
                  Text(
                    live.customerName!,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  dateFmt.format(live.date),
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 4),
                Text(
                  statusLabel,
                  style: AppTypography.labelSmall.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: live.orderStatus == OrderStatus.cancelled
              ? const Color(0xFFFEF2F2)
              : const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (live.orderStatus == OrderStatus.cancelled)
              Text(
                '$currency ${fmt.format(live.total)}',
                style: AppTypography.displayMedium.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w800,
                  decoration: TextDecoration.lineThrough,
                ),
              )
            else
              Text(
                '$currency ${fmt.format(live.total)}',
                style: AppTypography.displayMedium.copyWith(
                  color: const Color(0xFF10B981),
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    ]);
  }

  // ── Zero-COGS alert ─────────────────────────────────────

  Widget _buildZeroCogsBanner(
      BuildContext context, Sale live, String currency, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showEditCogsDialog(context, live, currency, ref),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.warningLight,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.warning.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: AppColors.warning, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Missing Cost of Goods',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'COGS is zero — profit numbers may be inaccurate.',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.warning,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Fix',
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditCogsDialog(
      BuildContext context, Sale sale, String currency, WidgetRef ref) {
    showDialog<bool>(
      context: context,
      builder: (_) => EditCogsDialog(sale: sale, currency: currency),
    );
  }

  // ── Items ───────────────────────────────────────────────

  Widget _buildItemsList(Sale live, String currency, NumberFormat fmt, WidgetRef ref) {
    return _Card(
      title: 'Items (${live.items.length})',
      children: [
        for (int i = 0; i < live.items.length; i++) ...[
          if (i > 0)
            Divider(
                color: AppColors.borderLight.withValues(alpha: 0.5),
                height: 16),
          _buildItemRow(live.items[i], currency, fmt, ref),
        ],
      ],
    );
  }

  Widget _buildItemRow(SaleItem item, String currency, NumberFormat fmt, WidgetRef ref) {
    // Look up product image from inventory
    String? imageUrl;
    final products = ref.read(inventoryProvider).value;
    if (products != null && item.productId != null) {
      final product = products.where((p) => p.id == item.productId).firstOrNull;
      if (product != null) {
        if (item.variantId != null) {
          final variant = product.variantById(item.variantId!);
          imageUrl = variant?.imageUrl ?? product.imageUrl;
        } else {
          imageUrl = product.imageUrl;
        }
      }
    }

    return Row(
      children: [
        _itemThumbnail(imageUrl, 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${item.quantity} × $currency ${fmt.format(item.unitPrice)}',
                style: AppTypography.captionSmall
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Text(
          '$currency ${fmt.format(item.lineTotal)}',
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ── Totals ──────────────────────────────────────────────

  Widget _buildTotalsCard(BuildContext context, Sale live, String currency, NumberFormat fmt, WidgetRef ref) {
    return _Card(
      title: 'Totals',
      children: [
        _row('Subtotal', '$currency ${fmt.format(live.subtotal)}'),
        if (live.taxAmount > 0) ...[
          const SizedBox(height: 6),
          _row('Tax', '+ $currency ${fmt.format(live.taxAmount)}'),
        ],
        if (live.discountAmount > 0) ...[
          const SizedBox(height: 6),
          _row('Discount', '- $currency ${fmt.format(live.discountAmount)}'),
        ],
        const Divider(height: 16),
        _row('Total', '$currency ${fmt.format(live.total)}', bold: true),
        if (live.totalCogs > 0) ...[
          const SizedBox(height: 6),
          _row('COGS', '$currency ${fmt.format(live.totalCogs)}',
              valueColor: AppColors.danger),
          const SizedBox(height: 4),
          _row('Gross Profit', '$currency ${fmt.format(live.grossProfit)}',
              bold: true,
              valueColor:
                  live.grossProfit >= 0 ? AppColors.success : AppColors.danger),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => _showEditCogsDialog(context, live, currency, ref),
              child: Text(
                'Edit COGS',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
        if (live.outstanding > 0) ...[
          const Divider(height: 16),
          _row('Outstanding', '$currency ${fmt.format(live.outstanding)}',
              valueColor: AppColors.danger, bold: true),
        ],
      ],
    );
  }

  Widget _itemThumbnail(String? imageUrl, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: imageUrl != null && imageUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: imageUrl,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                width: size,
                height: size,
                color: const Color(0xFFF1F5F9),
                child: Icon(Icons.shopping_bag_rounded,
                    size: size * 0.45, color: AppColors.textTertiary),
              ),
              errorWidget: (_, __, ___) => Container(
                width: size,
                height: size,
                color: const Color(0xFFF1F5F9),
                child: Icon(Icons.shopping_bag_rounded,
                    size: size * 0.45, color: AppColors.textTertiary),
              ),
            )
          : Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.shopping_bag_rounded,
                  size: size * 0.45, color: AppColors.textTertiary),
            ),
    );
  }

  Widget _row(String label, String value,
      {bool bold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: AppTypography.bodySmall.copyWith(
              color: bold ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            )),
        Text(value,
            style: AppTypography.bodySmall.copyWith(
              color: valueColor ?? AppColors.textPrimary,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            )),
      ],
    );
  }

  // ── Payment Info ────────────────────────────────────────

  Widget _buildPaymentInfo(BuildContext context, Sale live, WidgetRef ref) {
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (live.paymentStatus) {
      case PaymentStatus.paid:
        statusColor = AppColors.success;
        statusLabel = 'Paid';
        statusIcon = Icons.check_circle_rounded;
        break;
      case PaymentStatus.refunded:
        statusColor = AppColors.danger;
        statusLabel = 'Refunded';
        statusIcon = Icons.money_off_rounded;
        break;
      case PaymentStatus.partial:
        statusColor = AppColors.warning;
        statusLabel = 'Partial';
        statusIcon = Icons.timelapse_rounded;
        break;
      case PaymentStatus.unpaid:
        statusColor = AppColors.danger;
        statusLabel = 'Unpaid';
        statusIcon = Icons.money_off_rounded;
        break;
    }

    final isCancelled = live.orderStatus == OrderStatus.cancelled;

    return _Card(
      title: 'Payment',
      children: [
        Row(
          children: [
            Icon(Icons.payments_rounded,
                size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              live.paymentMethod,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: isCancelled
                  ? null
                  : () => _showPaymentStatusSheet(context, ref, live),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: AppTypography.labelSmall.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!isCancelled) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.edit_rounded,
                          size: 12, color: statusColor),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        if (live.amountPaid > 0 && live.paymentStatus != PaymentStatus.paid) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Amount Paid',
                  style: AppTypography.captionSmall
                      .copyWith(color: AppColors.textSecondary)),
              Text(
                ref.watch(currencyProvider) +
                    ' ' +
                    NumberFormat('#,##0.00', 'en').format(live.amountPaid),
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _showPaymentStatusSheet(
      BuildContext context, WidgetRef ref, Sale live) {
    final statuses = [
      (PaymentStatus.unpaid, 'Unpaid', Icons.money_off_rounded, AppColors.danger),
      (PaymentStatus.partial, 'Partial', Icons.pie_chart_rounded, AppColors.warning),
      (PaymentStatus.paid, 'Paid', Icons.check_circle_rounded, AppColors.success),
      (PaymentStatus.refunded, 'Refunded', Icons.money_off_rounded, AppColors.danger),
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderLight,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Update Payment Status',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                for (final (status, label, icon, color) in statuses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        HapticFeedback.mediumImpact();
                        final updated = live.copyWith(
                          paymentStatus: status,
                          amountPaid: status == PaymentStatus.paid
                              ? live.total
                              : status == PaymentStatus.unpaid
                                  ? 0
                                  : live.amountPaid,
                          updatedAt: DateTime.now(),
                        );
                        ref.read(salesProvider.notifier).updateSale(updated);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: live.paymentStatus == status
                              ? color.withValues(alpha: 0.08)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: live.paymentStatus == status
                                ? color
                                : AppColors.borderLight.withValues(alpha: 0.5),
                            width: live.paymentStatus == status ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(icon, size: 22, color: color),
                            const SizedBox(width: 12),
                            Text(
                              label,
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            if (live.paymentStatus == status)
                              Icon(Icons.check_rounded,
                                  size: 20, color: color),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Tracking Info ───────────────────────────────────────

  Widget _buildTrackingCard(BuildContext context, Sale live) {
    // Build a tracking URL based on common carriers or use raw number
    String? trackingUrl;
    final tracking = live.trackingNumber!;
    final method = (live.shippingMethod ?? '').toLowerCase();

    if (tracking.startsWith('http://') || tracking.startsWith('https://')) {
      trackingUrl = tracking;
    } else if (method.contains('aramex')) {
      trackingUrl =
          'https://www.aramex.com/track/results?ShipmentNumber=$tracking';
    } else if (method.contains('fedex')) {
      trackingUrl =
          'https://www.fedex.com/fedextrack/?trknbr=$tracking';
    } else if (method.contains('dhl')) {
      trackingUrl =
          'https://www.dhl.com/en/express/tracking.html?AWB=$tracking';
    } else if (method.contains('ups')) {
      trackingUrl =
          'https://www.ups.com/track?tracknum=$tracking';
    } else {
      // Generic Google search for tracking
      trackingUrl =
          'https://www.google.com/search?q=track+$tracking';
    }

    return _Card(
      title: 'Tracking',
      children: [
        GestureDetector(
          onTap: () async {
            HapticFeedback.lightImpact();
            final uri = Uri.parse(trackingUrl!);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_shipping_rounded,
                      size: 18, color: Color(0xFF3B82F6)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tracking,
                        style: AppTypography.labelSmall.copyWith(
                          color: const Color(0xFF3B82F6),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (live.shippingMethod != null &&
                          live.shippingMethod!.isNotEmpty)
                        Text(
                          live.shippingMethod!,
                          style: AppTypography.captionSmall
                              .copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.open_in_new_rounded,
                    size: 18, color: Color(0xFF3B82F6)),
              ],
            ),
          ),
        ),
        if (live.deliveryStatus != null &&
            live.deliveryStatus!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                live.deliveryStatus == 'Delivered'
                    ? Icons.check_circle_rounded
                    : live.deliveryStatus == 'Shipped'
                        ? Icons.local_shipping_rounded
                        : Icons.hourglass_empty_rounded,
                size: 16,
                color: live.deliveryStatus == 'Delivered'
                    ? AppColors.success
                    : live.deliveryStatus == 'Shipped'
                        ? const Color(0xFF3B82F6)
                        : AppColors.warning,
              ),
              const SizedBox(width: 6),
              Text(
                live.deliveryStatus!,
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ── Shipping Info ───────────────────────────────────────

  Widget _buildShippingCard(Sale live) {
    return _Card(
      title: 'Shipping',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on_rounded,
                size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                live.shippingAddress!,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        if (live.shippingCost > 0) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Shipping Cost',
                  style: AppTypography.captionSmall
                      .copyWith(color: AppColors.textSecondary)),
              Text(
                'EGP ${NumberFormat('#,##0.00', 'en').format(live.shippingCost)}',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
        if (live.shippingNotes != null && live.shippingNotes!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            live.shippingNotes!,
            style: AppTypography.captionSmall
                .copyWith(color: AppColors.textTertiary),
          ),
        ],
      ],
    );
  }

  // ── Notes ───────────────────────────────────────────────

  Widget _buildNotesCard(Sale live) {
    return _Card(
      title: 'Notes',
      children: [
        Text(
          live.notes!,
          style:
              AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  // ── Bottom Actions Content ───────────────────────────────

  Widget _buildBottomActionsContent(BuildContext context, Sale live,
      WidgetRef ref, String currency, NumberFormat fmt) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Mark as Paid button (only when unpaid / partial) ──
        if (live.paymentStatus != PaymentStatus.paid) ...[
            GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                final updated = live.copyWith(
                  paymentStatus: PaymentStatus.paid,
                  amountPaid: live.total,
                  updatedAt: DateTime.now(),
                );
                ref.read(salesProvider.notifier).updateSale(updated);

                // Sync to Shopify if linked
                if (live.externalSource == 'shopify' &&
                    live.externalOrderId != null) {
                  ref
                      .read(shopifyApiServiceProvider)
                      .markOrderPaid(orderId: live.externalOrderId!)
                      .then((result) {
                    if (!context.mounted) return;
                    if (result.isSuccess) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content:
                            const Text('Payment synced to Shopify'),
                        backgroundColor: AppColors.primaryNavy,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ));
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'Shopify payment sync failed: ${result.error}'),
                        backgroundColor: AppColors.danger,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ));
                    }
                  });
                }

                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Order marked as paid'),
                  backgroundColor: AppColors.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ));
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.success.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Mark as Paid — $currency ${fmt.format(live.outstanding)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          // ── Cancel + Edit row ──
          Row(
            children: [
              // Cancel button
              Expanded(
                flex: 1,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    _confirmCancel(context, ref, live);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      'Cancel',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Edit button
              Expanded(
                flex: 2,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    context
                        .pushNamed('RecordSaleScreen', extra: {'sale': live});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accentOrange.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Edit Order',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
  }
}

// ── Order Status Badge ────────────────────────────────────

class _OrderStatusBadge extends StatelessWidget {
  final OrderStatus status;
  const _OrderStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color color, String label, IconData icon) = switch (status) {
      OrderStatus.pending => (AppColors.warning, 'Pending', Icons.schedule_rounded),
      OrderStatus.confirmed => (const Color(0xFF3B82F6), 'Confirmed', Icons.check_circle_outline_rounded),
      OrderStatus.processing => (const Color(0xFF8B5CF6), 'Processing', Icons.sync_rounded),
      OrderStatus.completed => (AppColors.success, 'Completed', Icons.task_alt_rounded),
      OrderStatus.cancelled => (AppColors.danger, 'Cancelled', Icons.cancel_outlined),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable card ─────────────────────────────────────────

class _Card extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const _Card({this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
          if (title != null) ...[
            Text(
              title!,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    );
  }
}
