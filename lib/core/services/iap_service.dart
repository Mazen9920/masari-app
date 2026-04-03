import 'dart:async';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../providers/app_settings_provider.dart';

/// Product IDs — must match App Store Connect & Google Play Console.
const kGrowthMonthlyId = 'revvo_growth_monthly';
const kGrowthYearlyId = 'revvo_growth_yearly';

const _kAllProductIds = {kGrowthMonthlyId, kGrowthYearlyId};

/// Whether the current platform supports native IAP.
bool get isIapAvailable => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

/// Maps store product IDs to the plan names used by our backend.
String planFromProductId(String productId) => switch (productId) {
  kGrowthMonthlyId => 'growth_monthly',
  kGrowthYearlyId => 'growth_yearly',
  _ => productId,
};

// ─── State ─────────────────────────────────────────────────────────────────

class IapState {
  const IapState({
    this.products = const [],
    this.loading = false,
    this.error,
  });

  final List<ProductDetails> products;
  final bool loading;
  final String? error;

  IapState copyWith({
    List<ProductDetails>? products,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return IapState(
      products: products ?? this.products,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ─── Notifier ──────────────────────────────────────────────────────────────

final iapProvider = NotifierProvider<IapNotifier, IapState>(IapNotifier.new);

class IapNotifier extends Notifier<IapState> {
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _initialized = false;

  @override
  IapState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    return const IapState();
  }

  /// Initialize IAP listener. Call once from subscription screen.
  Future<void> init() async {
    if (_initialized || !isIapAvailable) return;
    _initialized = true;

    final available = await InAppPurchase.instance.isAvailable();
    if (!available) return;

    _sub = InAppPurchase.instance.purchaseStream.listen(
      _onPurchaseUpdate,
      onError: (error) {
        state = state.copyWith(
          error: 'Purchase error: $error',
          loading: false,
        );
      },
    );

    await loadProducts();
  }

  /// Load available subscription products from the store.
  Future<void> loadProducts() async {
    final response =
        await InAppPurchase.instance.queryProductDetails(_kAllProductIds);
    if (response.productDetails.isNotEmpty) {
      state = state.copyWith(products: response.productDetails);
    }
  }

  /// Initiate a subscription purchase.
  Future<void> buy(ProductDetails product) async {
    state = state.copyWith(loading: true, clearError: true);
    final purchaseParam = PurchaseParam(productDetails: product);
    await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: purchaseParam,
    );
  }

  /// Restore previous purchases (useful when user reinstalls).
  Future<void> restorePurchases() async {
    state = state.copyWith(loading: true, clearError: true);
    await InAppPurchase.instance.restorePurchases();
  }

  /// Clear error state.
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Handle incoming purchase updates.
  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndActivate(purchase);
        case PurchaseStatus.error:
          state = state.copyWith(
            error: purchase.error?.message ?? 'Purchase failed',
            loading: false,
          );
        case PurchaseStatus.canceled:
          state = state.copyWith(loading: false);
        case PurchaseStatus.pending:
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(purchase);
      }
    }
  }

  /// Send receipt to server for validation + subscription activation.
  Future<void> _verifyAndActivate(PurchaseDetails purchase) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('verifyIapReceipt');

      await callable.call<Map<String, dynamic>>({
        'platform': Platform.isIOS ? 'ios' : 'android',
        'product_id': purchase.productID,
        'purchase_token':
            purchase.verificationData.serverVerificationData,
        'transaction_id': purchase.purchaseID,
      });

      await ref
          .read(appSettingsProvider.notifier)
          .refreshSubscription();

      state = state.copyWith(loading: false, clearError: true);
    } catch (e) {
      state = state.copyWith(
        error: 'Verification failed. Please try again.',
        loading: false,
      );
    }
  }
}
