import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/auth_repository.dart';
import '../services/notification_service.dart';
import 'repository_providers.dart';
import 'app_providers.dart';
import 'app_settings_provider.dart';
import 'hub_settings_provider.dart';
import 'security_settings_provider.dart';
import 'notification_settings_provider.dart';
import 'user_profile_provider.dart';
import 'business_profile_provider.dart';
import '../../features/cash_flow/providers/scheduled_transactions_provider.dart';
import '../../features/dashboard/providers/dashboard_config_provider.dart';
import '../../features/dashboard/providers/dashboard_state_provider.dart';
import '../../features/shopify/providers/shopify_connection_provider.dart';
import '../../features/shopify/providers/shopify_product_mappings_provider.dart';
import '../../features/shopify/providers/shopify_products_provider.dart';
import '../../features/shopify/providers/shopify_sync_log_provider.dart';
import '../../features/shopify/providers/shopify_sync_provider.dart';
import '../../features/shopify/providers/shopify_webhook_listener_provider.dart';
import '../../shared/models/category_data.dart';

/// Authentication state — represents what the UI should show.
enum AuthStatus {
  /// Haven't checked yet (splash screen).
  unknown,

  /// User is authenticated.
  authenticated,

  /// User is not authenticated.
  unauthenticated,

  /// Auth operation in progress (login/signup).
  loading,
}

/// Holds the current auth state.
class AuthState {
  final AuthStatus status;
  final AuthUser? user;
  final String? error;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    AuthUser? user,
    String? error,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
    );
  }

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLoading => status == AuthStatus.loading;
}

/// Manages authentication state across the app.
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Transitions to authenticated and initialises FCM.
  void _setAuthenticated(AuthUser user) {
    state = AuthState(status: AuthStatus.authenticated, user: user);
    // Fire-and-forget; may throw in test environments without Firebase.
    _initNotifications();
    // Sync profile data from auth so name/email/phone are reflected.
    _syncProfile();
  }

  Future<void> _syncProfile() async {
    try {
      await ref.read(userProfileProvider.notifier).syncFromAuth();
    } catch (_) {
      // Non-critical — profile will load on next screen anyway.
    }
  }

  Future<void> _initNotifications() async {
    try {
      await NotificationService.init();
    } catch (_) {
      // Swallowed — expected in unit-test environments without Firebase.
    }
  }

  /// Check if user is already logged in (called on app start).
  Future<void> checkAuthState() async {
    try {
      final user = await _repo.getCurrentUser();
      if (user != null) {
        _setAuthenticated(user);
      } else {
        state = const AuthState(status: AuthStatus.unauthenticated);
      }
    } catch (e) {
      // If secure storage crashes (e.g., MissingPluginException), default to logged out
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Sign in with email/password.
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);

    try {
      final result = await _repo.signIn(email: email, password: password);

      if (result.isSuccess) {
        _setAuthenticated(result.data!);
        return true;
      } else {
        state = AuthState(
          status: AuthStatus.unauthenticated,
          error: result.error,
        );
        return false;
      }
    } catch (e) {
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Login failed. Please try again.',
      );
      return false;
    }
  }

  /// Sign up with name/email/password.
  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
    String phone = '',
  }) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);

    try {
      final result = await _repo.signUp(
        name: name,
        email: email,
        password: password,
        phone: phone,
      );

      if (result.isSuccess) {
        _setAuthenticated(result.data!);
        return true;
      } else {
        state = AuthState(
          status: AuthStatus.unauthenticated,
          error: result.error,
        );
        return false;
      }
    } catch (e) {
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Sign up failed. Please try again.',
      );
      return false;
    }
  }

  /// Sign in with Google.
  Future<bool> signInWithGoogle() async {
    state = state.copyWith(status: AuthStatus.loading, error: null);

    try {
      final result = await _repo.signInWithGoogle();

      if (result.isSuccess) {
        _setAuthenticated(result.data!);
        return true;
      } else {
        state = AuthState(
          status: AuthStatus.unauthenticated,
          error: result.error,
        );
        return false;
      }
    } catch (e) {
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Google sign-in failed. Please try again.',
      );
      return false;
    }
  }

  /// Sign in with Apple.
  Future<bool> signInWithApple() async {
    state = state.copyWith(status: AuthStatus.loading, error: null);

    try {
      final result = await _repo.signInWithApple();

      if (result.isSuccess) {
        _setAuthenticated(result.data!);
        return true;
      } else {
        state = AuthState(
          status: AuthStatus.unauthenticated,
          error: result.error,
        );
        return false;
      }
    } catch (e) {
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        error: 'Apple sign-in failed. Please try again.',
      );
      return false;
    }
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    try {
      await _repo.signOut();
    } catch (_) {
      // Ignore errors on signout, force unauthenticated state locally
    }

    CategoryData.customCategories = [];

    // Set unauthenticated FIRST so GoRouter redirects to /login
    // and unmounts all data-watching widgets.
    state = const AuthState(status: AuthStatus.unauthenticated);

    // Defer provider invalidation until after the redirect frame
    // completes and all data-watching widgets are unmounted.
    // This prevents the '_dependents.isEmpty framework assertion
    // that occurs when providers are invalidated while widgets
    // still depend on them.
    // In unit tests WidgetsBinding may not be initialised.
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) async {
      ref.invalidate(transactionsProvider);
      ref.invalidate(categoriesProvider);
      ref.invalidate(inventoryProvider);
      ref.invalidate(suppliersProvider);
      ref.invalidate(purchasesProvider);
      ref.invalidate(paymentsProvider);
      ref.invalidate(scheduledTransactionsProvider);
      ref.invalidate(salesProvider);
      ref.invalidate(goodsReceiptsProvider);
      ref.invalidate(userProfileProvider);
      ref.invalidate(businessProfileProvider);

      // Invalidate all settings providers so the next user gets their own data
      ref.invalidate(appSettingsProvider);
      ref.invalidate(hubSettingsProvider);
      ref.invalidate(securitySettingsProvider);
      ref.invalidate(notificationSettingsProvider);
      ref.invalidate(balanceSheetEntriesProvider);
      ref.invalidate(userProvider);

      // Invalidate dashboard providers
      ref.invalidate(dashboardConfigProvider);
      ref.invalidate(dashboardStateProvider);

      // Invalidate Shopify providers
      ref.invalidate(shopifyConnectionProvider);
      ref.invalidate(shopifyProductsProvider);
      ref.invalidate(shopifyMappingsProvider);
      ref.invalidate(shopifySyncLogProvider);
      ref.invalidate(shopifySyncProvider);
      ref.invalidate(shopifyWebhookListenerProvider);

      // Clear Firestore local cache so the next user starts fresh
      try {
        await FirebaseFirestore.instance.clearPersistence();
      } catch (_) {
        // clearPersistence can fail if Firestore client is still active
      }
    });
  }

  /// Clear any error state.
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Global auth state provider.
final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});
