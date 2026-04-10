/// Represents a user's connection to their Shopify store.
///
/// Stores sync preferences, webhook registration IDs, and connection status.
///
/// The Shopify access token is stored only in the Firestore document and
/// accessed exclusively by Cloud Functions — it is intentionally excluded
/// from this client-side model for security.
class ShopifyConnection {
  final String userId;
  final String shopDomain;

  /// Granted OAuth scopes, e.g. ["read_orders", "write_orders", ...].
  final List<String> scopes;

  /// Whether to sync Shopify orders ↔ Revvo sales.
  final bool syncOrdersEnabled;

  /// Whether inventory sync is enabled (manual, not automatic).
  final bool syncInventoryEnabled;

  /// Direction of last/preferred inventory sync.
  /// "shopify_to_masari" | "masari_to_shopify" | null
  final String? inventorySyncDirection;

  /// Inventory sync mode: "always" (auto-sync bar visible) or "on_demand".
  /// Default is "on_demand" — user manually triggers sync from the screen.
  final String inventorySyncMode;

  /// Timestamp of the most recent order sync completion.
  final DateTime? lastOrderSyncAt;

  /// Timestamp of the most recent inventory sync completion.
  final DateTime? lastInventorySyncAt;

  /// Maps webhook topic → Shopify webhook ID, e.g.
  /// { "orders/create": "123456", "orders/updated": "123457" }
  final Map<String, String> webhookIds;

  /// How far back to import historical orders (max 3 months).
  final DateTime? importFromDate;

  /// When the Shopify connection was first established.
  final DateTime connectedAt;

  /// Current connection health.
  /// "active" — working normally
  /// "disconnected" — user disconnected or app uninstalled from Shopify
  /// "error" — token invalid or API errors
  final String status;

  /// Shopify location ID used for inventory level operations.
  final String? shopifyLocationId;

  /// Human-readable name of the selected Shopify location.
  final String? shopifyLocationName;

  /// Whether the setup wizard has been completed.
  final bool setupCompleted;

  /// IANA timezone of the Shopify store (e.g. "Africa/Cairo").
  /// Used for timezone-aware period boundary calculations.
  final String? shopTimezone;

  const ShopifyConnection({
    required this.userId,
    required this.shopDomain,
    this.scopes = const [],
    this.syncOrdersEnabled = true,
    this.syncInventoryEnabled = false,
    this.inventorySyncDirection,
    this.inventorySyncMode = 'on_demand',
    this.lastOrderSyncAt,
    this.lastInventorySyncAt,
    this.webhookIds = const {},
    this.importFromDate,
    required this.connectedAt,
    this.status = 'active',
    this.shopifyLocationId,
    this.shopifyLocationName,
    this.setupCompleted = false,
    this.shopTimezone,
  });

  // ── Computed ─────────────────────────────────────────────

  bool get isActive => status == 'active';
  bool get isDisconnected => status == 'disconnected';
  bool get hasError => status == 'error';

  /// Formatted shop name without ".myshopify.com" suffix.
  String get shopName {
    final idx = shopDomain.indexOf('.myshopify.com');
    return idx > 0 ? shopDomain.substring(0, idx) : shopDomain;
  }

  // ── copyWith ─────────────────────────────────────────────

