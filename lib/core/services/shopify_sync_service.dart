import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/sale_model.dart';
import '../../shared/models/product_model.dart';
import '../../shared/models/shopify_product_mapping_model.dart';
import '../repositories/product_repository.dart';
import '../repositories/sale_repository.dart';
import '../repositories/shopify_connection_repository.dart';
import '../repositories/shopify_product_mapping_repository.dart';
import '../repositories/shopify_sync_log_repository.dart';
import '../repositories/transaction_repository.dart';
import '../../shared/models/transaction_model.dart' as transaction_model;
import '../providers/repository_providers.dart';
import '../providers/app_settings_provider.dart';
import 'result.dart';
import 'shopify_api_service.dart';

/// High-level Shopify sync orchestrator.
///
/// Coordinates between the local Revvo repositories, the product mapping
/// table, and the [ShopifyApiService] proxy to push/pull data.
class ShopifySyncService {
  final ShopifyApiService _api;
  final SaleRepository _saleRepo;
  final ProductRepository _productRepo;
  final ShopifyConnectionRepository _connRepo;
  final ShopifyProductMappingRepository _mappingRepo;
  final ShopifySyncLogRepository _logRepo;
  // ignore: unused_field
  final TransactionRepository _transactionRepo;
  String valuationMethod;

  ShopifySyncService({
    required ShopifyApiService api,
    required SaleRepository saleRepo,
    required ProductRepository productRepo,
    required ShopifyConnectionRepository connRepo,
    required ShopifyProductMappingRepository mappingRepo,
    required ShopifySyncLogRepository logRepo,
    required TransactionRepository transactionRepo,
    this.valuationMethod = 'fifo',
  })  : _api = api,
        _saleRepo = saleRepo,
        _productRepo = productRepo,
        _connRepo = connRepo,
        _mappingRepo = mappingRepo,
        _logRepo = logRepo,
        _transactionRepo = transactionRepo;

  // ═══════════════════════════════════════════════════════════
  //  Push: Revvo → Shopify
  // ═══════════════════════════════════════════════════════════

  /// Pushes local Sale changes back to the linked Shopify order.
  ///
  /// Only certain fields can be synced back (Shopify API limitations):
  /// - Payment status → financial_status note (via tags/metafield)
  /// - Order fulfilled → create/update fulfillment
  /// - Tracking number → update fulfillment tracking
  /// - Notes → order note
  ///
  /// **Line items are NOT editable via the Shopify Orders API.**
  /// Returns a [SyncResult] describing what was pushed.
  Future<Result<SyncResult>> syncOrderToShopify(Sale sale) async {
    if (sale.externalOrderId == null || sale.externalSource != 'shopify') {
      return Result.failure('Sale is not linked to a Shopify order');
    }

    final orderId = sale.externalOrderId!;
    final changes = <String>[];
    final errors = <String>[];

    // ── Notes ──────────────────────────────────────────────
    // Always push the note (cheap, idempotent)
    final noteResult = await _api.updateOrder(
      orderId: orderId,
      fields: {
        'note': sale.notes ?? '',
      },
    );
    if (noteResult.isSuccess) {
      changes.add('notes');
    } else {
      errors.add('notes: ${noteResult.error}');
    }

    // ── Fulfillment / Tracking ─────────────────────────────
    // If order status is completed (3) and we have a tracking number,
    // create a fulfillment on Shopify.
    if (sale.orderStatus == OrderStatus.completed &&
        sale.trackingNumber != null &&
        sale.trackingNumber!.isNotEmpty) {
      final fulfillResult = await _api.createFulfillment(
        orderId: orderId,
        trackingNumber: sale.trackingNumber,
      );
      if (fulfillResult.isSuccess) {
        changes.add('fulfillment');
      } else {
        // Shopify may return 422 if already fulfilled — not an error
        final err = fulfillResult.error ?? '';
        if (!err.contains('422')) {
          errors.add('fulfillment: $err');
        }
      }
    }

    // ── Log ────────────────────────────────────────────────
    await _logRepo.log(ShopifySyncLogEntry(
      id: '',
      userId: '',
      action: 'order_push',
      direction: 'masari_to_shopify',
      status: errors.isEmpty ? 'success' : 'partial',
      error: errors.isEmpty ? null : errors.join('; '),
      shopifyOrderId: orderId,
      revvoSaleId: sale.id,
      metadata: {'changed_fields': changes},
      createdAt: DateTime.now(),
    ));

    if (errors.isNotEmpty) {
      return Result.failure(
        'Partial sync — errors: ${errors.join('; ')}',
      );
    }

    return Result.success(SyncResult(
      action: 'order_push',
      changedFields: changes,
      itemCount: changes.length,
    ));
  }

  /// Pushes a Revvo stock level to Shopify for a mapped variant.
  ///
  /// Looks up the mapping to find the Shopify inventory item ID and
  /// location ID, then calls the proxy to set the absolute stock level.
  Future<Result<void>> syncInventoryToShopify({
    required String productId,
    required String variantId,
    required int newStock,
  }) async {
    // Find the mapping
    final mappingResult = await _mappingRepo.getMappingByRevvoVariantId(
      variantId,
    );
    if (!mappingResult.isSuccess || mappingResult.data == null) {
      return Result.failure(
        'No Shopify mapping found for variant $variantId',
      );
    }

    final mapping = mappingResult.data!;
    if (mapping.shopifyInventoryItemId.isEmpty) {
      return Result.failure('Mapping has no Shopify inventory item ID');
    }
    if (mapping.shopifyLocationId == null ||
        mapping.shopifyLocationId!.isEmpty) {
      // Fallback: use connection-level location
      final connResult = await _connRepo.getConnection();
      final connLocationId = connResult.isSuccess
          ? connResult.data?.shopifyLocationId
          : null;
      if (connLocationId == null || connLocationId.isEmpty) {
        return Result.failure(
          'No Shopify location ID set — '
          'please set a location in Shopify settings',
        );
      }
      // Use the connection-level location
      final result = await _api.updateInventoryLevel(
        inventoryItemId: mapping.shopifyInventoryItemId,
        locationId: connLocationId,
        available: newStock,
      );
      if (!result.isSuccess) {
        return Result.failure(result.error ?? 'Failed to push inventory');
      }
    } else {
      final result = await _api.updateInventoryLevel(
        inventoryItemId: mapping.shopifyInventoryItemId,
        locationId: mapping.shopifyLocationId!,
        available: newStock,
      );
      if (!result.isSuccess) {
        return Result.failure(result.error ?? 'Failed to push inventory');
      }
    }

    // Set echo-prevention metadata so the returning webhook is detected
    // as our own push and skipped by the Cloud Function.
    await _productRepo.markInventoryPushed(productId, variantId, newStock);

    await _logRepo.log(ShopifySyncLogEntry(
      id: '',
      userId: '',
      action: 'inventory_push',
      direction: 'masari_to_shopify',
      status: 'success',
      revvoProductId: productId,
      metadata: {
        'variant_id': variantId,
        'shopify_inventory_item_id': mapping.shopifyInventoryItemId,
        'new_stock': newStock,
      },
      createdAt: DateTime.now(),
    ));

    return Result.success(null);
  }

