import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/salary_model.dart';
import '../../services/result.dart';
import '../salary_repository.dart';

/// Firestore implementation — stores documents at
/// `salaries/{uid}/items/{salaryId}`.
class FirestoreSalaryRepository implements SalaryRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not authenticated');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('salaries').doc(_uid).collection('items');

  @override
  Future<Result<List<Salary>>> getAll() async {
    try {
      final snap = await _col.orderBy('start_date', descending: true).get();
      final salaries = snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return Salary.fromJson(data);
      }).toList();
      return Result.success(salaries);
    } catch (e) {
      return Result.failure('Failed to load salaries: $e');
    }
  }

  @override
  Future<Result<Salary>> getById(String id) async {
    try {
      final doc = await _col.doc(id).get();
      if (!doc.exists) return Result.failure('Salary not found');
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(Salary.fromJson(data));
    } catch (e) {
      return Result.failure('Failed to load salary: $e');
    }
  }

  @override
  Future<Result<Salary>> create(Salary salary) async {
    try {
      final ref = _col.doc();
      final created = salary.copyWith(
        id: ref.id,
        createdAt: DateTime.now(),
      );
      await ref.set(created.toJson());
      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create salary: $e');
    }
  }

  @override
  Future<Result<Salary>> update(Salary salary) async {
    try {
      final updated = salary.copyWith(updatedAt: DateTime.now());
      await _col.doc(salary.id).update(updated.toJson());
      return Result.success(updated);
    } catch (e) {
      return Result.failure('Failed to update salary: $e');
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      await _col.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete salary: $e');
    }
  }
}
