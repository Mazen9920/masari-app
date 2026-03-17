import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../shared/models/category_data.dart';
import '../../services/result.dart';
import '../category_repository.dart';

/// Firestore implementation of [CategoryRepository].
/// System categories (the 20 defaults) are NOT stored in Firestore —
/// they are hardcoded in [CategoryData.all]. Only user-created custom
/// categories live in Firestore.
class FirestoreCategoryRepository implements CategoryRepository {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('categories');

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) throw StateError( 'Not authenticated');
    return user.uid;
  }

  @override
  Future<Result<List<CategoryData>>> getCategories() async {
    try {
      final snapshot =
          await _collection.where('user_id', isEqualTo: _uid).get();

      final custom = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return CategoryData.fromJson(data);
      }).toList();

      // Merge: user overrides replace system defaults by name
      final customNames = custom.map((c) => c.name).toSet();
      final merged = [
        for (final s in CategoryData.all)
          if (!customNames.contains(s.name)) s,
        ...custom,
      ];
      return Result.success(merged);
    } catch (e) {
      return Result.failure( 'Failed to fetch categories: $e');
    }
  }

  @override
  Future<Result<CategoryData>> getCategoryById(String id) async {
    try {
      // Check system categories first
      final system = CategoryData.all.where((c) => c.id == id);
      if (system.isNotEmpty) return Result.success(system.first);

      // Then check Firestore
      final doc = await _collection.doc(id).get();
      if (!doc.exists) return Result.failure('Category not found');
      final data = doc.data()!;
      data['id'] = doc.id;
      return Result.success(CategoryData.fromJson(data));
    } catch (e) {
      return Result.failure( 'Failed to fetch category: $e');
    }
  }

  @override
  Future<Result<CategoryData>> createCategory(CategoryData category) async {
    try {
      final json = category.toJson();
      json['user_id'] = _uid;
      json['created_at'] = DateTime.now().toIso8601String();
      final id = category.id;
      json.remove('id');

      await _collection.doc(id).set(json);
      json['id'] = id;
      return Result.success(CategoryData.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to create category: $e');
    }
  }

  @override
  Future<Result<CategoryData>> updateCategory(
      CategoryData updated) async {
    try {
      final json = updated.toJson();
      json['updated_at'] = DateTime.now().toIso8601String();
      json.remove('id');
      json['user_id'] = _uid;

      // Use set() to handle both existing and new (system override) docs
      // without a pre-read that would fail on security rules for non-existent docs
      await _collection.doc(updated.id).set(json);

      json['id'] = updated.id;
      return Result.success(CategoryData.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to update category: $e');
    }
  }

  @override
  Future<Result<void>> deleteCategory(String id) async {
    try {
      final doc = _collection.doc(id);
      final snapshot = await doc.get();

      if (!snapshot.exists) {
        return Result.failure('Category "$id" not found');
      }

      await doc.delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete category: $e');
    }
  }
}
