import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/goods_receipt_model.dart';
import '../../services/result.dart';
import '../goods_receipt_repository.dart';

/// Firestore implementation of [GoodsReceiptRepository].
class FirestoreGoodsReceiptRepository implements GoodsReceiptRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('goods_receipts');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<List<GoodsReceipt>>> getReceipts(
      {int? limit, String? startAfterId}) async {
    try {
      developer.log('[GoodsReceiptRepo] getReceipts – uid=$_uid');
      Query<Map<String, dynamic>> query =
          _collection.where('user_id', isEqualTo: _uid)
              .orderBy('date', descending: true);
      query = query.limit(limit ?? 500);

      final snapshot = await query.get();
      developer.log('[GoodsReceiptRepo] docs found: ${snapshot.docs.length}');
      final receipts = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return GoodsReceipt.fromJson(data);
      }).toList();

      return Result.success(receipts);
    } catch (e) {
      developer.log('[GoodsReceiptRepo] getReceipts ERROR: $e');
      return Result.failure( 'Failed to fetch receipts: $e');
    }
  }

  @override
  Future<Result<List<GoodsReceipt>>> getReceiptsForSupplier(
      String supplierId) async {
    try {
      developer.log('[GoodsReceiptRepo] getReceiptsForSupplier – sid=$supplierId');
      final snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .where('supplier_id', isEqualTo: supplierId)
          .orderBy('date', descending: true)
          .limit(500)
          .get();

      final receipts = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return GoodsReceipt.fromJson(data);
      }).toList();

      return Result.success(receipts);
    } catch (e) {
      developer.log('[GoodsReceiptRepo] getReceiptsForSupplier ERROR: $e');
      return Result.failure( 'Failed to fetch receipts for supplier: $e');
    }
  }

  @override
  Future<Result<GoodsReceipt>> getReceiptById(String id) async {
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) return Result.failure( 'Receipt not found');
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(GoodsReceipt.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to fetch receipt: $e');
    }
  }

  @override
  Future<Result<GoodsReceipt>> createReceipt(GoodsReceipt receipt) async {
    try {
      final json = receipt.toJson();
      json['user_id'] = _uid;
      json['created_at'] = DateTime.now().toIso8601String();
      final id = receipt.id;
      json.remove('id');

      await _collection.doc(id).set(json);
      json['id'] = id;
      developer.log('[GoodsReceiptRepo] created receipt $id');
      return Result.success(GoodsReceipt.fromJson(json));
    } catch (e) {
      developer.log('[GoodsReceiptRepo] createReceipt ERROR: $e');
      return Result.failure( 'Failed to create receipt: $e');
    }
  }

  @override
  Future<Result<GoodsReceipt>> updateReceipt(
      String id, GoodsReceipt updated) async {
    try {
      final json = updated.toJson();
      json['user_id'] = _uid;
      json['updated_at'] = DateTime.now().toIso8601String();
      json.remove('id');

      await _collection.doc(id).update(json);
      json['id'] = id;
      return Result.success(GoodsReceipt.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to update receipt: $e');
    }
  }

  @override
  Future<Result<void>> deleteReceipt(String id) async {
    try {
      await _collection.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete receipt: $e');
    }
  }
}
