import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/conversion_order_model.dart';
import '../../services/result.dart';
import '../conversion_order_repository.dart';

/// Firestore implementation of [ConversionOrderRepository].
class FirestoreConversionOrderRepository implements ConversionOrderRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('conversion_orders');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<List<ConversionOrder>>> getOrders({int? limit}) async {
    try {
      Query<Map<String, dynamic>> query =
          _collection.where('user_id', isEqualTo: _uid);
      if (limit != null) query = query.limit(limit);

      final snapshot = await query.get();
      final orders = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return ConversionOrder.fromJson(data);
      }).toList();

      orders.sort((a, b) => b.date.compareTo(a.date));
      return Result.success(orders);
    } catch (e) {
      return Result.failure( 'Failed to fetch conversion orders: $e');
    }
  }

  @override
  Future<Result<List<ConversionOrder>>> getOrdersForProduct(
      String productId) async {
    try {
      final snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .where('product_id', isEqualTo: productId)
          .get();

      final orders = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return ConversionOrder.fromJson(data);
      }).toList();

      orders.sort((a, b) => b.date.compareTo(a.date));
      return Result.success(orders);
    } catch (e) {
      return Result.failure( 'Failed to fetch conversion orders: $e');
    }
  }

  @override
  Future<Result<ConversionOrder>> createOrder(ConversionOrder order) async {
    try {
      final json = order.toJson();
      json['user_id'] = _uid;
      json['created_at'] = DateTime.now().toIso8601String();
      final id = order.id;
      json.remove('id');

      await _collection.doc(id).set(json);
      json['id'] = id;
      return Result.success(ConversionOrder.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to create conversion order: $e');
    }
  }

  @override
  Future<Result<void>> deleteOrder(String id) async {
    try {
      await _collection.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete conversion order: $e');
    }
  }
}
