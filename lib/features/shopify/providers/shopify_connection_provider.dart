import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/services/result.dart';
import '../../../shared/models/shopify_connection_model.dart';

/// Manages the user's Shopify connection lifecycle.
///
/// Watches auth state, loads the connection doc from Firestore,
/// and exposes methods to connect/disconnect/update settings.
class ShopifyConnectionNotifier
    extends AsyncNotifier<ShopifyConnection?> {
  @override
  Future<ShopifyConnection?> build() async {
    final repo = ref.read(shopifyConnectionRepositoryProvider);
    final result = await repo.getConnection();
    if (result.isSuccess) return result.data;
    throw Exception(result.error ??  'Failed to load Shopify connection');
  }

  /// Starts the Shopify OAuth flow.
  ///
  /// 1. Calls `shopifyAuthStart` Cloud Function to get the OAuth URL.
  /// 2. Opens the URL in the system browser.
  /// 3. After user approves on Shopify, the callback Cloud Function
  ///    stores the encrypted token — [refresh] then picks it up.
  Future<Result<void>> connect(String shopDomain) async {
    try {
      final functions =
          FirebaseFunctions.instanceFor(region: 'us-central1');
      final callable = functions.httpsCallable('shopifyAuthStart');
      final result = await callable.call<Map<String, dynamic>>({
        'shopDomain': shopDomain,
      });

      final oauthUrl = result.data['oauthUrl'] as String?;
      if (oauthUrl == null || oauthUrl.isEmpty) {
        return Result.failure( 'No OAuth URL returned');
      }

      final uri = Uri.parse(oauthUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        return Result.failure( 'Could not open browser');
      }

      return Result.success(null);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(e.message ??  'Failed to start OAuth');
    } catch (e) {
      return Result.failure( 'Failed to connect: $e');
    }
  }

  /// Disconnects from Shopify: deletes the connection doc and
  /// clears all product mappings.
  Future<Result<void>> disconnect() async {
    final connRepo = ref.read(shopifyConnectionRepositoryProvider);
    final mappingRepo = ref.read(shopifyProductMappingRepositoryProvider);

    final current = state.value;
    if (current == null) {
      return Result.failure( 'No active connection');
    }

    // Delete all product mappings first
    await mappingRepo.deleteAllMappings();

    // Delete the connection doc
    final result = await connRepo.deleteConnection(current.userId);
    if (result.isSuccess) {
      state = const AsyncValue.data(null);
      return Result.success(null);
    }
    return Result.failure(result.error ??  'Failed to disconnect');
  }

  /// Updates sync preferences on the connection doc.
  Future<Result<void>> updateSettings({
    bool? syncOrdersEnabled,
    bool? syncInventoryEnabled,
    String? inventorySyncDirection,
    String? inventorySyncMode,
    String? shopifyLocationId,
    String? shopifyLocationName,
  }) async {
    final current = state.value;
    if (current == null) {
      return Result.failure( 'No active connection');
    }

    final updated = current.copyWith(
      syncOrdersEnabled: syncOrdersEnabled,
      syncInventoryEnabled: syncInventoryEnabled,
      inventorySyncDirection: inventorySyncDirection,
      inventorySyncMode: inventorySyncMode,
      shopifyLocationId: shopifyLocationId,
      shopifyLocationName: shopifyLocationName,
    );

    final repo = ref.read(shopifyConnectionRepositoryProvider);
    final result = await repo.updateConnection(current.userId, updated);
    if (result.isSuccess) {
      state = AsyncValue.data(result.data);
      return Result.success(null);
    }
    return Result.failure(result.error ??  'Failed to update settings');
  }

  /// Reloads the connection from the server (bypasses cache).
  /// Used after OAuth or when we need guaranteed-fresh data.
  /// Preserves the previous value during reload so the UI doesn't flash
  /// "not connected" while the fetch is in-flight.
  Future<void> refresh() async {
    // Don't reset to loading — keep the current state visible while fetching.
    final newState = await AsyncValue.guard(() async {
      final repo = ref.read(shopifyConnectionRepositoryProvider);
      final result = await repo.getConnectionFromServer();
      if (result.isSuccess) return result.data;
      throw Exception(result.error ??  'Failed to load Shopify connection');
    });
    state = newState;
  }
}

// ── Provider ───────────────────────────────────────────────

final shopifyConnectionProvider = AsyncNotifierProvider<
    ShopifyConnectionNotifier, ShopifyConnection?>(() {
  return ShopifyConnectionNotifier();
});

/// Convenience — true when an active Shopify connection exists.
/// Preserves the previous value while a refresh is in-flight
/// (via copyWithPrevious in refresh()) so UI doesn't flash.
final isShopifyConnectedProvider = Provider<bool>((ref) {
  final asyncConn = ref.watch(shopifyConnectionProvider);
  final conn = asyncConn.value;
  return conn != null && conn.isActive;
});
