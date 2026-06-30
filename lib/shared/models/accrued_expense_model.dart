/// An accrued expense — a cost the business has incurred but not yet paid
/// (e.g. accrued rent, utilities, interest). It is a LIABILITY ("what you owe")
/// that is settled by future cash payments.
///
/// Firestore collection: `accrued_expenses/{uid}/items/{id}`
class AccruedExpense {
  final String id;

  /// What the accrual is for, e.g. "Accrued rent — June", "Electricity Q2".
  final String name;

  /// Outstanding (unpaid) amount still owed — the liability.
  final double amount;

  final AccruedExpenseStatus status;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// The accrual's P&L expense transaction id (when it was recognized in the
  /// P&L on creation), so deleting the accrual can remove it.
  final String? expenseTransactionId;

  /// Payments made against this accrual (each reduces [amount] and may post a
  /// matching cash outflow).
  final List<AccruedExpensePayment> payments;

  const AccruedExpense({
    required this.id,
    required this.name,
    this.amount = 0,
    this.status = AccruedExpenseStatus.active,
    this.notes,
    required this.createdAt,
    this.updatedAt,
    this.expenseTransactionId,
    this.payments = const [],
  });

  // ── Computed helpers ──────────────────────────────
  bool get isActive => status == AccruedExpenseStatus.active;

  double get totalPaid => payments.fold(0.0, (s, e) => s + e.amount);

  DateTime? get lastPaymentDate {
    if (payments.isEmpty) return null;
    return payments.reduce((a, b) => a.date.isAfter(b.date) ? a : b).date;
  }

  // ── Serialization ─────────────────────────────────
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        'status': status.name,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'expense_transaction_id': expenseTransactionId,
        'payments': payments.map((p) => p.toJson()).toList(),
      };

  factory AccruedExpense.fromJson(Map<String, dynamic> json) {
    return AccruedExpense(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      status: AccruedExpenseStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => AccruedExpenseStatus.active,
      ),
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      expenseTransactionId: json['expense_transaction_id'] as String?,
      payments: (json['payments'] as List<dynamic>?)
              ?.map((p) =>
                  AccruedExpensePayment.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  AccruedExpense copyWith({
    String? id,
    String? name,
    double? amount,
    AccruedExpenseStatus? status,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? expenseTransactionId,
    List<AccruedExpensePayment>? payments,
  }) {
    return AccruedExpense(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expenseTransactionId: expenseTransactionId ?? this.expenseTransactionId,
      payments: payments ?? this.payments,
    );
  }
}

/// A payment made against an accrued expense.
class AccruedExpensePayment {
  final String id;
  final double amount;
  final DateTime date;
  final String? note;
  final String? transactionId;

  const AccruedExpensePayment({
    required this.id,
    required this.amount,
    required this.date,
    this.note,
    this.transactionId,
  });

  AccruedExpensePayment copyWith({String? transactionId}) =>
      AccruedExpensePayment(
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

  factory AccruedExpensePayment.fromJson(Map<String, dynamic> json) {
    return AccruedExpensePayment(
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

enum AccruedExpenseStatus {
  active,
  settled;

  String get label {
    switch (this) {
      case active:
        return 'Active';
      case settled:
        return 'Settled';
    }
  }
}
