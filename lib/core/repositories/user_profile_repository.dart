import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/result.dart';

/// User profile data for Firestore persistence.
class UserProfile {
  final String name;
  final String email;
  final String phone;
  final String? avatarUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserProfile({
    this.name = '',
    this.email = '',
    this.phone = '',
    this.avatarUrl,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  UserProfile copyWith({
    String? name,
    String? email,
    String? phone,
    String? avatarUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Business profile data for Firestore persistence.
class BusinessProfile {
  final String businessName;
  final String businessType;
  final String address;
  final String taxId;
  final String? logoUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BusinessProfile({
    this.businessName = '',
    this.businessType = '',
    this.address = '',
    this.taxId = '',
    this.logoUrl,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'business_name': businessName,
      'business_type': businessType,
      'address': address,
      'tax_id': taxId,
      if (logoUrl != null) 'logo_url': logoUrl,
      if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      businessName: json['business_name'] as String? ?? '',
      businessType: json['business_type'] as String? ?? '',
      address: json['address'] as String? ?? '',
      taxId: json['tax_id'] as String? ?? '',
      logoUrl: json['logo_url'] as String?,
      createdAt: UserProfile._parseDateTime(json['created_at']),
      updatedAt: UserProfile._parseDateTime(json['updated_at']),
    );
  }

  BusinessProfile copyWith({
    String? businessName,
    String? businessType,
    String? address,
    String? taxId,
    String? logoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BusinessProfile(
      businessName: businessName ?? this.businessName,
      businessType: businessType ?? this.businessType,
      address: address ?? this.address,
      taxId: taxId ?? this.taxId,
      logoUrl: logoUrl ?? this.logoUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Contract for user & business profile data operations.
abstract class UserProfileRepository {
  /// Fetches the user profile.
  Future<Result<UserProfile>> getProfile(String userId);

  /// Updates the user profile.
  Future<Result<UserProfile>> updateProfile(String userId, UserProfile profile);

  /// Fetches the business profile.
  Future<Result<BusinessProfile>> getBusinessProfile(String userId);

  /// Updates the business profile.
  Future<Result<BusinessProfile>> updateBusinessProfile(
    String userId,
    BusinessProfile profile,
  );
}
