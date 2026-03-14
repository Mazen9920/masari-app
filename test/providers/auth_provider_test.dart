import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:masari_app/core/repositories/auth_repository.dart';
import 'package:masari_app/core/services/result.dart';
import 'package:masari_app/core/providers/auth_provider.dart';
import 'package:masari_app/core/providers/repository_providers.dart';

// Stub repository for testing
class StubAuthRepository implements AuthRepository {
  bool loggedIn = false;
  
  @override
  Future<AuthUser?> getCurrentUser() async {
    if (loggedIn) {
      return const AuthUser(id: '1', email: 'test@test.com', name: 'TestUser');
    }
    return null;
  }
  
  @override
  Future<Result<AuthUser>> signIn({required String email, required String password}) async {
    if (email == 'test@test.com' && password == 'password') {
      loggedIn = true;
      return Result.success(const AuthUser(id: '1', email: 'test@test.com', name: 'TestUser'));
    }
    return Result.failure('Invalid credentials');
  }
  
  @override
  Future<Result<void>> signOut() async {
    loggedIn = false;
    return Result.success(null);
  }

  @override
  Future<Result<AuthUser>> signUp({required String name, required String email, required String password, String phone = ''}) async => Result.failure('Not implemented');
  @override
  Future<Result<AuthUser>> signInWithGoogle() async => Result.failure('Not implemented');
  @override
  Future<Result<AuthUser>> signInWithApple() async => Result.failure('Not implemented');
  @override
  Future<Result<void>> resetPassword({required String email}) async => Result.success(null);
}

void main() {
  group('AuthNotifier Tests', () {
    late ProviderContainer container;
    late StubAuthRepository authRepo;

    setUp(() {
      authRepo = StubAuthRepository();
      container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(authRepo),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial state is unauthenticated (unknown)', () {
      final state = container.read(authProvider);
      expect(state.status, AuthStatus.unknown);
    });

    test('Successful sign in updates state to authenticated', () async {
      await container.read(authProvider.notifier).signIn(email: 'test@test.com', password: 'password');
      
      final state = container.read(authProvider);
      
      expect(state.status, AuthStatus.authenticated);
      expect(state.user?.email, 'test@test.com');
      expect(state.user?.name, 'TestUser');
    });

    test('Failed sign in updates state with error', () async {
      await container.read(authProvider.notifier).signIn(email: 'wrong@test.com', password: 'badpass');
      
      final state = container.read(authProvider);
      
      expect(state.status, AuthStatus.unauthenticated);
      expect(state.error, 'Invalid credentials');
    });

    test('Sign out updates state to unauthenticated', () async {
      // Setup initial logged-in state
      await container.read(authProvider.notifier).signIn(email: 'test@test.com', password: 'password');
      
      // Perform sign out
      await container.read(authProvider.notifier).signOut();
      
      final state = container.read(authProvider);
      expect(state.status, AuthStatus.unauthenticated);
    });
  });
}
