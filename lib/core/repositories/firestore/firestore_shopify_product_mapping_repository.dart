import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/shopify_product_mapping_model.dart';
import '../../services/result.dart';
import '../shopify_product_mapping_repository.dart';

/// Firestore implementation of [ShopifyProductMappingRepository].
class FirestoreShopifyProductMappingRepository
    implements ShopifyProductMappingRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('shopify_product_mappings');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<List<ShopifyProductMapping>>> getMappings() async {
    try {
      final snapshot =
          await _collection.where('user_id', isEqualTo: _uid).get();
      final mappings = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return ShopifyProductMapping.fromJson(data);
      }).toList();
      return Result.success(mappings);
    } catch (e) {
      return Result.failure( 'Failed to fetch product mappings: $e');
    }
  }

  @override
  Future<Result<ShopifyProductMapping>> getMappingById(String id) async {
    try {
      final doc = await _collection.doc(id).get();
      if (!doc.exists) {
        return Result.failure( 'Mapping not found');
      }
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(ShopifyProductMapping.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to fetch mapping: $e');
    }
  }

  @override
  Future<Result<List<ShopifyProductMapping>>> getMappingsByShopifyVariantId(
      String shopifyVariantId) async {
    try {
      final snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .where('shopify_variant_id', isEqualTo: shopifyVariantId)
          .get();
      final mappings = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return ShopifyProductMapping.fromJson(data);
      }).toList();
      return Result.success(mappings);
    } catch (e) {
      return Result.failure( 'Failed to query mappings by Shopify variant: $e');
    }
  }

  @override
  Future<Result<ShopifyProductMapping?>> getMappingByMasariVariantId(
      String masariVariantId) async {
    try {
      final snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .where('masari_variant_id', isEqualTo: masariVariantId)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return Result.success(null);
      final data = snapshot.docs.first.data();
      data['id'] = snapshot.docs.first.id;
      return Result.success(ShopifyProductMapping.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to query mapping by Masari variant: $e');
    }
  }

  @override
  Future<Result<ShopifyProductMapping?>> getMappingByInventoryItemId(
      String shopifyInventoryItemId) async {
    try {
      final snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .where('shopify_inventory_item_id',
              isEqualTo: shopifyInventoryItemId)
          .limit(1)
          .get();
      if (snapshot.docs.isEmpty) return Result.success(null);
      final data = snapshot.docs.first.data();
      data['id'] = snapshot.docs.first.id;
      return Result.success(ShopifyProductMapping.fromJson(data));
    } catch (e) {
      return Result.failure(
           'Failed to query mapping by inventory item ID: $e');
    }
  }

  @override
  Future<Result<ShopifyProductMapping>> createMapping(
      ShopifyProductMapping mapping) async {
    try {
      final json = mapping.toJson();
      json['user_id'] = _uid; // enforce ownership
      final docRef = await _collection.add(json);
      return Result.success(mapping.copyWith(id: docRef.id));
    } catch (e) {
      return Result.failure( 'Failed to create product mapping: $e');
    }
  }

  @override
  Future<Result<List<ShopifyProductMapping>>> createMappingsBatch(
      List<ShopifyProductMapping> mappings) async {
    try {
      final batch = _firestore.batch();
      final results = <ShopifyProductMapping>[];
      for (final mapping in mappings) {
        final docRef = _collection.doc();
        final json = mapping.toJson();
        json['user_id'] = _uid;
        json['id'] = docRef.id;
        batch.set(docRef, json);
        results.add(mapping.copyWith(id: docRef.id));
      }
      await batch.commit();
      return Result.success(results);
    } catch (e) {
      return Result.failure( 'Failed to batch-create product mappings: $e');
    }
  }

  @override
  Future<Result<ShopifyProductMapping>> updateMapping(
      String id, ShopifyProductMapping updated) async {
    try {
      final json = updated.toJson();
      json['user_id'] = _uid;
      await _collection.doc(id).update(json);
      return Result.success(updated.copyWith(id: id));
    } catch (e) {
      return Result.failure( 'Failed to update product mapping: $e');
    }
  }

  @override
  Future<Result<void>> deleteMapping(String id) async {
    try {
      await _collection.doc(id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete product mapping: $e');
    }
  }

  @override
  Future<Result<void>> deleteAllMappings() async {
    try {
      final snapshot =
          await _collection.where('user_id', isEqualTo: _uid).get();
      if (snapshot.docs.isEmpty) return Result.success(null);
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete all product mappings: $e');
    }
  }
}
