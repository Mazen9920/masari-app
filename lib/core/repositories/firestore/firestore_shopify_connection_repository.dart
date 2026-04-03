import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/shopify_connection_model.dart';
import '../../services/result.dart';
import '../shopify_connection_repository.dart';

/// Firestore implementation of [ShopifyConnectionRepository].
///
/// Each user has at most ONE connection document. The document ID is the
/// user's Firebase UID for easy lookup (no query needed).
class FirestoreShopifyConnectionRepository
    implements ShopifyConnectionRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('shopify_connections');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<ShopifyConnection?>> getConnection() async {
    try {
      // Direct doc lookup by UID — uses Firestore default (server when
      // online, cache when offline) for fast reads.
      final doc = await _collection.doc(_uid).get();
      if (!doc.exists || doc.data() == null) return Result.success(null);
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(ShopifyConnection.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to fetch Shopify connection: $e');
    }
  }

  /// Same as [getConnection] but forces a server round-trip.
  /// Used after OAuth to ensure we pick up the freshly-written token.
  @override
  Future<Result<ShopifyConnection?>> getConnectionFromServer() async {
    try {
      final doc = await _collection
          .doc(_uid)
          .get(const GetOptions(source: Source.server));
      if (!doc.exists || doc.data() == null) return Result.success(null);
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(ShopifyConnection.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to fetch Shopify connection: $e');
    }
  }

  @override
  Future<Result<ShopifyConnection>> saveConnection(
      ShopifyConnection connection) async {
    try {
      final json = connection.toJson();
      json['user_id'] = _uid; // enforce ownership
      final docRef = _collection.doc(_uid); // one doc per user
      // merge: true so we don't overwrite the CF-managed access_token
      await docRef.set(json, SetOptions(merge: true));
      return Result.success(connection);
    } catch (e) {
      return Result.failure( 'Failed to save Shopify connection: $e');
    }
  }

  @override
  Future<Result<ShopifyConnection>> updateConnection(
      String docId, ShopifyConnection updated) async {
    try {
      final json = updated.toJson();
      json['user_id'] = _uid; // re-inject ownership
      await _collection.doc(docId).update(json);
      return Result.success(updated);
    } catch (e) {
      return Result.failure( 'Failed to update Shopify connection: $e');
    }
  }

  @override
  Future<Result<void>> updateField(String field, dynamic value) async {
    try {
      await _collection.doc(_uid).update({field: value});
      return Result.success(null);
    } catch (e) {
      return Result.failure('Failed to update field $field: $e');
    }
  }

  @override
  Future<Result<void>> deleteConnection(String docId) async {
    try {
      await _collection.doc(docId).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete Shopify connection: $e');
    }
  }

  @override
  Stream<ShopifyConnection?> watchConnection() {
    return _collection.doc(_uid).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      final data = snap.data()!;
      data['id'] = snap.id;
      return ShopifyConnection.fromJson(data);
    });
  }
}
