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

  /// Typical settlement cycle in days (Paymob ≈ 2, others weekly). Drives the
  /// "expected in ~N days" hint and the overdue-settlement warning.
  final int? settlementDays;

  /// The gateway's default fee percentage (e.g. 2.5 for 2.5%). Used to
  /// pre-fill the fee when recording a settlement.
  final double? feePercent;

  final GatewayReceivableStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Amounts the gateway has COLLECTED on the business's behalf (each raises
  /// the receivable). Lets the balance be a real ledger instead of a number
  /// the user has to keep re-typing.
  final List<GatewayCollection> collections;

  /// Settlements received from the gateway (each reduces the receivable and
  /// posts a matching cash inflow, net of fees).
  final List<GatewaySettlement> settlements;

  const GatewayReceivable({
    required this.id,
    required this.gatewayName,
    this.pendingBalance = 0,
    this.settlementDays,
    this.feePercent,
    this.status = GatewayReceivableStatus.active,
    this.notes,
    required this.createdAt,
    this.updatedAt,
    this.collections = const [],
    this.settlements = const [],
  });

  // ── Computed helpers ──────────────────────────────
  bool get isActive => status == GatewayReceivableStatus.active;

  /// Gross cleared from the receivable (before the gateway's fee).
  double get totalSettled => settlements.fold(0.0, (s, e) => s + e.amount);

  /// Fees the gateway kept across all settlements — a real cost of selling.
  double get totalFees => settlements.fold(0.0, (s, e) => s + e.fee);

  /// Cash that actually landed in the bank (gross minus fees).
  double get totalCashReceived =>
      settlements.fold(0.0, (s, e) => s + e.netAmount);

  double get totalCollected =>
      collections.fold(0.0, (s, e) => s + e.amount);

  /// Effective fee rate across everything settled so far, as a percentage.
  double get effectiveFeeRate =>
      totalSettled > 0 ? (totalFees / totalSettled) * 100 : 0;

  /// Share of what the gateway ever held that has now been paid out.
  double get progressPct {
    final everHeld = totalSettled + pendingBalance;
    return everHeld > 0 ? (totalSettled / everHeld).clamp(0, 1) : 0;
  }

  bool get isCleared => pendingBalance <= 0.01;

  DateTime? get lastSettlementDate {
    if (settlements.isEmpty) return null;
    return settlements.reduce((a, b) => a.date.isAfter(b.date) ? a : b).date;
  }

  DateTime? get lastCollectionDate {
    if (collections.isEmpty) return null;
    return collections.reduce((a, b) => a.date.isAfter(b.date) ? a : b).date;
  }

  /// Days since the gateway last paid out — null when it never has.
  int? get daysSinceLastSettlement {
    final d = lastSettlementDate;
    if (d == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
  }

  /// Money is sitting longer than this gateway's stated cycle — worth chasing.
  bool get settlementOverdue {
    final cycle = settlementDays;
    final since = daysSinceLastSettlement;
    if (cycle == null || pendingBalance <= 0.01) return false;
    // Never settled: measure from when the account was created.
    final elapsed = since ??
        DateTime.now().difference(createdAt).inDays;
    return elapsed > cycle;
  }

  // ── Serialization ─────────────────────────────────
  Map<String, dynamic> toJson() => {
        'id': id,
        'gateway_name': gatewayName,
        'pending_balance': pendingBalance,
        'settlement_days': settlementDays,
        'fee_percent': feePercent,
        'collections': collections.map((c) => c.toJson()).toList(),
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
      settlementDays: (json['settlement_days'] as num?)?.toInt(),
      feePercent: (json['fee_percent'] as num?)?.toDouble(),
      collections: (json['collections'] as List<dynamic>?)
              ?.map((c) =>
                  GatewayCollection.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
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
    int? settlementDays,
    double? feePercent,
    GatewayReceivableStatus? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<GatewayCollection>? collections,
    List<GatewaySettlement>? settlements,
  }) {
    return GatewayReceivable(
      id: id ?? this.id,
      gatewayName: gatewayName ?? this.gatewayName,
      pendingBalance: pendingBalance ?? this.pendingBalance,
      settlementDays: settlementDays ?? this.settlementDays,
      feePercent: feePercent ?? this.feePercent,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      collections: collections ?? this.collections,
      settlements: settlements ?? this.settlements,
    );
  }
}

/// Money the gateway collected on the business's behalf — raises the
/// receivable. Recording these turns the balance into an auditable ledger
/// instead of a figure the user retypes by hand.
class GatewayCollection {
  final String id;
  final double amount;
  final DateTime date;
  final String? note;

  const GatewayCollection({
    required this.id,
    required this.amount,
    required this.date,
    this.note,
  });

  GatewayCollection copyWith({
    double? amount,
    DateTime? date,
    String? note,
  }) =>
      GatewayCollection(
        id: id,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
      };

  factory GatewayCollection.fromJson(Map<String, dynamic> json) =>
      GatewayCollection(
        id: json['id'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        date: json['date'] != null
            ? DateTime.parse(json['date'] as String)
            : DateTime.now(),
        note: json['note'] as String?,
      );
}

/// A single settlement (payout) received from the gateway into the bank.
///
/// [amount] is the GROSS sum cleared from the receivable; [fee] is the
/// gateway's cut, which never reaches the bank. Cash actually banked is
/// [netAmount]. Posting the gross as cash (the old behaviour) overstated the
/// bank balance on every settlement.
class GatewaySettlement {
  final String id;
  final double amount;

  /// The gateway's fee deducted from this payout (0 when there is none).
  final double fee;
  final DateTime date;
  final String? note;

  /// Cash-in transaction id.
  final String? transactionId;

  /// Expense transaction id for [fee], when one was posted.
  final String? feeTransactionId;

  const GatewaySettlement({
    required this.id,
    required this.amount,
    this.fee = 0,
    required this.date,
    this.note,
    this.transactionId,
    this.feeTransactionId,
  });

  /// What actually hits the bank.
  double get netAmount => (amount - fee).clamp(0, double.maxFinite);

  /// This payout's fee as a percentage of the gross.
  double get feeRate => amount > 0 ? (fee / amount) * 100 : 0;

  GatewaySettlement copyWith({
    double? amount,
    double? fee,
    DateTime? date,
    String? note,
    String? transactionId,
    String? feeTransactionId,
  }) =>
      GatewaySettlement(
        id: id,
        amount: amount ?? this.amount,
        fee: fee ?? this.fee,
        date: date ?? this.date,
        note: note ?? this.note,
        transactionId: transactionId ?? this.transactionId,
        feeTransactionId: feeTransactionId ?? this.feeTransactionId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'fee': fee,
        'date': date.toIso8601String(),
        'note': note,
        'transaction_id': transactionId,
        'fee_transaction_id': feeTransactionId,
      };

  factory GatewaySettlement.fromJson(Map<String, dynamic> json) {
    return GatewaySettlement(
      id: json['id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      fee: (json['fee'] as num?)?.toDouble() ?? 0,
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      note: json['note'] as String?,
      transactionId: json['transaction_id'] as String?,
      feeTransactionId: json['fee_transaction_id'] as String?,
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
