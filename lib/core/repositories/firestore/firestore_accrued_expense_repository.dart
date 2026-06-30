import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/accrued_expense_model.dart';
import '../../services/result.dart';
import '../accrued_expense_repository.dart';

/// Firestore implementation — stores documents at
/// `accrued_expenses/{uid}/items/{id}`.
class FirestoreAccruedExpenseRepository implements AccruedExpenseRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not authenticated');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _col => _firestore
      .collection('accrued_expenses')
      .doc(_uid)
      .collection('items');

  @override
  Future<Result<List<AccruedExpense>>> getAll() async {
    try {
      final snap = await _col.orderBy('created_at', descending: true).get();
      final items = snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return AccruedExpense.fromJson(data);
      }).toList();
      return Result.success(items);
    } catch (e) {
      return Result.failure('Failed to load accrued expenses: $e');
    }
  }

  @override
  Future<Result<AccruedExpense>> getById(String id) async {
    try {
      final doc = await _col.doc(id).get();
      if (!doc.exists) return Result.failure('Accrued expense not found');
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(AccruedExpense.fromJson(data));
    } catch (e) {
      return Result.failure('Failed to load accrued expense: $e');
    }
  }

  @override
  Future<Result<AccruedExpense>> create(AccruedExpense expense) async {
    try {
      final ref = _col.doc();
      final created =
          expense.copyWith(id: ref.id, createdAt: DateTime.now());
      await ref.set(created.toJson());
      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create accrued expense: $e');
    }
  }

  @override
  Future<Result<AccruedExpense>> update(AccruedExpense expense) async {
    try {
      final updated = expense.copyWith(updatedAt: DateTime.now());
      await _col.doc(expense.id).update(updated.toJson());
      return Result.success(updated);
    } catch (e) {
      return Result.failure('Failed to update accrued expense: $e');
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      await _col.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete accrued expense: $e');
    }
  }
}
