import '../utils/money_utils.dart';

// ═══════════════════════════════════════════════════════════
//  PRODUCTION PLAN — transient view-model produced by the planner.
//  Not persisted. Drives the planner screen (material needs by
//  supplier, shortfalls, cost roll-up) before a run is started.
// ═══════════════════════════════════════════════════════════

/// One material requirement line in a production plan.
class ProductionPlanLine {
  final String materialProductId;
  final String materialVariantId;
  final String materialName;
  final String supplierName;
  final String unit;

  /// Quantity required for the whole run, including scrap if applicable.
  final double requiredQty;

  /// Current on-hand stock of the resolved material variant.
  final double availableQty;

  /// max(0, requiredQty - availableQty).
  final double shortfallQty;

  /// Material's current weighted-average cost.
  final double unitCost;

  /// requiredQty * unitCost.
  final double lineCost;

  /// True when the material product/variant could not be resolved.
  final bool unresolved;

  /// True when this component is produced together with the finished product
  /// during the run (e.g. the finishing supplier makes the mini bag with the
  /// straps). Its cost still counts, but it is NOT consumed from raw stock and
  /// a stock shortfall on it does NOT block starting the run.
  final bool madeToOrder;

  const ProductionPlanLine({
    required this.materialProductId,
    required this.materialVariantId,
    required this.materialName,
    required this.supplierName,
    required this.unit,
    required this.requiredQty,
    required this.availableQty,
    required this.shortfallQty,
    required this.unitCost,
    required this.lineCost,
    this.unresolved = false,
    this.madeToOrder = false,
  });

  bool get hasShortfall => shortfallQty > 0;

  /// A shortfall that should actually block starting the run.
  bool get blocksStart => shortfallQty > 0 && !madeToOrder;
}

/// Result of planning a production run for [quantity] units of a finished
/// product/variant.
class ProductionPlan {
  final String productId;
  final String productName;
  final String variantId;
  final String variantName;
  final int quantity;
  final List<ProductionPlanLine> lines;
  final double materialsCost;
  final double laborCost;
  final String? laborSupplierId;
  final String? laborSupplierName;
  final double totalCost;
  final double unitCost;

  const ProductionPlan({
    required this.productId,
    required this.productName,
    required this.variantId,
    required this.variantName,
    required this.quantity,
    required this.lines,
    required this.materialsCost,
    required this.laborCost,
    this.laborSupplierId,
    this.laborSupplierName,
    required this.totalCost,
    required this.unitCost,
  });

  /// Only real, blocking shortfalls (made-to-order lines are excluded).
  bool get hasShortfall => lines.any((l) => l.blocksStart);
  bool get hasUnresolved => lines.any((l) => l.unresolved);

  /// Material lines grouped by supplier name (for the planner's PO view).
  Map<String, List<ProductionPlanLine>> get linesBySupplier {
    final map = <String, List<ProductionPlanLine>>{};
    for (final l in lines) {
      map.putIfAbsent(l.supplierName.isEmpty ? '—' : l.supplierName, () => [])
          .add(l);
    }
    return map;
  }
}

/// Lifecycle status of a production order.
///
/// Stored NUMERICALLY in Firestore (0/1/2) — never as a string — to match the
/// rest of the app's enum convention (see order_status, payment_status, etc.).
enum ProductionStatus {
  inProgress, // 0 — materials consumed, finished goods not yet produced (WIP)
  completed, // 1 — finished goods added to inventory
  cancelled, // 2 — cancelled; consumed materials restocked
}

/// A snapshot of one raw material consumed by a production run. Captured at
/// START so the order is a faithful historical record even if the material's
/// cost or the BOM later changes.
class ProductionInputLine {
  final String materialProductId;
  final String materialVariantId;
  final String materialName;

  /// Total quantity of this material consumed for the whole run.
  final double quantity;

  /// COGS per consumed unit, computed from the material's cost layers using
  /// the active valuation method at START.
  final double unitCost;

  /// quantity * unitCost.
  final double totalCost;

  /// True when this input was produced with the run (cost capitalized but not
  /// drawn from stock) — so cancelling must NOT restock it.
  final bool madeToOrder;

  const ProductionInputLine({
    required this.materialProductId,
    required this.materialVariantId,
    required this.materialName,
    required this.quantity,
    required this.unitCost,
    required this.totalCost,
    this.madeToOrder = false,
  });

