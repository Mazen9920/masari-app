import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/product_model.dart';
import '../../shared/models/supplier_model.dart';
import '../../l10n/app_localizations.dart';
import 'bom_economics.dart';
import 'manufacturing_widgets.dart';

/// Mutable draft for one BOM component row while editing.
class _ComponentDraft {
  String? materialProductId;
  String? materialVariantId;
  bool colorLinked;
  final TextEditingController qty;
  final TextEditingController unit;
  bool applyScrap;
  /// Preserved per-colour material map (Black/Red separate products). Edited
  /// outside this screen; carried through so saving the BOM never drops it.
  Map<String, String>? materialByColor;
  /// Produced with the order (made-to-order) — cost counts but not stocked.
  bool madeToOrder;

  _ComponentDraft({
    this.materialProductId,
    this.materialVariantId,
    this.colorLinked = false,
    String qtyText = '1',
    String unitText = 'pcs',
    this.applyScrap = false,
    this.materialByColor,
    this.madeToOrder = false,
  })  : qty = TextEditingController(text: qtyText),
        unit = TextEditingController(text: unitText);

  void dispose() {
    qty.dispose();
    unit.dispose();
  }
}

class EditBomScreen extends ConsumerStatefulWidget {
  final String productId;
  const EditBomScreen({super.key, required this.productId});

  @override
  ConsumerState<EditBomScreen> createState() => _EditBomScreenState();
}

class _EditBomScreenState extends ConsumerState<EditBomScreen> {
  final List<_ComponentDraft> _drafts = [];
  final _laborController = TextEditingController(text: '0');
  String? _laborSupplierId;
  bool _initialized = false;
  bool _saving = false;
  /// Currently-previewed colour (drives the summary + per-component resolution).
  String? _previewColor;

  /// Known colour vocabulary used to detect a product's colour option values.
  static const _colorVocab = {
    'black', 'red', 'pink', 'blue', 'green', 'white', 'grey', 'gray',
    'yellow', 'orange', 'purple', 'navy', 'brown', 'gold', 'silver',
    'beige', 'maroon', 'teal', 'cyan', 'magenta',
  };

  /// Distinct colour option values present across a product's variants
  /// (first-seen order, original casing).
  List<String> _colorsOf(Product p) {
    final seen = <String, String>{};
    for (final v in p.variants) {
      for (final val in v.optionValues.values) {
        final lo = val.toLowerCase();
        if (_colorVocab.contains(lo) && !seen.containsKey(lo)) seen[lo] = val;
      }
    }
    return seen.values.toList();
  }

  /// The finished variant used to preview [color] (first match, else first).
  ProductVariant _variantForColor(Product p, String? color) {
    if (color != null) {
      for (final v in p.variants) {
        if (v.optionValues.values
            .any((x) => x.toLowerCase() == color.toLowerCase())) {
          return v;
        }
      }
    }
    return p.variants.isNotEmpty
        ? p.variants.first
        : const ProductVariant(
            id: '_', optionValues: {}, sku: '',
            costPrice: 0, sellingPrice: 0, currentStock: 0);
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    _laborController.dispose();
    super.dispose();
  }

  void _initFrom(Product product) {
    if (_initialized) return;
    _initialized = true;
    final bom = product.manufacturingBom;
    if (bom != null) {
      for (final c in bom.components) {
        _drafts.add(_ComponentDraft(
          materialProductId: c.materialProductId,
          materialVariantId: c.materialVariantId,
          colorLinked: c.colorLinked,
          qtyText: _trimNum(c.quantityPerUnit),
          unitText: c.unit,
          applyScrap: c.applyScrap,
          materialByColor: c.materialByColor,
          madeToOrder: c.madeToOrder,
        ));
      }
      _laborController.text = _trimNum(bom.laborCostPerUnit);
      _laborSupplierId = bom.laborSupplierId;
    }
  }

  static String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  double get _laborPerUnit => double.tryParse(_laborController.text) ?? 0;

