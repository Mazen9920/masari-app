import '../../shared/models/product_model.dart';
import '../../shared/utils/money_utils.dart';

/// Per-component resolution detail (used to render rows with live stock/cost).
class BomLineEconomics {
  final BomComponent component;
  final Product? material;
  final ProductVariant? materialVariant;
  final double perUnitRequired; // incl. scrap
  final double unitCost; // material variant cost
  final double lineCostPerUnit; // perUnitRequired * unitCost
  final double availableStock;
  final bool resolved;

  const BomLineEconomics({
    required this.component,
    required this.material,
    required this.materialVariant,
    required this.perUnitRequired,
    required this.unitCost,
    required this.lineCostPerUnit,
    required this.availableStock,
    required this.resolved,
  });

  /// Whole units producible from this single component's stock.
  int get maxFromThisLine =>
      perUnitRequired <= 0 ? 1 << 30 : (availableStock / perUnitRequired).floor();
}

/// Derived economics for one finished variant's BOM. Mirrors the planner math
/// (`planProduction`) but works directly off components so it can run live in
/// the editor on unsaved drafts.
class BomEconomics {
  final List<BomLineEconomics> lines;
  final double materialsPerUnit;
  final double laborPerUnit;
  final double unitCost; // materials + labor
  final double sellingPrice;
  final double margin; // sellingPrice - unitCost
  final double marginPct; // margin / sellingPrice * 100
  final int maxProducible;
  final bool resolvable; // every component resolves to a known material variant

  const BomEconomics({
    required this.lines,
    required this.materialsPerUnit,
    required this.laborPerUnit,
    required this.unitCost,
    required this.sellingPrice,
    required this.margin,
    required this.marginPct,
    required this.maxProducible,
    required this.resolvable,
  });

  bool get hasSellingPrice => sellingPrice > 0;
  bool get belowCost => hasSellingPrice && margin < 0;
  bool get isEmpty => lines.isEmpty;

  /// Computes economics for [components] producing one [finishedVariant].
  ///
  /// [allProducts] supplies materials by id; [sellingPrice] is the finished
  /// variant's price (0 when unset).
  factory BomEconomics.compute({
    required List<BomComponent> components,
    required double laborPerUnit,
    required ProductVariant finishedVariant,
    required List<Product> allProducts,
    required double sellingPrice,
    String valuationMethod = 'fifo',
  }) {
    final productsById = {for (final p in allProducts) p.id: p};
    final lines = <BomLineEconomics>[];
    double materials = 0;
    var resolvable = true;
    int maxProducible = 1 << 30;
    var sawConstraint = false;

    for (final c in components) {
      // Resolve effective material product+variant (honours per-colour map).
      final resolved =
          Product.resolveComponentMaterial(c, finishedVariant, productsById);
      final material = productsById[resolved.productId];
      if (material == null) {
        resolvable = false;
        lines.add(BomLineEconomics(
          component: c,
          material: null,
          materialVariant: null,
          perUnitRequired: c.quantityPerUnit,
          unitCost: 0,
          lineCostPerUnit: 0,
          availableStock: 0,
          resolved: false,
        ));
        continue;
      }
      final matVar = resolved.variantId != null
          ? material.variantById(resolved.variantId!)
          : null;
      if (matVar == null) resolvable = false;

      var perUnit = c.quantityPerUnit;
      final scrap = material.scrapPercentage ?? 0;
      if (c.applyScrap && scrap > 0) perUnit = perUnit * (1 + scrap / 100);
      perUnit = roundMoney(perUnit);

      // FIFO-accurate per-unit material cost (next layer consumed), not WAC.
      final unitCost =
          matVar?.cogsPerUnit(perUnit.ceil(), valuationMethod) ?? 0;
      final lineCost = roundMoney(perUnit * unitCost);
      materials += lineCost;

      final stock = matVar?.currentStock ?? 0;
      if (perUnit > 0) {
        sawConstraint = true;
        final canMake = (stock / perUnit).floor();
        if (canMake < maxProducible) maxProducible = canMake;
      }

      lines.add(BomLineEconomics(
        component: c,
        material: material,
        materialVariant: matVar,
        perUnitRequired: perUnit,
        unitCost: unitCost,
        lineCostPerUnit: lineCost,
        availableStock: stock,
        resolved: matVar != null,
      ));
    }

    materials = roundMoney(materials);
    final unitCost = roundMoney(materials + laborPerUnit);
    final margin = roundMoney(sellingPrice - unitCost);
    final marginPct =
        sellingPrice > 0 ? roundMoney(margin / sellingPrice * 100) : 0.0;

    return BomEconomics(
      lines: lines,
      materialsPerUnit: materials,
      laborPerUnit: roundMoney(laborPerUnit),
      unitCost: unitCost,
      sellingPrice: sellingPrice,
      margin: margin,
      marginPct: marginPct,
      maxProducible:
          !sawConstraint ? 0 : (maxProducible < 0 ? 0 : maxProducible),
      resolvable: resolvable,
    );
  }

  /// Convenience for a saved product: builds economics for its primary variant.
  static BomEconomics? forProduct(Product product, List<Product> allProducts,
      {String valuationMethod = 'fifo'}) {
    if (!product.hasBom || product.variants.isEmpty) return null;
    final v = product.variants.first;
    return BomEconomics.compute(
      components: product.manufacturingBom!.components,
      laborPerUnit: product.manufacturingBom!.laborCostPerUnit,
      finishedVariant: v,
      allProducts: allProducts,
      sellingPrice: v.sellingPrice,
      valuationMethod: valuationMethod,
    );
  }
}