  Map<String, dynamic> toJson() => {
        'material_product_id': materialProductId,
        'material_variant_id': materialVariantId,
        'material_name': materialName,
        'quantity': quantity,
        'unit_cost': roundMoney(unitCost),
        'total_cost': roundMoney(totalCost),
        if (madeToOrder) 'made_to_order': true,
      };

  factory ProductionInputLine.fromJson(Map<String, dynamic> json) {
    return ProductionInputLine(
      materialProductId: json['material_product_id'] as String,
      materialVariantId: json['material_variant_id'] as String? ?? '',
      materialName: json['material_name'] as String? ?? '',
      quantity: (json['quantity'] as num).toDouble(),
      unitCost: (json['unit_cost'] as num?)?.toDouble() ?? 0,
      totalCost: (json['total_cost'] as num?)?.toDouble() ?? 0,
      madeToOrder: json['made_to_order'] as bool? ?? false,
    );
  }
}

/// A manufacturing run: consumes raw materials (START) and produces a finished
/// good (COMPLETE). The inverse of a [ConversionOrder] / breakdown.
///
/// Accounting: materials + labor are CAPITALIZED into the finished good's cost
/// layer (they hit P&L as COGS only when the finished good is sold). The labor
/// cash payment recorded at completion is `exclude_from_pl: true` so it never
/// double-counts against the eventual COGS.
class ProductionOrder {
  final String id;
  final String userId;

  /// Finished product being made.
  final String productId;
  final String productName;
  final String variantId;
  final String variantName;

  /// Units to produce (e.g. 100).
  final int quantity;

  /// Units finished/received so far. A run may be received in batches; it stays
  /// in-progress until [completedQty] reaches [quantity].
  final int completedQty;

  final ProductionStatus status;

  /// Snapshot of materials consumed at START.
  final List<ProductionInputLine> inputs;

  /// Cost of materials CONSUMED FROM STOCK at START (drives WIP). Excludes
  /// made-to-order components (those are invoiced by the supplier at
  /// completion, see [madeToOrderCost]).
  final double materialsCost;

  /// Cost of made-to-order components (produced by the finishing supplier with
  /// the run). Not in stock at START; billed to the supplier together with
  /// labor at completion. Capitalized into the finished unit cost.
  final double madeToOrderCost;

  /// laborCostPerUnit * quantity.
  final double laborCost;

  /// materialsCost + laborCost.
  final double totalCost;

  /// totalCost / quantity — the unit cost of the finished cost layer.
  final double unitCost;

  /// Optional finishing supplier the labor was paid/owed to.
  final String? laborSupplierId;

  /// The ledger transaction id created for the labor cash payment (payNow), if
  /// any.
  final String? laborTransactionId;

  final DateTime startedAt;
  final DateTime? completedAt;
  final String? notes;
  final DateTime? createdAt;

  const ProductionOrder({
    required this.id,
    required this.userId,
    required this.productId,
    required this.productName,
    required this.variantId,
    required this.variantName,
    required this.quantity,
    this.completedQty = 0,
    this.status = ProductionStatus.inProgress,
    this.inputs = const [],
    this.materialsCost = 0,
    this.madeToOrderCost = 0,
    this.laborCost = 0,
    this.totalCost = 0,
    this.unitCost = 0,
    this.laborSupplierId,
    this.laborTransactionId,
    required this.startedAt,
    this.completedAt,
    this.notes,
    this.createdAt,
  });

  bool get isInProgress => status == ProductionStatus.inProgress;
  bool get isCompleted => status == ProductionStatus.completed;
  bool get isCancelled => status == ProductionStatus.cancelled;

  /// Units still to be received.
  int get remainingQty => (quantity - completedQty).clamp(0, quantity);

  /// Whether any units have been received but not all (partially received).
  bool get isPartiallyReceived => completedQty > 0 && completedQty < quantity;

  /// WIP asset value tied up in this run = the **materials** actually consumed
  /// for the units not yet finished (= `materialsCost × remaining/quantity`).
  /// Drops as batches are received. Finishing labor + made-to-order are NOT
  /// capitalized here — they're recognized only at completion (when the work is
  /// done and billed), so WIP holds just the raw materials already spent.
  double get wipValue => quantity <= 0
      ? 0
      : roundMoney(materialsCost * remainingQty / quantity);

