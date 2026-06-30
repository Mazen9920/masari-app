import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/production_order_model.dart';
import '../../l10n/app_localizations.dart';
import 'bom_economics.dart';
import 'purchase_order_review_screen.dart';

class ProductionPlannerScreen extends ConsumerStatefulWidget {
  /// Optionally pre-select a finished product.
  final String? initialProductId;
  const ProductionPlannerScreen({super.key, this.initialProductId});

  @override
  ConsumerState<ProductionPlannerScreen> createState() =>
      _ProductionPlannerScreenState();
}

class _ProductionPlannerScreenState
    extends ConsumerState<ProductionPlannerScreen> {
  String? _productId;
  String? _variantId;
  final _qtyController = TextEditingController(text: '100');
  final _notesController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _productId = widget.initialProductId;
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int get _qty => int.tryParse(_qtyController.text) ?? 0;

  Future<void> _start(ProductionPlan plan) async {
    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    final error = await ref.read(productionOrdersProvider.notifier).startProduction(
          productId: plan.productId,
          variantId: plan.variantId,
          quantity: plan.quantity,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    final l10n = AppLocalizations.of(context)!;
    if (error == null) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10n.productionStartedMsg),
            backgroundColor: AppColors.success),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppColors.danger),
      );
    }
  }

  /// Flips the "produced with the order" flag on the BOM component backing
  /// [line] and persists it, so the shortfall stops blocking the run.
  Future<void> _toggleMadeToOrder(ProductionPlanLine line) async {
    final products = ref.read(inventoryProvider).value ?? [];
    final product = products.where((p) => p.id == _productId).firstOrNull;
    if (product?.manufacturingBom == null) return;
    final bom = product!.manufacturingBom!;

    final newComponents = bom.components.map((c) {
      final matches = c.materialProductId == line.materialProductId ||
          (c.materialByColor?.values.contains(line.materialProductId) ?? false);
      return matches ? c.copyWith(madeToOrder: !c.madeToOrder) : c;
    }).toList();

    setState(() => _busy = true);
    HapticFeedback.lightImpact();
    final result = await ref.read(inventoryProvider.notifier).updateProduct(
        product.id, product.copyWith(manufacturingBom: bom.copyWith(components: newComponents)));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result.error ?? 'Error'),
            backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _createPurchaseOrders(ProductionPlan plan) async {
    final shortfalls =
        plan.lines.where((l) => l.shortfallQty > 0 && !l.madeToOrder).toList();
    if (shortfalls.isEmpty) return;
    // Open the review/confirm screen; it creates the POs on confirm.
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PurchaseOrderReviewScreen(
        productName: plan.productName,
        shortfallLines: shortfalls,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0.##');
    final products = ref.watch(filteredInventoryProvider).value ?? [];
    final bomProducts = products
        .where((p) =>
            !p.isMaterial &&
            p.hasBom &&
            !isShopifyBundle(p) &&
            p.shopifyStatus != 'draft')
        .toList();

    final product = products.where((p) => p.id == _productId).firstOrNull;
    // Default variant selection.
    if (product != null &&
        (_variantId == null ||
            product.variantById(_variantId!) == null)) {
      _variantId = product.variants.isNotEmpty ? product.variants.first.id : null;
    }

    final plan = (product != null && _variantId != null && _qty > 0)
        ? ref
            .read(productionOrdersProvider.notifier)
            .planProduction(_productId!, _variantId!, _qty)
        : null;

    // Economics (for "max producible") need the full product list to resolve
    // materials, which filteredInventory may exclude.
    final allProducts = ref.watch(inventoryProvider).value ?? products;
    final selectedVariant =
        product != null && _variantId != null ? product.variantById(_variantId!) : null;
    final econ = (product != null && product.hasBom && selectedVariant != null)
        ? BomEconomics.compute(
            components: product.manufacturingBom!.components,
            laborPerUnit: product.manufacturingBom!.laborCostPerUnit,
            finishedVariant: selectedVariant,
            allProducts: allProducts,
            sellingPrice: selectedVariant.sellingPrice,
            valuationMethod: ref.watch(appSettingsProvider).valuationMethod,
          )
        : null;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          l10n.productionPlanner,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.primaryNavy,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _card(children: [
            DropdownButtonFormField<String>(
              initialValue: _productId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.finishedProduct,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              hint: Text(l10n.selectBomProduct),
              items: bomProducts
                  .map((p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(p.name, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() {
                _productId = v;
                _variantId = null;
              }),
            ),
            if (product != null && product.variants.length > 1) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _variantId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.variantLabel,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: product.variants
                    .map((v) => DropdownMenuItem(
                          value: v.id,
                          child: Text(
                              v.isDefault ? product.name : v.displayName,
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _variantId = v),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _qtyController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.quantityToProduce,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            if (econ != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.inventory_2_rounded,
                      size: 14,
                      color: econ.maxProducible > 0
                          ? AppColors.textTertiary
                          : AppColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      econ.maxProducible > 0
                          ? '${l10n.mfgMaxFromStock}: ${econ.maxProducible} ${l10n.mfgUnits}'
                          : l10n.mfgNoStockForRun,
                      style: AppTypography.captionSmall.copyWith(
                        color: econ.maxProducible > 0
                            ? AppColors.textTertiary
                            : AppColors.danger,
                      ),
                    ),
                  ),
                  if (econ.maxProducible > 0)
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => setState(() => _qtyController.text =
                          econ.maxProducible.toString()),
                      child: Text(l10n.mfgUseMax,
                          style: AppTypography.captionSmall.copyWith(
                              color: AppColors.primaryNavy,
                              fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ],
          ]),
          const SizedBox(height: 16),
          if (plan == null)
            _EmptyHint(message: l10n.selectBomProduct)
          else ...[
            _sectionLabel(l10n.materialRequirements),
            const SizedBox(height: 8),
            ..._buildSupplierGroups(plan, currency, fmt),
            const SizedBox(height: 16),
            _manufacturerCard(plan, currency, fmt),
            const SizedBox(height: 16),
            _costSummary(plan, currency, fmt),
            if (plan.hasShortfall) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.warning, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(l10n.shortfallWarning,
                          style: AppTypography.captionSmall
                              .copyWith(color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _createPurchaseOrders(plan),
                icon: const Icon(Icons.shopping_cart_outlined),
                label: Text(l10n.createPurchaseOrders),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryNavy,
                  minimumSize: const Size.fromHeight(48),
                  side: BorderSide(color: AppColors.borderLight),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.mfgRunNotesOptional,
                filled: true,
                fillColor: Colors.white,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_busy || plan.hasShortfall || plan.hasUnresolved)
                    ? null
                    : () => _start(plan),
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
                    : Text(l10n.startProduction,
                        style: AppTypography.labelMedium
                            .copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildSupplierGroups(
      ProductionPlan plan, String currency, NumberFormat fmt) {
    final groups = plan.linesBySupplier;
    final widgets = <Widget>[];
    groups.forEach((supplier, lines) {
      final subtotal = lines.fold<double>(0, (s, l) => s + l.lineCost);
      widgets.add(_card(children: [
        Row(
          children: [
            const Icon(Icons.store_rounded,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(supplier,
                  style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700)),
            ),
            Text('$currency ${fmt.format(subtotal)}',
                style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const Divider(height: 16),
        ...lines.map((l) {
          final l10n = AppLocalizations.of(context)!;
          final subtitle = l.madeToOrder
              ? '${fmt.format(l.requiredQty)} ${l.unit} · ${l10n.mfgMadeToOrderShort}'
              : '${fmt.format(l.requiredQty)} ${l.unit} · '
                  '${_avail(l)} ${fmt.format(l.availableQty)}'
                  '${l.shortfallQty > 0 ? ' · ${_short()} ${fmt.format(l.shortfallQty)}' : ''}';
          final subtitleColor = l.madeToOrder
              ? AppColors.primaryNavy
              : (l.shortfallQty > 0
                  ? AppColors.danger
                  : AppColors.textTertiary);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.materialName,
                          style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600)),
                      Text(subtitle,
                          style: AppTypography.captionSmall
                              .copyWith(color: subtitleColor)),
                      const SizedBox(height: 4),
                      // Tappable toggle to mark this component made-to-order.
                      InkWell(
                        onTap: _busy ? null : () => _toggleMadeToOrder(l),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: l.madeToOrder
                                ? AppColors.primaryNavy.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: l.madeToOrder
                                    ? AppColors.primaryNavy
                                        .withValues(alpha: 0.3)
                                    : AppColors.borderLight),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                l.madeToOrder
                                    ? Icons.check_circle_rounded
                                    : Icons.add_circle_outline_rounded,
                                size: 12,
                                color: l.madeToOrder
                                    ? AppColors.primaryNavy
                                    : AppColors.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(l10n.mfgMadeToOrderShort,
                                  style: AppTypography.captionSmall.copyWith(
                                      fontSize: 10,
                                      color: l.madeToOrder
                                          ? AppColors.primaryNavy
                                          : AppColors.textTertiary,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Text('$currency ${fmt.format(l.lineCost)}',
                    style: AppTypography.captionSmall
                        .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          );
        }),
      ]));
      widgets.add(const SizedBox(height: 8));
    });
    return widgets;
  }

  String _avail(ProductionPlanLine l) =>
      AppLocalizations.of(context)!.availableQty;
  String _short() => AppLocalizations.of(context)!.shortfallQty;

  /// Highlights the manufacturer (finishing supplier) for this run: who does
  /// the finishing, the made-to-order items they produce, and what they'll be
  /// invoiced for.
  Widget _manufacturerCard(
      ProductionPlan plan, String currency, NumberFormat fmt) {
    final l10n = AppLocalizations.of(context)!;
    final qty = plan.quantity;
    final mtoLines = plan.lines.where((l) => l.madeToOrder).toList();
    final mtoCost = mtoLines.fold<double>(0, (s, l) => s + l.lineCost);
    final labor = plan.laborCost;
    final charge = labor + mtoCost;
    final name = plan.laborSupplierName ??
        (mtoLines.isNotEmpty && mtoLines.first.supplierName.isNotEmpty
            ? mtoLines.first.supplierName
            : null);

    String per(double v) =>
        qty > 0 ? ' · ${fmt.format(v / qty)}/${l10n.mfgPerUnit}' : '';
    String amt(double v) => '$currency ${fmt.format(v)}${per(v)}';

    // Nothing external — made in-house.
    if (charge <= 0 && (name == null || name.isEmpty)) {
      return _card(children: [
        Row(children: [
          const Icon(Icons.home_work_outlined,
              size: 18, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.mfgInHouse,
                style: AppTypography.captionSmall
                    .copyWith(color: AppColors.textTertiary)),
          ),
        ]),
      ]);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accentOrange.withValues(alpha: 0.10),
            AppColors.accentOrange.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.accentOrange.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.precision_manufacturing_rounded,
                  size: 16, color: AppColors.accentOrange),
              const SizedBox(width: 6),
              Text(
                '${l10n.mfgManufacturer.toUpperCase()} · ${l10n.mfgFinishingPhase}',
                style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.accentOrange.withValues(alpha: 0.15),
                child: Text(
                  (name != null && name.isNotEmpty)
                      ? name.characters.first.toUpperCase()
                      : '?',
                  style: AppTypography.labelMedium.copyWith(
                      color: AppColors.accentOrange,
                      fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name ?? '—',
                    style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const Divider(height: 22),
          if (labor > 0) ...[
            _row(l10n.mfgFinishingWord, amt(labor)),
            const SizedBox(height: 6),
          ],
          ...mtoLines.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _row(
                    '${l.materialName} · ${l10n.mfgMadeToOrderShort}',
                    amt(l.lineCost)),
              )),
          const Divider(height: 10),
          const SizedBox(height: 6),
          _row(l10n.mfgManufacturingInvoice, amt(charge), bold: true),
        ],
      ),
    );
  }

  Widget _costSummary(ProductionPlan plan, String currency, NumberFormat fmt) {
    final l10n = AppLocalizations.of(context)!;
    return _card(children: [
      _row(l10n.materialsCostLabel, '$currency ${fmt.format(plan.materialsCost)}'),
      const SizedBox(height: 6),
      _row(l10n.laborCostLabel, '$currency ${fmt.format(plan.laborCost)}'),
      const Divider(height: 16),
      _row(l10n.totalCostLabel, '$currency ${fmt.format(plan.totalCost)}',
          bold: true),
      const SizedBox(height: 6),
      _row(l10n.unitCostLabel, '$currency ${fmt.format(plan.unitCost)}'),
    ]);
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

class _EmptyHint extends StatelessWidget {
  final String message;
  const _EmptyHint({required this.message});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.tune_rounded,
              size: 56,
              color: AppColors.textTertiary.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(message,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}
