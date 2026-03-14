import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/payment_model.dart';
import '../../services/result.dart';
import '../payment_repository.dart';

/// Firestore implementation of [PaymentRepository].
class FirestorePaymentRepository implements PaymentRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('payments');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<Payment>> getPaymentById(String id) async {
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) {
        return Result.failure( 'Payment not found');
      }
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(Payment.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to fetch payment: $e');
    }
  }

  @override
  Future<Result<List<Payment>>> getPayments({
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
      final payments = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Payment.fromJson(data);
      }).toList();

      return Result.success(payments);
    } catch (e) {
      return Result.failure( 'Failed to fetch payments: $e');
    }
  }

  @override
  Future<Result<Payment>> createPayment(Payment payment) async {
    try {
      final json = payment.toJson();
      json['user_id'] = _uid;
      json['created_at'] = DateTime.now().toIso8601String();
      final id = payment.id;
      json.remove('id');

      await _collection.doc(id).set(json);
      json['id'] = id;
      return Result.success(Payment.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to create payment: $e');
    }
  }

  @override
  Future<Result<Payment>> updatePayment(String id, Payment updated) async {
    try {
      final json = updated.toJson();
      json['user_id'] = _uid;
      json.remove('id');

      await _collection.doc(id).update(json);
      json['id'] = id;
      return Result.success(Payment.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to update payment: $e');
    }
  }

  @override
  Future<Result<void>> deletePayment(String id) async {
    try {
      await _collection.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete payment: $e');
    }
  }
}
