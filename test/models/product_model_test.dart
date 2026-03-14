import 'package:flutter_test/flutter_test.dart';
import 'package:masari_app/shared/models/product_model.dart';

void main() {
  group('Product Model Tests', () {
    final variant = ProductVariant(
      id: 'prod_123_v0',
      optionValues: const {},
      sku: 'WDG-001',
      costPrice: 50.0,
      sellingPrice: 100.0,
      currentStock: 20,
      reorderPoint: 5,
    );

    final product = Product(
      id: 'prod_123',
      userId: 'user_1',
      name: 'Widget X',
      category: 'Electronics',
      supplier: 'Acme',
      variants: [variant],
    );

    test('stock status evaluates correctly', () {
      // In stock
      expect(product.status, StockStatus.inStock);

      // Low stock
      final lowStock = product.copyWith(
        variants: [variant.copyWith(currentStock: 4)],
      );
      expect(lowStock.status, StockStatus.lowStock);

      // Out of stock
      final outOfStock = product.copyWith(
        variants: [variant.copyWith(currentStock: 0)],
      );
      expect(outOfStock.status, StockStatus.outOfStock);
    });

    test('totalValue and profitMargin are calculated accurately', () {
      expect(product.totalValue, 2000.0); // 20 * 100.0
      expect(product.profitMargin, 50.0); // (100 - 50) / 100 * 100
    });

    test('JSON serialization works correctly', () {
      final json = product.toJson();

      expect(json['id'], 'prod_123');
      expect(json['name'], 'Widget X');
      expect(json['cost_price'], 50.0);
      expect(json['selling_price'], 100.0);
      expect(json['current_stock'], 20);
    });

    test('JSON deserialization creates correct object', () {
      final json = {
        'id': 'prod_456',
        'user_id': 'user_2',
        'name': 'Widget Y',
        'sku': 'WDG-002',
        'category': 'Hardware',
        'supplier': 'Globex',
        'cost_price': 10.0,
        'selling_price': 30.0,
        'current_stock': 100,
        'reorder_point': 20,
      };

      final deserialized = Product.fromJson(json);

      expect(deserialized.id, 'prod_456');
      expect(deserialized.name, 'Widget Y');
      expect(deserialized.costPrice, 10.0);
      expect(deserialized.currentStock, 100);
      expect(deserialized.profitMargin.toStringAsFixed(2), '66.67');
      expect(deserialized.status, StockStatus.inStock);
    });
  });
}