  /// Finishing labor + made-to-order cost still to be incurred for the units not
  /// yet received. NOT a booked liability — the finisher hasn't done the work
  /// yet; it is recognized (cash / supplier bill + capitalized into the finished
  /// good) only at completion. Informational: "what you'll owe the finisher when
  /// this batch is received".
  double get pendingFinishingCost => quantity <= 0
      ? 0
      : roundMoney(manufacturingCharge * remainingQty / quantity);

  /// Total amount invoiced to the finishing supplier for the whole run:
  /// finishing labor + any made-to-order components they produce.
  double get manufacturingCharge => roundMoney(laborCost + madeToOrderCost);

  ProductionOrder copyWith({
    String? userId,
    String? productName,
    String? variantName,
    int? quantity,
    int? completedQty,
    ProductionStatus? status,
    List<ProductionInputLine>? inputs,
    double? materialsCost,
    double? madeToOrderCost,
    double? laborCost,
    double? totalCost,
    double? unitCost,
    String? laborSupplierId,
    String? laborTransactionId,
    DateTime? startedAt,
    DateTime? completedAt,
    String? notes,
    DateTime? createdAt,
  }) {
    return ProductionOrder(
      id: id,
      userId: userId ?? this.userId,
      productId: productId,
      productName: productName ?? this.productName,
      variantId: variantId,
      variantName: variantName ?? this.variantName,
      quantity: quantity ?? this.quantity,
      completedQty: completedQty ?? this.completedQty,
      status: status ?? this.status,
      inputs: inputs ?? this.inputs,
      materialsCost: materialsCost ?? this.materialsCost,
      madeToOrderCost: madeToOrderCost ?? this.madeToOrderCost,
      laborCost: laborCost ?? this.laborCost,
      totalCost: totalCost ?? this.totalCost,
      unitCost: unitCost ?? this.unitCost,
      laborSupplierId: laborSupplierId ?? this.laborSupplierId,
      laborTransactionId: laborTransactionId ?? this.laborTransactionId,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'product_id': productId,
        'product_name': productName,
        'variant_id': variantId,
        'variant_name': variantName,
        'quantity': quantity,
        if (completedQty > 0) 'completed_qty': completedQty,
        'status': status.index,
        'inputs': inputs.map((i) => i.toJson()).toList(),
        'materials_cost': roundMoney(materialsCost),
        if (madeToOrderCost > 0)
          'made_to_order_cost': roundMoney(madeToOrderCost),
        'labor_cost': roundMoney(laborCost),
        'total_cost': roundMoney(totalCost),
        'unit_cost': roundMoney(unitCost),
        if (laborSupplierId != null) 'labor_supplier_id': laborSupplierId,
        if (laborTransactionId != null)
          'labor_transaction_id': laborTransactionId,
        'started_at': startedAt.toIso8601String(),
        if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
        if (notes != null) 'notes': notes,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };

  factory ProductionOrder.fromJson(Map<String, dynamic> json) {
    final statusIdx = (json['status'] as num?)?.toInt() ?? 0;
    return ProductionOrder(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      productId: json['product_id'] as String,
      productName: json['product_name'] as String? ?? '',
      variantId: json['variant_id'] as String? ?? '',
      variantName: json['variant_name'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      completedQty: (json['completed_qty'] as num?)?.toInt() ?? 0,
      status: statusIdx >= 0 && statusIdx < ProductionStatus.values.length
          ? ProductionStatus.values[statusIdx]
          : ProductionStatus.inProgress,
      inputs: (json['inputs'] as List<dynamic>?)
              ?.map((i) => ProductionInputLine.fromJson(i as Map<String, dynamic>))
              .toList() ??
          const [],
      materialsCost: (json['materials_cost'] as num?)?.toDouble() ?? 0,
      madeToOrderCost: (json['made_to_order_cost'] as num?)?.toDouble() ?? 0,
      laborCost: (json['labor_cost'] as num?)?.toDouble() ?? 0,
      totalCost: (json['total_cost'] as num?)?.toDouble() ?? 0,
      unitCost: (json['unit_cost'] as num?)?.toDouble() ?? 0,
      laborSupplierId: json['labor_supplier_id'] as String?,
      laborTransactionId: json['labor_transaction_id'] as String?,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : DateTime.now(),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }
}
