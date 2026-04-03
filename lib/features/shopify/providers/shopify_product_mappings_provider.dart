import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/repository_providers.dart';
import '../../../core/services/result.dart';
import '../../../core/services/shopify_sync_service.dart';
import '../../../shared/models/shopify_product_mapping_model.dart';

/// Manages Shopify ↔ Revvo product/variant mappings.
///
/// Provides CRUD and an auto-match-by-SKU helper that
/// scans both systems for matching SKUs and creates mappings.
class ShopifyMappingsNotifier
    extends AsyncNotifier<List<ShopifyProductMapping>> {
  @override
  Future<List<ShopifyProductMapping>> build() async {
    final repo = ref.read(shopifyProductMappingRepositoryProvider);
    final result = await repo.getMappings();
    if (result.isSuccess && result.data != null) {
      return result.data!;
    }
    throw Exception(result.error ?? 'Failed to load product mappings');
  }

  // ── CRUD ─────────────────────────────────────────────────

  /// Creates a manual mapping between a Revvo variant and a Shopify variant.
  Future<Result<ShopifyProductMapping>> createMapping(
    ShopifyProductMapping mapping,
  ) async {
    final repo = ref.read(shopifyProductMappingRepositoryProvider);
    final result = await repo.createMapping(mapping);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([...current, result.data!]);
    }
    return result;
  }

  /// Updates an existing mapping (e.g. re-link to different Revvo product).
  Future<Result<ShopifyProductMapping>> updateMapping(
    String id,
    ShopifyProductMapping updated,
  ) async {
    final repo = ref.read(shopifyProductMappingRepositoryProvider);
    final result = await repo.updateMapping(id, updated);
    if (result.isSuccess && result.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([
        for (final m in current)
          if (m.id == id) result.data! else m,
      ]);
    }
    return result;
  }

  /// Deletes a mapping.
  Future<Result<void>> deleteMapping(String id) async {
    final repo = ref.read(shopifyProductMappingRepositoryProvider);
    final result = await repo.deleteMapping(id);
    if (result.isSuccess) {
      final current = state.value ?? [];
      state = AsyncValue.data(current.where((m) => m.id != id).toList());
    }
    return result;
  }

  /// Deletes all mappings (used on Shopify disconnect).
  Future<Result<void>> deleteAll() async {
    final repo = ref.read(shopifyProductMappingRepositoryProvider);
    final result = await repo.deleteAllMappings();
    if (result.isSuccess) {
      state = const AsyncValue.data([]);
    }
    return result;
  }

  // ── Auto-match ───────────────────────────────────────────

  /// Fetches products from both Shopify and Revvo, matches by SKU,
  /// and bulk-creates mappings for all matches found.
  ///
  /// Returns the count of new mappings created.
  Future<Result<int>> autoMatchBySku() async {
    final api = ref.read(shopifyApiServiceProvider);
    final productRepo = ref.read(productRepositoryProvider);
    final mappingRepo = ref.read(shopifyProductMappingRepositoryProvider);

    // 1. Fetch Shopify products
    final shopifyResult = await api.fetchProducts();
    if (!shopifyResult.isSuccess) {
      return Result.failure(
        shopifyResult.error ?? 'Failed to fetch Shopify products',
      );
    }
    final shopifyProducts = shopifyResult.data!;

    // 2. Fetch all Revvo products
    final revvoResult = await productRepo.getProducts();
    if (!revvoResult.isSuccess) {
      return Result.failure(
        revvoResult.error ?? 'Failed to fetch Revvo products',
      );
    }
    final revvoProducts = revvoResult.data!;

    // 3. Build lookup maps for Revvo products:
    //    a) SKU → revvo ref (for matching by SKU)
    //    b) shopifyVariantId → revvo ref (for re-linking after reconnect)
    //    c) shopifyProductId → product (for product-level matching)
    final revvoSkuMap = <String, _RevvoVariantRef>{};
    final revvoShopifyVarMap = <String, _RevvoVariantRef>{};
    final revvoShopifyProdMap = <String, String>{}; // shopifyProdId → revvoProdId
    for (final product in revvoProducts) {
      // Match by Shopify product ID stored on the Revvo product
      if (product.shopifyProductId != null &&
          product.shopifyProductId!.isNotEmpty) {
        revvoShopifyProdMap[product.shopifyProductId!] = product.id;
      }
      for (final variant in product.variants) {
        // Match by Shopify variant ID stored on the Revvo variant
        if (variant.shopifyVariantId != null &&
            variant.shopifyVariantId!.isNotEmpty) {
          revvoShopifyVarMap[variant.shopifyVariantId!] = _RevvoVariantRef(
            productId: product.id,
            variantId: variant.id,
          );
        }
        // Match by SKU
        final sku = variant.sku.trim().toLowerCase();
        if (sku.isNotEmpty) {
          revvoSkuMap[sku] = _RevvoVariantRef(
            productId: product.id,
            variantId: variant.id,
          );
        }
      }
    }

    // 4. Load existing mappings to avoid duplicates
    final existingMappings = state.value ?? [];
    final existingShopifyVariantIds = <String>{
      for (final m in existingMappings) m.shopifyVariantId,
    };

    // 5. Match Shopify variants against Revvo by:
    //    Priority 1: shopifyVariantId (exact re-link)
    //    Priority 2: SKU
    final newMappings = <ShopifyProductMapping>[];
    for (final sp in shopifyProducts) {
      final shopifyProductId = sp['id']?.toString() ?? '';
      final shopifyTitle = sp['title']?.toString() ?? '';
      final variants = (sp['variants'] as List<dynamic>? ?? []);

      for (final sv in variants) {
        final variant = Map<String, dynamic>.from(sv as Map);
        final shopifyVariantId = variant['id']?.toString() ?? '';
        final shopifySku =
            (variant['sku']?.toString() ?? '').trim().toLowerCase();
        final inventoryItemId =
            variant['inventory_item_id']?.toString() ?? '';

        // Skip if already mapped
        if (existingShopifyVariantIds.contains(shopifyVariantId)) continue;

        // Try matching by shopify variant ID first, then SKU
        final match = revvoShopifyVarMap[shopifyVariantId] ??
            (shopifySku.isNotEmpty ? revvoSkuMap[shopifySku] : null);
        if (match == null) continue;

        newMappings.add(ShopifyProductMapping(
          id: '', // will be set by Firestore
          userId: '', // will be set by repo
          revvoProductId: match.productId,
          revvoVariantId: match.variantId,
          shopifyProductId: shopifyProductId,
          shopifyVariantId: shopifyVariantId,
          shopifyInventoryItemId: inventoryItemId,
          shopifySku: shopifySku,
          shopifyTitle:
              '$shopifyTitle — ${variant['title'] ?? 'Default'}',
          autoImported: true,
          createdAt: DateTime.now(),
        ));
      }
    }

    if (newMappings.isEmpty) return Result.success(0);

    // 6. Batch create
    final batchResult = await mappingRepo.createMappingsBatch(newMappings);
    if (batchResult.isSuccess && batchResult.data != null) {
      final current = state.value ?? [];
      state = AsyncValue.data([...current, ...batchResult.data!]);
      return Result.success(batchResult.data!.length);
    }

    return Result.failure(
      batchResult.error ?? 'Failed to create mappings',
    );
  }

  /// Reloads all mappings from Firestore.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => build());
  }
}

/// Internal helper for SKU matching.
class _RevvoVariantRef {
  final String productId;
  final String variantId;

  const _RevvoVariantRef({
    required this.productId,
    required this.variantId,
  });
}

// ── Provider ───────────────────────────────────────────────

final shopifyMappingsProvider = AsyncNotifierProvider<
    ShopifyMappingsNotifier, List<ShopifyProductMapping>>(() {
  return ShopifyMappingsNotifier();
});
