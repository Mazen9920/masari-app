import '../../shared/models/product_model.dart';

/// Result of computing a stock change for a single product variant.
class StockChangeResult {
  /// The updated product with new stock, cost layers, WAC, and movement.
  final Product updatedProduct;

  /// The unit cost attributed to this movement (COGS per unit for sales).
  final double movementUnitCost;

  const StockChangeResult({
    required this.updatedProduct,
    required this.movementUnitCost,
  });
}

/// Pure function that computes the stock change for a single variant of a
/// product. Supports FIFO, LIFO, and Average costing.
///
/// [product] — the product to modify
/// [variantId] — which variant to adjust
/// [delta] — positive = restock, negative = consumption
/// [valuationMethod] — 'fifo', 'lifo', or 'average'
/// [reason] — movement type label (e.g. 'Sale', 'Restock', 'Correction')
/// [unitCost] — cost per unit for restocks (required when delta > 0)
/// [supplierName] — optional supplier for restock movements
/// [clearLegacyLayers] — skip synthetic legacy migration
/// [skipCostLayer] — adjust quantity only, no cost layer (manufactured products)
///
/// Throws [Exception] if variant not found or insufficient stock.
StockChangeResult computeStockChange({
  required Product product,
  required String variantId,
  required int delta,
  required String valuationMethod,
  required String reason,
  double? unitCost,
  String? supplierName,
  bool clearLegacyLayers = false,
  bool skipCostLayer = false,
}) {
  final variantIndex = product.variants.indexWhere((v) => v.id == variantId);
  if (variantIndex == -1) {
    throw Exception('Variant not found: $variantId');
  }
  final variant = product.variants[variantIndex];

  final newStock = variant.currentStock + delta;
  if (newStock < 0) {
    throw Exception(
      'Insufficient stock: ${product.name} / ${variant.displayName} '
      'has ${variant.currentStock} units, cannot adjust by $delta',
    );
  }

  // --- Cost layer logic ---
  var layers = (clearLegacyLayers && variant.costLayers.isEmpty)
      ? <CostLayer>[]
      : List<CostLayer>.from(variant.effectiveCostLayers);
  double movementUnitCost = variant.costPrice;

  if (skipCostLayer && delta > 0) {
    // ── MANUFACTURED RESTOCK: adjust qty only, no cost layer ──
    movementUnitCost = unitCost ?? variant.costPrice;
  } else if (delta > 0 && unitCost != null) {
    // ── RESTOCK: add a new cost layer ──
    layers.add(CostLayer(
      date: DateTime.now(),
      unitCost: unitCost,
      remainingQty: delta,
    ));
    movementUnitCost = unitCost;
  } else if (delta < 0) {
    // ── CONSUMPTION: consume layers based on valuation method ──
    final absQty = -delta;

    if (valuationMethod == 'average' || layers.isEmpty) {
      movementUnitCost = variant.costPrice;
      if (layers.isNotEmpty) {
        final totalLayerQty =
            layers.fold<int>(0, (s, l) => s + l.remainingQty);
        if (totalLayerQty > 0) {
          final updated = <CostLayer>[];
          int cumulativeAssigned = 0;
          for (var idx = 0; idx < layers.length; idx++) {
            final layer = layers[idx];
            final idealCumulative = ((idx + 1) == layers.length)
                ? absQty
                : (layer.remainingQty * absQty / totalLayerQty).round();
            final take = ((idx + 1) == layers.length)
                ? (absQty - cumulativeAssigned).clamp(0, layer.remainingQty)
                : (idealCumulative).clamp(0, layer.remainingQty);
            cumulativeAssigned += take;
            final newQty = layer.remainingQty - take;
            if (newQty > 0) updated.add(layer.copyWith(remainingQty: newQty));
          }
          layers = updated;
        }
      }
    } else {
      // FIFO or LIFO: consume specific layers
      if (valuationMethod == 'lifo') {
        layers.sort((a, b) => b.date.compareTo(a.date)); // newest first
      } else {
        layers.sort((a, b) => a.date.compareTo(b.date)); // oldest first
      }

      var remaining = absQty;
      var totalCost = 0.0;
      final updated = <CostLayer>[];

      for (final layer in layers) {
        if (remaining <= 0) {
          updated.add(layer);
          continue;
        }
        final take =
            remaining < layer.remainingQty ? remaining : layer.remainingQty;
        totalCost += take * layer.unitCost;
        remaining -= take;
        final newQty = layer.remainingQty - take;
        if (newQty > 0) updated.add(layer.copyWith(remainingQty: newQty));
      }

      movementUnitCost = absQty > 0
          ? (totalCost / absQty * 100).roundToDouble() / 100
          : variant.costPrice;
      layers = updated;
    }
  }

  // Recalculate WAC from remaining layers
  double newCostPrice;
  if (skipCostLayer && delta > 0) {
    newCostPrice = variant.costPrice;
  } else {
    final totalLayerStock =
        layers.fold<int>(0, (s, l) => s + l.remainingQty);
    if (totalLayerStock > 0) {
      final totalValue =
          layers.fold<double>(0, (s, l) => s + l.remainingQty * l.unitCost);
      newCostPrice =
          (totalValue / totalLayerStock * 100).roundToDouble() / 100;
    } else if (unitCost != null) {
      newCostPrice = unitCost;
    } else {
      newCostPrice = variant.costPrice;
    }
  }

  final movement = StockMovement(
    type: reason,
    quantity: delta,
    dateTime: DateTime.now(),
    variantId: variantId,
    unitCost: movementUnitCost,
    supplierName: supplierName,
  );

  final updatedVariant = variant.copyWith(
    currentStock: newStock,
    costPrice: newCostPrice,
    costLayers: layers,
    movements: [...variant.movements, movement],
  );

  final updatedVariants = List<ProductVariant>.from(product.variants);
  updatedVariants[variantIndex] = updatedVariant;

  final updatedProduct = product.copyWith(
    variants: updatedVariants,
    updatedAt: DateTime.now(),
  );

  return StockChangeResult(
    updatedProduct: updatedProduct,
    movementUnitCost: movementUnitCost,
  );
}
