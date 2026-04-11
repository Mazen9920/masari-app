/// Represents a Bosta delivery tracked for shipping expense purposes.
///
/// Each shipment maps to a single Bosta delivery. When the delivery's
/// `wallet.cashCycle` is settled and has `bosta_fees > 0`, an expense
/// transaction is created in Revvo.
///
/// Collection: `bosta_shipments/{bostaDeliveryId}`
class BostaShipment {
  /// Bosta internal delivery ID (`_id`).
  final String bostaDeliveryId;

  /// Revvo user who owns this shipment.
  final String userId;

  /// Bosta tracking number.
  final String trackingNumber;

  /// Shopify order reference from Bosta (used for matching to Revvo sale).
  /// Null for deliveries without a business reference (e.g. customer returns).
  final String? businessReference;

  /// Linked Revvo sale ID, null if unlinked.
  final String? saleId;

  /// Bosta state code (e.g. 45=Delivered, 60=RTO, 46=Returned).
  final int state;

  /// Bosta state name (e.g. "Delivered", "Returned to stock").
  final String stateValue;

  /// Delivery type (e.g. "FXF_SEND", "Customer Return Pickup").
  final String type;

  /// Total settled fees from `wallet.cashCycle.bosta_fees`.
  /// Null if not yet settled.
  final double? totalFees;

  /// Breakdown of fees from `wallet.cashCycle`.
  /// Keys: shipping_fees, fulfillment_fees, vat, cod_fees, insurance_fees,
  ///        expedite_fees, opening_package_fees, flex_ship_fees, pos_fees,
  ///        collection_fees.
  final Map<String, double>? feeBreakdown;

  /// Settlement date from `wallet.cashCycle.deposited_at`.
  final DateTime? depositedAt;

  /// True when delivery is in a terminal state but cashCycle is not yet settled.
  final bool awaitingSettlement;

  /// COD amount (informational, NOT an expense).
  final double? cod;

  /// Whether a Revvo expense transaction has been created for this shipment.
  final bool expenseRecorded;

  /// The Revvo transaction ID created for this shipment's expense.
  final String? expenseTransactionId;

  /// Whether this shipment is linked to a Revvo sale.
  final bool matched;

  /// When this shipment was last synced from Bosta.
  final DateTime? syncedAt;

  /// Estimated fee recorded at catalog time (accrual basis).
  final double? estimatedFee;

  /// Original Bosta creation date (fulfillment date for accrual).
  final DateTime? bostaCreatedAt;

  /// Whether an estimate transaction has been written for this shipment.
  final bool estimateRecorded;

  const BostaShipment({
    required this.bostaDeliveryId,
    required this.userId,
    required this.trackingNumber,
    this.businessReference,
    this.saleId,
    this.state = 0,
    this.stateValue = '',
    this.type = '',
    this.totalFees,
    this.feeBreakdown,
    this.depositedAt,
    this.awaitingSettlement = false,
    this.cod,
    this.expenseRecorded = false,
    this.expenseTransactionId,
    this.matched = false,
    this.syncedAt,
    this.estimatedFee,
    this.bostaCreatedAt,
    this.estimateRecorded = false,
  });

  // ── Computed ─────────────────────────────────────────────

  /// Whether this is a delivered order (state 45).
  bool get isDelivered => state == 45;

  /// Whether this is a return-to-origin / RTO (state 60).
  bool get isRTO => state == 60;

  /// Whether this is a customer return (state 46).
  bool get isReturned => state == 46;

  /// Whether fees are settled and recorded.
  bool get isSettled => totalFees != null && totalFees! > 0;

  /// Whether an estimate has been assigned.
  bool get hasEstimate => estimatedFee != null;

  /// Whether this shipment has been fully reconciled.
  bool get isReconciled => totalFees != null && estimateRecorded;

  // ── copyWith ─────────────────────────────────────────────

