import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/product_model.dart';
import '../../services/result.dart';
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
      {double? unitCost, String valuationMethod = 'fifo', String? supplierName, bool clearLegacyLayers = false}) async {
    try {
      final result = await _firestore.runTransaction<Product>((txn) async {
        final docRef = _collection.doc(id);
        final snapshot = await txn.get(docRef);

        if (!snapshot.exists) throw Exception('Product not found');

        final data = snapshot.data()!;
        data['id'] = snapshot.id;
        final product = Product.fromJson(data);

        final variantIndex =
            product.variants.indexWhere((v) => v.id == variantId);
        if (variantIndex == -1) {
          throw Exception( 'Variant not found: $variantId');
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
        // clearLegacyLayers: skip synthetic legacy migration (used for
        // breakdown outputs so manually-entered costPrice doesn't pollute WAC)
        var layers = (clearLegacyLayers && variant.costLayers.isEmpty)
            ? <CostLayer>[]
            : List<CostLayer>.from(variant.effectiveCostLayers);
        double movementUnitCost = variant.costPrice;

        if (delta > 0 && unitCost != null) {
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
            // Average: reduce all layers proportionally, COGS = WAC
            movementUnitCost = variant.costPrice;
            if (layers.isNotEmpty) {
              var remaining = absQty;
              // Remove proportionally from each layer
              final totalLayerQty =
                  layers.fold<int>(0, (s, l) => s + l.remainingQty);
              if (totalLayerQty > 0) {
                final updated = <CostLayer>[];
                for (final layer in layers) {
                  // Use floor to avoid over-deduction from rounding
                  final take = (layer.remainingQty * absQty / totalLayerQty)
                      .floor()
                      .clamp(0, layer.remainingQty);
                  final newQty = layer.remainingQty - take;
                  remaining -= take;
                  if (newQty > 0) {
                    updated.add(layer.copyWith(remainingQty: newQty));
                  }
                }
                // Handle rounding remainder — take from first available layer
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
              if (newQty > 0) {
                updated.add(layer.copyWith(remainingQty: newQty));
              }
            }

            movementUnitCost = absQty > 0
                ? (totalCost / absQty * 100).roundToDouble() / 100
                : variant.costPrice;
            layers = updated;
          }
        }

        // Recalculate WAC from remaining layers
        double newCostPrice;
        final totalLayerStock =
            layers.fold<int>(0, (s, l) => s + l.remainingQty);
        if (totalLayerStock > 0) {
          final totalValue = layers.fold<double>(
              0, (s, l) => s + l.remainingQty * l.unitCost);
          newCostPrice = (totalValue / totalLayerStock * 100).roundToDouble() / 100;
        } else if (unitCost != null) {
          newCostPrice = unitCost;
        } else {
          newCostPrice = variant.costPrice;
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

        final json = updatedProduct.toJson();
        json.remove('id');
        json['updated_at'] = DateTime.now().toIso8601String();
        json['_last_modified_by'] = 'masari';
        json['_last_inventory_push'] = {
          'variant_id': variantId,
          'stock': newStock,
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
}