  /// Build the (possibly partial) component list from current drafts.
  List<BomComponent> _draftComponents() {
    final out = <BomComponent>[];
    for (final d in _drafts) {
      final map = d.materialByColor;
      final hasMap = map != null && map.isNotEmpty;
      // Fallback product id: explicit single material, or first mapped colour.
      final fallbackId = d.materialProductId ?? (hasMap ? map.values.first : null);
      if (fallbackId == null) continue;
      final qty = double.tryParse(d.qty.text) ?? 0;
      if (qty <= 0) continue;
      out.add(BomComponent(
        materialProductId: fallbackId,
        materialVariantId: (d.colorLinked || hasMap) ? null : d.materialVariantId,
        colorLinked: d.colorLinked,
        quantityPerUnit: qty,
        unit: d.unit.text.trim().isEmpty ? 'pcs' : d.unit.text.trim(),
        applyScrap: d.applyScrap,
        materialByColor: hasMap ? map : null,
        madeToOrder: d.madeToOrder,
      ));
    }
    return out;
  }

  Future<void> _save(Product product, List<Supplier> suppliers) async {
    final components = _draftComponents();

    Supplier? laborSup;
    for (final s in suppliers) {
      if (s.id == _laborSupplierId) {
        laborSup = s;
        break;
      }
    }

    final bom = ManufacturingBom(
      components: components,
      laborCostPerUnit: _laborPerUnit,
      laborSupplierId: _laborSupplierId,
      laborSupplierName: laborSup?.name,
    );

    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    final updated = product.copyWith(manufacturingBom: bom);
    final result = await ref
        .read(inventoryProvider.notifier)
        .updateProduct(product.id, updated);
    if (!mounted) return;
    setState(() => _saving = false);

    final l10n = AppLocalizations.of(context)!;
    if (result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.bomSaved), backgroundColor: AppColors.success),
      );
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Error'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.mfgClearAll),
        content: Text(l10n.mfgClearAllConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.mfgClearAll),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    HapticFeedback.mediumImpact();
    setState(() {
      for (final d in _drafts) {
        d.dispose();
      }
      _drafts.clear();
    });
  }

  Future<void> _pickMaterial(_ComponentDraft draft, List<Product> materials) async {
    final picked = await _showMaterialPicker(materials);
    if (picked != null) {
      setState(() {
        // Changing the material invalidates any preserved per-colour map.
        if (draft.materialProductId != picked.id) draft.materialByColor = null;
        draft.materialProductId = picked.id;
        draft.materialVariantId =
            picked.variants.isNotEmpty ? picked.variants.first.id : null;
        if (draft.unit.text.isEmpty || draft.unit.text == 'pcs') {
          draft.unit.text = picked.unitOfMeasure;
        }
      });
    }
  }

  /// Picks the material for one specific finished colour → stores it in the
  /// component's per-colour map.
  Future<void> _pickMaterialForColor(
      _ComponentDraft draft, String color, List<Product> materials) async {
    final picked = await _showMaterialPicker(materials);
    if (picked != null) {
      setState(() {
        final map = Map<String, String>.from(draft.materialByColor ?? {});
        map[color.toLowerCase()] = picked.id;
        draft.materialByColor = map;
        draft.materialProductId ??= picked.id;
        if (draft.unit.text.isEmpty || draft.unit.text == 'pcs') {
          draft.unit.text = picked.unitOfMeasure;
        }
      });
    }
  }

  Future<Product?> _showMaterialPicker(List<Product> materials) async {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.read(currencyProvider);
    final fmt = NumberFormat('#,##0.##');
    return showModalBottomSheet<Product>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        if (materials.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Text(l10n.bomNoMaterials,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textTertiary)),
          );
        }
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final q = query.trim().toLowerCase();
            final shown = q.isEmpty
                ? materials
                : materials
                    .where((m) => m.name.toLowerCase().contains(q))
                    .toList();
            return SafeArea(
              child: Padding(
                // Lift content above the keyboard.
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.75),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: [
                            const Icon(Icons.inventory_2_rounded,
                                size: 18, color: AppColors.textSecondary),
                            const SizedBox(width: 8),
                            Text(l10n.bomAddMaterial,
                                style: AppTypography.labelMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: TextField(
                          autofocus: true,
                          onChanged: (v) => setSheet(() => query = v),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l10n.mfgSearchMaterials,
                            prefixIcon:
                                const Icon(Icons.search_rounded, size: 20),
                            filled: true,
                            fillColor: AppColors.backgroundLight,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: AppColors.borderLight
                                      .withValues(alpha: 0.6)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: AppColors.borderLight
                                      .withValues(alpha: 0.6)),
                            ),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Flexible(
                        child: shown.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(l10n.mfgNoResults,
                                    textAlign: TextAlign.center,
                                    style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textTertiary)),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                itemCount: shown.length,
                                itemBuilder: (context, i) {
                                  final m = shown[i];
                                  final stock = m.variants.fold<double>(
                                      0.0, (s, v) => s + v.currentStock);
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor:
                                          m.color.withValues(alpha: 0.12),
                                      child: Icon(m.icon,
                                          color: m.color, size: 18),
                                    ),
                                    title: Text(m.name),
                                    subtitle: Text(
                                      '$stock ${m.unitOfMeasure} ${l10n.mfgInStock} · '
                                      '$currency ${fmt.format(m.costPrice)}',
                                      style: AppTypography.captionSmall.copyWith(
                                          color: AppColors.textTertiary),
                                    ),
                                    onTap: () => Navigator.of(ctx).pop(m),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0.##');
    final products = ref.watch(inventoryProvider).value ?? [];
    final product = products.where((p) => p.id == widget.productId).firstOrNull;
    final materials = products.where((p) => p.isMaterial).toList();
    final suppliers = ref.watch(suppliersProvider).value ?? [];

    if (product == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.billOfMaterials)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    _initFrom(product);

    // Colour selector drives which finished variant we preview; per-colour
    // material components resolve against it (Red → Red fabric, etc.).
    final colors = _colorsOf(product);
    if (_previewColor == null && colors.isNotEmpty) _previewColor = colors.first;
    final previewVariant = _variantForColor(product, _previewColor);
    final econ = BomEconomics.compute(
      components: _draftComponents(),
      laborPerUnit: _laborPerUnit,
      finishedVariant: previewVariant,
      allProducts: products,
      sellingPrice: previewVariant.sellingPrice,
      valuationMethod: ref.watch(appSettingsProvider).valuationMethod,
    );

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          l10n.editBillOfMaterials,
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: product.color.withValues(alpha: 0.12),
                child: Icon(product.icon, color: product.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  product.name,
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (colors.length >= 2) ...[
            Row(
              children: [
                _sectionLabel(l10n.mfgColorLabel),
                const Spacer(),
                Text('${l10n.mfgPreviewingColor}: ${_previewColor ?? ''}',
                    style: AppTypography.captionSmall
                        .copyWith(color: AppColors.textTertiary)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: colors.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => MfgChip(
                  label: colors[i],
                  selected:
                      _previewColor?.toLowerCase() == colors[i].toLowerCase(),
                  onTap: () => setState(() => _previewColor = colors[i]),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _summaryCard(econ, currency, fmt, l10n),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _sectionLabel(l10n.bomMaterials),
                    if (_drafts.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primaryNavy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${_drafts.length}',
                            style: AppTypography.captionSmall.copyWith(
                                color: AppColors.primaryNavy,
                                fontWeight: FontWeight.w700,
                                fontSize: 10)),
                      ),
                    ],
                  ],
                ),
              ),
              if (_drafts.isNotEmpty)
                TextButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                  label: Text(l10n.mfgClearAll),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: AppTypography.captionSmall
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (econ.isEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.primaryNavy.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(l10n.mfgBomEmptyHint,
                  style: AppTypography.captionSmall
                      .copyWith(color: AppColors.textSecondary)),
            ),
          ..._drafts.asMap().entries.map((e) => _componentCard(
                e.value,
                products,
                materials,
                currency,
                fmt,
                index: e.key,
                previewVariant: previewVariant,
                colors: colors,
              )),
          const SizedBox(height: 4),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _drafts.add(_ComponentDraft())),
            child: DottedBorderBox(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline_rounded,
                      size: 18, color: AppColors.primaryNavy),
                  const SizedBox(width: 8),
                  Text(l10n.bomAddMaterial,
                      style: AppTypography.labelMedium.copyWith(
                          color: AppColors.primaryNavy,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _sectionLabel(l10n.bomLaborCost),
          const SizedBox(height: 8),
          _card(children: [
            TextField(
              controller: _laborController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.bomLaborCost,
                prefixText: '$currency ',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _laborSupplierId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: '${l10n.bomFinishingSupplier} (${l10n.bomOptional})',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l10n.bomOptional),
                ),
                ...suppliers.map((s) => DropdownMenuItem<String?>(
                      value: s.id,
                      child: Text(s.name, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) => setState(() => _laborSupplierId = v),
            ),
          ]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : () => _save(product, suppliers),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(l10n.save,
                      style: AppTypography.labelMedium
                          .copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ),
    );
  }

  // ── Live cost & margin summary ──────────────────────────────────────────
  Widget _summaryCard(BomEconomics econ, String currency, NumberFormat fmt,
      AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryNavy.withValues(alpha: 0.06),
            AppColors.primaryNavy.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryNavy.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.mfgCostAndMargin.toUpperCase(),
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    fontSize: 10,
                  )),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (econ.maxProducible == 0
                          ? AppColors.danger
                          : AppColors.primaryNavy)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${l10n.mfgMaxFromStock}: ${econ.maxProducible} ${l10n.mfgUnits}',
                  style: AppTypography.captionSmall.copyWith(
                    color: econ.maxProducible == 0
                        ? AppColors.danger
                        : AppColors.primaryNavy,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.mfgUnitCostShort,
                        style: AppTypography.captionSmall
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 2),
                    Text('$currency ${fmt.format(econ.unitCost)}',
                        style: AppTypography.h2.copyWith(
                            color: AppColors.primaryNavy,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.mfgMargin,
                        style: AppTypography.captionSmall
                            .copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    MarginMeter(
                      marginPct: econ.marginPct,
                      belowCost: econ.belowCost,
                      hasSellingPrice: econ.hasSellingPrice,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          CostCompositionBar(
            materials: econ.materialsPerUnit,
            labor: econ.laborPerUnit,
            showLegend: true,
          ),
          const SizedBox(height: 14),
          _miniRow(l10n.mfgMaterialsPerUnit,
              '$currency ${fmt.format(econ.materialsPerUnit)}'),
          const SizedBox(height: 6),
          _miniRow(l10n.mfgLaborPerUnit,
              '$currency ${fmt.format(econ.laborPerUnit)}'),
          const SizedBox(height: 6),
          _miniRow(
              l10n.mfgSellingPrice,
              econ.hasSellingPrice
                  ? '$currency ${fmt.format(econ.sellingPrice)}'
                  : '—'),
        ],
      ),
    );
  }

  Widget _miniRow(String label, String value, {Color? valueColor}) => Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary)),
          ),
          Text(value,
              style: AppTypography.labelMedium.copyWith(
                  color: valueColor ?? AppColors.textPrimary,
                  fontWeight: FontWeight.w700)),
        ],
      );

  Widget _componentCard(
    _ComponentDraft draft,
    List<Product> products,
    List<Product> materials,
    String currency,
    NumberFormat fmt, {
    required int index,
    required ProductVariant previewVariant,
    required List<String> colors,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final productsById = {for (final p in products) p.id: p};
    final perColor =
        draft.materialByColor != null && draft.materialByColor!.isNotEmpty;
    final canVaryByColor = colors.length >= 2;

    // Effective material resolved for the currently-previewed colour.
    Product? effMaterial;
    if (perColor) {
      final tmp = BomComponent(
        materialProductId:
            draft.materialProductId ?? draft.materialByColor!.values.first,
        quantityPerUnit: 1,
        materialByColor: draft.materialByColor,
      );
      final r =
          Product.resolveComponentMaterial(tmp, previewVariant, productsById);
      effMaterial = productsById[r.productId];
    } else {
      effMaterial = productsById[draft.materialProductId];
    }

    final qty = double.tryParse(draft.qty.text) ?? 0;
    final matVar = effMaterial == null
        ? null
        : (effMaterial.variantById(draft.materialVariantId ?? '') ??
            (effMaterial.variants.isNotEmpty
                ? effMaterial.variants.first
                : null));
    final scrap = effMaterial?.scrapPercentage ?? 0;
    final effQty =
        draft.applyScrap && scrap > 0 ? qty * (1 + scrap / 100) : qty;
    final lineCost = (matVar?.costPrice ?? 0) * effQty;
    final stock = matVar?.currentStock ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Material selector(s) ──
          if (!perColor)
            Row(
              children: [
                Expanded(
                  child: _materialBox(
                    effMaterial,
                    () => _pickMaterial(draft, materials),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger),
                  onPressed: () =>
                      setState(() => _drafts.removeAt(index).dispose()),
                ),
              ],
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text(l10n.mfgPerColorHint,
                      style: AppTypography.captionSmall
                          .copyWith(color: AppColors.textSecondary)),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppColors.danger),
                  onPressed: () =>
                      setState(() => _drafts.removeAt(index).dispose()),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...colors.map((color) {
              final pid = draft.materialByColor?[color.toLowerCase()];
              final mat = pid != null ? productsById[pid] : null;
              final isPreview =
                  _previewColor?.toLowerCase() == color.toLowerCase();
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 58,
                      child: Text(color,
                          style: AppTypography.captionSmall.copyWith(
                              color: isPreview
                                  ? AppColors.primaryNavy
                                  : AppColors.textSecondary,
                              fontWeight: isPreview
                                  ? FontWeight.w800
                                  : FontWeight.w600)),
                    ),
                    Expanded(
                      child: _materialBox(
                        mat,
                        () => _pickMaterialForColor(draft, color, materials),
                        dense: true,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: draft.qty,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l10n.bomQtyPerUnit,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: draft.unit,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: l10n.bomUnit,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
          if (effMaterial != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.inventory_rounded,
                    size: 13,
                    color:
                        stock > 0 ? AppColors.textTertiary : AppColors.danger),
                const SizedBox(width: 4),
                Text(
                  '$stock ${effMaterial.unitOfMeasure} ${l10n.mfgInStock}'
                  '${perColor ? ' · ${_previewColor ?? ''}' : ''}',
                  style: AppTypography.captionSmall.copyWith(
                      color: stock > 0
                          ? AppColors.textTertiary
                          : AppColors.danger),
                ),
                const Spacer(),
                Text(
                  '${l10n.mfgLineCost}: $currency ${fmt.format(lineCost)}',
                  style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
          if (canVaryByColor)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: perColor,
              onChanged: (on) => setState(() {
                if (on) {
                  final map = <String, String>{};
                  if (draft.materialProductId != null &&
                      _previewColor != null) {
                    map[_previewColor!.toLowerCase()] = draft.materialProductId!;
                  }
                  draft.materialByColor = map;
                } else {
                  final map = draft.materialByColor;
                  if (map != null && map.isNotEmpty) {
                    draft.materialProductId =
                        map[_previewColor?.toLowerCase()] ?? map.values.first;
                  }
                  draft.materialByColor = null;
                }
              }),
              title: Text(l10n.mfgVariesByColor,
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.textPrimary)),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: draft.applyScrap,
            onChanged: (v) => setState(() => draft.applyScrap = v),
            title: Text(
                scrap > 0
                    ? '${l10n.bomApplyScrap} (+${_trimNum(scrap)}%)'
                    : l10n.bomApplyScrap,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textPrimary)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: draft.madeToOrder,
            onChanged: (v) => setState(() => draft.madeToOrder = v),
            title: Text(l10n.mfgMadeToOrder,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textPrimary)),
            subtitle: Text(l10n.mfgMadeToOrderHint,
                style: AppTypography.captionSmall
                    .copyWith(color: AppColors.textTertiary)),
          ),
        ],
      ),
    );
  }

  /// Tappable box showing a chosen material (or a "select" placeholder).
  Widget _materialBox(Product? material, VoidCallback onTap,
      {bool dense = false}) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 9 : 12),
        decoration: BoxDecoration(
          color: AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Icon(material?.icon ?? Icons.inventory_2_rounded,
                size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                material?.name ?? l10n.mfgSelectMaterial,
                style: AppTypography.labelMedium.copyWith(
                  color: material != null
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.expand_more_rounded,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

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
