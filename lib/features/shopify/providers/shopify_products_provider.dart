import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/shopify_sync_service.dart';

/// Fetches and caches all Shopify products (with variants) for the mapping UI.
///
/// Each item is a raw Shopify product JSON map:
/// `{ id, title, variants: [{ id, title, sku, inventory_item_id, ... }], ... }`
class ShopifyProductsNotifier
    extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final api = ref.read(shopifyApiServiceProvider);
    final result = await api.fetchProducts();
    if (result.isSuccess && result.data != null) {
      return result.data!;
    }
    throw Exception(result.error ??  'Failed to load Shopify products');
  }

  /// Force-refresh from Shopify API.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }
}

final shopifyProductsProvider = AsyncNotifierProvider<
    ShopifyProductsNotifier, List<Map<String, dynamic>>>(() {
  return ShopifyProductsNotifier();
});
