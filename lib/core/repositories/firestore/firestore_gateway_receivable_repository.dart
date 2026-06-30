import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/gateway_receivable_model.dart';
import '../../services/result.dart';
import '../gateway_receivable_repository.dart';

/// Firestore implementation — stores documents at
/// `gateway_receivables/{uid}/items/{id}`.
class FirestoreGatewayReceivableRepository
    implements GatewayReceivableRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not authenticated');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _col => _firestore
      .collection('gateway_receivables')
      .doc(_uid)
      .collection('items');

  @override
  Future<Result<List<GatewayReceivable>>> getAll() async {
    try {
      final snap = await _col.orderBy('created_at', descending: true).get();
      final items = snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return GatewayReceivable.fromJson(data);
      }).toList();
      return Result.success(items);
    } catch (e) {
      return Result.failure('Failed to load gateway receivables: $e');
    }
  }

  @override
  Future<Result<GatewayReceivable>> getById(String id) async {
    try {
      final doc = await _col.doc(id).get();
      if (!doc.exists) return Result.failure('Gateway receivable not found');
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(GatewayReceivable.fromJson(data));
    } catch (e) {
      return Result.failure('Failed to load gateway receivable: $e');
    }
  }

  @override
  Future<Result<GatewayReceivable>> create(
      GatewayReceivable receivable) async {
    try {
      final ref = _col.doc();
      final created =
          receivable.copyWith(id: ref.id, createdAt: DateTime.now());
      await ref.set(created.toJson());
      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create gateway receivable: $e');
    }
  }

  @override
  Future<Result<GatewayReceivable>> update(
      GatewayReceivable receivable) async {
    try {
      final updated = receivable.copyWith(updatedAt: DateTime.now());
      await _col.doc(receivable.id).update(updated.toJson());
      return Result.success(updated);
    } catch (e) {
      return Result.failure('Failed to update gateway receivable: $e');
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      await _col.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete gateway receivable: $e');
    }
  }
}
