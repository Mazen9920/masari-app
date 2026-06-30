import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../shared/models/production_order_model.dart';
import '../../shared/models/purchase_model.dart';
import '../../shared/models/supplier_model.dart';
import '../../shared/utils/money_utils.dart';
import '../../l10n/app_localizations.dart';

/// One editable purchase-order line.
class _PoLine {
  final String materialName;
  final String? productId;
  final String? variantId;
  final String unit;
  final TextEditingController qty;
  final TextEditingController price;

  _PoLine({
    required this.materialName,
    required this.productId,
    required this.variantId,
    required this.unit,
    required double qtyValue,
    required double priceValue,
  })  : qty = TextEditingController(text: qtyValue.ceil().toString()),
        price = TextEditingController(text: _money(priceValue));

  double get qtyVal => double.tryParse(qty.text) ?? 0;
  double get priceVal => double.tryParse(price.text) ?? 0;
  double get total => roundMoney(qtyVal * priceVal);

  void dispose() {
    qty.dispose();
    price.dispose();
  }

  static String _money(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

/// One editable purchase order (per supplier).
class _PoDraft {
  final String supplierName;
  String? supplierId;
  bool include = true;
  DateTime date;
  final TextEditingController reference;
  final List<_PoLine> lines;

  _PoDraft({
    required this.supplierName,
    required this.supplierId,
    required this.date,
    required String refText,
    required this.lines,
  }) : reference = TextEditingController(text: refText);

  double get subtotal =>
      roundMoney(lines.fold<double>(0, (s, l) => s + l.total));

  void dispose() {
    reference.dispose();
    for (final l in lines) {
      l.dispose();
    }
  }
}

/// Review / edit / confirm the purchase orders generated from a production
/// plan's shortfalls. One card per supplier; each is independently editable
/// and can be excluded before creating.
class PurchaseOrderReviewScreen extends ConsumerStatefulWidget {
  final String productName;
  final List<ProductionPlanLine> shortfallLines;
  const PurchaseOrderReviewScreen({
    super.key,
    required this.productName,
    required this.shortfallLines,
  });

  @override
  ConsumerState<PurchaseOrderReviewScreen> createState() =>
      _PurchaseOrderReviewScreenState();
}

class _PurchaseOrderReviewScreenState
    extends ConsumerState<PurchaseOrderReviewScreen> {
  final List<_PoDraft> _drafts = [];
  bool _busy = false;
  bool _initialized = false;

  void _init(List<Supplier> suppliers) {
    if (_initialized) return;
    _initialized = true;
    final now = DateTime.now();
    final stamp = DateFormat('yyMMdd').format(now);
    final bySupplier = <String, List<ProductionPlanLine>>{};
    for (final l in widget.shortfallLines) {
      if (l.shortfallQty <= 0) continue;
      bySupplier.putIfAbsent(l.supplierName, () => []).add(l);
    }
    var n = 1;
    bySupplier.forEach((supName, lines) {
      final sup = suppliers
          .where((s) => s.name.toLowerCase() == supName.toLowerCase())
          .firstOrNull;
      _drafts.add(_PoDraft(
        supplierName: supName.isEmpty ? '—' : supName,
        supplierId: sup?.id,
        date: now,
        refText: 'PROD-$stamp-${n++}',
        lines: lines
            .map((l) => _PoLine(
                  materialName: l.materialName,
                  productId: l.materialProductId,
                  variantId: l.materialVariantId,
                  unit: l.unit,
                  qtyValue: l.shortfallQty,
                  priceValue: l.unitCost,
                ))
            .toList(),
      ));
    });
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  List<_PoDraft> get _included =>
      _drafts.where((d) => d.include && d.lines.any((l) => l.qtyVal > 0)).toList();

  double get _grandTotal =>
      roundMoney(_included.fold<double>(0, (s, d) => s + d.subtotal));

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context)!;
    final included = _included;
    if (included.isEmpty) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final uid = ref.read(authProvider).user?.id ?? '';

    for (final d in included) {
      final items = d.lines
          .where((l) => l.qtyVal > 0)
          .map((l) => PurchaseItem(
                name: l.materialName,
                category: 'Raw Material',
                qty: l.qtyVal.ceil(),
                unitPrice: l.priceVal,
                productId: l.productId,
                variantId: l.variantId,
              ))
          .toList();
      if (items.isEmpty) continue;
      ref.read(purchasesProvider.notifier).addPurchase(Purchase(
            id: const Uuid().v4(),
            userId: uid,
            supplierId: d.supplierId ?? '',
            supplierName: d.supplierName,
            date: d.date,
            referenceNo: d.reference.text.trim(),
            items: items,
            createdAt: DateTime.now(),
          ));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop(included.length);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${included.length} ${l10n.mfgPoCreatedN}'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0.##');
    final suppliers = ref.watch(suppliersProvider).value ?? [];
    _init(suppliers);

    final includedCount = _included.length;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Column(
          children: [
            Text(l10n.mfgReviewPOs,
                style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w700,
                    fontSize: 16)),
            Text(l10n.mfgReviewPOsSub,
                style: AppTypography.captionSmall
                    .copyWith(color: AppColors.textTertiary, fontSize: 10)),
          ],
        ),
        centerTitle: true,
      ),
      body: _drafts.isEmpty
          ? Center(
              child: Text(l10n.mfgPoNoneSelected,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textTertiary)),
            )
          : ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: _drafts.length,
              itemBuilder: (_, i) => _poCard(_drafts[i], currency, fmt, l10n),
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
                top: BorderSide(
                    color: AppColors.borderLight.withValues(alpha: 0.6))),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$includedCount ${l10n.mfgPoOrdersWord}',
                      style: AppTypography.captionSmall
                          .copyWith(color: AppColors.textTertiary)),
                  Text('$currency ${fmt.format(_grandTotal)}',
                      style: AppTypography.h3.copyWith(
                          color: AppColors.primaryNavy,
                          fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: (_busy || includedCount == 0) ? null : _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.borderLight,
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
                            includedCount == 0
                                ? l10n.mfgPoNoneSelected
                                : '${l10n.mfgPoConfirm} ($includedCount)',
                            style: AppTypography.labelMedium
                                .copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poCard(
      _PoDraft d, String currency, NumberFormat fmt, AppLocalizations l10n) {
    final dim = !d.include;
    return Opacity(
      opacity: dim ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: d.include
                  ? AppColors.primaryNavy.withValues(alpha: 0.18)
                  : AppColors.borderLight.withValues(alpha: 0.6)),
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppColors.primaryNavy.withValues(alpha: 0.1),
                    child: Text(
                      d.supplierName.isNotEmpty
                          ? d.supplierName.characters.first.toUpperCase()
                          : '?',
                      style: AppTypography.labelMedium.copyWith(
                          color: AppColors.primaryNavy,
                          fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.supplierName,
                            style: AppTypography.labelMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text('${d.lines.length} ${l10n.mfgPoItemsWord}',
                            style: AppTypography.captionSmall
                                .copyWith(color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                  Switch(
                    value: d.include,
                    activeThumbColor: AppColors.primaryNavy,
                    onChanged: (v) => setState(() => d.include = v),
                  ),
                ],
              ),
            ),
            if (d.supplierId == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 13, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(l10n.mfgPoUnassigned,
                          style: AppTypography.captionSmall
                              .copyWith(color: AppColors.warning)),
                    ),
                  ],
                ),
              ),
            // Reference + date
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: d.reference,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: l10n.mfgPoReference,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: d.date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setState(() => d.date = picked);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: l10n.mfgPoOrderDate,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(DateFormat.yMMMd().format(d.date),
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.textPrimary)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Lines
            ...d.lines.asMap().entries.map((e) =>
                _lineRow(d, e.value, e.key, currency, fmt, l10n)),
            // Subtotal
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
              child: Row(
                children: [
                  Text(l10n.mfgPoGrandTotal.toUpperCase(),
                      style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6)),
                  const Spacer(),
                  Text('$currency ${fmt.format(d.subtotal)}',
                      style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineRow(_PoDraft d, _PoLine l, int index, String currency,
      NumberFormat fmt, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l.materialName,
                    style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600)),
              ),
              Text('$currency ${fmt.format(l.total)}',
                  style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700)),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded,
                    size: 16, color: AppColors.textTertiary),
                onPressed: () => setState(() {
                  d.lines.removeAt(index).dispose();
                }),
              ),
            ],
          ),
          Row(
            children: [
              SizedBox(
                width: 92,
                child: TextField(
                  controller: l.qty,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: '${l10n.mfgPoLineQty} (${l.unit})',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('×', style: TextStyle(color: AppColors.textTertiary)),
              ),
              Expanded(
                child: TextField(
                  controller: l.price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l10n.mfgPoUnitPrice,
                    prefixText: '$currency ',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Divider(height: 1, color: AppColors.borderLight.withValues(alpha: 0.4)),
        ],
      ),
    );
  }
}
