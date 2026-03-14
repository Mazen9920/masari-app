import '../services/result.dart';

/// Holds authenticated user information.
class AuthUser {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final String? token;

  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    this.token,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      };

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        avatarUrl: json['avatar_url'] as String?,
        token: json['token'] as String?,
      );
}

/// Contract for authentication operations.
abstract class AuthRepository {
  /// Signs in with email and password.
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  });

  /// Creates a new account.
  Future<Result<AuthUser>> signUp({
    required String name,
    required String email,
    required String password,
    String phone = '',
  });

  /// Signs out the current user.
  Future<Result<void>> signOut();

  /// Returns the currently authenticated user, or null.
  Future<AuthUser?> getCurrentUser();

  /// Signs in with Google.
  Future<Result<AuthUser>> signInWithGoogle();

  /// Signs in with Apple.
  Future<Result<AuthUser>> signInWithApple();

  /// Sends a password reset email.
  Future<Result<void>> resetPassword({required String email});
}
