/// A single output line in a conversion order.
class ConversionOutputLine {
  final String variantId;
  final String variantName;
  final double quantity;
  final double unitCost;
  final double totalCost;

  const ConversionOutputLine({
    required this.variantId,
    required this.variantName,
    required this.quantity,
    required this.unitCost,
    required this.totalCost,
  });

  Map<String, dynamic> toJson() => {
        'variant_id': variantId,
        'variant_name': variantName,
        'quantity': quantity,
        'unit_cost': unitCost,
        'total_cost': totalCost,
      };

  factory ConversionOutputLine.fromJson(Map<String, dynamic> json) {
    return ConversionOutputLine(
      variantId: json['variant_id'] as String,
      variantName: json['variant_name'] as String? ?? '',
      quantity: (json['quantity'] as num).toDouble(),
      unitCost: (json['unit_cost'] as num).toDouble(),
      totalCost: (json['total_cost'] as num).toDouble(),
    );
  }
}

/// Audit trail for a variant breakdown operation.
class ConversionOrder {
  final String id;
  final String userId;
  final String productId;
  final String productName;
  final String sourceVariantId;
  final double sourceQuantity;
  final double sourceTotalCost;
  final List<ConversionOutputLine> outputs;
  final DateTime date;
  final String? notes;
  final DateTime? createdAt;

  const ConversionOrder({
    required this.id,
    required this.userId,
    required this.productId,
    required this.productName,
    required this.sourceVariantId,
    required this.sourceQuantity,
    required this.sourceTotalCost,
    required this.outputs,
    required this.date,
    this.notes,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'product_id': productId,
        'product_name': productName,
        'source_variant_id': sourceVariantId,
        'source_quantity': sourceQuantity,
        'source_total_cost': sourceTotalCost,
        'outputs': outputs.map((o) => o.toJson()).toList(),
        'date': date.toIso8601String(),
        if (notes != null) 'notes': notes,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };

  factory ConversionOrder.fromJson(Map<String, dynamic> json) {
    return ConversionOrder(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      productId: json['product_id'] as String,
      productName: json['product_name'] as String? ?? '',
      sourceVariantId: json['source_variant_id'] as String,
      sourceQuantity: (json['source_quantity'] as num).toDouble(),
      sourceTotalCost: (json['source_total_cost'] as num).toDouble(),
      outputs: (json['outputs'] as List<dynamic>)
          .map((o) => ConversionOutputLine.fromJson(o as Map<String, dynamic>))
          .toList(),
      date: DateTime.parse(json['date'] as String),
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}
