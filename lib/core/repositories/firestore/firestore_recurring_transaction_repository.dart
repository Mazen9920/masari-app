import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../features/cash_flow/models/recurring_transaction_model.dart';
import '../../services/result.dart';
import '../recurring_transaction_repository.dart';

/// Firestore implementation of [RecurringTransactionRepository].
class FirestoreRecurringTransactionRepository
    implements RecurringTransactionRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('recurring_transactions');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<List<RecurringTransaction>>> getRecurringTransactions() async {
    try {
      final snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .orderBy('next_due_date')
          .get();

      final transactions = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return RecurringTransaction.fromJson(data);
      }).toList();

      return Result.success(transactions);
    } catch (e) {
      return Result.failure( 'Failed to fetch recurring transactions: $e');
    }
  }

  @override
  Future<Result<RecurringTransaction>> createRecurringTransaction(
    RecurringTransaction transaction,
  ) async {
    try {
      final json = transaction.toJson();
      json['user_id'] = _uid;
      json['created_at'] = DateTime.now().toIso8601String();
      final id = transaction.id;
      json.remove('id');

      await _collection.doc(id).set(json);
      json['id'] = id;
      return Result.success(RecurringTransaction.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to create recurring transaction: $e');
    }
  }

  @override
  Future<Result<RecurringTransaction>> updateRecurringTransaction(
    String id,
    RecurringTransaction updated,
  ) async {
    try {
      final json = updated.toJson();
      json['user_id'] = _uid;
      json['updated_at'] = DateTime.now().toIso8601String();
      json.remove('id');

      await _collection.doc(id).update(json);
      json['id'] = id;
      return Result.success(RecurringTransaction.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to update recurring transaction: $e');
    }
  }

  @override
  Future<Result<void>> deleteRecurringTransaction(String id) async {
    try {
      await _collection.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete recurring transaction: $e');
    }
  }

  @override
  Future<Result<RecurringTransaction>> toggleActive(
      String id, bool active) async {
    try {
      await _collection.doc(id).update({
        'is_active': active,
        'updated_at': DateTime.now().toIso8601String(),
      });

      final doc = await _collection.doc(id).get();
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(RecurringTransaction.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to toggle recurring transaction: $e');
    }
  }
}
