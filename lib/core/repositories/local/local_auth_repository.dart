import '../../services/secure_storage_service.dart';
import '../../services/result.dart';
import '../auth_repository.dart';

/// Local mock implementation of [AuthRepository].
/// Simulates auth flow with secure local storage for auto-login.
class LocalAuthRepository implements AuthRepository {
  final SecureStorageService _storage;
  AuthUser? _currentUser;
  
  LocalAuthRepository(this._storage);

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Mock: accept any non-empty credentials
    if (email.isEmpty || password.isEmpty) {
      return Result.failure( 'Email and password are required');
    }

    _currentUser = AuthUser(
      id: 'local_user_1',
      name: email.split('@').first,
      email: email,
      token: 'mock_jwt_token_123',
    );
    
    await _storage.saveToken(_currentUser!.token!);
    await _storage.saveUserLocally(
      id: _currentUser!.id,
      email: _currentUser!.email,
      name: _currentUser!.name,
    );

    return Result.success(_currentUser!);
  }

  @override
  Future<Result<AuthUser>> signUp({
    required String name,
    required String email,
    required String password,
    String phone = '',
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      return Result.failure( 'All fields are required');
    }

    _currentUser = AuthUser(
      id: 'local_user_2',
      name: name,
      email: email,
      token: 'mock_jwt_token_456',
    );
    
    await _storage.saveToken(_currentUser!.token!);
    await _storage.saveUserLocally(
      id: _currentUser!.id,
      email: _currentUser!.email,
      name: _currentUser!.name,
    );

    return Result.success(_currentUser!);
  }

  @override
  Future<Result<void>> signOut() async {
    _currentUser = null;
    await _storage.clearAll();
    return Result.success(null);
  }

  @override
  Future<AuthUser?> getCurrentUser() async {
    if (_currentUser != null) return _currentUser;

    // Check secure storage for existing session
    final token = await _storage.getToken();
    if (token != null) {
      final localUser = await _storage.getLocalUser();
      if (localUser != null) {
        _currentUser = AuthUser(
          id: localUser['id']!,
          email: localUser['email']!,
          name: localUser['name']!,
          token: token,
        );
        return _currentUser;
      }
    }
    return null;
  }

  @override
  Future<Result<AuthUser>> signInWithGoogle() async {
    await Future.delayed(const Duration(milliseconds: 500));
    _currentUser = const AuthUser(
      id: 'google_user_1',
      name:  'Google User',
      email: 'user@gmail.com',
      token: 'mock_google_token_789'
    );
    
    await _storage.saveToken(_currentUser!.token!);
    await _storage.saveUserLocally(
      id: _currentUser!.id,
      email: _currentUser!.email,
      name: _currentUser!.name,
    );
    
    return Result.success(_currentUser!);
  }

  @override
  Future<Result<AuthUser>> signInWithApple() async {
    await Future.delayed(const Duration(milliseconds: 500));
    _currentUser = const AuthUser(
      id: 'apple_user_1',
      name:  'Apple User',
      email: 'user@icloud.com',
      token: 'mock_apple_token_000',
    );
    
    await _storage.saveToken(_currentUser!.token!);
    await _storage.saveUserLocally(
      id: _currentUser!.id,
      email: _currentUser!.email,
      name: _currentUser!.name,
    );

    return Result.success(_currentUser!);
  }

  @override
  Future<Result<void>> resetPassword({required String email}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return Result.success(null);
  }
}
