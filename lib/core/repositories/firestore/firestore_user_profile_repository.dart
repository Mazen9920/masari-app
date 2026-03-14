import 'package:cloud_firestore/cloud_firestore.dart';

import '../../services/result.dart';
import '../user_profile_repository.dart';

/// Firestore implementation of [UserProfileRepository].
/// Stores user and business profiles under `users/{uid}`.
class FirestoreUserProfileRepository implements UserProfileRepository {
  final _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _userDoc(String userId) =>
      _firestore.collection('users').doc(userId);

  @override
  Future<Result<UserProfile>> getProfile(String userId) async {
    try {
      final doc = await _userDoc(userId).get();
      if (!doc.exists) {
        return Result.success(const UserProfile());
      }
      return Result.success(UserProfile.fromJson(doc.data()!));
    } catch (e) {
      return Result.failure( 'Failed to fetch profile: $e');
    }
  }

  @override
  Future<Result<UserProfile>> updateProfile(
      String userId, UserProfile profile) async {
    try {
      final json = profile.toJson();
      json['updated_at'] = DateTime.now().toIso8601String();

      await _userDoc(userId).set(json, SetOptions(merge: true));
      return Result.success(profile.copyWith(updatedAt: DateTime.now()));
    } catch (e) {
      return Result.failure( 'Failed to update profile: $e');
    }
  }

  @override
  Future<Result<BusinessProfile>> getBusinessProfile(String userId) async {
    try {
      final doc = await _userDoc(userId).get();
      if (!doc.exists || doc.data()?['business'] == null) {
        return Result.success(const BusinessProfile());
      }
      final businessData = doc.data()!['business'] as Map<String, dynamic>;
      return Result.success(BusinessProfile.fromJson(businessData));
    } catch (e) {
      return Result.failure( 'Failed to fetch business profile: $e');
    }
  }

  @override
  Future<Result<BusinessProfile>> updateBusinessProfile(
      String userId, BusinessProfile profile) async {
    try {
      final json = profile.toJson();
      json['updated_at'] = DateTime.now().toIso8601String();

      await _userDoc(userId).set(
        {'business': json},
        SetOptions(merge: true),
      );
      return Result.success(profile.copyWith(updatedAt: DateTime.now()));
    } catch (e) {
      return Result.failure( 'Failed to update business profile: $e');
    }
  }

  /// Creates the initial user document on first sign-up.
  /// Called once after auth registration.
  Future<void> createUserIfNotExists({
    required String userId,
    required String name,
    required String email,
    String phone = '',
  }) async {
    final doc = await _userDoc(userId).get();
    if (!doc.exists) {
      await _userDoc(userId).set({
        'name': name,
        'email': email,
        'phone': phone,
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }
}
