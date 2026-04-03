import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../shared/models/product_model.dart';
import '../../../shared/models/sale_model.dart';
import '../../../shared/models/transaction_model.dart' as models;
import '../../services/result.dart';
import '../../utils/stock_computation.dart';
import '../sale_repository.dart';

/// Firestore implementation of [SaleRepository].
class FirestoreSaleRepository implements SaleRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('sales');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<List<Sale>>> getSales({int? limit, String? startAfterId}) async {
    try {
      Query<Map<String, dynamic>> query =
          _collection.where('user_id', isEqualTo: _uid).orderBy('date', descending: true);

      if (startAfterId != null) {
        final cursorDoc = await _collection.doc(startAfterId).get();
        if (cursorDoc.exists) {
          query = query.startAfterDocument(cursorDoc);
        }
      }

      if (limit != null) query = query.limit(limit);

      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await query.get();
      } catch (_) {
        // Index may not be ready yet — fall back to unordered query
        Query<Map<String, dynamic>> fallback =
            _collection.where('user_id', isEqualTo: _uid);
        if (limit != null) fallback = fallback.limit(limit);
        snapshot = await fallback.get();
      }

      final sales = <Sale>[];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          data['id'] = doc.id;
          sales.add(Sale.fromJson(data));
        } catch (e) {
          if (kDebugMode) debugPrint('[SaleRepo] Failed to parse sale ${doc.id}: $e');
        }
      }

      // Client-side sort (ensures order even with fallback query)
      sales.sort((a, b) => b.date.compareTo(a.date));

      return Result.success(sales);
    } catch (e) {
      return Result.failure( 'Failed to fetch sales: $e');
    }
  }

  @override
  Future<Result<Sale>> getSaleById(String id) async {
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) return Result.failure('Sale not found');
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(Sale.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to fetch sale: $e');
    }
  }

  @override
  Future<Result<Sale>> createSale(Sale sale) async {
    try {
      final json = sale.toJson();
      json['user_id'] = _uid;
      json['created_at'] = FieldValue.serverTimestamp();
      json.remove('id');

      // Preserve client-side ID so transactions can reference it reliably
      await _collection.doc(sale.id).set(json);
      return Result.success(sale);
    } catch (e) {
      return Result.failure( 'Failed to create sale: $e');
    }
  }

  @override
  Future<Result<Sale>> createSaleWithTransactions(
      Sale sale, List<models.Transaction> transactions) async {
    try {
      final batch = _firestore.batch();
      final now = FieldValue.serverTimestamp();

      // 1. Sale document
      final saleJson = sale.toJson();
      saleJson['user_id'] = _uid;
      saleJson['created_at'] = now;
      saleJson.remove('id');
      batch.set(_collection.doc(sale.id), saleJson);

      // 2. Associated transactions (revenue, COGS, etc.)
      final txnCollection = _firestore.collection('transactions');
      for (final txn in transactions) {
        final txnJson = txn.toJson();
        txnJson['user_id'] = _uid;
        txnJson['created_at'] = now;
        txnJson.remove('id');
        batch.set(txnCollection.doc(txn.id), txnJson);
      }

      // Atomic commit — all succeed or all fail
      await batch.commit();

      return Result.success(sale);
    } catch (e) {
      return Result.failure( 'Failed to create sale: $e');
    }
  }

  @override
  Future<Result<Sale>> createSaleWithTransactionsAndStock(
      Sale sale,
      List<models.Transaction> transactions,
      List<StockDeduction> stockDeductions) async {
    if (stockDeductions.isEmpty) {
      // No stock to adjust — fall back to the simpler batch write.
      return createSaleWithTransactions(sale, transactions);
    }

    try {
      final productsCollection = _firestore.collection('products');

      await _firestore.runTransaction((txn) async {
        // ── Phase 1: READ all affected product documents ─────────
        // Firestore requires all reads before any write in a transaction.
        final productSnapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
        for (final deduction in stockDeductions) {
          if (productSnapshots.containsKey(deduction.productId)) continue;
          final docRef = productsCollection.doc(deduction.productId);
          productSnapshots[deduction.productId] = await txn.get(docRef);
        }

        // ── Phase 2: COMPUTE stock changes ───────────────────────
        // Group deductions by product so multiple line items for the
        // same product are processed together.
        final productUpdates = <String, Product>{};

        for (final deduction in stockDeductions) {
          final snapshot = productSnapshots[deduction.productId]!;
          if (!snapshot.exists) continue;

          // Use already-computed product if we've processed another
          // deduction for the same product in this loop.
          Product product;
          if (productUpdates.containsKey(deduction.productId)) {
            product = productUpdates[deduction.productId]!;
          } else {
            final data = snapshot.data()!;
            data['id'] = snapshot.id;
            product = Product.fromJson(data);
          }

          final variantIndex =
              product.variants.indexWhere((v) => v.id == deduction.variantId);
          if (variantIndex == -1) continue;

          final variant = product.variants[variantIndex];
          final delta = -deduction.quantity;
          final newStock = variant.currentStock + delta;
          // Allow stock to go to zero — UI already warned the user
          final clampedStock = newStock < 0 ? 0 : newStock;

          // Cost layer consumption
          var layers = List<CostLayer>.from(variant.effectiveCostLayers);
          double movementUnitCost = variant.costPrice;
          final absQty = deduction.quantity;

          if (deduction.valuationMethod == 'average' || layers.isEmpty) {
            movementUnitCost = variant.costPrice;
            if (layers.isNotEmpty) {
              final totalLayerQty =
                  layers.fold<int>(0, (s, l) => s + l.remainingQty);
              if (totalLayerQty > 0) {
                final updated = <CostLayer>[];
                // Accumulator pattern: track cumulative assigned count
                // to guarantee the sum of all takes == absQty exactly.
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
            if (deduction.valuationMethod == 'lifo') {
              layers.sort((a, b) => b.date.compareTo(a.date));
            } else {
              layers.sort((a, b) => a.date.compareTo(b.date));
            }
            var remaining = absQty;
            var totalCost = 0.0;
            final updated = <CostLayer>[];
            for (final layer in layers) {
              if (remaining <= 0) { updated.add(layer); continue; }
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

          // Recalculate WAC from remaining layers
          double newCostPrice;
          final totalLayerStock =
              layers.fold<int>(0, (s, l) => s + l.remainingQty);
          if (totalLayerStock > 0) {
            final totalValue =
                layers.fold<double>(0, (s, l) => s + l.remainingQty * l.unitCost);
            newCostPrice = (totalValue / totalLayerStock * 100).roundToDouble() / 100;
          } else {
            newCostPrice = variant.costPrice;
          }

          final movement = StockMovement(
            type: 'Sale',
            quantity: delta,
            dateTime: DateTime.now(),
            variantId: deduction.variantId,
            unitCost: movementUnitCost,
          );

          final updatedVariant = variant.copyWith(
            currentStock: clampedStock,
            costPrice: newCostPrice,
            costLayers: layers,
            movements: [...variant.movements, movement],
          );

          final updatedVariants = List<ProductVariant>.from(product.variants);
          updatedVariants[variantIndex] = updatedVariant;
          productUpdates[deduction.productId] =
              product.copyWith(variants: updatedVariants, updatedAt: DateTime.now());
        }

        // ── Phase 3: WRITE everything atomically ─────────────────

        // Sale document
        final saleJson = sale.toJson();
        saleJson['user_id'] = _uid;
        saleJson['created_at'] = FieldValue.serverTimestamp();
        saleJson.remove('id');
        txn.set(_collection.doc(sale.id), saleJson);

        // Transaction documents (revenue, COGS, shipping)
        final txnCollection = _firestore.collection('transactions');
        for (final t in transactions) {
          final txnJson = t.toJson();
          txnJson['user_id'] = _uid;
          txnJson['created_at'] = FieldValue.serverTimestamp();
          txnJson.remove('id');
          txn.set(txnCollection.doc(t.id), txnJson);
        }

        // Product stock updates
        for (final entry in productUpdates.entries) {
          final json = entry.value.toJson();
          json.remove('id');
          json['updated_at'] = DateTime.now().toIso8601String();
          json['_last_modified_by'] = 'masari';
          txn.update(productsCollection.doc(entry.key), json);
        }
      });

      return Result.success(sale);
    } catch (e) {
      return Result.failure('Failed to create sale: $e');
    }
  }

  @override
  Future<Result<Sale>> createSaleWithTransactionsAndStockBatch(
      Sale sale,
      List<models.Transaction> transactions,
      List<StockDeduction> stockDeductions) async {
    if (stockDeductions.isEmpty) {
      return createSaleWithTransactions(sale, transactions);
    }

    try {
      final productsCollection = _firestore.collection('products');
      final batch = _firestore.batch();
      final now = FieldValue.serverTimestamp();

      // ── Phase 1: READ product documents (served from cache when offline) ──
      final productSnapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final deduction in stockDeductions) {
        if (productSnapshots.containsKey(deduction.productId)) continue;
        final docRef = productsCollection.doc(deduction.productId);
        productSnapshots[deduction.productId] = await docRef.get();
      }

      // ── Phase 2: COMPUTE stock changes using shared helper ──
      final productUpdates = <String, Product>{};

      for (final deduction in stockDeductions) {
        final snapshot = productSnapshots[deduction.productId]!;
        if (!snapshot.exists) continue;

        Product product;
        if (productUpdates.containsKey(deduction.productId)) {
          product = productUpdates[deduction.productId]!;
        } else {
          final data = snapshot.data()!;
          data['id'] = snapshot.id;
          product = Product.fromJson(data);
        }

        final result = computeStockChange(
          product: product,
          variantId: deduction.variantId,
          delta: -deduction.quantity,
          valuationMethod: deduction.valuationMethod,
          reason: 'Sale',
        );
        productUpdates[deduction.productId] = result.updatedProduct;
      }

      // ── Phase 3: WRITE everything via batch ──

      // Sale document
      final saleJson = sale.toJson();
      saleJson['user_id'] = _uid;
      saleJson['created_at'] = now;
      saleJson.remove('id');
      batch.set(_collection.doc(sale.id), saleJson);

      // Transaction documents (revenue, COGS, shipping)
      final txnCollection = _firestore.collection('transactions');
      for (final t in transactions) {
        final txnJson = t.toJson();
        txnJson['user_id'] = _uid;
        txnJson['created_at'] = now;
        txnJson.remove('id');
        batch.set(txnCollection.doc(t.id), txnJson);
      }

      // Product stock updates
      for (final entry in productUpdates.entries) {
        final json = entry.value.toJson();
        json.remove('id');
        json['updated_at'] = DateTime.now().toIso8601String();
        json['_last_modified_by'] = 'masari';
        batch.update(productsCollection.doc(entry.key), json);
      }

      await batch.commit();

      return Result.success(sale);
    } catch (e) {
      return Result.failure('Failed to create sale (batch): $e');
    }
  }

  @override
  Future<Result<Sale>> updateSale(String id, Sale updated) async {
    try {
      final json = updated.toJson();
      json['user_id'] = _uid;
      json['updated_at'] = FieldValue.serverTimestamp();
      json.remove('id');

      await _collection.doc(id).update(json);
      return Result.success(updated);
    } catch (e) {
      return Result.failure( 'Failed to update sale: $e');
    }
  }

  @override
  Future<Result<void>> deleteSale(String id) async {
    try {
      await _collection.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete sale: $e');
    }
  }
}
