/// Maps a Revvo product/variant to a Shopify product/variant.
///
/// This decoupled mapping table allows:
/// - Auto-import of Shopify products into Revvo inventory
/// - Manual override (re-link a Shopify variant to a different Revvo product)
/// - SKU-based auto-matching
/// - Independent ID spaces (Revvo UUIDs vs Shopify numeric IDs)
class ShopifyProductMapping {
  final String id;
  final String userId;

  // ── Revvo side ──────────────────────────────────────────
  final String revvoProductId;
  final String revvoVariantId;

  // ── Shopify side ─────────────────────────────────────────
  final String shopifyProductId;
  final String shopifyVariantId;

  /// Shopify inventory item ID — needed for stock-level API calls.
  final String shopifyInventoryItemId;

  /// Shopify SKU at time of mapping (for display / re-matching).
  final String shopifySku;

  /// Shopify product + variant title (for display in mapping UI).
  final String shopifyTitle;

  /// Shopify location ID for inventory operations.
  final String? shopifyLocationId;

  /// Whether this mapping was auto-created during import or manually linked.
  final bool autoImported;

  final DateTime createdAt;

  const ShopifyProductMapping({
    required this.id,
    required this.userId,
    required this.revvoProductId,
    required this.revvoVariantId,
    required this.shopifyProductId,
    required this.shopifyVariantId,
    required this.shopifyInventoryItemId,
    this.shopifySku = '',
    this.shopifyTitle = '',
    this.shopifyLocationId,
    this.autoImported = false,
    required this.createdAt,
  });

  // ── copyWith ─────────────────────────────────────────────

  ShopifyProductMapping copyWith({
    String? id,
    String? userId,
    String? revvoProductId,
    String? revvoVariantId,
    String? shopifyProductId,
    String? shopifyVariantId,
    String? shopifyInventoryItemId,
    String? shopifySku,
    String? shopifyTitle,
    String? shopifyLocationId,
    bool? autoImported,
    DateTime? createdAt,
  }) {
    return ShopifyProductMapping(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      revvoProductId: revvoProductId ?? this.revvoProductId,
      revvoVariantId: revvoVariantId ?? this.revvoVariantId,
      shopifyProductId: shopifyProductId ?? this.shopifyProductId,
      shopifyVariantId: shopifyVariantId ?? this.shopifyVariantId,
      shopifyInventoryItemId: shopifyInventoryItemId ?? this.shopifyInventoryItemId,
      shopifySku: shopifySku ?? this.shopifySku,
      shopifyTitle: shopifyTitle ?? this.shopifyTitle,
      shopifyLocationId: shopifyLocationId ?? this.shopifyLocationId,
      autoImported: autoImported ?? this.autoImported,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ── Serialization ────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'masari_product_id': revvoProductId,
        'masari_variant_id': revvoVariantId,
        'shopify_product_id': shopifyProductId,
        'shopify_variant_id': shopifyVariantId,
        'shopify_inventory_item_id': shopifyInventoryItemId,
        'shopify_sku': shopifySku,
        'shopify_title': shopifyTitle,
        if (shopifyLocationId != null) 'shopify_location_id': shopifyLocationId,
        'auto_imported': autoImported,
        'created_at': createdAt.toIso8601String(),
      };

  factory ShopifyProductMapping.fromJson(Map<String, dynamic> json) {
    return ShopifyProductMapping(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      revvoProductId: json['masari_product_id'] as String,
      revvoVariantId: json['masari_variant_id'] as String,
      shopifyProductId: json['shopify_product_id'] as String,
      shopifyVariantId: json['shopify_variant_id'] as String,
      shopifyInventoryItemId: json['shopify_inventory_item_id'] as String,
      shopifySku: json['shopify_sku'] as String? ?? '',
      shopifyTitle: json['shopify_title'] as String? ?? '',
      shopifyLocationId: json['shopify_location_id'] as String?,
      autoImported: json['auto_imported'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