  /// Pushes product detail changes (title, variant prices/SKUs) to Shopify.
  ///
  /// Looks up variant mappings to find the Shopify product + variant IDs,
  /// then calls the proxy to update the product on Shopify.
  Future<Result<void>> syncProductToShopify({
    required String productId,
    required String productName,
    required List<({String variantId, double sellingPrice, String sku})> variants,
  }) async {
    // Collect Shopify variant updates by looking up each mapping
    String? shopifyProductId;
    final shopifyVariants = <Map<String, dynamic>>[];

    for (final v in variants) {
      final mapResult = await _mappingRepo.getMappingByRevvoVariantId(v.variantId);
      if (!mapResult.isSuccess || mapResult.data == null) continue;
      final mapping = mapResult.data!;
      shopifyProductId ??= mapping.shopifyProductId;

      shopifyVariants.add({
        'id': int.tryParse(mapping.shopifyVariantId) ?? mapping.shopifyVariantId,
        'price': v.sellingPrice.toStringAsFixed(2),
        'sku': v.sku,
      });
    }

    if (shopifyProductId == null || shopifyProductId.isEmpty) {
      return Result.failure('No Shopify mapping found for product');
    }

    final result = await _api.updateProduct(
      shopifyProductId: shopifyProductId,
      title: productName,
      variants: shopifyVariants.isEmpty ? null : shopifyVariants,
    );

    if (!result.isSuccess) {
      return Result.failure(result.error ?? 'Failed to push product to Shopify');
    }

    await _logRepo.log(ShopifySyncLogEntry(
      id: '',
      userId: '',
      action: 'product_push',
      direction: 'masari_to_shopify',
      status: 'success',
      revvoProductId: productId,
      metadata: {
        'shopify_product_id': shopifyProductId,
        'variants_pushed': shopifyVariants.length,
      },
      createdAt: DateTime.now(),
    ));

    return Result.success(null);
  }

  /// Pushes Revvo stock levels to Shopify for a batch of preview items.
  ///
  /// Only pushes items where [InventoryPreviewItem.hasChange] is true.
  /// Returns the count of successfully pushed variants.
  Future<Result<int>> pushInventoryBatch(
    List<InventoryPreviewItem> items,
  ) async {
    var pushed = 0;
    final errors = <String>[];

    for (final item in items) {
      if (!item.hasChange) continue;

      var result = await syncInventoryToShopify(
        productId: item.revvoProductId,
        variantId: item.revvoVariantId,
        newStock: item.revvoStock,
      );

      // One retry on failure (covers transient network / rate-limit errors)
      if (!result.isSuccess) {
        await Future.delayed(const Duration(seconds: 2));
        result = await syncInventoryToShopify(
          productId: item.revvoProductId,
          variantId: item.revvoVariantId,
          newStock: item.revvoStock,
        );
      }

      if (result.isSuccess) {
        pushed++;
      } else {
        errors.add('${item.displayName}: ${result.error}');
      }
    }

    // Update connection timestamp
    await _connRepo.updateField(
      'last_inventory_sync_at',
      DateTime.now().toIso8601String(),
    );

    await _logRepo.log(ShopifySyncLogEntry(
      id: '',
      userId: '',
      action: 'inventory_push_batch',
      direction: 'masari_to_shopify',
      status: errors.isEmpty ? 'success' : 'partial',
      error: errors.isEmpty ? null : errors.join('; '),
      metadata: {
        'total_items': items.length,
        'pushed': pushed,
        'errors': errors.length,
      },
      createdAt: DateTime.now(),
    ));

    if (errors.isNotEmpty && pushed == 0) {
      return Result.failure(errors.join('; '));
    }
    return Result.success(pushed);
  }

  /// Fetches all Shopify locations for the connected store.
  Future<Result<List<Map<String, dynamic>>>> fetchLocations() async {
    return _api.fetchLocations();
  }

  // ═══════════════════════════════════════════════════════════
  //  Pull: Shopify → Revvo
  // ═══════════════════════════════════════════════════════════

  /// Builds a preview of what pulling inventory from Shopify would change.
  ///
  /// Returns a list of [InventoryPreviewItem] — one per mapped variant —
  /// showing current Revvo stock, Shopify stock, and delta.
  /// Does NOT apply any changes.
  Future<Result<List<InventoryPreviewItem>>> previewPullInventory() async {
    // 1. Get all mappings
    final mappingsResult = await _mappingRepo.getMappings();
    if (!mappingsResult.isSuccess) {
      return Result.failure(
        mappingsResult.error ?? 'Failed to load mappings',
      );
    }

    final mappings = mappingsResult.data!;
    if (mappings.isEmpty) return Result.success([]);

    // 1b. Resolve the selected Shopify location
    final connResult = await _connRepo.getConnection();
    final locationId = connResult.isSuccess
        ? connResult.data?.shopifyLocationId
        : null;

    // 2. Gather all inventory item IDs
    final itemIds = mappings
        .where((m) => m.shopifyInventoryItemId.isNotEmpty)
        .map((m) => m.shopifyInventoryItemId)
        .toList();
    if (itemIds.isEmpty) return Result.success([]);

    // 3. Fetch levels from Shopify (filtered to selected location)
    final allLevels = <Map<String, dynamic>>[];
    for (var i = 0; i < itemIds.length; i += 50) {
      final chunk = itemIds.sublist(
        i,
        i + 50 > itemIds.length ? itemIds.length : i + 50,
      );
      final levelsResult = await _api.getInventoryLevels(
        inventoryItemIds: chunk,
        locationIds:
            locationId != null && locationId.isNotEmpty ? [locationId] : null,
      );
      if (levelsResult.isSuccess) {
        allLevels.addAll(levelsResult.data!);
      }
    }

    // 4. Build a lookup: inventoryItemId → available qty (single location)
    final stockMap = <String, int>{};
    for (final level in allLevels) {
      final id = level['inventory_item_id']?.toString() ?? '';
      final available = (level['available'] as num?)?.toInt() ?? 0;
      if (id.isNotEmpty) stockMap[id] = available;
    }

    // 5. Build preview items
    final previews = <InventoryPreviewItem>[];
    for (final mapping in mappings) {
      if (mapping.shopifyInventoryItemId.isEmpty) continue;

      final shopifyStock = stockMap[mapping.shopifyInventoryItemId];
      if (shopifyStock == null) {
        // Unmapped / no Shopify level found — show warning
        previews.add(InventoryPreviewItem(
          productName: mapping.shopifyTitle,
          variantName: null,
          revvoProductId: mapping.revvoProductId,
          revvoVariantId: mapping.revvoVariantId,
          revvoStock: 0,
          shopifyStock: 0,
          delta: 0,
          isUnmapped: true,
        ));
        continue;
      }

      // Get current Revvo stock
      final prodResult = await _productRepo.getProductById(
        mapping.revvoProductId,
      );
      int revvoStock = 0;
      String productName = mapping.shopifyTitle;
      String? variantName;
      if (prodResult.isSuccess) {
        final product = prodResult.data!;
        productName = product.name;
        final variant = product.variants.firstWhere(
          (v) => v.id == mapping.revvoVariantId,
          orElse: () => product.variants.first,
        );
        revvoStock = variant.currentStock;
        if (product.variants.length > 1) {
          variantName = variant.optionValues.values.join(' / ');
        }
      }

      final delta = shopifyStock - revvoStock;

      previews.add(InventoryPreviewItem(
        productName: productName,
        variantName: variantName,
        revvoProductId: mapping.revvoProductId,
        revvoVariantId: mapping.revvoVariantId,
        revvoStock: revvoStock,
        shopifyStock: shopifyStock,
        delta: delta,
      ));
    }

    return Result.success(previews);
  }

