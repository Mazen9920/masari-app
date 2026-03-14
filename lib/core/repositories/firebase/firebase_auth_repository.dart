import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:google_sign_in/google_sign_in.dart';
import '../../services/result.dart';
import '../auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  final firebase.FirebaseAuth _auth;

  FirebaseAuthRepository({firebase.FirebaseAuth? auth})
      : _auth = auth ?? firebase.FirebaseAuth.instance {
    _initializePersistence();
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
        return Result.failure( 'Sign in failed: No user returned.');
      }
    } on firebase.FirebaseAuthException catch (e) {
      return Result.failure(e.message ??  'Authentication failed.');
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: ${e.toString()}');
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
        return Result.failure( 'Sign up failed: No user returned.');
      }
    } on firebase.FirebaseAuthException catch (e) {
      return Result.failure(e.message ??  'Registration failed.');
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: ${e.toString()}');
    }
  }

  @override
  Future<Result<void>> signOut() async {
    try {
      await GoogleSignIn().signOut();
      await _auth.signOut();
      return Result.success(null);
    } catch (e) {
      return Result.failure( 'Failed to sign out: ${e.toString()}');
    }
  }

  @override
  Future<AuthUser?> getCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      return _mapFirebaseUser(user);
    }
    return null;
  }

  @override
  Future<Result<AuthUser>> signInWithGoogle() async {
    try {
      // On iOS, pass the CLIENT_ID from GoogleService-Info.plist explicitly
      final googleSignIn = GoogleSignIn(
        clientId: Platform.isIOS
            ? '686452990628-tblkqh5lquus1g26fvisce7t0nh0ne54.apps.googleusercontent.com'
            : null,
      );
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
        return Result.failure( 'Google sign-in failed: No user returned.');
      }

      final user = _mapFirebaseUser(userCredential.user!);

      // Create Firestore user doc on first social sign-in
      await _createUserDocIfNotExists(userCredential.user!);

      return Result.success(user);
    } on firebase.FirebaseAuthException catch (e) {
      return Result.failure(e.message ??  'Google sign-in failed.');
    } catch (e) {
      return Result.failure( 'Google sign-in error: ${e.toString()}');
    }
  }

  @override
  Future<Result<AuthUser>> signInWithApple() async {
    // Note: Requires configuring Apple Sign-In on Apple Developer portal and Firebase.
    return Result.failure( 'Apple Sign-In is not yet configured.');
  }

  @override
  Future<Result<void>> resetPassword({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return Result.success(null);
    } on firebase.FirebaseAuthException catch (e) {
      return Result.failure(e.message ??  'Password reset failed.');
    } catch (e) {
      return Result.failure( 'Failed to send reset email: ${e.toString()}');
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
