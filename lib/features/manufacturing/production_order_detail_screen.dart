import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/production_order_model.dart';
import '../../shared/models/goods_receipt_model.dart';
import '../../shared/utils/money_utils.dart';
import '../../l10n/app_localizations.dart';
import 'manufacturing_widgets.dart';
import '../suppliers/purchase_detail_screen.dart';
import '../suppliers/receipt_detail_screen.dart';

class ProductionOrderDetailScreen extends ConsumerStatefulWidget {
  final String orderId;
  const ProductionOrderDetailScreen({super.key, required this.orderId});

  @override
  ConsumerState<ProductionOrderDetailScreen> createState() =>
      _ProductionOrderDetailScreenState();
}

class _ProductionOrderDetailScreenState
    extends ConsumerState<ProductionOrderDetailScreen> {
  bool _busy = false;
  bool _payNow = true;

  Future<void> _complete(ProductionOrder order) async {
    final l10n = AppLocalizations.of(context)!;
    final remaining = order.remainingQty;
    var batchQty = remaining;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final valid = batchQty > 0 && batchQty <= remaining;
          return AlertDialog(
            title: Text(l10n.mfgReceiveUnits),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.completeProductionConfirm),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: '$remaining',
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (v) =>
                      setLocal(() => batchQty = int.tryParse(v) ?? 0),
                  decoration: InputDecoration(
                    labelText: l10n.mfgUnitsToReceive,
                    helperText: '$remaining ${l10n.mfgRemaining}',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (order.laborCost > 0 && order.laborSupplierId != null) ...[
                  const SizedBox(height: 8),
                  RadioGroup<bool>(
                    groupValue: _payNow,
                    onChanged: (v) => setLocal(() => _payNow = v ?? true),
                    child: Column(
                      children: [
                        RadioListTile<bool>(
                          contentPadding: EdgeInsets.zero,
                          value: true,
                          title: Text(l10n.payFinishingNow,
                              style: AppTypography.bodySmall),
                        ),
                        RadioListTile<bool>(
                          contentPadding: EdgeInsets.zero,
                          value: false,
                          title: Text(l10n.addFinishingToPayable,
                              style: AppTypography.bodySmall),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.cancel)),
              ElevatedButton(
                  onPressed:
                      valid ? () => Navigator.of(ctx).pop(true) : null,
                  child: Text(l10n.mfgReceiveBatch)),
            ],
          );
        },
      ),
    );
    if (confirmed != true || batchQty <= 0) return;

    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    final error = await ref
        .read(productionOrdersProvider.notifier)
        .completeProduction(order.id, payNow: _payNow, qty: batchQty);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.productionCompletedMsg),
          backgroundColor: AppColors.success));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _cancel(ProductionOrder order) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cancelRun),
        content: Text(l10n.cancelProductionConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.cancelRun),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final error = await ref
        .read(productionOrdersProvider.notifier)
        .cancelProduction(order.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.productionCancelledMsg),
          backgroundColor: AppColors.textSecondary));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _delete(ProductionOrder order) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.mfgDeleteOrderConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await ref
        .read(productionOrdersProvider.notifier)
        .deleteOrder(order.id);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.mfgOrderDeletedMsg),
          backgroundColor: AppColors.textSecondary));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _edit(ProductionOrder order) async {
    final l10n = AppLocalizations.of(context)!;
    final suppliers = ref.read(suppliersProvider).value ?? [];
    var notes = order.notes ?? '';
    String? supplierId = order.laborSupplierId;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setLocal) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.mfgEditOrder,
                      style: AppTypography.h3.copyWith(
                          color: AppColors.primaryNavy,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: notes,
                    minLines: 1,
                    maxLines: 3,
                    onChanged: (v) => notes = v,
                    decoration: InputDecoration(
                      labelText: l10n.mfgNotesLabel,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: supplierId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.bomFinishingSupplier,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    items: suppliers
                        .map((s) => DropdownMenuItem<String?>(
                              value: s.id,
                              child: Text(s.name,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setLocal(() => supplierId = v),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryNavy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(l10n.save,
                          style: AppTypography.labelMedium
                              .copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final error = await ref.read(productionOrdersProvider.notifier).editOrder(
          order.id,
          notes: notes.trim(),
          laborSupplierId: supplierId,
        );
    if (!mounted) return;
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.mfgOrderUpdatedMsg),
          backgroundColor: AppColors.success));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.danger));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0.##');
    final orders = ref.watch(productionOrdersProvider).value ?? [];
    final order = orders.where((o) => o.id == widget.orderId).firstOrNull;
    final products = ref.watch(inventoryProvider).value ?? [];

    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.productionOrderTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final (statusLabel, statusColor) = switch (order.status) {
      ProductionStatus.inProgress => (l10n.statusInProgress, AppColors.warning),
      ProductionStatus.completed => (l10n.statusCompleted, AppColors.success),
      ProductionStatus.cancelled =>
        (l10n.statusCancelled, AppColors.textTertiary),
    };

    // Margin-at-sale: finished variant's selling price vs the order's
    // capitalized unit cost.
    final finishedProduct =
        products.where((p) => p.id == order.productId).firstOrNull;
    final finishedVariant = finishedProduct?.variantById(order.variantId);
    final sellingPrice = finishedVariant?.sellingPrice ?? 0;
    final marginPerUnit = roundMoney(sellingPrice - order.unitCost);
    final marginPct =
        sellingPrice > 0 ? roundMoney(marginPerUnit / sellingPrice * 100) : 0.0;

    // Batch receipt events for the progress timeline.
    final timelineReceipts = ref
        .watch(goodsReceiptsProvider)
        .where((r) => r.id.startsWith('prodrcpt_${order.id}'))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          l10n.productionOrderTitle,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.primaryNavy,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.textSecondary),
            onSelected: (v) {
              if (v == 'edit') _edit(order);
              if (v == 'delete') _delete(order);
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  const Icon(Icons.edit_outlined,
                      size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Text(l10n.edit),
                ]),
              ),
              if (order.isCancelled)
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    const Icon(Icons.delete_outline_rounded,
                        size: 18, color: AppColors.danger),
                    const SizedBox(width: 10),
                    Text(l10n.delete,
                        style: const TextStyle(color: AppColors.danger)),
                  ]),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _card(children: [
            Row(
              children: [
                Expanded(
                  child: Text('${order.quantity} × ${order.variantName}',
                      style: AppTypography.h3.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800)),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(statusLabel,
                      style: AppTypography.captionSmall.copyWith(
                          color: statusColor, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(order.productName,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(
              '${DateFormat.yMMMd().add_jm().format(order.startedAt)}'
              '${order.completedAt != null ? ' → ${DateFormat.yMMMd().format(order.completedAt!)}' : ''}',
              style: AppTypography.captionSmall
                  .copyWith(color: AppColors.textTertiary),
            ),
            if (order.completedQty > 0 && order.isInProgress) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '${order.completedQty} / ${order.quantity} ${l10n.mfgReceived}',
                    style: AppTypography.captionSmall.copyWith(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text('${order.remainingQty} ${l10n.mfgRemaining}',
                      style: AppTypography.captionSmall
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: order.quantity > 0
                      ? order.completedQty / order.quantity
                      : 0,
                  minHeight: 6,
                  backgroundColor:
                      AppColors.borderLight.withValues(alpha: 0.5),
                  valueColor: const AlwaysStoppedAnimation(
                      AppColors.primaryNavy),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 16),
          _sectionLabel(l10n.materialsConsumed),
          const SizedBox(height: 8),
          _card(children: [
            ...order.inputs.map((i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(i.materialName,
                            style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textPrimary)),
                      ),
                      Text(
                          '${fmt.format(i.quantity)} · $currency ${fmt.format(i.totalCost)}',
                          style: AppTypography.captionSmall
                              .copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                )),
            if (order.inputs.isEmpty)
              Text('—',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textTertiary)),
          ]),
          const SizedBox(height: 16),
          _card(children: [
            CostCompositionBar(
              materials: order.materialsCost,
              labor: order.manufacturingCharge,
              showLegend: true,
            ),
            const SizedBox(height: 14),
            _row(l10n.materialsCostLabel,
                '$currency ${fmt.format(order.materialsCost)}'),
            if (order.madeToOrderCost > 0) ...[
              const SizedBox(height: 6),
              _row(l10n.mfgMadeToOrderShort,
                  '$currency ${fmt.format(order.madeToOrderCost)}'),
            ],
            const SizedBox(height: 6),
            _row(l10n.laborCostLabel,
                '$currency ${fmt.format(order.laborCost)}'),
            if (order.madeToOrderCost > 0) ...[
              const SizedBox(height: 6),
              _row(l10n.mfgManufacturingInvoice,
                  '$currency ${fmt.format(order.manufacturingCharge)}',
                  bold: true),
            ],
            const Divider(height: 16),
            _row(l10n.totalCostLabel,
                '$currency ${fmt.format(order.totalCost)}',
                bold: true),
            const SizedBox(height: 6),
            _row(l10n.unitCostLabel,
                '$currency ${fmt.format(order.unitCost)}'),
          ]),
          const SizedBox(height: 16),
          _sectionLabel(l10n.mfgCostBuildUp),
          const SizedBox(height: 8),
          _card(children: [
            _CostWaterfall(
              materials: order.materialsCost,
              madeToOrder: order.madeToOrderCost,
              labor: order.laborCost,
              total: order.totalCost,
              currency: currency,
              fmt: fmt,
            ),
          ]),
          const SizedBox(height: 16),
          _sectionLabel(l10n.mfgTimeline),
          const SizedBox(height: 8),
          _card(children: [
            _ProgressTimeline(
              order: order,
              receipts: timelineReceipts,
              currency: currency,
              fmt: fmt,
            ),
          ]),
          if (sellingPrice > 0) ...[
            const SizedBox(height: 16),
            _sectionLabel(l10n.mfgMarginAtSale),
            const SizedBox(height: 8),
            _card(children: [
              _row(l10n.mfgSellingPrice,
                  '$currency ${fmt.format(sellingPrice)}'),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.mfgMargin,
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textSecondary)),
                  ),
                  Text(
                    '$currency ${fmt.format(marginPerUnit)} · '
                    '${marginPct.toStringAsFixed(0)}%',
                    style: AppTypography.labelMedium.copyWith(
                      color: marginPerUnit < 0
                          ? AppColors.danger
                          : marginPct >= 40
                              ? AppColors.success
                              : AppColors.warning,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ]),
          ],
          if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionLabel(l10n.mfgNotesLabel),
            const SizedBox(height: 8),
            _card(children: [
              Text(order.notes!,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textPrimary)),
            ]),
          ],
          ..._linkedRecords(order, currency, fmt, l10n),
          const SizedBox(height: 24),
          if (order.isInProgress) ...[
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _busy ? null : () => _complete(order),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        '${l10n.mfgReceiveUnits} (${order.remainingQty} ${l10n.mfgRemaining})',
                        style: AppTypography.labelMedium
                            .copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
            // Cancel is only possible before any units have been received.
            if (order.completedQty == 0) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _cancel(order),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(l10n.cancelRun,
                      style: AppTypography.labelMedium
                          .copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Bills + goods receipts created by this production order, linked back so
  /// you can jump into the suppliers section.
  List<Widget> _linkedRecords(ProductionOrder order, String currency,
      NumberFormat fmt, AppLocalizations l10n) {
    final bills = (ref.watch(purchasesProvider).value ?? const [])
        .where((p) =>
            p.id.startsWith('prodbill_${order.id}') ||
            p.referenceNo == order.id)
        .toList();
    final receipts = ref
        .watch(goodsReceiptsProvider)
        .where((r) => r.id.startsWith('prodrcpt_${order.id}'))
        .toList();
    if (bills.isEmpty && receipts.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      _sectionLabel(l10n.mfgLinkedRecords),
      const SizedBox(height: 8),
      _card(children: [
        ...receipts.map((r) => _linkTile(
              icon: Icons.inventory_2_rounded,
              title: l10n.mfgGoodsReceipt,
              subtitle:
                  '${fmt.format(r.totalReceived)} ${l10n.mfgUnitsShort} · ${DateFormat.yMMMd().format(r.date)}',
              trailing: '$currency ${fmt.format(r.totalCost)}',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ReceiptDetailScreen(receipt: r))),
            )),
        ...bills.map((p) => _linkTile(
              icon: Icons.receipt_long_rounded,
              title: '${l10n.mfgSupplierBill} · ${p.supplierName}',
              subtitle:
                  '${p.localizedStatusLabel(l10n)} · ${DateFormat.yMMMd().format(p.date)}',
              trailing: '$currency ${fmt.format(p.total)}',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PurchaseDetailScreen(purchase: p))),
            )),
      ]),
    ];
  }

  Widget _linkTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required String trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(subtitle,
                      style: AppTypography.captionSmall
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(trailing,
                style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700)),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppTypography.bodySmall.copyWith(
                    color: bold
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          ),
          Text(value,
              style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      );

  Widget _sectionLabel(String text) => Text(
        text.toUpperCase(),
        style: AppTypography.captionSmall.copyWith(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          fontSize: 10,
        ),
      );

  Widget _card({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );
}

/// One column of the cost waterfall.
class _WfCol {
  final String label;
  final Color color;
  final double base;
  final double value;
  final bool isTotal;
  const _WfCol({
    required this.label,
    required this.color,
    required this.base,
    required this.value,
    this.isTotal = false,
  });
  double get top => base + value;
}

/// Cost waterfall: how the run cost builds up — materials, (+made-to-order),
/// +finishing — to the total. Build-up bars float on the cumulative cost below
/// them and are linked by dashed connectors; the total is a full summary bar.
/// Value labels sit in a reserved zone above each bar so they never overlap.
class _CostWaterfall extends StatelessWidget {
  final double materials;
  final double madeToOrder;
  final double labor;
  final double total;
  final String currency;
  final NumberFormat fmt;
  const _CostWaterfall({
    required this.materials,
    required this.madeToOrder,
    required this.labor,
    required this.total,
    required this.currency,
    required this.fmt,
  });

  // Geometry.
  static const double _h = 156; // chart area height
  static const double _labelZone = 26; // reserved space at top for value labels
  static const double _barAreaH = _h - _labelZone;
  static const double _pad = 9; // horizontal padding inside each column

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final safeTotal = total <= 0 ? 1.0 : total;

    // Build-up segments stack to the total; then a separate total summary bar.
    var cum = 0.0;
    final cols = <_WfCol>[];
    void addSeg(String label, Color color, double value) {
      cols.add(_WfCol(label: label, color: color, base: cum, value: value));
      cum += value;
    }

    addSeg(l10n.mfgMaterialsWord, AppColors.primaryNavy, materials);
    if (madeToOrder > 0) {
      addSeg(l10n.mfgMadeToOrderShort,
          AppColors.accentOrange.withValues(alpha: 0.6), madeToOrder);
    }
    addSeg(l10n.mfgFinishingWord, AppColors.accentOrange, labor);
    cols.add(_WfCol(
        label: l10n.totalCostLabel,
        color: AppColors.success,
        base: 0,
        value: total,
        isTotal: true));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _h,
          child: Stack(
            children: [
              // Baseline + dashed step connectors behind the bars.
              Positioned.fill(
                child: CustomPaint(
                  painter: _WaterfallPainter(
                    cols: cols,
                    total: safeTotal,
                    barAreaH: _barAreaH,
                    pad: _pad,
                  ),
                ),
              ),
              Row(
                children: [
                  for (final c in cols)
                    Expanded(
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: _pad),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // Bar.
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: (c.base / safeTotal) * _barAreaH,
                              height: ((c.value / safeTotal) * _barAreaH)
                                  .clamp(4.0, _barAreaH),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: c.color,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: c.color.withValues(alpha: 0.22),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Value label in the reserved zone above the bar.
                            Positioned(
                              left: -2,
                              right: -2,
                              bottom:
                                  (c.top / safeTotal) * _barAreaH + 5,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  fmt.format(roundMoney(c.value)),
                                  style: AppTypography.captionSmall.copyWith(
                                    color: c.isTotal
                                        ? AppColors.success
                                        : AppColors.textPrimary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final c in cols)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    c.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.captionSmall.copyWith(
                      color: c.isTotal
                          ? AppColors.textSecondary
                          : AppColors.textTertiary,
                      fontWeight:
                          c.isTotal ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 10.5,
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

/// Draws the baseline and the dashed step connectors that link each build-up
/// bar's top to the start of the next bar (and to the total summary bar).
class _WaterfallPainter extends CustomPainter {
  final List<_WfCol> cols;
  final double total;
  final double barAreaH;
  final double pad;
  const _WaterfallPainter({
    required this.cols,
    required this.total,
    required this.barAreaH,
    required this.pad,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = cols.length;
    if (n == 0) return;
    final colW = size.width / n;

    double yFor(double v) => size.height - (v / total) * barAreaH;

    // Baseline.
    final basePaint = Paint()
      ..color = AppColors.borderLight.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 0.5),
        Offset(size.width, size.height - 0.5), basePaint);

    // Dashed step connectors between consecutive build-up bars, and from the
    // last build-up bar to the total summary bar — at their shared level.
    final linePaint = Paint()
      ..color = AppColors.textTertiary.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final buildup = cols.where((c) => !c.isTotal).toList();
    for (int i = 0; i < buildup.length; i++) {
      final y = yFor(buildup[i].top);
      final rightX = (i + 1) * colW - pad;
      final nextLeftX = (i + 1) * colW + pad;
      _dashedLine(canvas, Offset(rightX, y), Offset(nextLeftX, y), linePaint);
    }
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 4.0, gap = 3.0;
    final len = (b - a).distance;
    if (len <= 0) return;
    final dir = (b - a) / len;
    var d = 0.0;
    while (d < len) {
      final endD = (d + dash) > len ? len : (d + dash);
      canvas.drawLine(a + dir * d, a + dir * endD, paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _WaterfallPainter old) =>
      old.cols != cols || old.total != total || old.barAreaH != barAreaH;
}

/// Vertical lifecycle timeline: Started → each received batch → Completed /
/// Pending / Cancelled. Done nodes are filled; the open node is hollow.
class _ProgressTimeline extends StatelessWidget {
  final ProductionOrder order;
  final List<GoodsReceipt> receipts;
  final String currency;
  final NumberFormat fmt;
  const _ProgressTimeline({
    required this.order,
    required this.receipts,
    required this.currency,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final df = DateFormat.yMMMd();

    final events = <({
      IconData icon,
      Color color,
      String title,
      String subtitle,
      bool done,
    })>[];

    // 1. Started.
    events.add((
      icon: Icons.play_arrow_rounded,
      color: AppColors.primaryNavy,
      title: l10n.mfgStarted,
      subtitle:
          '${df.format(order.startedAt)} · ${l10n.materialsConsumed} $currency ${fmt.format(order.materialsCost)}',
      done: true,
    ));

    // 2. Received batches (from linked goods receipts, else a synthetic node).
    if (receipts.isNotEmpty) {
      for (final r in receipts) {
        events.add((
          icon: Icons.inventory_2_rounded,
          color: AppColors.success,
          title:
              '${l10n.mfgGoodsReceipt} · ${fmt.format(r.totalReceived)} ${l10n.mfgUnitsShort}',
          subtitle:
              '${df.format(r.date)} · $currency ${fmt.format(r.totalCost)}',
          done: true,
        ));
      }
    } else if (order.completedQty > 0) {
      events.add((
        icon: Icons.inventory_2_rounded,
        color: AppColors.success,
        title:
            '${fmt.format(order.completedQty)} / ${fmt.format(order.quantity)} ${l10n.mfgReceived}',
        subtitle: order.completedAt != null
            ? df.format(order.completedAt!)
            : '',
        done: true,
      ));
    }

    // 3. Terminal node.
    if (order.isCompleted) {
      events.add((
        icon: Icons.check_circle_rounded,
        color: AppColors.success,
        title: l10n.statusCompleted,
        subtitle: order.completedAt != null ? df.format(order.completedAt!) : '',
        done: true,
      ));
    } else if (order.isCancelled) {
      events.add((
        icon: Icons.cancel_rounded,
        color: AppColors.textTertiary,
        title: l10n.statusCancelled,
        subtitle: '',
        done: true,
      ));
    } else {
      events.add((
        icon: Icons.schedule_rounded,
        color: AppColors.warning,
        title:
            '${fmt.format(order.remainingQty)} ${l10n.mfgRemaining} · ${l10n.mfgPending}',
        subtitle: '',
        done: false,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < events.length; i++)
          _timelineRow(events[i], isLast: i == events.length - 1),
      ],
    );
  }

  Widget _timelineRow(
    ({IconData icon, Color color, String title, String subtitle, bool done})
        e, {
    required bool isLast,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dot + connecting line.
          Column(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: e.done
                      ? e.color.withValues(alpha: 0.14)
                      : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: e.done
                          ? e.color
                          : AppColors.borderLight,
                      width: e.done ? 0 : 1.5),
                ),
                child: Icon(e.icon, size: 15, color: e.color),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: AppColors.borderLight.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16, top: 3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.title,
                      style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600)),
                  if (e.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(e.subtitle,
                        style: AppTypography.captionSmall
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