  /// Builds a preview of what pushing inventory to Shopify would change.
  ///
  /// Fetches current Shopify levels, compares against Revvo, returns
  /// a list of [InventoryPreviewItem] for user confirmation.
  Future<Result<List<InventoryPreviewItem>>> previewPushInventory({
    Set<String>? productIds,
  }) async {
    final mappingsResult = await _mappingRepo.getMappings();
    if (!mappingsResult.isSuccess) {
      return Result.failure(
        mappingsResult.error ?? 'Failed to load mappings',
      );
    }

    var mappings = mappingsResult.data!;
    if (productIds != null) {
      mappings = mappings
          .where((m) => productIds.contains(m.revvoProductId))
          .toList();
    }
    if (mappings.isEmpty) return Result.success([]);

    // Resolve the selected Shopify location for consistent comparison
    final connResult = await _connRepo.getConnection();
    final locationId = connResult.isSuccess
        ? connResult.data?.shopifyLocationId
        : null;

    // Fetch Shopify levels for comparison (filtered to selected location)
    final itemIds = mappings
        .where((m) => m.shopifyInventoryItemId.isNotEmpty)
        .map((m) => m.shopifyInventoryItemId)
        .toList();

    final stockMap = <String, int>{};
    for (var i = 0; i < itemIds.length; i += 50) {
      final chunk = itemIds.sublist(
        i,
        i + 50 > itemIds.length ? itemIds.length : i + 50,
      );
      final levelsResult = await _api.getInventoryLevels(
        inventoryItemIds: chunk,
        locationIds:
            locationId != null && locationId.isNotEmpty ? [locationId] : null,
      );
      if (levelsResult.isSuccess) {
        for (final level in levelsResult.data!) {
          final id = level['inventory_item_id']?.toString() ?? '';
          final available = (level['available'] as num?)?.toInt() ?? 0;
          if (id.isNotEmpty) stockMap[id] = available;
        }
      }
    }

    final previews = <InventoryPreviewItem>[];
    for (final mapping in mappings) {
      if (mapping.shopifyInventoryItemId.isEmpty) continue;

      // Check location
      if (mapping.shopifyLocationId == null ||
          mapping.shopifyLocationId!.isEmpty) {
        // Check connection-level location
        final connResult = await _connRepo.getConnection();
        final connLocationId = connResult.isSuccess
            ? connResult.data?.shopifyLocationId
            : null;
        if (connLocationId == null || connLocationId.isEmpty) {
          previews.add(InventoryPreviewItem(
            productName: mapping.shopifyTitle,
            variantName: null,
            revvoProductId: mapping.revvoProductId,
            revvoVariantId: mapping.revvoVariantId,
            revvoStock: 0,
            shopifyStock: 0,
            delta: 0,
            isUnmapped: true,
            warning: 'No Shopify location set',
          ));
          continue;
        }
      }

      final shopifyStock = stockMap[mapping.shopifyInventoryItemId];
      if (shopifyStock == null) {
        // Unmapped / no Shopify level found — show warning
        previews.add(InventoryPreviewItem(
          productName: mapping.shopifyTitle,
          variantName: null,
          revvoProductId: mapping.revvoProductId,
          revvoVariantId: mapping.revvoVariantId,
          revvoStock: 0,
          shopifyStock: 0,
          delta: 0,
          isUnmapped: true,
        ));
        continue;
      }

      final prodResult = await _productRepo.getProductById(
        mapping.revvoProductId,
      );
      int revvoStock = 0;
      String productName = mapping.shopifyTitle;
      String? variantName;
      if (prodResult.isSuccess) {
        final product = prodResult.data!;
        productName = product.name;
        final variant = product.variants.firstWhere(
          (v) => v.id == mapping.revvoVariantId,
          orElse: () => product.variants.first,
        );
        revvoStock = variant.currentStock;
        if (product.variants.length > 1) {
          variantName = variant.optionValues.values.join(' / ');
        }
      }

      final delta = revvoStock - shopifyStock;

      previews.add(InventoryPreviewItem(
        productName: productName,
        variantName: variantName,
        revvoProductId: mapping.revvoProductId,
        revvoVariantId: mapping.revvoVariantId,
        revvoStock: revvoStock,
        shopifyStock: shopifyStock,
        delta: delta,
      ));
    }

    return Result.success(previews);
  }

  /// Pulls ALL inventory levels from Shopify for mapped products and
  /// updates Revvo stock accordingly.
  ///
  /// Returns count of variants updated.
  Future<Result<int>> pullInventoryFromShopify() async {
    // 1. Get all mappings
    final mappingsResult = await _mappingRepo.getMappings();
    if (!mappingsResult.isSuccess) {
      return Result.failure(
        mappingsResult.error ?? 'Failed to load mappings',
      );
    }

    final mappings = mappingsResult.data!;
    if (mappings.isEmpty) return Result.success(0);

    // 1b. Resolve the selected Shopify location
    final connResult0 = await _connRepo.getConnection();
    final locationId = connResult0.isSuccess
        ? connResult0.data?.shopifyLocationId
        : null;

    // 2. Gather all inventory item IDs
    final itemIds = mappings
        .where((m) => m.shopifyInventoryItemId.isNotEmpty)
        .map((m) => m.shopifyInventoryItemId)
        .toList();
    if (itemIds.isEmpty) return Result.success(0);

    // 3. Fetch levels from Shopify (filtered to selected location)
    final allLevels = <Map<String, dynamic>>[];
    for (var i = 0; i < itemIds.length; i += 50) {
      final chunk = itemIds.sublist(
        i,
        i + 50 > itemIds.length ? itemIds.length : i + 50,
      );
      final levelsResult = await _api.getInventoryLevels(
        inventoryItemIds: chunk,
        locationIds:
            locationId != null && locationId.isNotEmpty ? [locationId] : null,
      );
      if (levelsResult.isSuccess) {
        allLevels.addAll(levelsResult.data!);
      }
    }

    // 4. Build a lookup: inventoryItemId → available qty (single location)
    final stockMap = <String, int>{};
    for (final level in allLevels) {
      final id = level['inventory_item_id']?.toString() ?? '';
      final available = (level['available'] as num?)?.toInt() ?? 0;
      if (id.isNotEmpty) stockMap[id] = available;
    }

    // 5. Update Revvo products
    var updated = 0;
    for (final mapping in mappings) {
      final qty = stockMap[mapping.shopifyInventoryItemId];
      if (qty == null) continue;

      // Get current Revvo stock to compute delta
      final prodResult = await _productRepo.getProductById(
        mapping.revvoProductId,
      );
      if (!prodResult.isSuccess) continue;

      final product = prodResult.data!;
      final variant = product.variants.firstWhere(
        (v) => v.id == mapping.revvoVariantId,
        orElse: () => product.variants.first,
      );

      final delta = qty - variant.currentStock;
      if (delta == 0) continue;

      await _productRepo.adjustStock(
        mapping.revvoProductId,
        mapping.revvoVariantId,
        delta,
        'Shopify inventory sync',
        unitCost: delta > 0 && variant.costPrice > 0 ? variant.costPrice : null,
        valuationMethod: valuationMethod,
      );
      updated++;
    }

    // 6. Update last sync timestamp
    await _connRepo.updateField(
      'last_inventory_sync_at',
      DateTime.now().toIso8601String(),
    );

    await _logRepo.log(ShopifySyncLogEntry(
      id: '',
      userId: '',
      action: 'inventory_pull',
      direction: 'shopify_to_masari',
      status: 'success',
      metadata: {
        'total_mappings': mappings.length,
        'items_updated': updated,
      },
      createdAt: DateTime.now(),
    ));

    return Result.success(updated);
  }

  // ═══════════════════════════════════════════════════════════
  //  Pull product details: Shopify → Revvo (title, variants, options)
  // ═══════════════════════════════════════════════════════════

