/// A loan (liability) recorded by the business.
///
/// Firestore collection: `loans/{uid}/items/{loanId}`
class Loan {
  final String id;
  final String name;
  final String? lender;
  final LoanType type;
  final double principalAmount;
  final double interestRate; // annual, as percentage (e.g. 12.0 = 12%)
  final int termMonths;
  final DateTime startDate;
  final DateTime? endDate;
  final LoanStatus status;
  final double totalPaid;
  final double totalDisbursed;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<LoanPayment> payments;
  final List<LoanDisbursement> disbursements;

  const Loan({
    required this.id,
    required this.name,
    this.lender,
    required this.type,
    required this.principalAmount,
    this.interestRate = 0,
    this.termMonths = 12,
    required this.startDate,
    this.endDate,
    this.status = LoanStatus.active,
    this.totalPaid = 0,
    this.totalDisbursed = 0,
    this.notes,
    required this.createdAt,
    this.updatedAt,
    this.payments = const [],
    this.disbursements = const [],
  });

  // ── Computed helpers ──────────────────────────────

  /// Total interest over the full term (simple interest).
  double get totalInterest =>
      principalAmount * (interestRate / 100) * (termMonths / 12);

  /// Total amount due (principal + interest).
  double get totalAmountDue => principalAmount + totalInterest;

  /// Outstanding balance.
  /// Uses manual disbursements when recorded, otherwise falls back to
  /// principal+interest calculation.
  double get outstandingBalance {
    if (totalDisbursed > 0 || disbursements.isNotEmpty) {
      return (totalDisbursed - totalPaid).clamp(0, double.maxFinite);
    }
    return (totalAmountDue - totalPaid).clamp(0, double.maxFinite);
  }

  /// Monthly payment amount.
  double get monthlyPayment {
    if (termMonths <= 0) return 0;
    return totalAmountDue / termMonths;
  }

  /// Progress percentage (0.0 to 1.0).
  double get progressPct =>
      totalAmountDue > 0 ? (totalPaid / totalAmountDue).clamp(0, 1) : 0;

  /// How many months have elapsed since start.
  int get monthsElapsed {
    final end = endDate ?? DateTime.now();
    return ((end.year - startDate.year) * 12 +
            (end.month - startDate.month))
        .clamp(0, termMonths);
  }

  /// Remaining months.
  int get remainingMonths => (termMonths - monthsElapsed).clamp(0, termMonths);

  /// Whether the loan is fully paid off.
  bool get isFullyPaid => outstandingBalance <= 0.01;

  // ── Serialization ─────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lender': lender,
        'type': type.name,
        'principal_amount': principalAmount,
        'interest_rate': interestRate,
        'term_months': termMonths,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'status': status.name,
        'total_paid': totalPaid,
        'total_disbursed': totalDisbursed,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'disbursements': disbursements.map((d) => d.toJson()).toList(),
      };

  factory Loan.fromJson(Map<String, dynamic> json) {
    return Loan(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      lender: json['lender'] as String?,
      type: LoanType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => LoanType.other,
      ),
      principalAmount:
          (json['principal_amount'] as num?)?.toDouble() ?? 0,
      interestRate: (json['interest_rate'] as num?)?.toDouble() ?? 0,
      termMonths: (json['term_months'] as num?)?.toInt() ?? 12,
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String)
          : DateTime.now(),
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : null,
      status: LoanStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => LoanStatus.active,
      ),
      totalPaid: (json['total_paid'] as num?)?.toDouble() ?? 0,
      totalDisbursed: (json['total_disbursed'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      payments: (json['payments'] as List<dynamic>?)
              ?.map((p) => LoanPayment.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      disbursements: (json['disbursements'] as List<dynamic>?)
              ?.map((d) =>
                  LoanDisbursement.fromJson(d as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Loan copyWith({
    String? id,
    String? name,
    String? lender,
    LoanType? type,
    double? principalAmount,
    double? interestRate,
    int? termMonths,
    DateTime? startDate,
    DateTime? endDate,
    LoanStatus? status,
    double? totalPaid,
    double? totalDisbursed,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<LoanPayment>? payments,
    List<LoanDisbursement>? disbursements,
  }) {
    return Loan(
      id: id ?? this.id,
      name: name ?? this.name,
      lender: lender ?? this.lender,
      type: type ?? this.type,
      principalAmount: principalAmount ?? this.principalAmount,
      interestRate: interestRate ?? this.interestRate,
      termMonths: termMonths ?? this.termMonths,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      totalPaid: totalPaid ?? this.totalPaid,
      totalDisbursed: totalDisbursed ?? this.totalDisbursed,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      payments: payments ?? this.payments,
      disbursements: disbursements ?? this.disbursements,
    );
  }
}

/// A loan disbursement record (money received from lender).
class LoanDisbursement {
  final String id;
  final double amount;
  final DateTime date;
  final String? note;
  final String? transactionId;

  const LoanDisbursement({
    required this.id,
    required this.amount,
    required this.date,
    this.note,
    this.transactionId,
  });

  LoanDisbursement copyWith({String? transactionId}) => LoanDisbursement(
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

  factory LoanDisbursement.fromJson(Map<String, dynamic> json) {
    return LoanDisbursement(
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

/// A single payment made toward a loan.
class LoanPayment {
  final String id;
  final double amount;
  final DateTime date;
  final String? note;
  final String? transactionId;

  const LoanPayment({
    required this.id,
    required this.amount,
    required this.date,
    this.note,
    this.transactionId,
  });

  LoanPayment copyWith({String? transactionId}) => LoanPayment(
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

  factory LoanPayment.fromJson(Map<String, dynamic> json) {
    return LoanPayment(
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

// ── Enums ──────────────────────────────────────────────

enum LoanType {
  bankLoan,
  personalLoan,
  businessLoan,
  creditLine,
  microfinance,
  other;

  String get label {
    switch (this) {
      case bankLoan:
        return 'Bank Loan';
      case personalLoan:
        return 'Personal Loan';
      case businessLoan:
        return 'Business Loan';
      case creditLine:
        return 'Credit Line';
      case microfinance:
        return 'Microfinance';
      case other:
        return 'Other';
    }
  }

  String get icon {
    switch (this) {
      case bankLoan:
        return '🏦';
      case personalLoan:
        return '🤝';
      case businessLoan:
        return '💼';
      case creditLine:
        return '💳';
      case microfinance:
        return '🏛️';
      case other:
        return '📋';
    }
  }
}

enum LoanStatus {
  active,
  paidOff,
  defaulted;

  String get label {
    switch (this) {
      case active:
        return 'Active';
      case paidOff:
        return 'Paid Off';
      case defaulted:
        return 'Defaulted';
    }
  }
}
