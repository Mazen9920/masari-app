import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/fixed_asset_model.dart';
import '../../services/result.dart';
import '../fixed_asset_repository.dart';

/// Firestore implementation — stores documents at
/// `fixed_assets/{uid}/assets/{assetId}`.
class FirestoreFixedAssetRepository implements FixedAssetRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not authenticated');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('fixed_assets').doc(_uid).collection('assets');

  @override
  Future<Result<List<FixedAsset>>> getAll() async {
    try {
      final snap = await _col.orderBy('purchase_date', descending: true).get();
      final assets = snap.docs.map((d) {
        final data = d.data();
        data['id'] = d.id;
        return FixedAsset.fromJson(data);
      }).toList();
      return Result.success(assets);
    } catch (e) {
      return Result.failure('Failed to load fixed assets: $e');
    }
  }

  @override
  Future<Result<FixedAsset>> getById(String id) async {
    try {
      final doc = await _col.doc(id).get();
      if (!doc.exists) return Result.failure('Asset not found');
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(FixedAsset.fromJson(data));
    } catch (e) {
      return Result.failure('Failed to load asset: $e');
    }
  }

  @override
  Future<Result<FixedAsset>> create(FixedAsset asset) async {
    try {
      final ref = _col.doc();
      final created = asset.copyWith(
        id: ref.id,
        createdAt: DateTime.now(),
      );
      await ref.set(created.toJson());
      return Result.success(created);
    } catch (e) {
      return Result.failure('Failed to create asset: $e');
    }
  }

  @override
  Future<Result<FixedAsset>> update(FixedAsset asset) async {
    try {
      final updated = asset.copyWith(updatedAt: DateTime.now());
      await _col.doc(asset.id).update(updated.toJson());
      return Result.success(updated);
    } catch (e) {
      return Result.failure('Failed to update asset: $e');
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      await _col.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete asset: $e');
    }
  }
}
