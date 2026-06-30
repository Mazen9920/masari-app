import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/features/manufacturing/bom_economics.dart';
import 'package:revvo_app/shared/models/product_model.dart';

ProductVariant _variant(String id, Map<String, String> opts,
    {double stock = 0, double cost = 0, double sell = 0}) {
  return ProductVariant(
    id: id,
    optionValues: opts,
    sku: id,
    costPrice: cost,
    sellingPrice: sell,
    currentStock: stock,
  );
}

Product _material({
  required String id,
  required List<ProductVariant> variants,
  double? scrap,
}) {
  return Product(
    id: id,
    userId: 'u',
    name: id,
    category: 'Raw Material',
    supplier: 'Sup',
    isMaterial: true,
    scrapPercentage: scrap,
    variants: variants,
  );
}

ProductVariant _layeredVariant(String id,
    {required List<CostLayer> layers, required double costPrice}) {
  final stock = layers.fold<double>(0.0, (s, l) => s + l.remainingQty);
  return ProductVariant(
    id: id,
    optionValues: const {},
    sku: id,
    costPrice: costPrice,
    sellingPrice: 0,
    currentStock: stock,
    costLayers: layers,
  );
}

void main() {
  group('FIFO cost flows into BOM preview', () {
    // Material received at 3, then later at 4. Weighted-average = 3.5.
    Product fabric() => Product(
          id: 'fabric',
          userId: 'u',
          name: 'fabric',
          category: 'Raw Material',
          supplier: 'Sup',
          isMaterial: true,
          variants: [
            _layeredVariant('fabric_v', costPrice: 3.5, layers: [
              CostLayer(
                  date: DateTime(2026, 1, 1), unitCost: 3, remainingQty: 1000),
              CostLayer(
                  date: DateTime(2026, 2, 1), unitCost: 4, remainingQty: 1000),
            ]),
          ],
        );

    const comp = [
      BomComponent(materialProductId: 'fabric', quantityPerUnit: 70),
    ];

    test('FIFO uses the oldest (3) layer, not the 3.5 weighted-average', () {
      final econ = BomEconomics.compute(
        components: comp,
        laborPerUnit: 0,
        finishedVariant: _variant('fig8', {}),
        allProducts: [fabric()],
        sellingPrice: 0,
        valuationMethod: 'fifo',
      );
      expect(econ.materialsPerUnit, 210); // 70 × 3, all from oldest layer
    });

    test('average method uses the weighted-average (3.5)', () {
      final econ = BomEconomics.compute(
        components: comp,
        laborPerUnit: 0,
        finishedVariant: _variant('fig8', {}),
        allProducts: [fabric()],
        sellingPrice: 0,
        valuationMethod: 'average',
      );
      expect(econ.materialsPerUnit, 245); // 70 × 3.5
    });

    test('once the 3 layer is gone, FIFO blends into the 4 layer', () {
      final fabric2 = Product(
        id: 'fabric',
        userId: 'u',
        name: 'fabric',
        category: 'Raw Material',
        supplier: 'Sup',
        isMaterial: true,
        variants: [
          _layeredVariant('fabric_v', costPrice: 3.5, layers: [
            CostLayer(
                date: DateTime(2026, 1, 1), unitCost: 3, remainingQty: 40),
            CostLayer(
                date: DateTime(2026, 2, 1), unitCost: 4, remainingQty: 1000),
          ]),
        ],
      );
      final econ = BomEconomics.compute(
        components: comp,
        laborPerUnit: 0,
        finishedVariant: _variant('fig8', {}),
        allProducts: [fabric2],
        sellingPrice: 0,
        valuationMethod: 'fifo',
      );
      // 40 × 3 + 30 × 4 = 240 for the 70 units consumed (±rounding of the
      // per-unit FIFO cost to 2 decimals).
      expect(econ.materialsPerUnit, closeTo(240, 0.5));
    });
  });

  group('BomEconomics.compute', () {
    test('unit cost = materials + labor; margin computed vs selling price', () {
      final fabric = _material(
          id: 'fabric',
          variants: [_variant('fabric_v', {}, stock: 1000, cost: 2)]);
      final logo = _material(
          id: 'logo',
          variants: [_variant('logo_v', {}, stock: 1000, cost: 1.5)]);
      final finished = _variant('fig8', {}, sell: 100);

      final econ = BomEconomics.compute(
        components: const [
          BomComponent(materialProductId: 'fabric', quantityPerUnit: 10), // 20
          BomComponent(materialProductId: 'logo', quantityPerUnit: 2), // 3
        ],
        laborPerUnit: 20,
        finishedVariant: finished,
        allProducts: [fabric, logo],
        sellingPrice: 100,
      );

      expect(econ.materialsPerUnit, 23); // 20 + 3
      expect(econ.laborPerUnit, 20);
      expect(econ.unitCost, 43);
      expect(econ.margin, 57);
      expect(econ.marginPct, 57);
      expect(econ.belowCost, isFalse);
      expect(econ.resolvable, isTrue);
    });

    test('max producible = tightest component constraint', () {
      // fabric: 100 stock / 10 per unit = 10 units.
      // logo: 12 stock / 2 per unit = 6 units → binding constraint.
      final fabric = _material(
          id: 'fabric',
          variants: [_variant('fabric_v', {}, stock: 100, cost: 2)]);
      final logo = _material(
          id: 'logo', variants: [_variant('logo_v', {}, stock: 12, cost: 1)]);

      final econ = BomEconomics.compute(
        components: const [
          BomComponent(materialProductId: 'fabric', quantityPerUnit: 10),
          BomComponent(materialProductId: 'logo', quantityPerUnit: 2),
        ],
        laborPerUnit: 0,
        finishedVariant: _variant('fig8', {}),
        allProducts: [fabric, logo],
        sellingPrice: 0,
      );

      expect(econ.maxProducible, 6);
    });

    test('scrap inflates per-unit requirement and cost', () {
      final fabric = _material(
        id: 'fabric',
        variants: [_variant('fabric_v', {}, stock: 1000, cost: 10)],
        scrap: 10, // +10%
      );
      final econ = BomEconomics.compute(
        components: const [
          BomComponent(
              materialProductId: 'fabric',
              quantityPerUnit: 10,
              applyScrap: true),
        ],
        laborPerUnit: 0,
        finishedVariant: _variant('fig8', {}),
        allProducts: [fabric],
        sellingPrice: 0,
      );
      // 10 * 1.1 = 11 units * 10 cost = 110.
      expect(econ.lines.single.perUnitRequired, 11);
      expect(econ.materialsPerUnit, 110);
    });

    test('belowCost true when unit cost exceeds selling price', () {
      final m = _material(
          id: 'm', variants: [_variant('m_v', {}, stock: 100, cost: 60)]);
      final econ = BomEconomics.compute(
        components: const [
          BomComponent(materialProductId: 'm', quantityPerUnit: 1),
        ],
        laborPerUnit: 0,
        finishedVariant: _variant('p', {}, sell: 50),
        allProducts: [m],
        sellingPrice: 50,
      );
      expect(econ.belowCost, isTrue);
      expect(econ.margin, -10);
    });

    test('unresolved component flips resolvable false and zero max', () {
      final econ = BomEconomics.compute(
        components: const [
          BomComponent(materialProductId: 'missing', quantityPerUnit: 1),
        ],
        laborPerUnit: 5,
        finishedVariant: _variant('p', {}),
        allProducts: const [],
        sellingPrice: 0,
      );
      expect(econ.resolvable, isFalse);
      expect(econ.maxProducible, 0);
      expect(econ.unitCost, 5); // labor only
    });
  });
}
