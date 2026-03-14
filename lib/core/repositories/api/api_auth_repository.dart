import '../../../shared/dtos/api_response.dart';
import '../../../shared/dtos/auth_dtos.dart';
import '../../services/api_client.dart';
import '../../services/result.dart';
import '../../services/secure_storage_service.dart';
import '../auth_repository.dart';

class ApiAuthRepository implements AuthRepository {
  final ApiClient _client;
  final SecureStorageService _storage;

  ApiAuthRepository(this._client, this._storage);

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final dto = LoginRequestDto(email: email, password: password);
      final responseMap = await _client.post('/auth/login', body: dto.toJson());
      
      final response = ApiResponse<AuthResponseDto>.fromJson(
        responseMap,
        (json) => AuthResponseDto.fromJson(json),
      );

      if (response.success && response.data != null) {
        final authData = response.data!;
        
        // Save token to secure storage
        await _storage.saveToken(authData.token);

        return Result.success(AuthUser(
          id: authData.userId,
          name: authData.name ?? 'User',
          email: authData.email ?? email,
          token: authData.token,
        ));
      } else {
        return Result.failure(response.message ??  'Login failed');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<AuthUser>> signUp({
    required String name,
    required String email,
    required String password,
    String phone = '',
  }) async {
    try {
      final dto = SignupRequestDto(email: email, password: password, name: name);
      final responseMap = await _client.post('/auth/signup', body: dto.toJson());
      
      final response = ApiResponse<AuthResponseDto>.fromJson(
        responseMap,
        (json) => AuthResponseDto.fromJson(json),
      );

      if (response.success && response.data != null) {
        final authData = response.data!;

        // Save token to secure storage
        await _storage.saveToken(authData.token);

        return Result.success(AuthUser(
          id: authData.userId,
          name: authData.name ?? name,
          email: authData.email ?? email,
          token: authData.token,
        ));
      } else {
        return Result.failure(response.message ??  'Signup failed');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await _client.post('/auth/logout');
      await _storage.clearAll();
      return Result.success(null);
    } on ApiException catch (e) {
      // Even if network fails, we clear locally to effectively log them out
      await _storage.clearAll();
      return Result.failure(e.message);
    } catch (e) {
      await _storage.clearAll();
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<AuthUser?> getCurrentUser() async {
    try {
      final token = await _storage.getToken();
      if (token == null || token.isEmpty) return null;

      // Ensure API requests are made with the latest token
      final authenticatedClient = _client.withToken(token);

      final responseMap = await authenticatedClient.get('/auth/me');
      final response = ApiResponse<AuthUser>.fromJson(
        responseMap,
        (json) => AuthUser.fromJson(json),
      );
      
      if (response.success && response.data != null) {
        return response.data;
      }
      
      // If token is invalid/expired according to the server
      await _storage.clearAll();
      return null;
    } catch (_) {
      // Network error offline — realistically we should maybe return a cached user here
      // but for standard API flow, we might force them to re-authenticate or handle offline gracefully.
      return null;
    }
  }

  @override
  Future<Result<AuthUser>> signInWithGoogle() async {
    return Result.failure( 'Google sign-in via API not implemented yet');
  }

  @override
  Future<Result<AuthUser>> signInWithApple() async {
    return Result.failure( 'Apple sign-in via API not implemented yet');
  }

  @override
  Future<Result<void>> resetPassword({required String email}) async {
    try {
      await _client.post('/auth/reset-password', body: {'email': email});
      return Result.success(null);
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'Failed to send reset email: $e');
    }
  }
}
