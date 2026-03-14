import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/purchase_model.dart';
import '../../services/result.dart';
import '../purchase_repository.dart';

/// Firestore implementation of [PurchaseRepository].
class FirestorePurchaseRepository implements PurchaseRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('purchases');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<List<Purchase>>> getPurchases({
    String? supplierId,
    int? limit,
    String? startAfterId,
  }) async {
    try {
      Query<Map<String, dynamic>> query =
          _collection.where('user_id', isEqualTo: _uid);

      if (supplierId != null) {
        query = query.where('supplier_id', isEqualTo: supplierId);
      }

      query = query.orderBy('date', descending: true);

      if (startAfterId != null) {
        final cursorDoc = await _collection.doc(startAfterId).get();
        if (cursorDoc.exists) {
          query = query.startAfterDocument(cursorDoc);
        }
      }

      if (limit != null) query = query.limit(limit);

      final snapshot = await query.get();
      final purchases = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Purchase.fromJson(data);
      }).toList();

      return Result.success(purchases);
    } catch (e) {
      return Result.failure( 'Failed to fetch purchases: $e');
    }
  }

  @override
  Future<Result<Purchase>> getPurchaseById(String id) async {
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) return Result.failure('Purchase not found');
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(Purchase.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to fetch purchase: $e');
    }
  }

  @override
  Future<Result<Purchase>> createPurchase(Purchase purchase) async {
    try {
      final json = purchase.toJson();
      json['user_id'] = _uid;
      json['created_at'] = DateTime.now().toIso8601String();
      final id = purchase.id;
      json.remove('id');

      await _collection.doc(id).set(json);
      json['id'] = id;
      return Result.success(Purchase.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to create purchase: $e');
    }
  }

  @override
  Future<Result<Purchase>> updatePurchase(
      String id, Purchase updated) async {
    try {
      final json = updated.toJson();
      json['user_id'] = _uid;
      json.remove('id');

      await _collection.doc(id).update(json);
      json['id'] = id;
      return Result.success(Purchase.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to update purchase: $e');
    }
  }

  @override
  Future<Result<void>> deletePurchase(String id) async {
    try {
      await _collection.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete purchase: $e');
    }
  }
}
