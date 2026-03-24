/// Goods receipt model — tracks which purchase-order items have physically arrived.
/// Each receipt is linked to a [Purchase] (via `purchaseId`) and records
/// the items + quantities that were received. On save, inventory stock is
/// adjusted upward automatically.
library;

import '../../l10n/app_localizations.dart';

/// Status of a goods receipt.
enum ReceiptStatus {
  pending,   // 0 – created but not confirmed
  confirmed, // 1 – goods counted and accepted
  rejected,  // 2 – goods rejected / returned
}

/// A single line-item within a goods receipt.
class ReceiptItem {
  final String? productId;
  final String? variantId;
  final String productName;
  final double orderedQty;
  final double receivedQty;
  final double unitCost;
  final String? notes;

  const ReceiptItem({
    this.productId,
    this.variantId,
    required this.productName,
    required this.orderedQty,
    required this.receivedQty,
    required this.unitCost,
    this.notes,
  });

  double get lineTotal => receivedQty * unitCost;
  double get shortfall => orderedQty - receivedQty;

  ReceiptItem copyWith({
    String? productId,
    String? variantId,
    String? productName,
    double? orderedQty,
    double? receivedQty,
    double? unitCost,
    String? notes,
  }) {
    return ReceiptItem(
      productId: productId ?? this.productId,
      variantId: variantId ?? this.variantId,
      productName: productName ?? this.productName,
      orderedQty: orderedQty ?? this.orderedQty,
      receivedQty: receivedQty ?? this.receivedQty,
      unitCost: unitCost ?? this.unitCost,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        if (productId != null) 'product_id': productId,
        if (variantId != null) 'variant_id': variantId,
        'product_name': productName,
        'ordered_qty': orderedQty,
        'received_qty': receivedQty,
        'unit_cost': unitCost,
        if (notes != null) 'notes': notes,
      };

  factory ReceiptItem.fromJson(Map<String, dynamic> json) {
    return ReceiptItem(
      productId: json['product_id'] as String?,
      variantId: json['variant_id'] as String?,
      productName: json['product_name'] as String,
      orderedQty: (json['ordered_qty'] as num).toDouble(),
      receivedQty: (json['received_qty'] as num).toDouble(),
      unitCost: (json['unit_cost'] as num).toDouble(),
      notes: json['notes'] as String?,
    );
  }
}

/// The main GoodsReceipt record.
class GoodsReceipt {
  final String id;
  final String userId;
  final String? purchaseId;
  final String supplierId;
  final String supplierName;
  final DateTime date;
  final List<ReceiptItem> items;
  final ReceiptStatus status;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const GoodsReceipt({
    required this.id,
    required this.userId,
    this.purchaseId,
    required this.supplierId,
    required this.supplierName,
    required this.date,
    required this.items,
    this.status = ReceiptStatus.pending,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  // ── Computed ─────────────────────────────────────────────

  /// Total cost of received items.
  double get totalCost =>
      items.fold(0.0, (sum, item) => sum + item.lineTotal);

  /// Total items received.
  double get totalReceived =>
      items.fold(0.0, (sum, item) => sum + item.receivedQty);

  /// Total items ordered.
  double get totalOrdered =>
      items.fold(0.0, (sum, item) => sum + item.orderedQty);

  /// Fulfilment percentage (0–100).
  double get fulfilmentPct =>
      totalOrdered > 0 ? (totalReceived / totalOrdered * 100) : 0;

  String get statusLabel {
    switch (status) {
      case ReceiptStatus.pending:
        return 'Pending';
      case ReceiptStatus.confirmed:
        return 'Confirmed';
      case ReceiptStatus.rejected:
        return 'Rejected';
    }
  }

  String localizedStatusLabel(AppLocalizations l10n) {
    switch (status) {
      case ReceiptStatus.pending:
        return l10n.pending;
      case ReceiptStatus.confirmed:
        return l10n.confirmed;
      case ReceiptStatus.rejected:
        return l10n.rejectedLabel;
    }
  }

  // ── copyWith ─────────────────────────────────────────────

  GoodsReceipt copyWith({
    String? id,
    String? userId,
    String? purchaseId,
    String? supplierId,
    String? supplierName,
    DateTime? date,
    List<ReceiptItem>? items,
    ReceiptStatus? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return GoodsReceipt(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      purchaseId: purchaseId ?? this.purchaseId,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      date: date ?? this.date,
      items: items ?? this.items,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ── Serialization ────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        if (purchaseId != null) 'purchase_id': purchaseId,
        'supplier_id': supplierId,
        'supplier_name': supplierName,
        'date': date.toIso8601String(),
        'items': items.map((i) => i.toJson()).toList(),
        'status': status.index,
        if (notes != null) 'notes': notes,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      };

  factory GoodsReceipt.fromJson(Map<String, dynamic> json) {
    return GoodsReceipt(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? 'system',
      purchaseId: json['purchase_id'] as String?,
      supplierId: json['supplier_id'] as String,
      supplierName: json['supplier_name'] as String,
      date: DateTime.parse(json['date'] as String),
      items: (json['items'] as List<dynamic>?)
              ?.map(
                  (i) => ReceiptItem.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      status:
          ReceiptStatus.values[(json['status'] as int?) ?? 0],
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }
}
