import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/supplier_model.dart';
import '../../services/result.dart';
import '../supplier_repository.dart';

/// Firestore implementation of [SupplierRepository].
class FirestoreSupplierRepository implements SupplierRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('suppliers');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<List<Supplier>>> getSuppliers({
    int? limit,
    String? startAfterId,
  }) async {
    try {
      Query<Map<String, dynamic>> query =
          _collection.where('user_id', isEqualTo: _uid).orderBy('name');

      if (startAfterId != null) {
        final cursorDoc = await _collection.doc(startAfterId).get();
        if (cursorDoc.exists) {
          query = query.startAfterDocument(cursorDoc);
        }
      }

      if (limit != null) query = query.limit(limit);

      final snapshot = await query.get();
      final suppliers = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Supplier.fromJson(data);
      }).toList();

      return Result.success(suppliers);
    } catch (e) {
      return Result.failure( 'Failed to fetch suppliers: $e');
    }
  }

  @override
  Future<Result<Supplier>> getSupplierById(String id) async {
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) return Result.failure('Supplier not found');
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(Supplier.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to fetch supplier: $e');
    }
  }

  @override
  Future<Result<Supplier>> createSupplier(Supplier supplier) async {
    try {
      final json = supplier.toJson();
      json['user_id'] = _uid;
      json['created_at'] = DateTime.now().toIso8601String();
      final id = supplier.id;
      json.remove('id');

      await _collection.doc(id).set(json);
      json['id'] = id;
      return Result.success(Supplier.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to create supplier: $e');
    }
  }

  @override
  Future<Result<Supplier>> updateSupplier(String id, Supplier updated) async {
    try {
      final json = updated.toJson();
      json['user_id'] = _uid;
      json['updated_at'] = DateTime.now().toIso8601String();
      json.remove('id');

      await _collection.doc(id).update(json);
      json['id'] = id;
      return Result.success(Supplier.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to update supplier: $e');
    }
  }

  @override
  Future<Result<void>> deleteSupplier(String id) async {
    try {
      await _collection.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete supplier: $e');
    }
  }

  @override
  Future<Result<Supplier>> recordPayment(String id, double amount) async {
    try {
      // Atomic balance update via Firestore transaction
      final result = await _firestore.runTransaction<Supplier>((txn) async {
        final docRef = _collection.doc(id);
        final snapshot = await txn.get(docRef);

        if (!snapshot.exists) throw Exception('Supplier not found');

        final data = snapshot.data()!;
        data['id'] = snapshot.id;
        final supplier = Supplier.fromJson(data);
        final newBalance = supplier.balance - amount;

        txn.update(docRef, {
          'balance': newBalance,
          'last_transaction': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });

        return supplier.copyWith(
          balance: newBalance,
          lastTransaction: DateTime.now(),
        );
      });

      return Result.success(result);
    } catch (e) {
      return Result.failure( 'Failed to record payment: $e');
    }
  }

  @override
  Future<Result<Supplier>> recordPurchase(String id, double amount, {DateTime? dueDate}) async {
    try {
      final result = await _firestore.runTransaction<Supplier>((txn) async {
        final docRef = _collection.doc(id);
        final snapshot = await txn.get(docRef);

        if (!snapshot.exists) throw Exception('Supplier not found');

        final data = snapshot.data()!;
        data['id'] = snapshot.id;
        final supplier = Supplier.fromJson(data);
        final newBalance = supplier.balance + amount;

        final updates = <String, dynamic>{
          'balance': newBalance,
          'last_transaction': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        if (dueDate != null) {
          // Only update dueDate if the new one is later than the current one
          if (supplier.dueDate == null || dueDate.isAfter(supplier.dueDate!)) {
            updates['due_date'] = dueDate.toIso8601String();
          }
        }

        txn.update(docRef, updates);

        return supplier.copyWith(
          balance: newBalance,
          lastTransaction: DateTime.now(),
          dueDate: dueDate != null &&
                  (supplier.dueDate == null || dueDate.isAfter(supplier.dueDate!))
              ? dueDate
              : supplier.dueDate,
        );
      });

      return Result.success(result);
    } catch (e) {
      return Result.failure('Failed to record purchase: $e');
    }
  }
}
