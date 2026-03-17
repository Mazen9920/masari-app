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
      {double? unitCost, String valuationMethod = 'fifo', String? supplierName, bool clearLegacyLayers = false, bool skipCostLayer = false}) async {
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

    if (skipCostLayer && delta > 0) {
      // ── MANUFACTURED RESTOCK: adjust qty only, no cost layer ──
      movementUnitCost = unitCost ?? variant.costPrice;
    } else if (delta > 0 && unitCost != null) {
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

    // Recalculate WAC from remaining layers (skip for manufactured products)
    final totalLayerStock = layers.fold<int>(0, (s, l) => s + l.remainingQty);
    double newCostPrice;
    if (skipCostLayer && delta > 0) {
      newCostPrice = variant.costPrice; // preserve existing cost
    } else if (totalLayerStock > 0) {
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

  @override
  Future<Result<Product>> breakdownStock({
    required String productId,
    required String sourceVariantId,
    required int qty,
    required String valuationMethod,
    required Map<String, ({int quantity, double unitCost})> outputAllocations,
  }) async {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return Result.failure('Product not found');

    var product = _products[index];

    // Deduct source
    final srcIdx = product.variants.indexWhere((v) => v.id == sourceVariantId);
    if (srcIdx == -1) return Result.failure('Source variant not found');
    final srcVariant = product.variants[srcIdx];
    if (srcVariant.currentStock < qty) return Result.failure('Insufficient stock');

    var variants = List<ProductVariant>.from(product.variants);
    variants[srcIdx] = srcVariant.copyWith(
      currentStock: srcVariant.currentStock - qty,
      movements: [
        StockMovement(type: 'Breakdown', quantity: -qty, dateTime: DateTime.now(), variantId: sourceVariantId, unitCost: srcVariant.costPrice),
        ...srcVariant.movements,
      ],
    );

    // Add outputs
    for (final entry in outputAllocations.entries) {
      final outIdx = variants.indexWhere((v) => v.id == entry.key);
      if (outIdx == -1) return Result.failure('Output variant not found');
      final outVariant = variants[outIdx];
      variants[outIdx] = outVariant.copyWith(
        currentStock: outVariant.currentStock + entry.value.quantity,
        movements: [
          StockMovement(type: 'Breakdown', quantity: entry.value.quantity, dateTime: DateTime.now(), variantId: entry.key, unitCost: entry.value.unitCost),
          ...outVariant.movements,
        ],
      );
    }

    final updated = product.copyWith(variants: variants);
    _products[index] = updated;
    return Result.success(updated);
  }
}
