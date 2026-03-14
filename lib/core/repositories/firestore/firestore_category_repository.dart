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
      String oldName, CategoryData updated) async {
    try {
      // Find the doc by user_id + old name
      final snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .where('name', isEqualTo: oldName)
          .limit(1)
          .get();

      final json = updated.toJson();
      json['updated_at'] = DateTime.now().toIso8601String();
      json.remove('id');

      if (snapshot.docs.isEmpty) {
        // System category — create a user-specific override in Firestore
        json['user_id'] = _uid;
        final overrideId = updated.id;
        await _collection.doc(overrideId).set(json);
        json['id'] = overrideId;
        return Result.success(CategoryData.fromJson(json));
      }

      final docId = snapshot.docs.first.id;
      json['user_id'] = _uid;
      await _collection.doc(docId).update(json);
      json['id'] = docId;
      return Result.success(CategoryData.fromJson(json));
    } catch (e) {
      return Result.failure( 'Failed to update category: $e');
    }
  }

  @override
  Future<Result<void>> deleteCategory(String name) async {
    try {
      final snapshot = await _collection
          .where('user_id', isEqualTo: _uid)
          .where('name', isEqualTo: name)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return Result.failure('Category "$name" not found');
      }

      await _collection.doc(snapshot.docs.first.id).delete();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to delete category: $e');
    }
  }
}
