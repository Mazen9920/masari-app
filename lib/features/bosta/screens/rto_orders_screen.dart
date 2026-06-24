import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../shared/utils/safe_pop.dart';

/// Shows RTO/returned Bosta shipments that may need action (refund/re-ship).
class RtoOrdersScreen extends ConsumerStatefulWidget {
  const RtoOrdersScreen({super.key});

  @override
  ConsumerState<RtoOrdersScreen> createState() => _RtoOrdersScreenState();
}

class _RtoOrdersScreenState extends ConsumerState<RtoOrdersScreen> {
  bool _loading = true;
  List<_RtoOrder> _orders = [];
  int _needsActionCount = 0;
  int _alreadyHandledCount = 0;
  int _reshipCount = 0;
  String _filter = 'all'; // all, needs_action, handled

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadData);
  }

  Future<void> _loadData() async {
    final uid = ref.read(authProvider).user?.id;
    if (uid == null) return;

    final shipSnap = await FirebaseFirestore.instance
        .collection('bosta_shipments')
        .where('user_id', isEqualTo: uid)
        .where('matched', isEqualTo: true)
        .get();

    final rtoShipments = <QueryDocumentSnapshot>[];
    for (final doc in shipSnap.docs) {
      final state = (doc.data()['state'] as num?)?.toInt() ?? 0;
      if (state == 60 || state == 46) rtoShipments.add(doc);
    }

    final orders = <_RtoOrder>[];
    int needsAction = 0;
    int handled = 0;
    int reshipCount = 0;

    for (final shipDoc in rtoShipments) {
      final sd = shipDoc.data() as Map<String, dynamic>;
      final saleId = sd['sale_id'] as String?;
      final tracking = sd['tracking_number']?.toString() ?? '';
      final cod = (sd['cod'] as num?)?.toDouble() ?? 0;
      final bostaState = (sd['state'] as num?)?.toInt() ?? 0;
      final bostaCreatedAt = sd['bosta_created_at'];

      DateTime? shipDate;
      if (bostaCreatedAt is Timestamp) {
        shipDate = bostaCreatedAt.toDate();
      }

      String customerName = 'Unknown';
      String orderNumber = '';
      double amountPaid = 0;
      double shippingCost = 0;
      int orderStatus = -1;
      int paymentStatus = 0;
      String saleTracking = '';

      if (saleId != null) {
        final saleDoc = await FirebaseFirestore.instance
            .collection('sales')
            .doc(saleId)
            .get();
        if (saleDoc.exists) {
          final s = saleDoc.data()!;
          customerName = (s['customer_name'] as String?) ?? 'Unknown';
          orderNumber = (s['shopify_order_number']?.toString()) ?? '';
          amountPaid = (s['amount_paid'] as num?)?.toDouble() ?? 0;
          shippingCost = (s['shipping_cost'] as num?)?.toDouble() ?? 0;
          orderStatus = (s['order_status'] as num?)?.toInt() ?? -1;
          paymentStatus = (s['payment_status'] as num?)?.toInt() ?? 0;
          saleTracking = (s['tracking_number']?.toString()) ?? '';
        }
      }

      // If the sale has a DIFFERENT tracking number, this shipment was
      // re-shipped and delivered — not a real RTO anymore.
      final isReshipped = saleTracking.isNotEmpty &&
          tracking.isNotEmpty &&
          saleTracking != tracking;

      if (isReshipped) {
        reshipCount++;
        continue; // Skip — order was re-shipped and delivered
      }

      // Determine action needed.
      _ActionNeeded action;
      if (orderStatus == 4) {
        // Already cancelled.
        action = _ActionNeeded.none;
        handled++;
      } else if (paymentStatus == 2 && amountPaid > 0) {
        // Prepaid but not cancelled → needs refund.
        action = _ActionNeeded.refund;
        needsAction++;
      } else if (cod > 0 && orderStatus != 4) {
        // COD with amount but not cancelled.
        action = _ActionNeeded.cancel;
        needsAction++;
      } else {
        // COD with 0 amount, not cancelled → just cancel in system.
        action = _ActionNeeded.cancel;
        needsAction++;
      }

      orders.add(_RtoOrder(
        saleId: saleId ?? '',
        orderNumber: orderNumber,
        customerName: customerName,
        amountPaid: amountPaid,
        shippingCost: shippingCost,
        cod: cod,
        tracking: tracking,
        bostaState: bostaState == 60 ? 'RTO' : 'Returned',
        orderStatus: orderStatus,
        paymentStatus: paymentStatus,
        action: action,
        shipDate: shipDate,
      ));
    }

    // Sort: needs-action first, then by order number descending.
    orders.sort((a, b) {
      if (a.action != _ActionNeeded.none && b.action == _ActionNeeded.none) {
        return -1;
      }
      if (a.action == _ActionNeeded.none && b.action != _ActionNeeded.none) {
        return 1;
      }
      return b.orderNumber.compareTo(a.orderNumber);
    });

    if (mounted) {
      setState(() {
        _orders = orders;
        _needsActionCount = needsAction;
        _alreadyHandledCount = handled;
        _reshipCount = reshipCount;
        _loading = false;
      });
    }
  }

  List<_RtoOrder> get _filteredOrders {
    switch (_filter) {
      case 'needs_action':
        return _orders.where((o) => o.action != _ActionNeeded.none).toList();
      case 'handled':
        return _orders.where((o) => o.action == _ActionNeeded.none).toList();
      default:
        return _orders;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            if (!_loading) _buildSummary(),
            if (!_loading) _buildFilterChips(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredOrders.isEmpty
                      ? _buildEmpty()
                      : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => context.safePop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RTO / Returned Orders',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (!_loading)
                  Text(
                    '${_orders.length} shipments',
                    style: AppTypography.caption,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final fmt = NumberFormat('#,##0.00', 'en');
    final refundTotal = _orders
        .where((o) => o.action == _ActionNeeded.refund)
        .fold(0.0, (s, o) => s + o.amountPaid);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _summaryChip(
            Icons.error_outline_rounded,
            '$_needsActionCount need action',
            AppColors.chartRed,
          ),
          _summaryChip(
            Icons.check_circle_outline_rounded,
            '$_alreadyHandledCount handled',
            const Color(0xFF10B981),
          ),
          if (_reshipCount > 0)
            _summaryChip(
              Icons.local_shipping_outlined,
              '$_reshipCount re-shipped',
              AppColors.primaryNavy,
            ),
          if (refundTotal > 0)
            _summaryChip(
              Icons.payments_outlined,
              'EGP ${fmt.format(refundTotal)}',
              AppColors.accentOrange,
            ),
        ],
      ),
    );
  }

  Widget _summaryChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          _chip('All', 'all'),
          const SizedBox(width: 8),
          _chip('Needs Action', 'needs_action'),
          const SizedBox(width: 8),
          _chip('Handled', 'handled'),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryNavy : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primaryNavy : AppColors.borderLight,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 48, color: AppColors.textTertiary.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text('No orders in this filter',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }

  Widget _buildList() {
    final orders = _filteredOrders;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _buildOrderCard(orders[i]),
    );
  }

  Widget _buildOrderCard(_RtoOrder order) {
    final fmt = NumberFormat('#,##0.00', 'en');
    final fmtDate = DateFormat('d MMM yyyy');

    final Color actionColor;
    final String actionLabel;
    final IconData actionIcon;

    switch (order.action) {
      case _ActionNeeded.refund:
        actionColor = AppColors.chartRed;
        actionLabel = 'Refund EGP ${fmt.format(order.amountPaid)}';
        actionIcon = Icons.payments_outlined;
      case _ActionNeeded.cancel:
        actionColor = AppColors.accentOrange;
        actionLabel = 'Cancel in Shopify';
        actionIcon = Icons.cancel_outlined;
      case _ActionNeeded.none:
        actionColor = const Color(0xFF10B981);
        actionLabel = 'Already cancelled';
        actionIcon = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: order number + action badge
          Row(
            children: [
              if (order.orderNumber.isNotEmpty)
                Text(
                  '#${order.orderNumber}',
                  style: AppTypography.labelLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: actionColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(actionIcon, size: 13, color: actionColor),
                    const SizedBox(width: 4),
                    Text(
                      actionLabel,
                      style: AppTypography.labelSmall.copyWith(
                        color: actionColor,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Customer name
          Text(
            order.customerName,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          // Detail grid
          Row(
            children: [
              Expanded(
                child: _detailItem('Bosta Status', order.bostaState,
                    AppColors.accentOrange),
              ),
              Expanded(
                child: _detailItem('Tracking', order.tracking, null),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _detailItem(
                  'Amount Paid',
                  order.amountPaid > 0
                      ? 'EGP ${fmt.format(order.amountPaid)}'
                      : 'EGP 0 (COD)',
                  order.amountPaid > 0 ? AppColors.chartRed : null,
                ),
              ),
              Expanded(
                child: _detailItem(
                  'Shipping',
                  'EGP ${fmt.format(order.shippingCost)}',
                  null,
                ),
              ),
            ],
          ),
          if (order.shipDate != null) ...[
            const SizedBox(height: 6),
            _detailItem('Ship Date', fmtDate.format(order.shipDate!), null),
          ],
          // Order status row
          const Divider(height: 20),
          Row(
            children: [
              Icon(Icons.storefront_rounded,
                  size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(
                'Order: ${_orderStatusLabel(order.orderStatus)}',
                style: AppTypography.caption,
              ),
              const SizedBox(width: 16),
              Icon(Icons.payment_rounded,
                  size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(
                'Payment: ${_paymentStatusLabel(order.paymentStatus)}',
                style: AppTypography.caption,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailItem(String label, String value, Color? valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.captionSmall.copyWith(
          color: AppColors.textTertiary,
          letterSpacing: 0.3,
        )),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  String _orderStatusLabel(int status) {
    switch (status) {
      case 0: return 'Pending';
      case 1: return 'Confirmed';
      case 2: return 'Processing';
      case 3: return 'Completed';
      case 4: return 'Cancelled';
      default: return 'Unknown';
    }
  }

  String _paymentStatusLabel(int status) {
    switch (status) {
      case 0: return 'Unpaid';
      case 1: return 'Partial';
      case 2: return 'Paid';
      default: return 'Unknown';
    }
  }
}

enum _ActionNeeded { refund, cancel, none }

class _RtoOrder {
  final String saleId;
  final String orderNumber;
  final String customerName;
  final double amountPaid;
  final double shippingCost;
  final double cod;
  final String tracking;
  final String bostaState;
  final int orderStatus;
  final int paymentStatus;
  final _ActionNeeded action;
  final DateTime? shipDate;

  const _RtoOrder({
    required this.saleId,
    required this.orderNumber,
    required this.customerName,
    required this.amountPaid,
    required this.shippingCost,
    required this.cod,
    required this.tracking,
    required this.bostaState,
    required this.orderStatus,
    required this.paymentStatus,
    required this.action,
    this.shipDate,
  });
}
