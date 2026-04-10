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

  /// Cached cursor from the last page for efficient pagination.
  DocumentSnapshot? _lastCursor;

  /// In-memory cache for [getSalesInRange] queries.
  final Map<String, Future<Result<List<Sale>>>> _rangeCache = {};

  /// Optional callback to invalidate transaction range cache when sale
  /// mutations also write transaction documents.
  VoidCallback? onTransactionCacheInvalidated;

  @override
  void clearRangeCache() => _rangeCache.clear();

  void _invalidateAll() {
    _rangeCache.clear();
    onTransactionCacheInvalidated?.call();
  }

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('sales');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<List<Sale>>> getSales({
    int? limit,
    String? startAfterId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query<Map<String, dynamic>> query =
          _collection.where('user_id', isEqualTo: _uid);

      // Server-side date bounds — dramatically reduces reads for large datasets
      if (startDate != null) {
        query = query.where('date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      if (endDate != null) {
        query = query.where('date',
            isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }

      query = query.orderBy('date', descending: true);

      if (startAfterId != null) {
        // Reuse cached cursor when it matches, avoiding an extra Firestore read.
        DocumentSnapshot? cursor = _lastCursor;
        if (cursor == null || cursor.id != startAfterId) {
          cursor = await _collection.doc(startAfterId).get();
        }
        if (cursor.exists) {
          query = query.startAfterDocument(cursor);
        }
      }

      if (limit != null) query = query.limit(limit);

      final snapshot = await query.get();

      // Cache last doc for the next loadMore() call.
      if (snapshot.docs.isNotEmpty) {
        _lastCursor = snapshot.docs.last;
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

      return Result.success(sales);
    } catch (e) {
      return Result.failure( 'Failed to fetch sales: $e');
    }
  }

  @override
  Future<Result<List<Sale>>> getSalesInRange({
    required DateTime start,
    required DateTime end,
  }) {
    final key = '${start.millisecondsSinceEpoch}_${end.millisecondsSinceEpoch}';
    final cached = _rangeCache[key];
    if (cached != null) return cached;

    final future = _doGetSalesInRange(start, end);
    _rangeCache[key] = future;
    future.then((r) { if (!r.isSuccess) _rangeCache.remove(key); });
    return future;
  }

  Future<Result<List<Sale>>> _doGetSalesInRange(
      DateTime start, DateTime end) async {
    try {
      final startTs = Timestamp.fromDate(start);
      final endTs = Timestamp.fromDate(end);

      final snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .where('date', isGreaterThanOrEqualTo: startTs)
          .where('date', isLessThanOrEqualTo: endTs)
          .orderBy('date', descending: true)
          .get();

      final sales = <Sale>[];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          data['id'] = doc.id;
          sales.add(Sale.fromJson(data));
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[SaleRepo] Failed to parse sale ${doc.id}: $e');
          }
        }
      }
      return Result.success(sales);
    } catch (e) {
      return Result.failure('Failed to fetch sales in range: $e');
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
      _rangeCache.clear();
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

      _invalidateAll();
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

          final result = computeStockChange(
            product: product,
            variantId: deduction.variantId,
            delta: -deduction.quantity,
            valuationMethod: deduction.valuationMethod,
            reason: 'Sale',
          );
          productUpdates[deduction.productId] = result.updatedProduct;
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

      _invalidateAll();
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

      _invalidateAll();
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
      _rangeCache.clear();
      return Result.success(updated);
    } catch (e) {
      return Result.failure( 'Failed to update sale: $e');
    }
  }

  @override
  Future<Result<void>> deleteSale(String id) async {
    try {
      await _collection.doc(id).delete();
      _rangeCache.clear();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete sale: $e');
    }
  }
}
