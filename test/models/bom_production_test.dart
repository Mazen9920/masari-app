import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/models/product_model.dart';
import 'package:revvo_app/shared/models/production_order_model.dart';

ProductVariant _variant(String id, Map<String, String> opts,
    {double stock = 0, double cost = 0}) {
  return ProductVariant(
    id: id,
    optionValues: opts,
    sku: id,
    costPrice: cost,
    sellingPrice: 0,
    currentStock: stock,
  );
}

Product _material({
  required String id,
  required List<ProductVariant> variants,
  String supplier = 'Sup',
  double? scrap,
}) {
  return Product(
    id: id,
    userId: 'u',
    name: id,
    category: 'Raw Material',
    supplier: supplier,
    isMaterial: true,
    scrapPercentage: scrap,
    variants: variants,
  );
}

void main() {
  group('Product.resolveComponentVariantId', () {
    test('explicit variant id wins', () {
      final material = _material(id: 'fabric', variants: [
        _variant('fabric_black', {'Color': 'Black'}),
        _variant('fabric_red', {'Color': 'Red'}),
      ]);
      final finished = _variant('fig8_red', {'Color': 'Red'});
      const c = BomComponent(
        materialProductId: 'fabric',
        materialVariantId: 'fabric_black',
        quantityPerUnit: 70,
      );
      expect(
        Product.resolveComponentVariantId(c, finished, material),
        'fabric_black',
      );
    });

    test('color-linked resolves to matching color variant', () {
      final material = _material(id: 'fabric', variants: [
        _variant('fabric_black', {'Color': 'Black'}),
        _variant('fabric_red', {'Color': 'Red'}),
      ]);
      final finished = _variant('fig8_red', {'Color': 'Red'});
      const c = BomComponent(
        materialProductId: 'fabric',
        colorLinked: true,
        quantityPerUnit: 70,
      );
      expect(
        Product.resolveComponentVariantId(c, finished, material),
        'fabric_red',
      );
    });

    test('color-linked is case-insensitive and supports "colour"', () {
      final material = _material(id: 'fabric', variants: [
        _variant('fabric_black', {'colour': 'black'}),
        _variant('fabric_red', {'colour': 'RED'}),
      ]);
      final finished = _variant('fig8_red', {'Color': 'Red'});
      const c = BomComponent(
        materialProductId: 'fabric',
        colorLinked: true,
        quantityPerUnit: 70,
      );
      expect(
        Product.resolveComponentVariantId(c, finished, material),
        'fabric_red',
      );
    });

    test('falls back to first variant when no color match', () {
      final material = _material(id: 'logo', variants: [
        _variant('logo_default', {}),
      ]);
      final finished = _variant('fig8_red', {'Color': 'Red'});
      const c = BomComponent(
        materialProductId: 'logo',
        colorLinked: true,
        quantityPerUnit: 2,
      );
      expect(
        Product.resolveComponentVariantId(c, finished, material),
        'logo_default',
      );
    });

    test('returns null when material has no variants', () {
      final material = _material(id: 'empty', variants: const []);
      final finished = _variant('fig8', {});
      const c = BomComponent(materialProductId: 'empty', quantityPerUnit: 1);
      expect(
        Product.resolveComponentVariantId(c, finished, material),
        isNull,
      );
    });
  });

  group('Product.resolveComponentMaterial (per-colour separate products)', () {
    final blackFabric = _material(
        id: 'fabric_black',
        variants: [_variant('fabric_black_v0', {}, stock: 100, cost: 0.18)]);
    final redFabric = _material(
        id: 'fabric_red',
        variants: [_variant('fabric_red_v0', {}, stock: 50, cost: 0.20)]);
    final byId = {
      for (final p in [blackFabric, redFabric]) p.id: p,
    };
    const comp = BomComponent(
      materialProductId: 'fabric_black',
      quantityPerUnit: 70,
      materialByColor: {'black': 'fabric_black', 'red': 'fabric_red'},
    );

    test('Red finished variant resolves to red fabric product', () {
      final finished = _variant('fig8_red', {'Option 1': 'Red'});
      final r = Product.resolveComponentMaterial(comp, finished, byId);
      expect(r.productId, 'fabric_red');
      expect(r.variantId, 'fabric_red_v0');
    });

    test('Black finished variant resolves to black fabric product', () {
      final finished = _variant('fig8_black', {'Option 1': 'Black'});
      final r = Product.resolveComponentMaterial(comp, finished, byId);
      expect(r.productId, 'fabric_black');
    });

    test('Unmapped colour (Pink) falls back to materialProductId', () {
      final finished = _variant('fig8_pink', {'Option 1': 'Pink'});
      final r = Product.resolveComponentMaterial(comp, finished, byId);
      expect(r.productId, 'fabric_black');
    });

    test('no colour map → always materialProductId', () {
      const plain = BomComponent(
          materialProductId: 'fabric_black', quantityPerUnit: 70);
      final finished = _variant('fig8_red', {'Option 1': 'Red'});
      final r = Product.resolveComponentMaterial(plain, finished, byId);
      expect(r.productId, 'fabric_black');
    });

    test('materialByColor round-trips through JSON', () {
      final restored = BomComponent.fromJson(comp.toJson());
      expect(restored.materialByColor, {
        'black': 'fabric_black',
        'red': 'fabric_red',
      });
    });
  });

  group('ManufacturingBom serialization', () {
    test('round-trips through JSON on a Product', () {
      final product = Product(
        id: 'fig8',
        userId: 'u',
        name: 'Figure-8 Straps',
        category: 'Straps',
        supplier: 'RPE',
        variants: [_variant('fig8_black', {'Color': 'Black'})],
        manufacturingBom: const ManufacturingBom(
          components: [
            BomComponent(
              materialProductId: 'fabric',
              colorLinked: true,
              quantityPerUnit: 70,
              unit: 'gm',
              applyScrap: true,
            ),
            BomComponent(
              materialProductId: 'logo',
              materialVariantId: 'logo_v0',
              quantityPerUnit: 4,
              unit: 'pcs',
            ),
          ],
          laborCostPerUnit: 20,
          laborSupplierId: 'sup_hassan',
          laborSupplierName: 'Hassan',
        ),
      );

      final restored = Product.fromJson(product.toJson());
      expect(restored.hasBom, isTrue);
      final bom = restored.manufacturingBom!;
      expect(bom.components.length, 2);
      expect(bom.components.first.colorLinked, isTrue);
      expect(bom.components.first.quantityPerUnit, 70);
      expect(bom.components.first.unit, 'gm');
      expect(bom.components.first.applyScrap, isTrue);
      expect(bom.components[1].materialVariantId, 'logo_v0');
      expect(bom.laborCostPerUnit, 20);
      expect(bom.laborSupplierName, 'Hassan');
    });

    test('hasBom is false when no components', () {
      final product = Product(
        id: 'x',
        userId: 'u',
        name: 'X',
        category: 'c',
        supplier: 's',
        variants: [_variant('x_v0', {})],
      );
      expect(product.hasBom, isFalse);
    });
  });

  group('ProductionOrder serialization', () {
    test('round-trips with numeric status enum', () {
      final order = ProductionOrder(
        id: 'po1',
        userId: 'u',
        productId: 'fig8',
        productName: 'Figure-8 Straps',
        variantId: 'fig8_black',
        variantName: 'Black',
        quantity: 100,
        status: ProductionStatus.inProgress,
        inputs: const [
          ProductionInputLine(
            materialProductId: 'fabric',
            materialVariantId: 'fabric_black',
            materialName: 'Strap Fabric (Black)',
            quantity: 7000,
            unitCost: 0.1824,
            totalCost: 1276.8,
          ),
        ],
        materialsCost: 1276.8,
        laborCost: 2000,
        totalCost: 3276.8,
        unitCost: 32.77,
        laborSupplierId: 'sup_hassan',
        startedAt: DateTime(2026, 6, 24),
      );

      final json = order.toJson();
      // Status must be stored numerically (gotcha #2).
      expect(json['status'], 0);

      final restored = ProductionOrder.fromJson(json);
      expect(restored.status, ProductionStatus.inProgress);
      expect(restored.quantity, 100);
      expect(restored.inputs.single.quantity, 7000);
      expect(restored.materialsCost, 1276.8);
      expect(restored.laborCost, 2000);
      expect(restored.unitCost, 32.77);
    });

    test('completed/cancelled statuses map to 1/2', () {
      expect(ProductionStatus.completed.index, 1);
      expect(ProductionStatus.cancelled.index, 2);
    });

    test('partial receipt: remainingQty, wipValue and progress', () {
      final order = ProductionOrder(
        id: 'po',
        userId: 'u',
        productId: 'fig8',
        productName: 'Figure-8',
        variantId: 'v',
        variantName: 'Black',
        quantity: 100,
        completedQty: 40,
        status: ProductionStatus.inProgress,
        materialsCost: 1000,
        laborCost: 2000,
        totalCost: 3000,
        unitCost: 30,
        startedAt: DateTime(2026, 6, 24),
      );
      expect(order.remainingQty, 60);
      expect(order.isPartiallyReceived, isTrue);
      // WIP = MATERIALS only of the 60 unreceived units (finishing isn't
      // capitalized until completion).
      expect(order.wipValue, 600); // 1000 * 60/100
      // Finishing still to be incurred on the unreceived units (informational,
      // NOT a booked liability).
      expect(order.pendingFinishingCost, 1200); // 2000 * 60/100

      // completed_qty survives JSON.
      expect(order.toJson()['completed_qty'], 40);
      expect(ProductionOrder.fromJson(order.toJson()).completedQty, 40);

      // Fully received → no WIP, no pending finishing, not "partial".
      final full = order.copyWith(completedQty: 100);
      expect(full.remainingQty, 0);
      expect(full.wipValue, 0);
      expect(full.pendingFinishingCost, 0);
      expect(full.isPartiallyReceived, isFalse);
    });

    test(
        'made-to-order cost: invoice = labor + made-to-order, WIP = materials only',
        () {
      final order = ProductionOrder(
        id: 'po',
        userId: 'u',
        productId: 'fig8',
        productName: 'Figure-8',
        variantId: 'v',
        variantName: 'Black',
        quantity: 100,
        status: ProductionStatus.inProgress,
        materialsCost: 3000, // stocked materials
        madeToOrderCost: 2250, // mini bags produced by supplier
        laborCost: 2000, // finishing
        totalCost: 7250,
        unitCost: 72.5,
        startedAt: DateTime(2026, 6, 24),
      );
      // Supplier invoice = finishing + made-to-order (NOT stocked materials).
      expect(order.manufacturingCharge, 4250);
      // WIP carries ONLY the stocked materials of the in-progress units...
      expect(order.wipValue, 3000);
      // ...and the finishing + made-to-order is a pending (not-yet-incurred)
      // cost recognized at completion, not a balance-sheet liability.
      expect(order.pendingFinishingCost, 4250);

      final restored = ProductionOrder.fromJson(order.toJson());
      expect(restored.madeToOrderCost, 2250);
      expect(restored.manufacturingCharge, 4250);
    });
  });

  group('ProductionPlan grouping & shortfalls', () {
    ProductionPlanLine line(String supplier,
        {double shortfall = 0, double cost = 0}) {
      return ProductionPlanLine(
        materialProductId: 'm_$supplier',
        materialVariantId: 'v',
        materialName: 'mat',
        supplierName: supplier,
        unit: 'pcs',
        requiredQty: 10,
        availableQty: 5,
        shortfallQty: shortfall,
        unitCost: 1,
        lineCost: cost,
      );
    }

    test('groups lines by supplier', () {
      final plan = ProductionPlan(
        productId: 'p',
        productName: 'P',
        variantId: 'v',
        variantName: 'V',
        quantity: 100,
        lines: [
          line('Haytham', cost: 100),
          line('Haytham', cost: 50),
          line('George', cost: 20),
        ],
        materialsCost: 170,
        laborCost: 30,
        totalCost: 200,
        unitCost: 2,
      );
      final groups = plan.linesBySupplier;
      expect(groups.keys.length, 2);
      expect(groups['Haytham']!.length, 2);
      expect(groups['George']!.length, 1);
    });

    test('hasShortfall reflects any shortfall line', () {
      final noShort = ProductionPlan(
        productId: 'p',
        productName: 'P',
        variantId: 'v',
        variantName: 'V',
        quantity: 1,
        lines: [line('A')],
        materialsCost: 0,
        laborCost: 0,
        totalCost: 0,
        unitCost: 0,
      );
      expect(noShort.hasShortfall, isFalse);

      final withShort = ProductionPlan(
        productId: 'p',
        productName: 'P',
        variantId: 'v',
        variantName: 'V',
        quantity: 1,
        lines: [line('A', shortfall: 3)],
        materialsCost: 0,
        laborCost: 0,
        totalCost: 0,
        unitCost: 0,
      );
      expect(withShort.hasShortfall, isTrue);
    });

    test('made-to-order shortfall does NOT block the run', () {
      ProductionPlanLine mto(double shortfall, bool madeToOrder) =>
          ProductionPlanLine(
            materialProductId: 'minibag',
            materialVariantId: 'v',
            materialName: 'Mini bag',
            supplierName: 'Hassan',
            unit: 'pcs',
            requiredQty: 100,
            availableQty: 0,
            shortfallQty: shortfall,
            unitCost: 22.5,
            lineCost: 2250,
            madeToOrder: madeToOrder,
          );

      // Same shortfall: blocks when stocked, not when made-to-order.
      expect(mto(100, false).blocksStart, isTrue);
      expect(mto(100, true).blocksStart, isFalse);
      expect(mto(100, true).hasShortfall, isTrue); // still a real shortfall

      final plan = ProductionPlan(
        productId: 'fig8',
        productName: 'Figure-8',
        variantId: 'v',
        variantName: 'V',
        quantity: 100,
        lines: [mto(100, true)],
        materialsCost: 2250,
        laborCost: 0,
        totalCost: 2250,
        unitCost: 22.5,
      );
      expect(plan.hasShortfall, isFalse); // made-to-order excluded
    });
  });

  group('BomComponent.madeToOrder', () {
    test('round-trips through JSON', () {
      const c = BomComponent(
        materialProductId: 'minibag',
        quantityPerUnit: 1,
        madeToOrder: true,
      );
      final restored = BomComponent.fromJson(c.toJson());
      expect(restored.madeToOrder, isTrue);
    });

    test('defaults to false and is omitted from JSON when false', () {
      const c = BomComponent(materialProductId: 'x', quantityPerUnit: 1);
      expect(c.madeToOrder, isFalse);
      expect(c.toJson().containsKey('made_to_order'), isFalse);
    });
  });
}
