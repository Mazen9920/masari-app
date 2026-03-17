import '../../shared/models/product_model.dart';
import '../services/result.dart';

/// Contract for inventory/product data operations.
abstract class ProductRepository {
  /// Fetches all products, optionally paginated.
  Future<Result<List<Product>>> getProducts({
    int? limit,
    String? startAfterId,
  });

  /// Fetches a single product by ID.
  Future<Result<Product>> getProductById(String id);

  /// Creates a new product.
  Future<Result<Product>> createProduct(Product product);

  /// Updates an existing product.
  ///
  /// [modifiedBy] controls the `_last_modified_by` flag for echo prevention.
  /// Defaults to `'masari'`. Set to `'shopify_sync'` when pulling from Shopify.
  Future<Result<Product>> updateProduct(String id, Product updated, {String modifiedBy = 'masari'});

  /// Deletes a product by ID.
  Future<Result<void>> deleteProduct(String id);

  /// Finds products matching a Shopify product ID (for deduplication).
  Future<Result<List<Product>>> getProductsByShopifyProductId(String shopifyProductId);

  /// Adjusts stock level for a specific variant of a product.
  /// When [unitCost] is provided with a positive [delta], a new cost layer
  /// is created and the variant's cost price is recalculated.
  /// [valuationMethod] controls how cost layers are consumed on negative deltas:
  /// 'fifo' (default), 'lifo', or 'average'.
  /// [skipCostLayer] when true, adjusts quantity without creating a cost layer
  /// or recalculating WAC — used for manufactured products whose cost is
  /// managed separately.
  Future<Result<Product>> adjustStock(String id, String variantId, int delta, String reason, {double? unitCost, String valuationMethod = 'fifo', String? supplierName, bool clearLegacyLayers = false, bool skipCostLayer = false});

  /// Performs a full breakdown operation atomically:
  /// deducts [qty] from [sourceVariantId] and adds proportional quantities
  /// to each output variant, all within a single Firestore transaction.
  /// [outputAllocations] maps output variantId → (quantity, unitCost).
  Future<Result<Product>> breakdownStock({
    required String productId,
    required String sourceVariantId,
    required int qty,
    required String valuationMethod,
    required Map<String, ({int quantity, double unitCost})> outputAllocations,
  });
}
