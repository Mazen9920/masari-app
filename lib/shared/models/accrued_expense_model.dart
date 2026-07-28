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

  /// The full amount originally accrued, before any payments. Kept separate
  /// from [amount] so progress ("2,000 of 5,000 paid") survives part-payments.
  /// Null on legacy records — [totalAccrued] reconstructs it from outstanding
  /// plus payments. Must stay nullable: defaulting it to [amount] would make
  /// legacy rows indistinguishable from genuinely-unpaid ones.
  final double? originalAmount;

  /// When the cost was INCURRED — this drives the P&L period, not the day the
  /// record happened to be typed in. Getting this wrong is what made June's
  /// rent land in July's P&L.
  final DateTime accrualDate;

  /// When payment is due. Null = no due date (never flagged overdue).
  final DateTime? dueDate;

  /// Real expense category for the P&L (rent, utilities…), so accruals don't
  /// all collapse into one lumped line. Null falls back to
  /// `cat_accrued_expense`.
  final String? categoryId;

  /// How often this repeats. [AccrualRecurrence.monthly] makes this record a
  /// template that spawns the next month's accrual automatically.
  final AccrualRecurrence recurrence;

  /// Period this record covers, `YYYY-MM`. Used to keep recurring generation
  /// idempotent (one accrual per source per period).
  final String? period;

  /// Id of the recurring accrual this one was generated from (null if it was
  /// created by hand or is itself the template).
  final String? recurringSourceId;

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
    this.originalAmount,
    DateTime? accrualDate,
    this.dueDate,
    this.categoryId,
    this.recurrence = AccrualRecurrence.none,
    this.period,
    this.recurringSourceId,
    this.status = AccruedExpenseStatus.active,
    this.notes,
    required this.createdAt,
    this.updatedAt,
    this.expenseTransactionId,
    this.payments = const [],
  }) : accrualDate = accrualDate ?? createdAt;

  // ── Computed helpers ──────────────────────────────
  bool get isActive => status == AccruedExpenseStatus.active;

  double get totalPaid => payments.fold(0.0, (s, e) => s + e.amount);

  /// Total ever accrued. Legacy rows (no [originalAmount]) reconstruct it from
  /// what's outstanding plus what's already been paid.
  double get totalAccrued => originalAmount ?? (amount + totalPaid);

  /// Share of the accrual settled (0.0 – 1.0).
  double get progressPct =>
      totalAccrued > 0 ? (totalPaid / totalAccrued).clamp(0, 1) : 0;

  bool get isSettled =>
      status == AccruedExpenseStatus.settled || amount <= 0.01;

  /// Past its due date with money still owed.
  bool get isOverdue {
    final d = dueDate;
    if (d == null || isSettled) return false;
    final today = DateTime.now();
    return DateTime(d.year, d.month, d.day)
        .isBefore(DateTime(today.year, today.month, today.day));
  }

  /// Days until due — negative once overdue, null when there's no due date.
  int? get daysUntilDue {
    final d = dueDate;
    if (d == null) return null;
    final today = DateTime.now();
    return DateTime(d.year, d.month, d.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }

  /// Due within the next [days] (and not already overdue or settled).
  bool dueSoon({int days = 7}) {
    final n = daysUntilDue;
    return !isSettled && n != null && n >= 0 && n <= days;
  }

  /// The `YYYY-MM` period this accrual belongs to, derived when not stored.
  String get periodKey =>
      period ??
      '${accrualDate.year}-${accrualDate.month.toString().padLeft(2, '0')}';

  bool get isRecurring => recurrence == AccrualRecurrence.monthly;

  /// The P&L category actually used when posting the expense.
  String get effectiveCategoryId => categoryId ?? 'cat_accrued_expense';

  DateTime? get lastPaymentDate {
    if (payments.isEmpty) return null;
    return payments.reduce((a, b) => a.date.isAfter(b.date) ? a : b).date;
  }

  // ── Serialization ─────────────────────────────────
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'amount': amount,
        // Persist the resolved figure so legacy rows self-migrate on next save.
        'original_amount': totalAccrued,
        'accrual_date': accrualDate.toIso8601String(),
        'due_date': dueDate?.toIso8601String(),
        'category_id': categoryId,
        'recurrence': recurrence.name,
        'period': periodKey,
        'recurring_source_id': recurringSourceId,
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
      originalAmount: (json['original_amount'] as num?)?.toDouble(),
      accrualDate: json['accrual_date'] != null
          ? DateTime.tryParse(json['accrual_date'] as String)
          : null,
      dueDate: json['due_date'] != null
          ? DateTime.tryParse(json['due_date'] as String)
          : null,
      categoryId: json['category_id'] as String?,
      recurrence: AccrualRecurrence.values.firstWhere(
        (r) => r.name == json['recurrence'],
        orElse: () => AccrualRecurrence.none,
      ),
      period: json['period'] as String?,
      recurringSourceId: json['recurring_source_id'] as String?,
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
    double? originalAmount,
    DateTime? accrualDate,
    DateTime? dueDate,
    String? categoryId,
    AccrualRecurrence? recurrence,
    String? period,
    String? recurringSourceId,
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
      originalAmount: originalAmount ?? this.originalAmount,
      accrualDate: accrualDate ?? this.accrualDate,
      dueDate: dueDate ?? this.dueDate,
      categoryId: categoryId ?? this.categoryId,
      recurrence: recurrence ?? this.recurrence,
      period: period ?? this.period,
      recurringSourceId: recurringSourceId ?? this.recurringSourceId,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expenseTransactionId: expenseTransactionId ?? this.expenseTransactionId,
      payments: payments ?? this.payments,
    );
  }

  /// The accrual for the month after this one — used to roll a monthly
  /// recurring accrual forward. Amount resets to the full original, payments
  /// clear, and dates shift by one month.
  AccruedExpense nextRecurrence({required String id}) {
    final nextAccrual =
        DateTime(accrualDate.year, accrualDate.month + 1, accrualDate.day);
    final d = dueDate;
    return AccruedExpense(
      id: id,
      name: name,
      amount: totalAccrued,
      originalAmount: totalAccrued,
      accrualDate: nextAccrual,
      dueDate: d == null ? null : DateTime(d.year, d.month + 1, d.day),
      categoryId: categoryId,
      // Only the original stays the template, so children don't each spawn.
      recurrence: AccrualRecurrence.none,
      period:
          '${nextAccrual.year}-${nextAccrual.month.toString().padLeft(2, '0')}',
      recurringSourceId: recurringSourceId ?? this.id,
      notes: notes,
      createdAt: DateTime.now(),
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

  AccruedExpensePayment copyWith({
    double? amount,
    DateTime? date,
    String? note,
    String? transactionId,
  }) =>
      AccruedExpensePayment(
        id: id,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        note: note ?? this.note,
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

/// How often an accrual repeats.
enum AccrualRecurrence {
  none,
  monthly;

  String get label => this == monthly ? 'Monthly' : 'One-off';
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
