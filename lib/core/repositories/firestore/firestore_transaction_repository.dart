import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../shared/models/transaction_model.dart';
import '../../services/result.dart';
import '../transaction_repository.dart';

/// Firestore implementation of [TransactionRepository].
class FirestoreTransactionRepository implements TransactionRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// Cached cursor from the last page for efficient pagination.
  DocumentSnapshot? _lastCursor;

  /// In-memory cache for [getTransactionsInRange] queries.
  /// Keyed by "startMs_endMs". Caches the Future itself so concurrent
  /// callers with the same range share a single Firestore round-trip.
  final Map<String, Future<Result<List<Transaction>>>> _rangeCache = {};

  @override
  void clearRangeCache() => _rangeCache.clear();

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('transactions');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<List<Transaction>>> getTransactions({
    TransactionFilter? filter,
    int? limit,
    String? startAfterId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      Query<Map<String, dynamic>> query =
          _collection.where('user_id', isEqualTo: _uid);

      final hasDateBounds = startDate != null || endDate != null;

      // Apply type filter (server-side only when no supplier filter AND no
      // date bounds, because Firestore disallows inequality filters on
      // different fields in the same query).
      final hasTypeFilter = filter != null && filter.type != TransactionType.all;
      final hasSupplierFilter = filter != null && filter.onlySuppliers;
      final canServerType = hasTypeFilter && !hasSupplierFilter && !hasDateBounds;
      if (canServerType) {
        if (filter.type == TransactionType.income) {
          query = query.where('amount', isGreaterThan: 0);
        } else {
          query = query.where('amount', isLessThan: 0);
        }
      }

      // Apply supplier filter (server-side only when type filter is off)
      if (hasSupplierFilter && !hasTypeFilter) {
        query = query.where('supplier_id', isNull: false);
      }

      // Apply category filter server-side when <= 30 categories and no
      // inequality filter is active (Firestore can't combine whereIn with
      // inequality on a different field).
      final canServerCategory = filter != null &&
          filter.selectedCategories.isNotEmpty &&
          filter.selectedCategories.length <= 30 &&
          !hasTypeFilter &&
          !hasDateBounds;
      if (canServerCategory) {
        query = query.where('category_id',
            whereIn: filter.selectedCategories.toList());
      }

      // Server-side date bounds — dramatically reduces reads for large datasets.
      // Inequality on date_time is compatible with equality on user_id and
      // orderBy on the same field (uses the user_id + date_time composite index).
      if (startDate != null) {
        query = query.where('date_time',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }
      if (endDate != null) {
        query = query.where('date_time',
            isLessThanOrEqualTo: Timestamp.fromDate(endDate));
      }

      // Order by date descending
      query = query.orderBy('date_time', descending: true);

      // Cursor-based pagination
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

      // Determine if client-side filters will still be applied
      final hasClientSideFilter = filter != null &&
          ((hasTypeFilter && !canServerType) ||
              (!canServerCategory && filter.selectedCategories.isNotEmpty) ||
              filter.amountRange.start > 0 ||
              filter.amountRange.end < double.infinity);

      // Over-fetch only when client-side filters remain active
      final fetchLimit = (limit != null && hasClientSideFilter) ? limit * 3 : limit;

      // Apply limit
      if (fetchLimit != null) {
        query = query.limit(fetchLimit);
      }

      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await query.get();
      } catch (_) {
        // Index may not be ready — fall back to unordered query
        Query<Map<String, dynamic>> fallback =
            _collection.where('user_id', isEqualTo: _uid);
        if (fetchLimit != null) fallback = fallback.limit(fetchLimit);
        snapshot = await fallback.get();
      }

      // Cache last doc for the next loadMore() call.
      if (snapshot.docs.isNotEmpty) {
        _lastCursor = snapshot.docs.last;
      }

      List<Transaction> transactions = <Transaction>[];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          data['id'] = doc.id;
          transactions.add(Transaction.fromJson(data));
        } catch (e) {
          if (kDebugMode) debugPrint('[TxnRepo] Failed to parse transaction ${doc.id}: $e');
        }
      }

      // Apply client-side filters that can't be combined as Firestore queries
      if (filter != null) {
        // Type filter applied client-side when it couldn't be server-side
        // (when supplier filter or date bounds prevented it)
        if (hasTypeFilter && !canServerType) {
          if (filter.type == TransactionType.income) {
            transactions = transactions.where((t) => t.amount > 0).toList();
          } else {
            transactions = transactions.where((t) => t.amount < 0).toList();
          }
        }

        // Supplier filter applied client-side when type filter prevented it
        if (hasSupplierFilter && hasTypeFilter) {
          transactions = transactions.where((t) => t.supplierId != null).toList();
        }

        // Category filter (skip if already applied server-side)
        if (!canServerCategory && filter.selectedCategories.isNotEmpty) {
          transactions = transactions
              .where((t) => filter.selectedCategories.contains(t.categoryId))
              .toList();
        }

        // Amount range filter
        if (filter.amountRange.start > 0 ||
            filter.amountRange.end < double.infinity) {
          transactions = transactions.where((t) {
            final abs = t.amount.abs();
            return abs >= filter.amountRange.start &&
                abs <= filter.amountRange.end;
          }).toList();
        }
      }

      // Client-side sort ensures correct order even with fallback query
      transactions.sort((a, b) => b.dateTime.compareTo(a.dateTime));

      // Trim to originally requested limit after client-side filtering
      if (limit != null && transactions.length > limit) {
        transactions = transactions.sublist(0, limit);
      }

      return Result.success(transactions);
    } catch (e) {
      return Result.failure( 'Failed to fetch transactions: $e');
    }
  }

  @override
  Future<Result<Transaction>> getTransactionById(String id) async {
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) {
        return Result.failure('Transaction not found');
      }
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(Transaction.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to fetch transaction: $e');
    }
  }

  @override
  Future<Result<Transaction>> createTransaction(
      Transaction transaction) async {
    try {
      final json = transaction.toJson();
      json['user_id'] = _uid;
      json['created_at'] = FieldValue.serverTimestamp();
      json.remove('id');

      // Preserve client-side ID so sale↔transaction linking survives Firestore reload
      await _collection.doc(transaction.id).set(json);
      _rangeCache.clear();
      return Result.success(transaction);
    } catch (e) {
      return Result.failure( 'Failed to create transaction: $e');
    }
  }

  @override
  Future<Result<Transaction>> updateTransaction(
      Transaction transaction) async {
    try {
      final json = transaction.toJson();
      json['user_id'] = _uid;
      json['updated_at'] = FieldValue.serverTimestamp();
      json.remove('id');

      await _collection.doc(transaction.id).update(json);
      _rangeCache.clear();
      return Result.success(transaction);
    } catch (e) {
      return Result.failure( 'Failed to update transaction: $e');
    }
  }

  @override
  Future<Result<void>> deleteTransaction(String id) async {
    try {
      await _collection.doc(id).delete();
      _rangeCache.clear();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete transaction: $e');
    }
  }

  @override
  Future<Result<List<Transaction>>> getTransactionsInRange({
    required DateTime start,
    required DateTime end,
  }) {
    final key = '${start.millisecondsSinceEpoch}_${end.millisecondsSinceEpoch}';
    final cached = _rangeCache[key];
    if (cached != null) return cached;

    final future = _doGetTransactionsInRange(start, end);
    _rangeCache[key] = future;
    // Evict on failure so the next call retries
    future.then((r) { if (!r.isSuccess) _rangeCache.remove(key); });
    return future;
  }

  Future<Result<List<Transaction>>> _doGetTransactionsInRange(
      DateTime start, DateTime end) async {
    try {
      final startTs = Timestamp.fromDate(start);
      final endTs = Timestamp.fromDate(end);

      final query = _collection
          .where('user_id', isEqualTo: _uid)
          .where('date_time', isGreaterThanOrEqualTo: startTs)
          .where('date_time', isLessThanOrEqualTo: endTs)
          .orderBy('date_time', descending: true);

      // Try disk cache first for instant startup / period switching,
      // then update from server in the background.
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await query.get(const GetOptions(source: Source.cache));
      } catch (_) {
        // Cache miss — fall through to server.
        snapshot = await query.get();
      }

      final transactions = _parseSnapshots(snapshot);

      // If we got data from cache, kick off a background server fetch
      // so the Firestore disk cache stays fresh for next time.
      if (snapshot.metadata.isFromCache && transactions.isNotEmpty) {
        query.get(const GetOptions(source: Source.server)).then((_) {},
            onError: (_) {});
      }

      return Result.success(transactions);
    } catch (e) {
      return Result.failure('Failed to fetch transactions in range: $e');
    }
  }

  List<Transaction> _parseSnapshots(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    final transactions = <Transaction>[];
    for (final doc in snapshot.docs) {
      try {
        final data = doc.data();
        data['id'] = doc.id;
        transactions.add(Transaction.fromJson(data));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[TxnRepo] Failed to parse transaction ${doc.id}: $e');
        }
      }
    }
    return transactions;
  }

  @override
  Future<Result<void>> reassignCategory(
      String oldCategoryId, String newCategoryId) async {
    try {
      // Paginated reassign — avoids loading all matching docs at once
      const pageSize = 500;
      while (true) {
        final snapshot = await _collection
            .where('user_id', isEqualTo: _uid)
            .where('category_id', isEqualTo: oldCategoryId)
            .limit(pageSize)
            .get();
        if (snapshot.docs.isEmpty) break;

        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.update(doc.reference, {
            'category_id': newCategoryId,
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }

      _rangeCache.clear();
      return Result.success(null);
    } catch (e) {
      return Result.failure('Failed to reassign transactions: $e');
    }
  }
}
