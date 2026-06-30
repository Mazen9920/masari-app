/// A payment-gateway receivable account — money a payment gateway (e.g. Paymob)
/// has collected from online/card sales but not yet settled to the business's
/// bank. It is an ASSET ("what you own"): a receivable that converts to cash
/// when the gateway settles.
///
/// Firestore collection: `gateway_receivables/{uid}/items/{id}`
class GatewayReceivable {
  final String id;

  /// The payment gateway / processor name, e.g. "Paymob", "Stripe", "Fawry".
  final String gatewayName;

  /// Current uncleared balance the gateway owes the business (the receivable).
  /// Maintained by the user and reduced as settlements are recorded.
  final double pendingBalance;

  final GatewayReceivableStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Settlements received from the gateway (each reduces [pendingBalance] and
  /// posts a matching cash inflow).
  final List<GatewaySettlement> settlements;

  const GatewayReceivable({
    required this.id,
    required this.gatewayName,
    this.pendingBalance = 0,
    this.status = GatewayReceivableStatus.active,
    this.notes,
    required this.createdAt,
    this.updatedAt,
    this.settlements = const [],
  });

  // ── Computed helpers ──────────────────────────────
  bool get isActive => status == GatewayReceivableStatus.active;

  double get totalSettled =>
      settlements.fold(0.0, (s, e) => s + e.amount);

  DateTime? get lastSettlementDate {
    if (settlements.isEmpty) return null;
    return settlements.reduce((a, b) => a.date.isAfter(b.date) ? a : b).date;
  }

  // ── Serialization ─────────────────────────────────
  Map<String, dynamic> toJson() => {
        'id': id,
        'gateway_name': gatewayName,
        'pending_balance': pendingBalance,
        'status': status.name,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'settlements': settlements.map((s) => s.toJson()).toList(),
      };

  factory GatewayReceivable.fromJson(Map<String, dynamic> json) {
    return GatewayReceivable(
      id: json['id'] as String? ?? '',
      gatewayName: json['gateway_name'] as String? ?? '',
      pendingBalance: (json['pending_balance'] as num?)?.toDouble() ?? 0,
      status: GatewayReceivableStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => GatewayReceivableStatus.active,
      ),
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      settlements: (json['settlements'] as List<dynamic>?)
              ?.map((s) =>
                  GatewaySettlement.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  GatewayReceivable copyWith({
    String? id,
    String? gatewayName,
    double? pendingBalance,
    GatewayReceivableStatus? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<GatewaySettlement>? settlements,
  }) {
    return GatewayReceivable(
      id: id ?? this.id,
      gatewayName: gatewayName ?? this.gatewayName,
      pendingBalance: pendingBalance ?? this.pendingBalance,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      settlements: settlements ?? this.settlements,
    );
  }
}

/// A single settlement (payout) received from the gateway into the bank.
class GatewaySettlement {
  final String id;
  final double amount;
  final DateTime date;
  final String? note;
  final String? transactionId;

  const GatewaySettlement({
    required this.id,
    required this.amount,
    required this.date,
    this.note,
    this.transactionId,
  });

  GatewaySettlement copyWith({String? transactionId}) => GatewaySettlement(
        id: id,
        amount: amount,
        date: date,
        note: note,
        transactionId: transactionId ?? this.transactionId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
        'transaction_id': transactionId,
      };

  factory GatewaySettlement.fromJson(Map<String, dynamic> json) {
    return GatewaySettlement(
      id: json['id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      note: json['note'] as String?,
      transactionId: json['transaction_id'] as String?,
    );
  }
}

enum GatewayReceivableStatus {
  active,
  closed;

  String get label {
    switch (this) {
      case active:
        return 'Active';
      case closed:
        return 'Closed';
    }
  }
}
