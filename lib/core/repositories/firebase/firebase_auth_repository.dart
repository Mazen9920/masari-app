import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../services/result.dart';
import '../auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final firebase.FirebaseAuth _auth;

  FirebaseAuthRepository({firebase.FirebaseAuth? auth})
      : _auth = auth ?? firebase.FirebaseAuth.instance {
    _initializePersistence();
  }

  /// Maps Firebase error codes to user-friendly messages.
  String _friendlyAuthError(firebase.FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already registered. Try signing in instead.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a different sign-in method (Google, Apple, or email). Try signing in with that method instead.';
      case 'invalid-credential':
      case 'wrong-password':
        return 'Invalid email or password. Please try again.';
      case 'user-not-found':
        return 'No account found with this email. Please sign up first.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Please use at least 6 characters.';
      case 'credential-already-in-use':
        return 'This credential is already associated with a different account.';
      case 'network-request-failed':
        return 'Network error. Please check your connection and try again.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled. Please contact support.';
      case 'requires-recent-login':
        return 'Please sign in again to complete this action.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }

  Future<void> _initializePersistence() async {
    // macOS requires Xcode Developer Certificates for Keychain (LOCAL) persistence.
    // To allow local development without Xcode, we force it to in-memory on Mac.
    if (Platform.isMacOS) {
      try {
        await _auth.setPersistence(firebase.Persistence.NONE);
      } catch (_) {
        // Ignore initialization errors
      }
    }
  }

  AuthUser _mapFirebaseUser(firebase.User user) {
    return AuthUser(
      id: user.uid,
      name: user.displayName ?? user.email?.split('@').first ?? 'User',
      email: user.email ?? '',
      // Note: We don't store the actual JWT from Firebase here usually, 
      // because Firebase handles token refresh and injection itself.
      // But if needed, we could fetch `await user.getIdToken()`.
    );
  }

  @override
  Future<Result<AuthUser>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      if (credential.user != null) {
        return Result.success(_mapFirebaseUser(credential.user!));
      } else {
        return Result.failure('Sign in failed. Please try again.');
      }
    } on firebase.FirebaseAuthException catch (e) {
      return Result.failure(_friendlyAuthError(e));
    } catch (e) {
      return Result.failure('An unexpected error occurred. Please try again.');
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
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      if (credential.user != null) {
        await credential.user!.updateDisplayName(name);

        // Create Firestore user doc on first sign-up.
        // Pass name and phone explicitly — user.displayName may not
        // reflect the update yet.
        await _createUserDocIfNotExists(
          credential.user!,
          explicitName: name,
          explicitPhone: phone,
        );

        // Map the user with the explicitly provided name since the credential.user
        // might not reflect the updated display name immediately in this instance.
        final userToReturn = AuthUser(
          id: credential.user!.uid,
          name: name,
          email: email,
        );
        return Result.success(userToReturn);
      } else {
        return Result.failure('Sign up failed. Please try again.');
      }
    } on firebase.FirebaseAuthException catch (e) {
      return Result.failure(_friendlyAuthError(e));
    } catch (e) {
      return Result.failure('An unexpected error occurred. Please try again.');
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await GoogleSignIn().signOut();
      await _auth.signOut();
      return Result.success(null);
    } catch (e) {
      return Result.failure('Failed to sign out. Please try again.');
    }
  }

  @override
  Future<AuthUser?> getCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      // Force a token refresh so deleted / revoked users are detected
      // immediately instead of waiting up to 1 hour for expiry.
      await user.getIdToken(true);
      return _mapFirebaseUser(user);
    }
    return null;
  }

  @override
  Future<Result<AuthUser>> signInWithGoogle() async {
    try {
      // On iOS the plugin reads CLIENT_ID from GoogleService-Info.plist automatically.
      final googleSignIn = GoogleSignIn();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the sign-in flow
        return Result.failure( 'Google sign-in was cancelled.');
      }

      final googleAuth = await googleUser.authentication;
      final credential = firebase.GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      if (userCredential.user == null) {
        return Result.failure('Google sign-in failed. Please try again.');
      }

      final user = _mapFirebaseUser(userCredential.user!);

      // Create Firestore user doc on first social sign-in
      await _createUserDocIfNotExists(userCredential.user!);

      return Result.success(user);
    } on firebase.FirebaseAuthException catch (e) {
      if (e.code == 'invalid-credential') {
        return Result.failure('Google sign-in failed. Please ensure Google sign-in is enabled and try again.');
      }
      return Result.failure(_friendlyAuthError(e));
    } catch (e) {
      return Result.failure('Google sign-in failed. Please try again.');
    }
  }

  @override
  Future<Result<AuthUser>> signInWithApple() async {
    try {
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      if (appleCredential.identityToken == null) {
        return Result.failure('Apple sign-in failed: No identity token received from Apple.');
      }

      final oauthCredential = firebase.OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken!,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential = await _auth.signInWithCredential(oauthCredential);
      if (userCredential.user == null) {
        return Result.failure('Apple sign-in failed. Please try again.');
      }

      // Apple only provides the name on the FIRST sign-in.
      // Persist it on the Firebase user so subsequent logins still show it.
      final givenName = appleCredential.givenName;
      final familyName = appleCredential.familyName;
      String? displayName;
      if (givenName != null && givenName.isNotEmpty) {
        displayName = '$givenName${familyName != null && familyName.isNotEmpty ? ' $familyName' : ''}';
        await userCredential.user!.updateDisplayName(displayName);
      }

      await _createUserDocIfNotExists(
        userCredential.user!,
        explicitName: displayName,
      );

      return Result.success(_mapFirebaseUser(userCredential.user!));
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return Result.failure('Apple sign-in was cancelled.');
      }
      return Result.failure('Apple sign-in failed. Please try again.');
    } on firebase.FirebaseAuthException catch (e) {
      if (e.code == 'invalid-credential') {
        return Result.failure('Apple sign-in failed (${e.code}): ${e.message}');
      }
      return Result.failure(_friendlyAuthError(e));
    } catch (e) {
      return Result.failure('Apple sign-in failed: $e');
    }
  }

  // ─── Nonce helpers for Apple Sign-In ───────────────────────────────────────

  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  @override
  Future<Result<void>> resetPassword({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return Result.success(null);
    } on firebase.FirebaseAuthException catch (e) {
      return Result.failure(_friendlyAuthError(e));
    } catch (e) {
      return Result.failure('Failed to send reset email. Please try again.');
    }
  }

  // ─── Firestore user document creation ─────────────────────────────────────

  /// Creates a user document in Firestore on first sign-up / social sign-in.
  /// Skips if the document already exists (idempotent).
  /// [explicitName] and [explicitPhone] are used when available (e.g. email/password signup)
  /// so we don't rely on the stale `user.displayName` which may still be null.
  Future<void> _createUserDocIfNotExists(
    firebase.User user, {
    String? explicitName,
    String? explicitPhone,
  }) async {
    try {
      final doc = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final snapshot = await doc.get();
      if (!snapshot.exists) {
        await doc.set({
          'name': explicitName ?? user.displayName ?? user.email?.split('@').first ?? 'User',
          'email': user.email ?? '',
          'phone': explicitPhone ?? '',
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (_) {
      // Non-critical — don't fail auth if Firestore write fails
    }
  }
}
