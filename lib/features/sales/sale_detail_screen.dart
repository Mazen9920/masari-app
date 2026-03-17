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

    // Calculate bottom padding based on visible action buttons
    final isCancelled = live.orderStatus == OrderStatus.cancelled;
    final showShipOrder = live.externalSource != 'shopify' &&
        live.fulfillmentStatus != FulfillmentStatus.fulfilled &&
        live.paymentStatus != PaymentStatus.refunded;
    final showMarkPaid = live.paymentStatus != PaymentStatus.paid;
    // Bottom sheet: 12 top pad + Cancel/Edit row ~52 + 12 bottom pad + safe area ~34 = ~110 base
    // Each action button adds ~58 (48 button + 10 spacing)
    double bottomPadding = 120.0; // base for Cancel/Edit + container chrome
    if (!isCancelled) {
      if (showShipOrder) bottomPadding += 58;
      if (showMarkPaid) bottomPadding += 58;
    }

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
                  padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
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
                      ).animate().fadeIn(duration: 250.ms, delay: 80.ms),
                    const SizedBox(height: 14),
                    _buildItemsList(live, currency, fmt, ref)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 100.ms),
                    const SizedBox(height: 14),
                    _buildTotalsCard(context, live, currency, fmt, ref)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 140.ms),
                    const SizedBox(height: 14),
                    _buildPaymentInfo(context, live, ref)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 180.ms),
                    if (live.trackingNumber != null &&
                        live.trackingNumber!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildTrackingCard(context, live)
                          .animate()
                          .fadeIn(duration: 250.ms, delay: 220.ms),
                    ],
                    if (live.shippingAddress != null &&
                        live.shippingAddress!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildShippingCard(live)
                          .animate()
                          .fadeIn(duration: 250.ms, delay: 260.ms),
                    ],
                    if (live.notes != null && live.notes!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _buildNotesCard(live)
                          .animate()
                          .fadeIn(duration: 250.ms, delay: 300.ms),
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
    // Shopify-synced orders: show real separate statuses
    if (live.isShopifyOrder) {
      return _buildShopifyOrderStatusCard(context, live);
    }
    // Manual orders: keep existing stepper
    return _buildManualOrderStatusCard(context, live, ref);
  }

  Widget _buildShopifyOrderStatusCard(BuildContext context, Sale live) {
    final isCancelled = live.orderStatus == OrderStatus.cancelled;

    // Payment status row
    final (Color payColor, String payLabel, IconData payIcon) =
        switch (live.paymentStatus) {
      PaymentStatus.paid => (AppColors.success, 'Paid', Icons.check_circle_rounded),
      PaymentStatus.partial => (AppColors.warning, 'Partially Paid', Icons.timelapse_rounded),
      PaymentStatus.refunded => (AppColors.danger, 'Refunded', Icons.replay_rounded),
      PaymentStatus.unpaid => (const Color(0xFFEF4444), 'Unpaid', Icons.money_off_rounded),
    };

    // Fulfillment status row
    final (Color fulfillColor, String fulfillLabel, IconData fulfillIcon) =
        switch (live.fulfillmentStatus) {
      FulfillmentStatus.fulfilled => (AppColors.success, 'Fulfilled', Icons.check_circle_rounded),
      FulfillmentStatus.partial => (AppColors.warning, 'Partially Fulfilled', Icons.timelapse_rounded),
      FulfillmentStatus.unfulfilled => (AppColors.textTertiary, 'Unfulfilled', Icons.inventory_2_outlined),
    };

    // Overall badge
    final (Color badgeColor, String badgeLabel, IconData badgeIcon) = isCancelled
        ? (AppColors.danger, 'Cancelled', Icons.cancel_outlined)
        : live.isCompleted
            ? (AppColors.success, 'Completed', Icons.task_alt_rounded)
            : (AppColors.warning, 'In Progress', Icons.sync_rounded);

    return _Card(
      children: [
        // Header
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(badgeIcon, size: 14, color: badgeColor),
                  const SizedBox(width: 4),
                  Text(
                    badgeLabel,
                    style: AppTypography.labelSmall.copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (isCancelled)
          Container(
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
          )
        else ...[
          // Payment row
          _buildStatusRow(
            icon: payIcon,
            label: 'Payment',
            value: payLabel,
            color: payColor,
          ),
          const SizedBox(height: 12),
          // Fulfillment row
          _buildStatusRow(
            icon: fulfillIcon,
            label: 'Fulfillment',
            value: fulfillLabel,
            color: fulfillColor,
          ),
          const SizedBox(height: 12),
          // Synced badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.sync_rounded,
                    size: 14, color: AppColors.success),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Synced from Shopify — statuses update automatically',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStatusRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTypography.labelMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualOrderStatusCard(
      BuildContext context, Sale live, WidgetRef ref) {
    final isCancelled = live.orderStatus == OrderStatus.cancelled;

    // Payment status
    final (Color payColor, String payLabel, IconData payIcon) =
        switch (live.paymentStatus) {
      PaymentStatus.paid => (AppColors.success, 'Paid', Icons.check_circle_rounded),
      PaymentStatus.partial => (AppColors.warning, 'Partially Paid', Icons.timelapse_rounded),
      PaymentStatus.refunded => (AppColors.danger, 'Refunded', Icons.replay_rounded),
      PaymentStatus.unpaid => (const Color(0xFFEF4444), 'Unpaid', Icons.money_off_rounded),
    };

    // Fulfillment status
    final (Color fulfillColor, String fulfillLabel, IconData fulfillIcon) =
        switch (live.fulfillmentStatus) {
      FulfillmentStatus.fulfilled => (AppColors.success, 'Fulfilled', Icons.check_circle_rounded),
      FulfillmentStatus.partial => (AppColors.warning, 'Partially Fulfilled', Icons.timelapse_rounded),
      FulfillmentStatus.unfulfilled => (AppColors.textTertiary, 'Unfulfilled', Icons.inventory_2_outlined),
    };

    // Overall badge
    final (Color badgeColor, String badgeLabel, IconData badgeIcon) = isCancelled
        ? (AppColors.danger, 'Cancelled', Icons.cancel_outlined)
        : live.isCompleted
            ? (AppColors.success, 'Completed', Icons.task_alt_rounded)
            : (AppColors.warning, 'In Progress', Icons.sync_rounded);

    return _Card(
      children: [
        // Header
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(badgeIcon, size: 14, color: badgeColor),
                  const SizedBox(width: 4),
                  Text(
                    badgeLabel,
                    style: AppTypography.labelSmall.copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (isCancelled)
          Container(
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
          )
        else ...[
          // Payment row — tappable to change
          GestureDetector(
            onTap: () => _showPaymentStatusSheet(context, ref, live),
            child: _buildStatusRow(
              icon: payIcon,
              label: 'Payment',
              value: payLabel,
              color: payColor,
            ),
          ),
          const SizedBox(height: 12),
          // Fulfillment row — tappable to change
          GestureDetector(
            onTap: () => _showFulfillmentStatusSheet(context, ref, live),
            child: _buildStatusRow(
              icon: fulfillIcon,
              label: 'Fulfillment',
              value: fulfillLabel,
              color: fulfillColor,
            ),
          ),
        ],
      ],
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

  void _changeFulfillment(
      BuildContext context, WidgetRef ref, Sale live, FulfillmentStatus newStatus, {
      String? trackingNumber,
      String? shippingMethod,
  }) {
    // Derive the matching orderStatus so the two stay in sync
    OrderStatus derivedOrderStatus = live.orderStatus;
    if (newStatus == FulfillmentStatus.fulfilled &&
        live.paymentStatus == PaymentStatus.paid) {
      derivedOrderStatus = OrderStatus.completed;
    } else if (newStatus != FulfillmentStatus.unfulfilled &&
        live.orderStatus == OrderStatus.confirmed) {
      derivedOrderStatus = OrderStatus.processing;
    }

    final updated = live.copyWith(
      fulfillmentStatus: newStatus,
      orderStatus: derivedOrderStatus,
      trackingNumber: trackingNumber ?? live.trackingNumber,
      shippingMethod: shippingMethod ?? live.shippingMethod,
      deliveryStatus: newStatus == FulfillmentStatus.fulfilled
          ? 'Delivered'
          : newStatus == FulfillmentStatus.partial
              ? 'Shipped'
              : live.deliveryStatus,
      updatedAt: DateTime.now(),
    );
    ref.read(salesProvider.notifier).updateSale(updated);

    if (context.mounted) {
      final label = switch (newStatus) {
        FulfillmentStatus.fulfilled => 'Order shipped & fulfilled',
        FulfillmentStatus.partial => 'Marked as partially shipped',
        FulfillmentStatus.unfulfilled => 'Marked as unfulfilled',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(label),
        backgroundColor: AppColors.primaryNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _showFulfillmentStatusSheet(
      BuildContext context, WidgetRef ref, Sale live) {
    // If not yet fulfilled, go straight to shipping flow
    if (live.fulfillmentStatus != FulfillmentStatus.fulfilled) {
      _showShipOrderSheet(context, ref, live);
      return;
    }
    // Already fulfilled — allow reverting
    final statuses = [
      (FulfillmentStatus.unfulfilled, 'Unfulfilled', Icons.inventory_2_outlined, AppColors.textTertiary),
      (FulfillmentStatus.partial, 'Partially Shipped', Icons.timelapse_rounded, AppColors.warning),
      (FulfillmentStatus.fulfilled, 'Fulfilled', Icons.check_circle_rounded, AppColors.success),
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
                  'Fulfillment Status',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                ...statuses.map((s) {
                  final isActive = live.fulfillmentStatus == s.$1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        if (!isActive) {
                          HapticFeedback.mediumImpact();
                          _changeFulfillment(context, ref, live, s.$1);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isActive
                              ? s.$4.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive
                                ? s.$4.withValues(alpha: 0.3)
                                : AppColors.borderLight.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(s.$3, size: 20, color: s.$4),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                s.$2,
                                style: AppTypography.labelMedium.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: isActive
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (isActive)
                              Icon(Icons.check_rounded,
                                  size: 20, color: s.$4),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showShipOrderSheet(
      BuildContext context, WidgetRef ref, Sale live) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _ShipOrderSheet(
          sale: live,
          onShip: ({
            required FulfillmentStatus status,
            String? trackingNumber,
            String? shippingMethod,
          }) {
            Navigator.pop(ctx);
            HapticFeedback.mediumImpact();
            _changeFulfillment(
              context,
              ref,
              live,
              status,
              trackingNumber: trackingNumber,
              shippingMethod: shippingMethod,
            );
          },
        );
      },
    );
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
                  live.displayOrderTitle,
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if ((live.shopifyOrderNumber != null || live.orderNumber != null) &&
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
        // ── Ship Order button (manual orders only, not fulfilled) ──
        if (live.externalSource != 'shopify' &&
            live.fulfillmentStatus != FulfillmentStatus.fulfilled &&
            live.paymentStatus != PaymentStatus.refunded) ...[
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              _showShipOrderSheet(context, ref, live);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF303030),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_shipping_rounded,
                      color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Ship Order',
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
          const SizedBox(height: 10),
        ],
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

// ── Ship Order Bottom Sheet ───────────────────────────────

class _ShipOrderSheet extends StatefulWidget {
  final Sale sale;
  final void Function({
    required FulfillmentStatus status,
    String? trackingNumber,
    String? shippingMethod,
  }) onShip;

  const _ShipOrderSheet({required this.sale, required this.onShip});

  @override
  State<_ShipOrderSheet> createState() => _ShipOrderSheetState();
}

class _ShipOrderSheetState extends State<_ShipOrderSheet> {
  late final TextEditingController _trackingCtrl;
  late final TextEditingController _carrierCtrl;
  bool _markFulfilled = true; // default: fully fulfilled

  static const _carriers = [
    'DHL',
    'FedEx',
    'UPS',
    'Aramex',
    'Egypt Post',
    'J&T Express',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _trackingCtrl =
        TextEditingController(text: widget.sale.trackingNumber ?? '');
    _carrierCtrl =
        TextEditingController(text: widget.sale.shippingMethod ?? '');
  }

  @override
  void dispose() {
    _trackingCtrl.dispose();
    _carrierCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
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
              const SizedBox(height: 20),

              // Title
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF303030).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.local_shipping_rounded,
                        size: 20, color: Color(0xFF303030)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ship Order',
                          style: AppTypography.h3.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${widget.sale.items.length} ${widget.sale.items.length == 1 ? 'item' : 'items'} to fulfill',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Shipping carrier
              Text(
                'Shipping Carrier',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              // Carrier chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _carriers.map((carrier) {
                  final isSelected =
                      _carrierCtrl.text.toLowerCase() == carrier.toLowerCase();
                  return GestureDetector(
                    onTap: () {
                      setState(() => _carrierCtrl.text = carrier);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color:
                            isSelected ? const Color(0xFF303030) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF303030)
                              : AppColors.borderLight,
                        ),
                      ),
                      child: Text(
                        carrier,
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Tracking number
              Text(
                'Tracking Number',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _trackingCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'e.g. 1Z999AA10123456784',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 14,
                  ),
                  prefixIcon: const Icon(Icons.qr_code_rounded,
                      size: 20, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: const Color(0xFFF8F9FA),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.borderLight),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.borderLight),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: Color(0xFF303030), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Fulfillment toggle
              GestureDetector(
                onTap: () =>
                    setState(() => _markFulfilled = !_markFulfilled),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _markFulfilled
                        ? AppColors.success.withValues(alpha: 0.06)
                        : const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _markFulfilled
                          ? AppColors.success.withValues(alpha: 0.3)
                          : AppColors.borderLight,
                    ),
                  ),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _markFulfilled
                              ? AppColors.success
                              : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _markFulfilled
                                ? AppColors.success
                                : AppColors.borderLight,
                            width: 2,
                          ),
                        ),
                        child: _markFulfilled
                            ? const Icon(Icons.check_rounded,
                                size: 14, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mark as fully fulfilled',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              'All items in this order will be marked as shipped',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Ship button
              GestureDetector(
                onTap: () {
                  widget.onShip(
                    status: _markFulfilled
                        ? FulfillmentStatus.fulfilled
                        : FulfillmentStatus.partial,
                    trackingNumber: _trackingCtrl.text.trim().isEmpty
                        ? null
                        : _trackingCtrl.text.trim(),
                    shippingMethod: _carrierCtrl.text.trim().isEmpty
                        ? null
                        : _carrierCtrl.text.trim(),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF303030),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.local_shipping_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _markFulfilled
                            ? 'Ship & Fulfill Order'
                            : 'Ship Partial Order',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
