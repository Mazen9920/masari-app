import '../services/result.dart';

/// A single sync log entry for audit/debugging.
class ShopifySyncLogEntry {
  final String id;
  final String userId;

  /// The sync action: "order_created", "order_updated", "order_cancelled",
  /// "inventory_pull", "inventory_push", "product_imported", "webhook_received", etc.
  final String action;

  /// Direction: "shopify_to_masari" | "masari_to_shopify" | "webhook"
  final String direction;

  /// Outcome: "success" | "error" | "skipped"
  final String status;

  /// Optional error message on failure.
  final String? error;

  /// Reference IDs for traceability.
  final String? shopifyOrderId;
  final String? masariSaleId;
  final String? shopifyProductId;
  final String? masariProductId;

  /// Arbitrary metadata (e.g. changed fields, counts).
  final Map<String, dynamic>? metadata;

  final DateTime createdAt;

  const ShopifySyncLogEntry({
    required this.id,
    required this.userId,
    required this.action,
    required this.direction,
    required this.status,
    this.error,
    this.shopifyOrderId,
    this.masariSaleId,
    this.shopifyProductId,
    this.masariProductId,
    this.metadata,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'action': action,
        'direction': direction,
        'status': status,
        if (error != null) 'error': error,
        if (shopifyOrderId != null) 'shopify_order_id': shopifyOrderId,
        if (masariSaleId != null) 'masari_sale_id': masariSaleId,
        if (shopifyProductId != null) 'shopify_product_id': shopifyProductId,
        if (masariProductId != null) 'masari_product_id': masariProductId,
        if (metadata != null) 'metadata': metadata,
        'created_at': createdAt.toIso8601String(),
      };

  factory ShopifySyncLogEntry.fromJson(Map<String, dynamic> json) {
    return ShopifySyncLogEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      action: json['action'] as String,
      direction: json['direction'] as String,
      status: json['status'] as String,
      error: json['error'] as String?,
      shopifyOrderId: json['shopify_order_id'] as String?,
      masariSaleId: json['masari_sale_id'] as String?,
      shopifyProductId: json['shopify_product_id'] as String?,
      masariProductId: json['masari_product_id'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Contract for Shopify sync log operations (write-heavy, read for audit).
abstract class ShopifySyncLogRepository {
  /// Writes a single log entry.
  Future<Result<void>> log(ShopifySyncLogEntry entry);

  /// Fetches recent log entries for the current user (for sync history UI).
  Future<Result<List<ShopifySyncLogEntry>>> getRecentLogs({int limit = 50});

  /// Deletes all logs for the current user (e.g. on disconnect).
  Future<Result<void>> clearLogs();
}