  BostaShipment copyWith({
    String? bostaDeliveryId,
    String? userId,
    String? trackingNumber,
    String? businessReference,
    String? saleId,
    int? state,
    String? stateValue,
    String? type,
    double? totalFees,
    Map<String, double>? feeBreakdown,
    DateTime? depositedAt,
    bool? awaitingSettlement,
    double? cod,
    bool? expenseRecorded,
    String? expenseTransactionId,
    bool? matched,
    DateTime? syncedAt,
    double? estimatedFee,
    DateTime? bostaCreatedAt,
    bool? estimateRecorded,
  }) {
    return BostaShipment(
      bostaDeliveryId: bostaDeliveryId ?? this.bostaDeliveryId,
      userId: userId ?? this.userId,
      trackingNumber: trackingNumber ?? this.trackingNumber,
      businessReference: businessReference ?? this.businessReference,
      saleId: saleId ?? this.saleId,
      state: state ?? this.state,
      stateValue: stateValue ?? this.stateValue,
      type: type ?? this.type,
      totalFees: totalFees ?? this.totalFees,
      feeBreakdown: feeBreakdown ?? this.feeBreakdown,
      depositedAt: depositedAt ?? this.depositedAt,
      awaitingSettlement: awaitingSettlement ?? this.awaitingSettlement,
      cod: cod ?? this.cod,
      expenseRecorded: expenseRecorded ?? this.expenseRecorded,
      expenseTransactionId: expenseTransactionId ?? this.expenseTransactionId,
      matched: matched ?? this.matched,
      syncedAt: syncedAt ?? this.syncedAt,
      estimatedFee: estimatedFee ?? this.estimatedFee,
      bostaCreatedAt: bostaCreatedAt ?? this.bostaCreatedAt,
      estimateRecorded: estimateRecorded ?? this.estimateRecorded,
    );
  }

  // ── Serialization ────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'bosta_delivery_id': bostaDeliveryId,
        'user_id': userId,
        'tracking_number': trackingNumber,
        if (businessReference != null) 'business_reference': businessReference,
        if (saleId != null) 'sale_id': saleId,
        'state': state,
        'state_value': stateValue,
        'type': type,
        if (totalFees != null) 'total_fees': totalFees,
        if (feeBreakdown != null) 'fee_breakdown': feeBreakdown,
        if (depositedAt != null) 'deposited_at': depositedAt!.toIso8601String(),
        'awaiting_settlement': awaitingSettlement,
        if (cod != null) 'cod': cod,
        'expense_recorded': expenseRecorded,
        if (expenseTransactionId != null) 'expense_transaction_id': expenseTransactionId,
        'matched': matched,
        if (syncedAt != null) 'synced_at': syncedAt!.toIso8601String(),
        if (estimatedFee != null) 'estimated_fee': estimatedFee,
        if (bostaCreatedAt != null) 'bosta_created_at': bostaCreatedAt!.toIso8601String(),
        'estimate_recorded': estimateRecorded,
      };

  factory BostaShipment.fromJson(Map<String, dynamic> json) {
    return BostaShipment(
      bostaDeliveryId: json['bosta_delivery_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      trackingNumber: json['tracking_number'] as String? ?? '',
      businessReference: json['business_reference'] as String?,
      saleId: json['sale_id'] as String?,
      state: (json['state'] as num?)?.toInt() ?? 0,
      stateValue: json['state_value'] as String? ?? '',
      type: json['type'] as String? ?? '',
      totalFees: (json['total_fees'] as num?)?.toDouble(),
      feeBreakdown: _parseFeeBreakdown(json['fee_breakdown']),
      depositedAt: _parseDateTime(json['deposited_at']),
      awaitingSettlement: json['awaiting_settlement'] as bool? ?? false,
      cod: (json['cod'] as num?)?.toDouble(),
      expenseRecorded: json['expense_recorded'] as bool? ?? false,
      expenseTransactionId: json['expense_transaction_id'] as String?,
      matched: json['matched'] as bool? ?? false,
      syncedAt: _parseDateTime(json['synced_at']),
      estimatedFee: (json['estimated_fee'] as num?)?.toDouble(),
      bostaCreatedAt: _parseDateTime(json['bosta_created_at']),
      estimateRecorded: json['estimate_recorded'] as bool? ?? false,
    );
  }

  static Map<String, double>? _parseFeeBreakdown(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    }
    return null;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      // ignore: avoid_dynamic_calls
      return (value as dynamic).toDate() as DateTime;
    } catch (_) {}
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {}
    }
    return null;
  }
}
