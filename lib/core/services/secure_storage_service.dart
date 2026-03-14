import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _authTokenKey = 'auth_token';
const String _userIdKey = 'user_id';
const String _userEmailKey = 'user_email';
const String _userNameKey = 'user_name';

/// A wrapper around [FlutterSecureStorage] for secure local persistence.
/// Includes a fallback to [SharedPreferences] for macOS local development
/// to bypass strict Apple Keychain signing requirements when Testing.
class SecureStorageService {
  final FlutterSecureStorage _storage;

  SecureStorageService(this._storage);

  Future<String?> _readWithFallback(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (e) {
      // Fallback to SharedPreferences ONLY in debug mode.
      // In release builds, rethrow to avoid plaintext token storage.
      if (kDebugMode) {
        debugPrint( 'SecureStorage read fallback triggered: ${e.message}');
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString('fallback_$key');
      }
      rethrow;
    }
  }

  Future<void> _writeWithFallback(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint( 'SecureStorage write fallback triggered: ${e.message}');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fallback_$key', value);
        return;
      }
      rethrow;
    }
  }

  Future<void> _deleteWithFallback(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint( 'SecureStorage delete fallback triggered: ${e.message}');
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('fallback_$key');
        return;
      }
      rethrow;
    }
  }

  // ─── Token Management ───

  /// Saves the authentication token.
  Future<void> saveToken(String token) async {
    await _writeWithFallback(_authTokenKey, token);
  }

  /// Retrieves the saved authentication token.
  Future<String?> getToken() async {
    return await _readWithFallback(_authTokenKey);
  }

  /// Deletes the authentication token.
  Future<void> deleteToken() async {
    await _deleteWithFallback(_authTokenKey);
  }

  // ─── Local Mock User Persistence ───
  // Useful for the LocalAuthRepository to "remember" the user offline
  
  Future<void> saveUserLocally({
    required String id,
    required String email,
    required String name,
  }) async {
    await _writeWithFallback(_userIdKey, id);
    await _writeWithFallback(_userEmailKey, email);
    await _writeWithFallback(_userNameKey, name);
  }

  Future<Map<String, String>?> getLocalUser() async {
    final id = await _readWithFallback(_userIdKey);
    final email = await _readWithFallback(_userEmailKey);
    final name = await _readWithFallback(_userNameKey);

    if (id != null && email != null && name != null) {
      return {'id': id, 'email': email, 'name': name};
    }
    return null;
  }

  Future<void> clearLocalUser() async {
    await _deleteWithFallback(_userIdKey);
    await _deleteWithFallback(_userEmailKey);
    await _deleteWithFallback(_userNameKey);
  }

  Future<void> clearAll() async {
    await deleteToken();
    await clearLocalUser();
  }
}

/// Provider for [SecureStorageService].
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  const storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );
  return SecureStorageService(storage);
});
