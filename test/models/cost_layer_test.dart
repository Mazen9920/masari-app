import 'package:flutter_test/flutter_test.dart';
import 'package:masari_app/shared/models/product_model.dart';

void main() {
  // ═══════════════════════════════════════════════════════════
  //  effectiveCostLayers
  // ═══════════════════════════════════════════════════════════
  group('effectiveCostLayers', () {
    test('returns actual layers when present', () {
      final layers = [
        CostLayer(date: DateTime(2024, 1, 1), unitCost: 10, remainingQty: 5),
      ];
      final v = _variant(costLayers: layers, currentStock: 5, costPrice: 10);
      expect(v.effectiveCostLayers, layers);
    });

    test('creates synthetic legacy layer when layers empty but stock/cost exist', () {
      final v = _variant(costLayers: [], currentStock: 10, costPrice: 25);
      final eff = v.effectiveCostLayers;
      expect(eff.length, 1);
      expect(eff[0].unitCost, 25);
      expect(eff[0].remainingQty, 10);
      expect(eff[0].date, DateTime(2000));
    });

    test('returns empty when no stock', () {
      final v = _variant(costLayers: [], currentStock: 0, costPrice: 25);
      expect(v.effectiveCostLayers, isEmpty);
    });

    test('returns empty when cost is zero', () {
      final v = _variant(costLayers: [], currentStock: 10, costPrice: 0);
      expect(v.effectiveCostLayers, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  cogsPerUnit — FIFO
  // ═══════════════════════════════════════════════════════════
  group('cogsPerUnit FIFO', () {
    test('single layer', () {
      final v = _variant(costLayers: [
        CostLayer(date: DateTime(2024, 1, 1), unitCost: 10, remainingQty: 20),
      ], currentStock: 20, costPrice: 10);
      expect(v.cogsPerUnit(5, 'fifo'), 10.0);
    });

    test('consumes oldest layer first', () {
      final v = _variant(costLayers: [
        CostLayer(date: DateTime(2024, 1, 1), unitCost: 10, remainingQty: 3),
        CostLayer(date: DateTime(2024, 6, 1), unitCost: 20, remainingQty: 7),
      ], currentStock: 10, costPrice: 15);
      // 3 units @ 10 + 2 units @ 20 = 70 / 5 = 14
      expect(v.cogsPerUnit(5, 'fifo'), 14.0);
    });

    test('spans multiple layers', () {
      final v = _variant(costLayers: [
        CostLayer(date: DateTime(2024, 1, 1), unitCost: 10, remainingQty: 2),
        CostLayer(date: DateTime(2024, 3, 1), unitCost: 15, remainingQty: 2),
        CostLayer(date: DateTime(2024, 6, 1), unitCost: 20, remainingQty: 6),
      ], currentStock: 10, costPrice: 15);
      // 2@10 + 2@15 + 1@20 = 20+30+20 = 70 / 5 = 14
      expect(v.cogsPerUnit(5, 'fifo'), 14.0);
    });

    test('exact layer match', () {
      final v = _variant(costLayers: [
        CostLayer(date: DateTime(2024, 1, 1), unitCost: 10, remainingQty: 5),
        CostLayer(date: DateTime(2024, 6, 1), unitCost: 20, remainingQty: 5),
      ], currentStock: 10, costPrice: 15);
      // All 5 from first layer @ 10 = 50 / 5 = 10
      expect(v.cogsPerUnit(5, 'fifo'), 10.0);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  cogsPerUnit — LIFO
  // ═══════════════════════════════════════════════════════════
  group('cogsPerUnit LIFO', () {
    test('consumes newest layer first', () {
      final v = _variant(costLayers: [
        CostLayer(date: DateTime(2024, 1, 1), unitCost: 10, remainingQty: 5),
        CostLayer(date: DateTime(2024, 6, 1), unitCost: 20, remainingQty: 5),
      ], currentStock: 10, costPrice: 15);
      // LIFO: 3 units from newest (20) = 60 / 3 = 20
      expect(v.cogsPerUnit(3, 'lifo'), 20.0);
    });

    test('spans layers newest first', () {
      final v = _variant(costLayers: [
        CostLayer(date: DateTime(2024, 1, 1), unitCost: 10, remainingQty: 5),
        CostLayer(date: DateTime(2024, 6, 1), unitCost: 20, remainingQty: 3),
      ], currentStock: 8, costPrice: 15);
      // LIFO: 3@20 + 2@10 = 60+20 = 80 / 5 = 16
      expect(v.cogsPerUnit(5, 'lifo'), 16.0);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  cogsPerUnit — Average
  // ═══════════════════════════════════════════════════════════
  group('cogsPerUnit Average', () {
    test('returns costPrice regardless of layers', () {
      final v = _variant(costLayers: [
        CostLayer(date: DateTime(2024, 1, 1), unitCost: 10, remainingQty: 5),
        CostLayer(date: DateTime(2024, 6, 1), unitCost: 20, remainingQty: 5),
      ], currentStock: 10, costPrice: 15);
      expect(v.cogsPerUnit(3, 'average'), 15.0);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  cogsPerUnit — Edge cases
  // ═══════════════════════════════════════════════════════════
  group('cogsPerUnit edge cases', () {
    test('qty=0 returns costPrice', () {
      final v = _variant(costLayers: [
        CostLayer(date: DateTime(2024, 1, 1), unitCost: 10, remainingQty: 5),
      ], currentStock: 5, costPrice: 99);
      expect(v.cogsPerUnit(0, 'fifo'), 99.0);
    });

    test('negative qty returns costPrice', () {
      final v = _variant(costLayers: [
        CostLayer(date: DateTime(2024, 1, 1), unitCost: 10, remainingQty: 5),
      ], currentStock: 5, costPrice: 42);
      expect(v.cogsPerUnit(-1, 'fifo'), 42.0);
    });

    test('layer insufficient — pads with costPrice', () {
      final v = _variant(costLayers: [
        CostLayer(date: DateTime(2024, 1, 1), unitCost: 10, remainingQty: 2),
      ], currentStock: 5, costPrice: 30);
      // 2@10 + 3@30 (padded) = 20+90 = 110 / 5 = 22
      expect(v.cogsPerUnit(5, 'fifo'), 22.0);
    });

    test('empty layers falls back to costPrice', () {
      final v = _variant(costLayers: [], currentStock: 0, costPrice: 25);
      expect(v.cogsPerUnit(3, 'fifo'), 25.0);
    });

    test('legacy synthetic layer works for FIFO', () {
      final v = _variant(costLayers: [], currentStock: 10, costPrice: 50);
      // effectiveCostLayers creates a synthetic layer @ costPrice
      expect(v.cogsPerUnit(5, 'fifo'), 50.0);
    });

    test('result is rounded to 2 decimal places', () {
      final v = _variant(costLayers: [
        CostLayer(date: DateTime(2024, 1, 1), unitCost: 10, remainingQty: 1),
        CostLayer(date: DateTime(2024, 6, 1), unitCost: 20, remainingQty: 2),
      ], currentStock: 3, costPrice: 15);
      // 1@10 + 2@20 = 50 / 3 = 16.666... → 16.67
      expect(v.cogsPerUnit(3, 'fifo'), 16.67);
    });
  });

  // ═══════════════════════════════════════════════════════════
  //  CostLayer serialization
  // ═══════════════════════════════════════════════════════════
  group('CostLayer', () {
    test('toJson/fromJson roundtrip', () {
      final layer = CostLayer(
        date: DateTime(2024, 3, 15),
        unitCost: 42.5,
        remainingQty: 10,
      );
      final json = layer.toJson();
      final restored = CostLayer.fromJson(json);
      expect(restored.unitCost, 42.5);
      expect(restored.remainingQty, 10);
      expect(restored.date.year, 2024);
      expect(restored.date.month, 3);
      expect(restored.date.day, 15);
    });
  });
}

/// Helper to create a ProductVariant with specified cost layer config.
ProductVariant _variant({
  List<CostLayer> costLayers = const [],
  int currentStock = 0,
  double costPrice = 0,
}) {
  return ProductVariant(
    id: 'test_v0',
    sku: 'TEST-001',
    costPrice: costPrice,
    sellingPrice: costPrice * 2,
    currentStock: currentStock,
    reorderPoint: 5,
    costLayers: costLayers,
  );
}