  /// Fetches all products from Shopify and syncs their details
  /// (title, variant option values, prices, SKUs) into Revvo.
  /// Also auto-imports unmapped Shopify products as new Revvo products.
  ///
  /// Returns the count of products that were updated or created.
  Future<Result<int>> pullProductDetailsFromShopify() async {
    // 1. Fetch all Shopify products via proxy
    final productsResult = await _api.fetchProducts();
    if (!productsResult.isSuccess) {
      return Result.failure(
        productsResult.error ?? 'Failed to fetch Shopify products',
      );
    }

    final shopifyProducts = productsResult.data!;
    if (shopifyProducts.isEmpty) return Result.success(0);

    // 2. Fetch all existing mappings
    final mappingsResult = await _mappingRepo.getMappings();
    if (!mappingsResult.isSuccess) {
      return Result.failure(
        mappingsResult.error ?? 'Failed to load mappings',
      );
    }
    final mappings = mappingsResult.data!;

    // Build lookup: shopify_product_id → list of mappings
    final mappingsByProduct = <String, List<ShopifyProductMapping>>{};
    for (final m in mappings) {
      mappingsByProduct.putIfAbsent(m.shopifyProductId, () => []).add(m);
    }

    var changed = 0;

    for (final sp in shopifyProducts) {
      final shopifyProdId = sp['id']?.toString() ?? '';
      if (shopifyProdId.isEmpty) continue;

      var productMappings = mappingsByProduct[shopifyProdId];

      if (productMappings == null || productMappings.isEmpty) {
        // Mappings may be missing after a disconnect/reconnect.
        // Check if a Revvo product with this shopifyProductId already exists.
        final existingResult =
            await _productRepo.getProductsByShopifyProductId(shopifyProdId);
        final existing =
            (existingResult.isSuccess ? existingResult.data : null) ?? [];

        if (existing.isEmpty) {
          // Genuinely new product — auto-import
          final imported = await _autoImportShopifyProduct(sp);
          if (imported) changed++;
          continue;
        }

        // Existing product found — _autoImportShopifyProduct handles
        // relinking & dedup, so delegate to it.
        final relinked = await _autoImportShopifyProduct(sp);
        if (relinked) changed++;

        // Refresh mappings so the sync-details block below can run
        final refreshed = await _mappingRepo.getMappings();
        if (refreshed.isSuccess && refreshed.data != null) {
          productMappings = refreshed.data!
              .where((m) => m.shopifyProductId == shopifyProdId)
              .toList();
        }
        if (productMappings == null || productMappings.isEmpty) continue;
      }

      // ── Existing product: sync details ─────────────────
      final revvoProductId = productMappings.first.revvoProductId;
      final prodResult = await _productRepo.getProductById(revvoProductId);
      if (!prodResult.isSuccess || prodResult.data == null) {
        // Orphaned mappings — product was deleted but mappings remain.
        // Clean up stale mappings and re-import the product.
        for (final m in productMappings) {
          if (m.id.isNotEmpty) {
            await _mappingRepo.deleteMapping(m.id);
          }
        }
        final reimported = await _autoImportShopifyProduct(sp);
        if (reimported) changed++;
        continue;
      }

      final product = prodResult.data!;
      final shopifyTitle = sp['title']?.toString();
      final shopifyVariants = (sp['variants'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      final shopifyOptions = (sp['options'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];

      // Build shopify variant lookup
      final svMap = <String, Map<String, dynamic>>{};
      for (final sv in shopifyVariants) {
        svMap[sv['id']?.toString() ?? ''] = sv;
      }

      // Build mapping lookup: shopify_variant_id → mapping
      final mappingByShopifyVar = <String, ShopifyProductMapping>{};
      for (final m in productMappings) {
        mappingByShopifyVar[m.shopifyVariantId] = m;
      }

      var productChanged = false;

      // Sync product name
      if (shopifyTitle != null &&
          shopifyTitle.isNotEmpty &&
          product.name != shopifyTitle) {
        productChanged = true;
      }

      // Sync product status (active / draft / archived)
      final shopifyStatus = sp['status']?.toString();
      if (shopifyStatus != null &&
          shopifyStatus.isNotEmpty &&
          product.shopifyStatus != shopifyStatus) {
        productChanged = true;
      }

      // Sync product type (e.g. 'bundle')
      final shopifyProductType = sp['product_type']?.toString();
      if (shopifyProductType != null &&
          product.shopifyProductType != shopifyProductType) {
        productChanged = true;
      }

      // Sync product tags
      final shopifyTags = sp['tags']?.toString();
      if (shopifyTags != null &&
          product.shopifyTags != shopifyTags) {
        productChanged = true;
      }

      // Sync product image
      final imageData = sp['image'];
      final shopifyImageUrl = imageData is Map
          ? Map<String, dynamic>.from(imageData)['src']?.toString()
          : null;
      if (shopifyImageUrl != null &&
          shopifyImageUrl.isNotEmpty &&
          product.imageUrl != shopifyImageUrl) {
        productChanged = true;
      }

      // Sync product options
      final newOptions = shopifyOptions.map((o) {
        final values =
            (o['values'] as List?)?.map((v) => v.toString()).toList() ?? [];
        return ProductOption(
          name: (o['name'] as String?) ?? 'Option ${o['position'] ?? 1}',
          values: values,
        );
      }).toList();

      if (newOptions.length != product.options.length) {
        productChanged = true;
      }

      // Sync existing variant details
      final updatedVariants = <ProductVariant>[];
      for (final v in product.variants) {
        // Find which Shopify variant maps to this Revvo variant
        ShopifyProductMapping? mapping;
        for (final m in productMappings) {
          if (m.revvoVariantId == v.id) {
            mapping = m;
            break;
          }
        }

        if (mapping == null) {
          updatedVariants.add(v);
          continue;
        }

        final sv = svMap[mapping.shopifyVariantId];
        if (sv == null) {
          // Shopify variant no longer exists — mark for removal
          continue;
        }

        var variantChanged = false;
        var updated = v;

        // Sync selling price
        final newPrice = (num.tryParse('${sv['price']}') ?? 0).toDouble();
        if (newPrice > 0 && v.sellingPrice != newPrice) {
          updated = updated.copyWith(sellingPrice: newPrice);
          variantChanged = true;
        }

        // Sync SKU
        final newSku = sv['sku']?.toString() ?? '';
        if (newSku.isNotEmpty && v.sku != newSku) {
          updated = updated.copyWith(sku: newSku);
          variantChanged = true;
        }

        // Sync option values
        final newOptValues = <String, String>{};
        if (sv['option1'] != null) {
          newOptValues['Option 1'] = sv['option1'].toString();
        }
        if (sv['option2'] != null) {
          newOptValues['Option 2'] = sv['option2'].toString();
        }
        if (sv['option3'] != null) {
          newOptValues['Option 3'] = sv['option3'].toString();
        }
        if (newOptValues.isNotEmpty &&
            _mapsDiffer(v.optionValues, newOptValues)) {
          updated = updated.copyWith(optionValues: newOptValues);
          variantChanged = true;
        }

        updatedVariants.add(updated);
        if (variantChanged) productChanged = true;
      }

      // Detect new Shopify variants not yet mapped
      final newVariants = <ProductVariant>[];
      final newMappings = <ShopifyProductMapping>[];
      for (final sv in shopifyVariants) {
        final svId = sv['id']?.toString() ?? '';
        if (mappingByShopifyVar.containsKey(svId)) continue;

        // Unmapped — create new Revvo variant + mapping
        final newVarId =
            '${revvoProductId}_v${updatedVariants.length + newVariants.length}';
        final optValues = <String, String>{};
        if (sv['option1'] != null) {
          optValues['Option 1'] = sv['option1'].toString();
        }
        if (sv['option2'] != null) {
          optValues['Option 2'] = sv['option2'].toString();
        }
        if (sv['option3'] != null) {
          optValues['Option 3'] = sv['option3'].toString();
        }

        newVariants.add(ProductVariant(
          id: newVarId,
          optionValues: optValues,
          sku: sv['sku']?.toString() ?? '',
          costPrice: 0,
          sellingPrice:
              (num.tryParse('${sv['price']}') ?? 0).toDouble(),
          currentStock: 0,
          reorderPoint: 10,
          shopifyVariantId: svId,
          shopifyInventoryItemId:
              sv['inventory_item_id']?.toString() ?? '',
        ));

        final variantTitle =
            sv['title']?.toString() ?? sv['option1']?.toString() ?? 'Default';
        newMappings.add(ShopifyProductMapping(
          id: '',
          userId: product.userId,
          revvoProductId: revvoProductId,
          revvoVariantId: newVarId,
          shopifyProductId: shopifyProdId,
          shopifyVariantId: svId,
          shopifyInventoryItemId:
              sv['inventory_item_id']?.toString() ?? '',
          shopifySku: sv['sku']?.toString() ?? '',
          shopifyTitle:
              '${shopifyTitle ?? product.name} — $variantTitle',
          autoImported: true,
          createdAt: DateTime.now(),
        ));

        productChanged = true;
      }

      // Detect removed Shopify variants — mappings whose Shopify variant
      // no longer exists in the Shopify product payload
      final staleMappings = <ShopifyProductMapping>[];
      for (final m in productMappings) {
        if (!svMap.containsKey(m.shopifyVariantId)) {
          staleMappings.add(m);
          productChanged = true;
        }
      }

      if (!productChanged) continue;

      // Build final variants: kept (updated) + new, excluding removed
      final removedVarIds = staleMappings.map((m) => m.revvoVariantId).toSet();
      final keptVariants = updatedVariants
          .where((v) => !removedVarIds.contains(v.id))
          .toList();
      final finalVariants = [...keptVariants, ...newVariants];
      final updatedProduct = product.copyWith(
        name: (shopifyTitle != null && shopifyTitle.isNotEmpty)
            ? shopifyTitle
            : product.name,
        imageUrl: (shopifyImageUrl != null && shopifyImageUrl.isNotEmpty)
            ? shopifyImageUrl
            : product.imageUrl,
        shopifyStatus: shopifyStatus ?? product.shopifyStatus,
        shopifyProductType: shopifyProductType ?? product.shopifyProductType,
        shopifyTags: shopifyTags ?? product.shopifyTags,
        options: newOptions.isNotEmpty ? newOptions : product.options,
        variants: finalVariants,
      );
      await _productRepo.updateProduct(
        revvoProductId, updatedProduct,
        modifiedBy: 'shopify_sync',
      );

      // Create new mappings
      if (newMappings.isNotEmpty) {
        await _mappingRepo.createMappingsBatch(newMappings);
      }

      // Delete stale mappings (removed Shopify variants)
      for (final m in staleMappings) {
        if (m.id.isNotEmpty) {
          await _mappingRepo.deleteMapping(m.id);
        }
      }

      changed++;
    }

    return Result.success(changed);
  }

  /// Auto-imports a Shopify product as a new Revvo product with mappings.
  /// If a Revvo product with the same shopifyProductId already exists
  /// (e.g. after disconnect + reconnect), reuses it and recreates mappings.
  /// Deduplicates if multiple copies exist.
  Future<bool> _autoImportShopifyProduct(
    Map<String, dynamic> sp,
  ) async {
    final shopifyProdId = sp['id']?.toString() ?? '';
    final title = sp['title']?.toString() ?? 'Shopify Product';
    final variants = (sp['variants'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    final options = (sp['options'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];

    if (variants.isEmpty) return false;

    // Get current user ID from connection
    final connResult = await _connRepo.getConnection();
    if (!connResult.isSuccess || connResult.data == null) return false;
    final userId = connResult.data!.userId;

    // ── Check for existing Revvo product with same shopifyProductId ──
    final existingResult =
        await _productRepo.getProductsByShopifyProductId(shopifyProdId);
    final existingProducts =
        (existingResult.isSuccess ? existingResult.data : null) ?? [];

    if (existingProducts.isNotEmpty) {
      // Reuse the first (oldest) product; deduplicate extras
      existingProducts.sort((a, b) =>
          (a.createdAt ?? DateTime(2000)).compareTo(
              b.createdAt ?? DateTime(2000)));
      final keeper = existingProducts.first;

      // Delete duplicate copies (keep the first)
      for (var i = 1; i < existingProducts.length; i++) {
        await _productRepo.deleteProduct(existingProducts[i].id);
      }

      // Recreate variant mappings for the keeper
      final newMappings = <ShopifyProductMapping>[];
      for (var i = 0; i < variants.length; i++) {
        final sv = variants[i];
        final svId = sv['id']?.toString() ?? '';

        // Try to match by Shopify variant ID or SKU
        final shopifySku = sv['sku']?.toString() ?? '';
        final matchedVariant = keeper.variants.cast<ProductVariant?>().firstWhere(
          (v) =>
              (v!.shopifyVariantId != null && v.shopifyVariantId == svId) ||
              (shopifySku.isNotEmpty && v.sku == shopifySku),
          orElse: () => null,
        ) ?? (i < keeper.variants.length ? keeper.variants[i] : null);

        if (matchedVariant == null) continue;

        final variantTitle =
            sv['title']?.toString() ?? sv['option1']?.toString() ?? 'Default';
        newMappings.add(ShopifyProductMapping(
          id: '',
          userId: userId,
          revvoProductId: keeper.id,
          revvoVariantId: matchedVariant.id,
          shopifyProductId: shopifyProdId,
          shopifyVariantId: svId,
          shopifyInventoryItemId:
              sv['inventory_item_id']?.toString() ?? '',
          shopifySku: shopifySku,
          shopifyTitle: '$title — $variantTitle',
          autoImported: true,
          createdAt: DateTime.now(),
        ));
      }

      if (newMappings.isNotEmpty) {
        await _mappingRepo.createMappingsBatch(newMappings);
      }
      return true; // Relinked existing product
    }

    // ── No existing product — create a new one ──
    // Use deterministic ID so reconnect upserts instead of duplicating
    final prodId = 'shopify_$shopifyProdId';

    final revvoOptions = options.map((o) {
      final values =
          (o['values'] as List?)?.map((v) => v.toString()).toList() ?? [];
      return ProductOption(
        name: (o['name'] as String?) ?? 'Option ${o['position'] ?? 1}',
        values: values,
      );
    }).toList();

    final revvoVariants = <ProductVariant>[];
    final newMappings = <ShopifyProductMapping>[];

    for (var i = 0; i < variants.length; i++) {
      final sv = variants[i];
      final varId = '${prodId}_v$i';
      final svId = sv['id']?.toString() ?? '';

      final optValues = <String, String>{};
      if (sv['option1'] != null) {
        optValues['Option 1'] = sv['option1'].toString();
      }
      if (sv['option2'] != null) {
        optValues['Option 2'] = sv['option2'].toString();
      }
      if (sv['option3'] != null) {
        optValues['Option 3'] = sv['option3'].toString();
      }

      revvoVariants.add(ProductVariant(
        id: varId,
        optionValues: optValues,
        sku: sv['sku']?.toString() ?? '',
        costPrice: 0,
        sellingPrice:
            (num.tryParse('${sv['price']}') ?? 0).toDouble(),
        currentStock: 0,
        reorderPoint: 10,
        shopifyVariantId: svId,
        shopifyInventoryItemId:
            sv['inventory_item_id']?.toString() ?? '',
      ));

      final variantTitle =
          sv['title']?.toString() ?? sv['option1']?.toString() ?? 'Default';
      newMappings.add(ShopifyProductMapping(
        id: '',
        userId: userId,
        revvoProductId: prodId,
        revvoVariantId: varId,
        shopifyProductId: shopifyProdId,
        shopifyVariantId: svId,
        shopifyInventoryItemId:
            sv['inventory_item_id']?.toString() ?? '',
        shopifySku: sv['sku']?.toString() ?? '',
        shopifyTitle: '$title — $variantTitle',
        autoImported: true,
        createdAt: DateTime.now(),
      ));
    }

    final imageData = sp['image'];
    final imageUrl = imageData is Map
        ? Map<String, dynamic>.from(imageData)['src']?.toString()
        : null;

    final product = Product(
      id: prodId,
      userId: userId,
      name: title,
      category: 'shopify_import',
      supplier: '',
      unitOfMeasure: 'pcs',
      isMaterial: false,
      shopifyProductId: shopifyProdId,
      shopifyStatus: sp['status']?.toString(),
      shopifyProductType: sp['product_type']?.toString(),
      shopifyTags: sp['tags']?.toString(),
      imageUrl: imageUrl,
      options: revvoOptions,
      variants: revvoVariants,
    );

    final createResult = await _productRepo.createProduct(product);
    if (!createResult.isSuccess) return false;

    if (newMappings.isNotEmpty) {
      await _mappingRepo.createMappingsBatch(newMappings);
    }

    return true;
  }

  /// Returns true if two string maps differ.
  bool _mapsDiffer(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return true;
    for (final key in a.keys) {
      if (a[key] != b[key]) return true;
    }
    return false;
  }

  /// Applies the cached pull preview items directly.
  ///
  /// Instead of re-fetching from Shopify, this uses the exact deltas
  /// the user reviewed in the preview table. Returns the count of
  /// variants updated.
  Future<Result<int>> applyPullPreview(
    List<InventoryPreviewItem> items,
  ) async {
    var updated = 0;
    for (final item in items) {
      if (!item.hasChange) continue;

      // delta = shopifyStock - revvoStock (already computed in preview)
      // For positive deltas (stock increase), pass current WAC so a cost
      // layer is created for the added units.
      double? unitCost;
      if (item.delta > 0) {
        final prodResult = await _productRepo.getProductById(item.revvoProductId);
        if (prodResult.isSuccess) {
          final variant = prodResult.data!.variants.firstWhere(
            (v) => v.id == item.revvoVariantId,
            orElse: () => prodResult.data!.variants.first,
          );
          if (variant.costPrice > 0) unitCost = variant.costPrice;
        }
      }
      await _productRepo.adjustStock(
        item.revvoProductId,
        item.revvoVariantId,
        item.delta,
        'Shopify inventory sync',
        unitCost: unitCost,
        valuationMethod: valuationMethod,
      );
      updated++;
    }

    // Update last sync timestamp
    await _connRepo.updateField(
      'last_inventory_sync_at',
      DateTime.now().toIso8601String(),
    );

    await _logRepo.log(ShopifySyncLogEntry(
      id: '',
      userId: '',
      action: 'inventory_pull_preview',
      direction: 'shopify_to_masari',
      status: 'success',
      metadata: {
        'total_items': items.length,
        'items_updated': updated,
      },
      createdAt: DateTime.now(),
    ));

    return Result.success(updated);
  }

  /// Imports historical Shopify orders as Revvo Sales.
  ///
  /// Fetches orders between [from] and [to] (max 3 months)
  /// and creates Sales for any that don't already exist.
  ///
  /// Returns the number of newly imported orders.
  Future<Result<ImportResult>> importOrders({
    required DateTime from,
    required DateTime to,
  }) async {
    // Enforce 3-month max window
    final maxTo = from.add(const Duration(days: 93));
    final effectiveTo = to.isAfter(maxTo) ? maxTo : to;

    // Fetch orders from Shopify
    final ordersResult = await _api.fetchOrders(
      since: from,
      until: effectiveTo,
    );
    if (!ordersResult.isSuccess) {
      return Result.failure(
        ordersResult.error ?? 'Failed to fetch Shopify orders',
      );
    }

    final orders = ordersResult.data!;
    if (orders.isEmpty) {
      return Result.success(ImportResult(
        imported: 0,
        skipped: 0,
        errors: 0,
        total: 0,
      ));
    }

    // Get existing external order IDs to skip duplicates
    final existingResult = await _saleRepo.getSales();
    final existingOrderIds = <String>{};
    if (existingResult.isSuccess) {
      for (final sale in existingResult.data!) {
        if (sale.externalOrderId != null) {
          existingOrderIds.add(sale.externalOrderId!);
        }
      }
    }

    var imported = 0;
    var skipped = 0;
    var errorCount = 0;

    // ── Pre-fetch Shopify inventory item costs ────────────
    // Collect all unique variant IDs and product IDs from orders
    final variantIdsToFetch = <String>{};
    final productIdsFromOrders = <String>{};
    for (final order in orders) {
      final shopifyOrderId = order['id']?.toString();
      if (shopifyOrderId == null ||
          existingOrderIds.contains(shopifyOrderId)) {
        continue;
      }
      final lineItems = order['line_items'] as List<dynamic>? ?? [];
      for (final li in lineItems) {
        final lineItem = Map<String, dynamic>.from(li as Map);
        final svId =
            (lineItem['variant_id'] ?? lineItem['product_id']).toString();
        variantIdsToFetch.add(svId);
        final pid = lineItem['product_id']?.toString();
        if (pid != null && pid != 'null') {
          productIdsFromOrders.add(pid);
        }
      }
    }

    // Resolve variant IDs → inventory item IDs via existing mappings
    final costMap = <String, double>{}; // shopifyVariantId → cost
    final inventoryItemIds = <String>{};
    final invItemToVariant = <String, String>{}; // invItemId → variantId
    final unmappedVariantIds = <String>{};
    for (final svId in variantIdsToFetch) {
      final mr = await _mappingRepo.getMappingsByShopifyVariantId(svId);
      if (mr.isSuccess && mr.data!.isNotEmpty) {
        final invId = mr.data!.first.shopifyInventoryItemId;
        if (invId.isNotEmpty) {
          inventoryItemIds.add(invId);
          invItemToVariant[invId] = svId;
        } else {
          unmappedVariantIds.add(svId);
        }
      } else {
        unmappedVariantIds.add(svId);
      }
    }

    // For unmapped variants, fetch Shopify products to get inventory_item_ids
    if (unmappedVariantIds.isNotEmpty && productIdsFromOrders.isNotEmpty) {
      final productsResult = await _api.fetchProducts(
        productIds: productIdsFromOrders.join(','),
      );
      if (productsResult.isSuccess) {
        for (final product in productsResult.data!) {
          final variants = product['variants'] as List<dynamic>? ?? [];
          for (final v in variants) {
            final variant = Map<String, dynamic>.from(v as Map);
            final vId = variant['id']?.toString();
            final invItemId = variant['inventory_item_id']?.toString();
            if (vId != null &&
                invItemId != null &&
                invItemId != 'null' &&
                unmappedVariantIds.contains(vId)) {
              inventoryItemIds.add(invItemId);
              invItemToVariant[invItemId] = vId;
            }
          }
        }
      }
    }

    // Batch-fetch costs from Shopify
    if (inventoryItemIds.isNotEmpty) {
      final costResult = await _api.getInventoryItems(
          inventoryItemIds: inventoryItemIds.toList());
      if (costResult.isSuccess) {
        for (final item in costResult.data!) {
          final invId = item['id']?.toString() ?? '';
          final cost =
              double.tryParse(item['cost']?.toString() ?? '0') ?? 0;
          final svId = invItemToVariant[invId];
          if (svId != null && cost > 0) {
            costMap[svId] = cost;
          }
        }
      }
    }

    for (final order in orders) {
      final shopifyOrderId = order['id']?.toString();
      if (shopifyOrderId == null) continue;

      // Skip already-imported orders
      if (existingOrderIds.contains(shopifyOrderId)) {
        skipped++;
        continue;
      }

      try {
        await _importSingleOrder(order, costMap);
        imported++;
      } catch (e) {
        errorCount++;
      }
    }

    // Update connection's last sync timestamp
    await _connRepo.updateField(
      'last_order_sync_at',
      DateTime.now().toIso8601String(),
    );

    await _logRepo.log(ShopifySyncLogEntry(
      id: '',
      userId: '',
      action: 'order_import',
      direction: 'shopify_to_masari',
      status: errorCount == 0 ? 'success' : 'partial',
      metadata: {
        'total': orders.length,
        'imported': imported,
        'skipped': skipped,
        'errors': errorCount,
        'from': from.toIso8601String(),
        'to': effectiveTo.toIso8601String(),
      },
      createdAt: DateTime.now(),
    ));

    return Result.success(ImportResult(
      imported: imported,
      skipped: skipped,
      errors: errorCount,
      total: orders.length,
    ));
  }

  // ── Private ──────────────────────────────────────────────

  /// Converts a single Shopify order JSON into a Revvo Sale and
  /// creates it with revenue + COGS transactions.
  Future<void> _importSingleOrder(
    Map<String, dynamic> order,
    Map<String, double> shopifyCostMap,
  ) async {
    final shopifyOrderId = order['id'].toString();
    final customer = order['customer'] is Map
        ? Map<String, dynamic>.from(order['customer'] as Map)
        : <String, dynamic>{};
    final shipping = order['shipping_address'] is Map
        ? Map<String, dynamic>.from(order['shipping_address'] as Map)
        : <String, dynamic>{};
    final shippingLines =
        order['shipping_lines'] as List<dynamic>? ?? [];
    final lineItems = order['line_items'] as List<dynamic>? ?? [];

    // Build SaleItems
    final saleItems = <SaleItem>[];
    for (final li in lineItems) {
      final lineItem = Map<String, dynamic>.from(li as Map);
      final shopifyVariantId =
          (lineItem['variant_id'] ?? lineItem['product_id']).toString();

      // Try to resolve mapping
      String? productId;
      String? variantId;
      String? variantName;
      double costPrice = 0;

      final mappingResult = await _mappingRepo.getMappingsByShopifyVariantId(
        shopifyVariantId,
      );
      if (mappingResult.isSuccess && mappingResult.data!.isNotEmpty) {
        final m = mappingResult.data!.first;
        productId = m.revvoProductId;
        variantId = m.revvoVariantId;
        variantName = lineItem['variant_title'] as String?;

        // Use Revvo's cost price
        final prodResult = await _productRepo.getProductById(productId);
        if (prodResult.isSuccess) {
          final v = prodResult.data!.variants.firstWhere(
            (v) => v.id == variantId,
            orElse: () => prodResult.data!.variants.first,
          );
          costPrice = v.costPrice;
        }
      }

      // Fall back to Shopify's inventory item cost
      if (costPrice <= 0) {
        costPrice = shopifyCostMap[shopifyVariantId] ?? 0;

        // Backfill cost on the Revvo product so future lookups use it
        if (costPrice > 0 && productId != null && variantId != null) {
          final prodResult = await _productRepo.getProductById(productId);
          if (prodResult.isSuccess) {
            final prod = prodResult.data!;
            final updatedVariants = prod.variants.map((v) {
              if (v.id == variantId && v.costPrice <= 0) {
                return v.copyWith(costPrice: costPrice);
              }
              return v;
            }).toList();
            await _productRepo.updateProduct(
              productId,
              prod.copyWith(variants: updatedVariants),
              modifiedBy: 'shopify_sync',
            );
          }
        }
      }

      saleItems.add(SaleItem(
        productId: productId,
        variantId: variantId,
        variantName: variantName,
        productName: lineItem['title'] as String? ?? 'Unknown',
        quantity: (lineItem['quantity'] as num?)?.toDouble() ?? 1,
        unitPrice: double.tryParse(
              lineItem['price']?.toString() ?? '0',
            ) ??
            0,
        costPrice: costPrice,
        shopifyLineItemId: lineItem['id']?.toString(),
      ));
    }

    // Compute financials
    final subtotal = saleItems.fold<double>(
      0,
      (sum, item) => sum + item.quantity * item.unitPrice,
    );
    final taxAmount =
        double.tryParse(order['total_tax']?.toString() ?? '0') ?? 0;
    final totalDiscounts = double.tryParse(
          order['total_discounts']?.toString() ?? '0',
        ) ??
        0;
    // Use discounted_price (net of shipping discounts) — what the customer
    // actually paid for shipping.  Falls back to price if unavailable.
    final shippingCost = shippingLines.fold<double>(0, (sum, sl) {
      final line = Map<String, dynamic>.from(sl as Map);
      return sum +
          (double.tryParse(
                (line['discounted_price'] ?? line['price'])?.toString() ?? '0',
              ) ??
              0);
    });
    // Shipping discounts are included in total_discounts but should only
    // reduce shipping revenue, not product revenue.
    final shippingDiscount = shippingLines.fold<double>(0, (sum, sl) {
      final line = Map<String, dynamic>.from(sl as Map);
      final gross = double.tryParse(line['price']?.toString() ?? '0') ?? 0;
      final net = double.tryParse(
            (line['discounted_price'] ?? line['price'])?.toString() ?? '0',
          ) ??
          0;
      return sum + (gross - net);
    });
    final discountAmount = totalDiscounts - shippingDiscount;

    final paymentStatus = _mapPaymentStatus(
      order['financial_status'] as String?,
    );
    final fulfillmentStatus = _mapFulfillmentStatus(
      order['fulfillment_status'] as String?,
    );
    final orderStatus = _deriveOrderStatus(
      paymentStatus,
      fulfillmentStatus,
      order['cancel_reason'] as String?,
      order['cancelled_at'] as String?,
    );

    final fulfillments = order['fulfillments'] as List<dynamic>? ?? [];
    final firstFulfillment = fulfillments.isNotEmpty
        ? Map<String, dynamic>.from(fulfillments[0] as Map)
        : null;

    // Use deterministic ID matching webhook pattern to prevent duplicates
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final saleId = 'shopify_${uid}_$shopifyOrderId';
    final sale = Sale(
      id: saleId,
      userId: '', // will be injected by repo
      customerName: [
        customer['first_name'],
        customer['last_name'],
      ].where((s) => s != null && s.toString().isNotEmpty).join(' '),
      customerEmail: customer['email'] as String?,
      customerPhone: customer['phone'] as String?,
      date: DateTime.tryParse(order['created_at']?.toString() ?? '') ??
          DateTime.now(),
      items: saleItems,
      taxAmount: taxAmount,
      discountAmount: discountAmount,
      paymentMethod: ((order['payment_gateway_names'] as List<dynamic>?) ??
              [])
          .firstOrNull
          ?.toString() ??
          'Shopify',
      paymentStatus: paymentStatus,
      amountPaid: paymentStatus == PaymentStatus.paid
          ? subtotal + taxAmount - totalDiscounts + shippingCost +
              shippingDiscount
          : 0,
      orderStatus: orderStatus,
      fulfillmentStatus: fulfillmentStatus,
      externalOrderId: shopifyOrderId,
      externalSource: 'shopify',
      shopifyOrderNumber: order['order_number']?.toString(),
      shippingAddress: [
        shipping['address1'],
        shipping['city'],
        shipping['country'],
      ].where((s) => s != null && s.toString().isNotEmpty).join(', '),
      shippingCost: shippingCost,
      trackingNumber: firstFulfillment?['tracking_number'] as String?,
      deliveryStatus: _mapDeliveryStatus(
        order['fulfillment_status'] as String?,
      ),
    );

    // ── Build Accounting Transactions ─────────────────────
    final transactionTime = sale.date;
    final transactions = <transaction_model.Transaction>[];

    // Skip financial transactions for already-cancelled orders —
    // they have no P&L impact and don't need reversals.
    if (orderStatus != OrderStatus.cancelled) {
      // Revenue (netRevenue = subtotal − discount, excludes tax & shipping)
      transactions.add(transaction_model.Transaction(
        id: 'sale_rev_$saleId',
        userId: '',
        amount: sale.netRevenue,
        categoryId: 'cat_sales_revenue',
        dateTime: transactionTime,
        title: 'Sale Revenue (Shopify)',
        note: sale.customerName != null
            ? 'Customer: ${sale.customerName}'
            : null,
        paymentMethod: sale.paymentMethod,
        saleId: saleId,
        excludeFromPL: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // COGS — always create even if $0, matching webhook processor behavior
      transactions.add(transaction_model.Transaction(
        id: 'sale_cogs_$saleId',
        userId: '',
        amount: -sale.totalCogs,
        categoryId: 'cat_cogs',
        dateTime: transactionTime,
        title: 'Cost of Goods Sold (Shopify)',
        note: 'Auto-generated from Shopify order',
        saleId: saleId,
        excludeFromPL: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      // Shipping revenue (customer-paid shipping = income)
      if (sale.shippingCost > 0) {
        transactions.add(transaction_model.Transaction(
          id: 'sale_ship_$saleId',
          userId: '',
          amount: sale.shippingCost,
          categoryId: 'cat_shipping',
          dateTime: transactionTime,
          title: 'Shipping — ${sale.customerName ?? 'Shopify Order'}',
          note: 'Auto-generated shipping revenue',
          saleId: saleId,
          excludeFromPL: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }

      // Tax
      if (sale.taxAmount > 0) {
        transactions.add(transaction_model.Transaction(
          id: 'sale_tax_$saleId',
          userId: '',
          amount: -sale.taxAmount,
          categoryId: 'cat_tax_payable',
          dateTime: transactionTime,
          title: 'Sales Tax / VAT (Shopify)',
          saleId: saleId,
          excludeFromPL: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }
    } // end if (orderStatus != OrderStatus.cancelled)

    // ── Atomic write: sale + all transactions in one batch ─
    final writeResult =
        await _saleRepo.createSaleWithTransactions(sale, transactions);
    if (!writeResult.isSuccess) {
      throw Exception(writeResult.error ?? 'Failed to save order');
    }

    // ── Deduct Inventory (skip for cancelled orders) ─────
    if (orderStatus != OrderStatus.cancelled) {
      for (final item in sale.items) {
        if (item.productId != null && item.quantity > 0) {
          final vId = item.variantId ?? '${item.productId}_v0';
          await _productRepo.adjustStock(
            item.productId!,
            vId,
            -item.quantity.toInt(),
            'Shopify order imported',
            valuationMethod: valuationMethod,
          );
        }
      }
    }
  }

  PaymentStatus _mapPaymentStatus(String? status) {
    switch (status) {
      case 'paid':
        return PaymentStatus.paid;
      case 'refunded':
        return PaymentStatus.refunded;
      case 'partially_paid':
      case 'partially_refunded':
        return PaymentStatus.partial;
      default:
        return PaymentStatus.unpaid;
    }
  }

  FulfillmentStatus _mapFulfillmentStatus(String? status) {
    switch (status) {
      case 'fulfilled':
        return FulfillmentStatus.fulfilled;
      case 'partial':
        return FulfillmentStatus.partial;
      default:
        return FulfillmentStatus.unfulfilled;
    }
  }

  OrderStatus _deriveOrderStatus(
    PaymentStatus payment,
    FulfillmentStatus fulfillment,
    String? cancelReason,
    [String? cancelledAt,]
  ) {
    if (cancelledAt != null && cancelledAt.isNotEmpty ||
        cancelReason == 'declined' || cancelReason == 'fraud') {
      return OrderStatus.cancelled;
    }
    if (payment == PaymentStatus.paid &&
        fulfillment == FulfillmentStatus.fulfilled) {
      return OrderStatus.completed;
    }
    if (payment.index >= 1 || fulfillment.index >= 1) {
      return OrderStatus.processing;
    }
    return OrderStatus.confirmed;
  }

  String _mapDeliveryStatus(String? status) {
    switch (status) {
      case 'fulfilled':
        return 'delivered';
      case 'partial':
        return 'partially_shipped';
      default:
        return 'pending';
    }
  }
}

// ═══════════════════════════════════════════════════════════
//  Result types
// ═══════════════════════════════════════════════════════════

/// Result of a single sync operation.
class SyncResult {
  final String action;
  final List<String> changedFields;
  final int itemCount;

  const SyncResult({
    required this.action,
    required this.changedFields,
    required this.itemCount,
  });
}

/// Result of a bulk import operation.
class ImportResult {
  final int imported;
  final int skipped;
  final int errors;
  final int total;

  const ImportResult({
    required this.imported,
    required this.skipped,
    required this.errors,
    required this.total,
  });

  bool get hasErrors => errors > 0;
  bool get isComplete => imported + skipped + errors == total;
}

/// Preview item for inventory sync — one per mapped variant.
class InventoryPreviewItem {
  final String productName;
  final String? variantName;
  final String revvoProductId;
  final String revvoVariantId;
  final int revvoStock;
  final int shopifyStock;
  final int delta;
  final bool isUnmapped;
  final String? warning;

  const InventoryPreviewItem({
    required this.productName,
    this.variantName,
    required this.revvoProductId,
    required this.revvoVariantId,
    required this.revvoStock,
    required this.shopifyStock,
    required this.delta,
    this.isUnmapped = false,
    this.warning,
  });

  /// Display name combining product and variant.
  String get displayName =>
      variantName != null ? '$productName — $variantName' : productName;

  /// Whether this item has a change to apply.
  bool get hasChange => delta != 0 && !isUnmapped;
}

// ═══════════════════════════════════════════════════════════
//  Riverpod Providers
// ═══════════════════════════════════════════════════════════

final shopifyApiServiceProvider = Provider<ShopifyApiService>((ref) {
  return ShopifyApiService();
});

final shopifySyncServiceProvider = Provider<ShopifySyncService>((ref) {
  return ShopifySyncService(
    api: ref.read(shopifyApiServiceProvider),
    saleRepo: ref.read(saleRepositoryProvider),
    productRepo: ref.read(productRepositoryProvider),
    connRepo: ref.read(shopifyConnectionRepositoryProvider),
    mappingRepo: ref.read(shopifyProductMappingRepositoryProvider),
    logRepo: ref.read(shopifySyncLogRepositoryProvider),
    transactionRepo: ref.read(transactionRepositoryProvider),
    valuationMethod: ref.read(appSettingsProvider).valuationMethod,
  );
});