  ShopifyConnection copyWith({
    String? userId,
    String? shopDomain,
    List<String>? scopes,
    bool? syncOrdersEnabled,
    bool? syncInventoryEnabled,
    String? inventorySyncDirection,
    String? inventorySyncMode,
    DateTime? lastOrderSyncAt,
    DateTime? lastInventorySyncAt,
    Map<String, String>? webhookIds,
    DateTime? importFromDate,
    DateTime? connectedAt,
    String? status,
    String? shopifyLocationId,
    String? shopifyLocationName,
    bool? setupCompleted,
    String? shopTimezone,
  }) {
    return ShopifyConnection(
      userId: userId ?? this.userId,
      shopDomain: shopDomain ?? this.shopDomain,
      scopes: scopes ?? this.scopes,
      syncOrdersEnabled: syncOrdersEnabled ?? this.syncOrdersEnabled,
      syncInventoryEnabled: syncInventoryEnabled ?? this.syncInventoryEnabled,
      inventorySyncDirection: inventorySyncDirection ?? this.inventorySyncDirection,
      inventorySyncMode: inventorySyncMode ?? this.inventorySyncMode,
      lastOrderSyncAt: lastOrderSyncAt ?? this.lastOrderSyncAt,
      lastInventorySyncAt: lastInventorySyncAt ?? this.lastInventorySyncAt,
      webhookIds: webhookIds ?? this.webhookIds,
      importFromDate: importFromDate ?? this.importFromDate,
      connectedAt: connectedAt ?? this.connectedAt,
      status: status ?? this.status,
      shopifyLocationId: shopifyLocationId ?? this.shopifyLocationId,
      shopifyLocationName: shopifyLocationName ?? this.shopifyLocationName,
      setupCompleted: setupCompleted ?? this.setupCompleted,
      shopTimezone: shopTimezone ?? this.shopTimezone,
    );
  }

  // ── Serialization ────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'shop_domain': shopDomain,
        // access_token intentionally omitted — managed only by Cloud Functions
        'scopes': scopes,
        'sync_orders_enabled': syncOrdersEnabled,
        'sync_inventory_enabled': syncInventoryEnabled,
        'inventory_sync_mode': inventorySyncMode,
        if (inventorySyncDirection != null)
          'inventory_sync_direction': inventorySyncDirection,
        if (lastOrderSyncAt != null)
          'last_order_sync_at': lastOrderSyncAt!.toIso8601String(),
        if (lastInventorySyncAt != null)
          'last_inventory_sync_at': lastInventorySyncAt!.toIso8601String(),
        'webhook_ids': webhookIds,
        if (importFromDate != null)
          'import_from_date': importFromDate!.toIso8601String(),
        'connected_at': connectedAt.toIso8601String(),
        'status': status,
        if (shopifyLocationId != null)
          'shopify_location_id': shopifyLocationId,
        if (shopifyLocationName != null)
          'shopify_location_name': shopifyLocationName,
        'setup_completed': setupCompleted,
        if (shopTimezone != null)
          'shop_timezone': shopTimezone,
      };

  factory ShopifyConnection.fromJson(Map<String, dynamic> json) {
    return ShopifyConnection(
      userId: json['user_id'] as String,
      shopDomain: json['shop_domain'] as String,
      // access_token intentionally not read — only CFs use it
      scopes: (json['scopes'] as List<dynamic>?)?.cast<String>() ?? const [],
      syncOrdersEnabled: json['sync_orders_enabled'] as bool? ?? true,
      syncInventoryEnabled: json['sync_inventory_enabled'] as bool? ?? false,
      inventorySyncDirection: json['inventory_sync_direction'] as String?,
      inventorySyncMode: json['inventory_sync_mode'] as String? ?? 'on_demand',
      lastOrderSyncAt: _parseDateTime(json['last_order_sync_at']),
      lastInventorySyncAt: _parseDateTime(json['last_inventory_sync_at']),
      webhookIds: (json['webhook_ids'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as String)) ??
          const {},
      importFromDate: _parseDateTime(json['import_from_date']),
      connectedAt: _parseDateTime(json['connected_at']) ?? DateTime.now(),
      status: json['status'] as String? ?? 'active',
      shopifyLocationId: json['shopify_location_id'] as String?,
      shopifyLocationName: json['shopify_location_name'] as String?,
      setupCompleted: json['setup_completed'] as bool? ?? false,
      shopTimezone: json['shop_timezone'] as String?,
    );
  }

  /// Parses a Firestore field that may be a [Timestamp], ISO-8601 [String],
  /// or null into a [DateTime].
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    // Firestore Timestamp (from FieldValue.serverTimestamp or Timestamp.now())
    if (value is DateTime) return value;
    // cloud_firestore Timestamp type
    try {
      // Attempt duck-typing for Timestamp.toDate()
      final ts = value as dynamic;
      if (ts.toDate != null) return (ts.toDate() as DateTime);
    } catch (_) {}
    // ISO-8601 string fallback
    if (value is String) {
      try { return DateTime.parse(value); } catch (_) {}
    }
    return null;
  }
}
