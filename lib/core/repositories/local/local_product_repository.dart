import '../../../shared/models/product_model.dart';
import '../product_repository.dart';
import '../../services/result.dart';

/// Local in-memory implementation of [ProductRepository].
class LocalProductRepository implements ProductRepository {
  final List<Product> _products = [];

  @override
  Future<Result<List<Product>>> getProducts({
    int? limit,
    String? startAfterId,
  }) async {
    var list = List<Product>.from(_products);
    
    // Apply cursor-based pagination
    if (startAfterId != null) {
      final idx = list.indexWhere((p) => p.id == startAfterId);
      if (idx != -1 && idx + 1 < list.length) {
        list = list.sublist(idx + 1);
      } else {
        return Result.success([]);
      }
    }
    if (limit != null && limit < list.length) {
      list = list.sublist(0, limit);
    }
    
    return Result.success(list);
  }

  @override
  Future<Result<Product>> getProductById(String id) async {
    try {
      final product = _products.firstWhere((p) => p.id == id);
      return Result.success(product);
    } catch (_) {
      return Result.failure('Product not found');
    }
  }

  @override
  Future<Result<Product>> createProduct(Product product) async {
    _products.add(product);
    return Result.success(product);
  }

  @override
  Future<Result<Product>> updateProduct(String id, Product updated, {String modifiedBy = 'masari'}) async {
    final index = _products.indexWhere((p) => p.id == id);
    if (index == -1) return Result.failure('Product not found');
    _products[index] = updated;
    return Result.success(updated);
  }

  @override
  Future<Result<void>> deleteProduct(String id) async {
    _products.removeWhere((p) => p.id == id);
    return Result.success(null);
  }

  @override
  Future<Result<List<Product>>> getProductsByShopifyProductId(String shopifyProductId) async {
    final matches = _products.where((p) => p.shopifyProductId == shopifyProductId).toList();
    return Result.success(matches);
  }

  @override
  Future<Result<Product>> adjustStock(
      String id, String variantId, int delta, String reason,
      {double? unitCost, String valuationMethod = 'fifo', String? supplierName, bool clearLegacyLayers = false}) async {
    final index = _products.indexWhere((p) => p.id == id);
    if (index == -1) return Result.failure('Product not found');

    final product = _products[index];
    final variantIndex = product.variants.indexWhere((v) => v.id == variantId);
    if (variantIndex == -1) return Result.failure('Variant not found: $variantId');

    final variant = product.variants[variantIndex];
    final newStock = (variant.currentStock + delta).clamp(0, 999999);

    var layers = (clearLegacyLayers && variant.costLayers.isEmpty)
        ? <CostLayer>[]
        : List<CostLayer>.from(variant.effectiveCostLayers);
    double movementUnitCost = variant.costPrice;

    if (delta > 0 && unitCost != null) {
      layers.add(CostLayer(
        date: DateTime.now(),
        unitCost: unitCost,
        remainingQty: delta,
      ));
      movementUnitCost = unitCost;
    } else if (delta < 0) {
      movementUnitCost = variant.cogsPerUnit(-delta, valuationMethod);
      // Consume layers (simplified for local repo)
      if (valuationMethod != 'average' && layers.isNotEmpty) {
        if (valuationMethod == 'lifo') {
          layers.sort((a, b) => b.date.compareTo(a.date));
        } else {
          layers.sort((a, b) => a.date.compareTo(b.date));
        }
        var remaining = -delta;
        final updated = <CostLayer>[];
        for (final layer in layers) {
          if (remaining <= 0) { updated.add(layer); continue; }
          final take = remaining < layer.remainingQty ? remaining : layer.remainingQty;
          remaining -= take;
          final newQty = layer.remainingQty - take;
          if (newQty > 0) updated.add(layer.copyWith(remainingQty: newQty));
        }
        layers = updated;
      }
    }

    // Recalculate WAC from remaining layers
    final totalLayerStock = layers.fold<int>(0, (s, l) => s + l.remainingQty);
    double newCostPrice;
    if (totalLayerStock > 0) {
      final totalValue = layers.fold<double>(0, (s, l) => s + l.remainingQty * l.unitCost);
      newCostPrice = (totalValue / totalLayerStock * 100).roundToDouble() / 100;
    } else {
      newCostPrice = unitCost ?? variant.costPrice;
    }

    final updatedVariant = variant.copyWith(
      currentStock: newStock,
      costPrice: newCostPrice,
      costLayers: layers,
      movements: [
        StockMovement(
          type: reason,
          quantity: delta,
          dateTime: DateTime.now(),
          variantId: variantId,
          unitCost: movementUnitCost,
          supplierName: supplierName,
        ),
        ...variant.movements,
      ],
    );

    final updatedVariants = List<ProductVariant>.from(product.variants);
    updatedVariants[variantIndex] = updatedVariant;

    final updated = product.copyWith(variants: updatedVariants);
    _products[index] = updated;
    return Result.success(updated);
  }
}
