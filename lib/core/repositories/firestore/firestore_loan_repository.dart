import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/loan_model.dart';
import '../../services/result.dart';
import '../loan_repository.dart';

/// Firestore implementation — stores documents at
/// `loans/{uid}/items/{loanId}`.
class FirestoreLoanRepository implements LoanRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not authenticated');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('loans').doc(_uid).collection('items');

  @override
  Future<Result<List<Loan>>> getAll() async {
    try {
      final snap = await _col.orderBy('start_date', descending: true).get();
      final loans = snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return Loan.fromJson(data);
      }).toList();
      return Result.success(loans);
    } catch (e) {
      return Result.failure('Failed to load loans: $e');
    }
  }

  @override
  Future<Result<Loan>> getById(String id) async {
    try {
      final doc = await _col.doc(id).get();
      if (!doc.exists) return Result.failure('Loan not found');
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(Loan.fromJson(data));
    } catch (e) {
      return Result.failure('Failed to load loan: $e');
    }
  }

  @override
  Future<Result<Loan>> create(Loan loan) async {
    try {
      final ref = _col.doc();
      final created = loan.copyWith(
        id: ref.id,
        createdAt: DateTime.now(),
      );
      await ref.set(created.toJson());
      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create loan: $e');
    }
  }

  @override
  Future<Result<Loan>> update(Loan loan) async {
    try {
      final updated = loan.copyWith(updatedAt: DateTime.now());
      await _col.doc(loan.id).update(updated.toJson());
      return Result.success(updated);
    } catch (e) {
      return Result.failure('Failed to update loan: $e');
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      await _col.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete loan: $e');
    }
  }
}
