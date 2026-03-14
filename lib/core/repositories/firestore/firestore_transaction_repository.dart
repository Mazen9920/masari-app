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

      // Apply type filter
      if (filter != null && filter.type != TransactionType.all) {
        if (filter.type == TransactionType.income) {
          query = query.where('amount', isGreaterThan: 0);
        } else {
          query = query.where('amount', isLessThan: 0);
        }
      }

      // Apply supplier filter
      if (filter != null && filter.onlySuppliers) {
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

      // Apply limit
      if (limit != null) {
        query = query.limit(limit);
      }

      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await query.get();
      } catch (_) {
        // Index may not be ready — fall back to unordered query
        Query<Map<String, dynamic>> fallback =
            _collection.where('user_id', isEqualTo: _uid);
        if (limit != null) fallback = fallback.limit(limit);
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
}
