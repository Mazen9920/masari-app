import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/production_order_model.dart';
import '../../services/result.dart';
import '../production_order_repository.dart';

/// Firestore implementation of [ProductionOrderRepository].
class FirestoreProductionOrderRepository implements ProductionOrderRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('production_orders');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<List<ProductionOrder>>> getOrders({int? limit}) async {
    try {
      Query<Map<String, dynamic>> query = _collection
          .where('user_id', isEqualTo: _uid)
          .orderBy('started_at', descending: true);
      query = query.limit(limit ?? 500);

      final snapshot = await query.get();
      final orders = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return ProductionOrder.fromJson(data);
      }).toList();
      return Result.success(orders);
    } catch (e) {
      return Result.failure('Failed to fetch production orders: $e');
    }
  }

  @override
  Future<Result<List<ProductionOrder>>> getOrdersForProduct(
      String productId) async {
    try {
      final snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .where('product_id', isEqualTo: productId)
          .orderBy('started_at', descending: true)
          .limit(500)
          .get();

      final orders = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return ProductionOrder.fromJson(data);
      }).toList();
      return Result.success(orders);
    } catch (e) {
      return Result.failure('Failed to fetch production orders: $e');
    }
  }

  @override
  Future<Result<ProductionOrder>> createOrder(ProductionOrder order) async {
    try {
      final json = order.toJson();
      json['user_id'] = _uid;
      json['created_at'] = DateTime.now().toIso8601String();
      final id = order.id;
      json.remove('id');

      await _collection.doc(id).set(json);
      json['id'] = id;
      return Result.success(ProductionOrder.fromJson(json));
    } catch (e) {
      return Result.failure('Failed to create production order: $e');
    }
  }

  @override
  Future<Result<ProductionOrder>> updateOrder(ProductionOrder order) async {
    try {
      final json = order.toJson();
      json['user_id'] = _uid;
      json['updated_at'] = DateTime.now().toIso8601String();
      final id = order.id;
      json.remove('id');

      await _collection.doc(id).set(json, SetOptions(merge: true));
      json['id'] = id;
      return Result.success(ProductionOrder.fromJson(json));
    } catch (e) {
      return Result.failure('Failed to update production order: $e');
    }
  }

  @override
  Future<Result<void>> deleteOrder(String id) async {
    try {
      await _collection.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure('Failed to delete production order: $e');
    }
  }
}
