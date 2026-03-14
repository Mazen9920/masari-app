import '../../shared/models/shopify_product_mapping_model.dart';
import '../services/result.dart';

/// Contract for Shopify product mapping operations.
abstract class ShopifyProductMappingRepository {
  /// Fetches all mappings for the current user.
  Future<Result<List<ShopifyProductMapping>>> getMappings();

  /// Fetches a single mapping by its ID.
  Future<Result<ShopifyProductMapping>> getMappingById(String id);

  /// Finds mappings by Shopify variant ID (for webhook processing).
  Future<Result<List<ShopifyProductMapping>>> getMappingsByShopifyVariantId(
      String shopifyVariantId);

  /// Finds a mapping by Masari variant ID (for push-to-Shopify).
  Future<Result<ShopifyProductMapping?>> getMappingByMasariVariantId(
      String masariVariantId);

  /// Finds a mapping by Shopify inventory item ID (for stock-level sync).
  Future<Result<ShopifyProductMapping?>> getMappingByInventoryItemId(
      String shopifyInventoryItemId);

  /// Creates a new mapping.
  Future<Result<ShopifyProductMapping>> createMapping(
      ShopifyProductMapping mapping);

  /// Creates multiple mappings in a batch (for auto-import).
  Future<Result<List<ShopifyProductMapping>>> createMappingsBatch(
      List<ShopifyProductMapping> mappings);

  /// Updates an existing mapping (e.g. manual re-link).
  Future<Result<ShopifyProductMapping>> updateMapping(
      String id, ShopifyProductMapping updated);

  /// Deletes a mapping by ID.
  Future<Result<void>> deleteMapping(String id);

  /// Deletes all mappings for the current user (on Shopify disconnect).
  Future<Result<void>> deleteAllMappings();
}
