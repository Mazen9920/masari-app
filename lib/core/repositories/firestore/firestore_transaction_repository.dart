import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/transaction_model.dart';
import '../../services/result.dart';
import '../transaction_repository.dart';

/// Firestore implementation of [TransactionRepository].
class FirestoreTransactionRepository implements TransactionRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

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
  }) async {
    try {
      Query<Map<String, dynamic>> query =
          _collection.where('user_id', isEqualTo: _uid);

      // Apply type filter (server-side only when supplier filter is off,
      // because Firestore disallows two inequality filters on different fields)
      final hasTypeFilter = filter != null && filter.type != TransactionType.all;
      final hasSupplierFilter = filter != null && filter.onlySuppliers;
      if (hasTypeFilter && !hasSupplierFilter) {
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

      // Order by date descending
      query = query.orderBy('date_time', descending: true);

      // Cursor-based pagination
      if (startAfterId != null) {
        final cursorDoc = await _collection.doc(startAfterId).get();
        if (cursorDoc.exists) {
          query = query.startAfterDocument(cursorDoc);
        }
      }

      // Determine if client-side filters will be applied
      final hasClientSideFilter = filter != null &&
          (filter.selectedCategories.isNotEmpty ||
              filter.amountRange.start > 0 ||
              filter.amountRange.end < double.infinity);

      // Over-fetch when client-side filters are active to compensate for
      // items that will be filtered out after the Firestore query.
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
      List<Transaction> transactions = <Transaction>[];
      for (final doc in snapshot.docs) {
        try {
          final data = doc.data();
          data['id'] = doc.id;
          transactions.add(Transaction.fromJson(data));
        } catch (e) {
          // Log and skip unparseable documents
          // ignore: avoid_print
          print('[TxnRepo] Failed to parse transaction ${doc.id}: $e');
        }
      }

      // Apply client-side filters that can't be combined as Firestore queries
      if (filter != null) {
        // Type filter applied client-side when supplier filter was server-side
        if (hasTypeFilter && hasSupplierFilter) {
          if (filter.type == TransactionType.income) {
            transactions = transactions.where((t) => t.amount > 0).toList();
          } else {
            transactions = transactions.where((t) => t.amount < 0).toList();
          }
        }

        // Supplier filter applied client-side when type filter was server-side
        if (hasSupplierFilter && hasTypeFilter) {
          transactions = transactions.where((t) => t.supplierId != null).toList();
        }

        // Category filter
        if (filter.selectedCategories.isNotEmpty) {
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
      return Result.success(transaction);
    } catch (e) {
      return Result.failure( 'Failed to update transaction: $e');
    }
  }

  @override
  Future<Result<void>> deleteTransaction(String id) async {
    try {
      await _collection.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete transaction: $e');
    }
  }

  @override
  Future<Result<void>> reassignCategory(
      String oldCategoryId, String newCategoryId) async {
    try {
      // Query ALL transactions with the old category for this user
      QuerySnapshot<Map<String, dynamic>> snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .where('category_id', isEqualTo: oldCategoryId)
          .get();

      if (snapshot.docs.isEmpty) return Result.success(null);

      // Batch update in groups of 500 (Firestore batch limit)
      final batches = <WriteBatch>[];
      var currentBatch = _firestore.batch();
      var count = 0;

      for (final doc in snapshot.docs) {
        currentBatch.update(doc.reference, {
          'category_id': newCategoryId,
          'updated_at': FieldValue.serverTimestamp(),
        });
        count++;
        if (count % 500 == 0) {
          batches.add(currentBatch);
          currentBatch = _firestore.batch();
        }
      }
      batches.add(currentBatch);

      for (final batch in batches) {
        await batch.commit();
      }

      return Result.success(null);
    } catch (e) {
      return Result.failure('Failed to reassign transactions: $e');
    }
  }
}
