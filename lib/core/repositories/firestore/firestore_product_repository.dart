import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/product_model.dart';
import '../../services/result.dart';
import '../../utils/connectivity_helper.dart';
import '../../utils/stock_computation.dart';
import '../product_repository.dart';

/// Firestore implementation of [ProductRepository].
class FirestoreProductRepository implements ProductRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('products');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<List<Product>>> getProducts({
    int? limit,
    String? startAfterId,
  }) async {
    try {
      Query<Map<String, dynamic>> query =
          _collection.where('user_id', isEqualTo: _uid).orderBy('name');

      if (startAfterId != null) {
        final cursorDoc = await _collection.doc(startAfterId).get();
        if (cursorDoc.exists) {
          query = query.startAfterDocument(cursorDoc);
        }
      }

      if (limit != null) query = query.limit(limit);

      final snapshot = await query.get();
      final products = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Product.fromJson(data);
      }).toList();

      return Result.success(products);
    } catch (e) {
      return Result.failure( 'Failed to fetch products: $e');
    }
  }

  @override
  Future<Result<Product>> getProductById(String id) async {
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) return Result.failure('Product not found');
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(Product.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to fetch product: $e');
    }
  }

  @override
  Future<Result<Product>> createProduct(Product product) async {
    try {
      final json = product.toJson();
      json['user_id'] = _uid;
      json['created_at'] = DateTime.now().toIso8601String();
      // Mark as shopify_sync if it's an auto-imported Shopify product
      if (product.shopifyProductId != null &&
          product.shopifyProductId!.isNotEmpty) {
        json['_last_modified_by'] = 'shopify_sync';
      }
      final id = product.id;
      json.remove('id');

      await _collection.doc(id).set(json);
      json['id'] = id;
      return Result.success(Product.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to create product: $e');
    }
  }

  @override
  Future<Result<Product>> updateProduct(String id, Product updated, {String modifiedBy = 'masari'}) async {
    try {
      final json = updated.toJson();
      json['user_id'] = _uid;
      json['updated_at'] = DateTime.now().toIso8601String();
      json['_last_modified_by'] = modifiedBy;
      json.remove('id');

      await _collection.doc(id).update(json);
      json['id'] = id;
      return Result.success(Product.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to update product: $e');
    }
  }

  @override
  Future<Result<void>> deleteProduct(String id) async {
    try {
      await _collection.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete product: $e');
    }
  }

  @override
  Future<Result<List<Product>>> getProductsByShopifyProductId(
      String shopifyProductId) async {
    try {
      final snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .where('shopify_product_id', isEqualTo: shopifyProductId)
          .get();
      final products = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Product.fromJson(data);
      }).toList();
      return Result.success(products);
    } catch (e) {
      return Result.failure( 'Failed to query products by Shopify ID: $e');
    }
  }

  @override
  Future<Result<Product>> adjustStock(
      String id, String variantId, int delta, String reason,
      {double? unitCost, String valuationMethod = 'fifo', String? supplierName, bool clearLegacyLayers = false, bool skipCostLayer = false}) async {
    final online = await hasConnectivity();
    if (online) {
      return _adjustStockTransaction(
          id, variantId, delta, reason,
          unitCost: unitCost,
          valuationMethod: valuationMethod,
          supplierName: supplierName,
          clearLegacyLayers: clearLegacyLayers,
          skipCostLayer: skipCostLayer)
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => _adjustStockBatch(
              id, variantId, delta, reason,
              unitCost: unitCost,
              valuationMethod: valuationMethod,
              supplierName: supplierName,
              clearLegacyLayers: clearLegacyLayers,
              skipCostLayer: skipCostLayer),
        );
    }
    return _adjustStockBatch(
        id, variantId, delta, reason,
        unitCost: unitCost,
        valuationMethod: valuationMethod,
        supplierName: supplierName,
        clearLegacyLayers: clearLegacyLayers,
        skipCostLayer: skipCostLayer);
  }

  /// Batch-based stock adjustment that works offline.
  Future<Result<Product>> _adjustStockBatch(
      String id, String variantId, int delta, String reason,
      {double? unitCost, String valuationMethod = 'fifo', String? supplierName, bool clearLegacyLayers = false, bool skipCostLayer = false}) async {
    try {
      final docRef = _collection.doc(id);
      final snapshot = await docRef.get();
      if (!snapshot.exists) return Result.failure('Product not found');

      final data = snapshot.data()!;
      data['id'] = snapshot.id;
      final product = Product.fromJson(data);

      final result = computeStockChange(
        product: product,
        variantId: variantId,
        delta: delta,
        valuationMethod: valuationMethod,
        reason: reason,
        unitCost: unitCost,
        supplierName: supplierName,
        clearLegacyLayers: clearLegacyLayers,
        skipCostLayer: skipCostLayer,
      );

      final updatedProduct = result.updatedProduct;
      final json = updatedProduct.toJson();
      json.remove('id');
      json['updated_at'] = DateTime.now().toIso8601String();
      json['_last_modified_by'] = 'masari';

      final updatedVariant = updatedProduct.variants
          .firstWhere((v) => v.id == variantId);
      json['_last_inventory_push'] = {
        'variant_id': variantId,
        'stock': updatedVariant.currentStock,
        'at': DateTime.now().toIso8601String(),
      };

      await docRef.update(json);
      return Result.success(updatedProduct);
    } catch (e) {
      return Result.failure('Failed to adjust stock: $e');
    }
  }

  @override
  Future<Result<void>> markInventoryPushed(String id, String variantId, int stock) async {
    try {
      await _collection.doc(id).update({
        '_last_modified_by': 'masari',
        'updated_at': DateTime.now().toIso8601String(),
        '_last_inventory_push': {
          'variant_id': variantId,
          'stock': stock,
          'at': DateTime.now().toIso8601String(),
        },
      });
      return Result.success(null);
    } catch (e) {
      return Result.failure('Failed to mark inventory pushed: $e');
    }
  }

  /// Transaction-based stock adjustment (original implementation).
  Future<Result<Product>> _adjustStockTransaction(
      String id, String variantId, int delta, String reason,
      {double? unitCost, String valuationMethod = 'fifo', String? supplierName, bool clearLegacyLayers = false, bool skipCostLayer = false}) async {
    try {
      final result = await _firestore.runTransaction<Product>((txn) async {
        final docRef = _collection.doc(id);
        final snapshot = await txn.get(docRef);

        if (!snapshot.exists) throw Exception('Product not found');

        final data = snapshot.data()!;
        data['id'] = snapshot.id;
        final product = Product.fromJson(data);

        // Log warning when stock would go negative (before delegating)
        final variant = product.variants.where((v) => v.id == variantId).firstOrNull;
        if (variant != null && variant.currentStock + delta < 0) {
          developer.log(
            'Stock would go negative: ${product.name} / ${variant.displayName} '
            'has ${variant.currentStock} units, adjusting by $delta — clamping to 0',
            name: 'FirestoreProductRepository',
          );
        }

        final changeResult = computeStockChange(
          product: product,
          variantId: variantId,
          delta: delta,
          valuationMethod: valuationMethod,
          reason: reason,
          unitCost: unitCost,
          supplierName: supplierName,
          clearLegacyLayers: clearLegacyLayers,
          skipCostLayer: skipCostLayer,
        );

        final updatedProduct = changeResult.updatedProduct;
        final updatedVariant = updatedProduct.variants
            .firstWhere((v) => v.id == variantId);

        final json = updatedProduct.toJson();
        json.remove('id');
        json['updated_at'] = DateTime.now().toIso8601String();
        json['_last_modified_by'] = 'masari';
        json['_last_inventory_push'] = {
          'variant_id': variantId,
          'stock': updatedVariant.currentStock,
          'at': DateTime.now().toIso8601String(),
        };

        txn.update(docRef, json);

        return updatedProduct;
      });

      return Result.success(result);
    } catch (e) {
      return Result.failure( 'Failed to adjust stock: $e');
    }
  }

  @override
  Future<Result<Product>> breakdownStock({
    required String productId,
    required String sourceVariantId,
    required int qty,
    required String valuationMethod,
    required Map<String, ({int quantity, double unitCost})> outputAllocations,
  }) async {
    try {
      final result = await _firestore.runTransaction<Product>((txn) async {
        final docRef = _collection.doc(productId);
        final snapshot = await txn.get(docRef);

        if (!snapshot.exists) throw Exception('Product not found');

        final data = snapshot.data()!;
        data['id'] = snapshot.id;
        var product = Product.fromJson(data);

        // ── 1. Deduct source variant ──────────────────────────
        final srcIdx = product.variants.indexWhere((v) => v.id == sourceVariantId);
        if (srcIdx == -1) throw Exception('Source variant not found');
        final srcVariant = product.variants[srcIdx];

        if (srcVariant.currentStock < qty) {
          throw Exception(
            'Insufficient stock: ${product.name} / ${srcVariant.displayName} '
            'has ${srcVariant.currentStock} units, cannot deduct $qty',
          );
        }

        // Consume cost layers from source
        var srcLayers = List<CostLayer>.from(srcVariant.effectiveCostLayers);
        double movementUnitCost = srcVariant.costPrice;

        if (valuationMethod == 'average' || srcLayers.isEmpty) {
          movementUnitCost = srcVariant.costPrice;
          if (srcLayers.isNotEmpty) {
            var remaining = qty;
            final totalLayerQty = srcLayers.fold<int>(0, (s, l) => s + l.remainingQty);
            if (totalLayerQty > 0) {
              final updated = <CostLayer>[];
              for (final layer in srcLayers) {
                final take = (layer.remainingQty * qty / totalLayerQty).floor().clamp(0, layer.remainingQty);
                final newQty = layer.remainingQty - take;
                remaining -= take;
                if (newQty > 0) updated.add(layer.copyWith(remainingQty: newQty));
              }
              for (var i = 0; i < updated.length && remaining > 0; i++) {
                final take = remaining.clamp(0, updated[i].remainingQty);
                final newQty = updated[i].remainingQty - take;
                remaining -= take;
                if (newQty > 0) {
                  updated[i] = updated[i].copyWith(remainingQty: newQty);
                } else {
                  updated.removeAt(i);
                  i--;
                }
              }
              srcLayers = updated;
            }
          }
        } else {
          if (valuationMethod == 'lifo') {
            srcLayers.sort((a, b) => b.date.compareTo(a.date));
          } else {
            srcLayers.sort((a, b) => a.date.compareTo(b.date));
          }
          var remaining = qty;
          var totalCost = 0.0;
          final updated = <CostLayer>[];
          for (final layer in srcLayers) {
            if (remaining <= 0) { updated.add(layer); continue; }
            final take = remaining < layer.remainingQty ? remaining : layer.remainingQty;
            totalCost += take * layer.unitCost;
            remaining -= take;
            final newQty = layer.remainingQty - take;
            if (newQty > 0) updated.add(layer.copyWith(remainingQty: newQty));
          }
          movementUnitCost = qty > 0 ? (totalCost / qty * 100).roundToDouble() / 100 : srcVariant.costPrice;
          srcLayers = updated;
        }

        // Recalculate source WAC
        final srcTotalLayerStock = srcLayers.fold<int>(0, (s, l) => s + l.remainingQty);
        double srcNewCost;
        if (srcTotalLayerStock > 0) {
          final totalValue = srcLayers.fold<double>(0, (s, l) => s + l.remainingQty * l.unitCost);
          srcNewCost = (totalValue / srcTotalLayerStock * 100).roundToDouble() / 100;
        } else {
          srcNewCost = srcVariant.costPrice;
        }

        final srcMovement = StockMovement(
          type: 'Breakdown',
          quantity: -qty,
          dateTime: DateTime.now(),
          variantId: sourceVariantId,
          unitCost: movementUnitCost,
        );

        final updatedSrc = srcVariant.copyWith(
          currentStock: srcVariant.currentStock - qty,
          costPrice: srcNewCost,
          costLayers: srcLayers,
          movements: [...srcVariant.movements, srcMovement],
        );

        var variants = List<ProductVariant>.from(product.variants);
        variants[srcIdx] = updatedSrc;

        // ── 2. Add each output variant ────────────────────────
        for (final entry in outputAllocations.entries) {
          final outVarId = entry.key;
          final outQty = entry.value.quantity;
          final outUnitCost = entry.value.unitCost;

          final outIdx = variants.indexWhere((v) => v.id == outVarId);
          if (outIdx == -1) throw Exception('Output variant not found: $outVarId');
          final outVariant = variants[outIdx];

          // Use clearLegacyLayers logic: skip synthetic legacy migration
          final outLayers = (outVariant.costLayers.isEmpty)
              ? <CostLayer>[]
              : List<CostLayer>.from(outVariant.effectiveCostLayers);

          outLayers.add(CostLayer(
            date: DateTime.now(),
            unitCost: outUnitCost,
            remainingQty: outQty,
          ));

          // Recalculate WAC for output
          final outTotalStock = outLayers.fold<int>(0, (s, l) => s + l.remainingQty);
          double outNewCost;
          if (outTotalStock > 0) {
            final outTotalValue = outLayers.fold<double>(0, (s, l) => s + l.remainingQty * l.unitCost);
            outNewCost = (outTotalValue / outTotalStock * 100).roundToDouble() / 100;
          } else {
            outNewCost = outUnitCost;
          }

          final outMovement = StockMovement(
            type: 'Breakdown',
            quantity: outQty,
            dateTime: DateTime.now(),
            variantId: outVarId,
            unitCost: outUnitCost,
          );

          variants[outIdx] = outVariant.copyWith(
            currentStock: outVariant.currentStock + outQty,
            costPrice: outNewCost,
            costLayers: outLayers,
            movements: [...outVariant.movements, outMovement],
          );
        }

        // ── 3. Write updated product ──────────────────────────
        final updatedProduct = product.copyWith(
          variants: variants,
          updatedAt: DateTime.now(),
        );

        final json = updatedProduct.toJson();
        json.remove('id');
        json['updated_at'] = DateTime.now().toIso8601String();
        json['_last_modified_by'] = 'masari';

        txn.update(docRef, json);
        return updatedProduct;
      });

      return Result.success(result);
    } catch (e) {
      return Result.failure('Failed to breakdown stock: $e');
    }
  }
}
