/// An employee salary record.
///
/// Firestore collection: `salaries/{uid}/items/{salaryId}`
class Salary {
  final String id;
  final String employeeName;
  final String? role;
  final SalaryType type;
  final double monthlySalary;
  final double totalPaid;
  final double manualAccrued;
  final SalaryStatus status;
  final DateTime startDate;
  final DateTime? endDate;
  final PaymentFrequency frequency;
  final String? notes;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<SalaryPayment> payments;
  final List<SalaryAccrual> accruals;

  const Salary({
    required this.id,
    required this.employeeName,
    this.role,
    required this.type,
    required this.monthlySalary,
    this.totalPaid = 0,
    this.manualAccrued = 0,
    this.status = SalaryStatus.active,
    required this.startDate,
    this.endDate,
    this.frequency = PaymentFrequency.monthly,
    this.notes,
    required this.createdAt,
    this.updatedAt,
    this.payments = const [],
    this.accruals = const [],
  });

  // ── Computed helpers ──────────────────────────────

  /// Number of months the employee has been on payroll.
  int get monthsEmployed {
    final end = endDate ?? DateTime.now();
    return ((end.year - startDate.year) * 12 +
            (end.month - startDate.month))
        .clamp(0, 9999);
  }

  /// Total salary obligation accrued to date.
  /// Uses manual accruals if recorded, otherwise auto-computes from salary × months.
  double get totalAccrued =>
      manualAccrued > 0 ? manualAccrued : (monthlySalary * monthsEmployed);

  /// Outstanding (unpaid) salary.
  double get unpaidAmount =>
      (totalAccrued - totalPaid).clamp(0, double.maxFinite);

  /// Whether all accrued salary has been paid.
  bool get isFullyPaid => unpaidAmount <= 0.01;

  /// Payment progress (0.0 – 1.0).
  double get progressPct =>
      totalAccrued > 0 ? (totalPaid / totalAccrued).clamp(0, 1) : 0;

  /// Annual salary cost.
  double get annualSalary => monthlySalary * 12;

  // ── Per-month view ────────────────────────────────
  // The all-time figures above ([totalPaid]/[unpaidAmount]) answer "ever";
  // these answer the day-to-day question "what does this employee still get
  // THIS month?".

  /// Whether the employee is on payroll during [month] (any day of it).
  /// False before they start and after they leave, so an ex-employee doesn't
  /// keep showing salary due.
  bool isEmployedInMonth(DateTime month) {
    final startsAfterMonth = startDate.year > month.year ||
        (startDate.year == month.year && startDate.month > month.month);
    if (startsAfterMonth) return false;
    final end = endDate;
    if (end == null) return true;
    final endedBeforeMonth =
        end.year < month.year || (end.year == month.year && end.month < month.month);
    return !endedBeforeMonth;
  }

  /// Salary owed for [month] — the contract rate, or 0 if not employed then.
  double dueForMonth(DateTime month) =>
      isEmployedInMonth(month) ? monthlySalary : 0;

  /// Total actually paid to this employee within [month].
  double paidInMonth(DateTime month) => payments
      .where((p) => p.date.year == month.year && p.date.month == month.month)
      .fold<double>(0.0, (acc, p) => acc + p.amount);

  /// Still owed for [month] (never negative — an overpayment reads as 0 left).
  double remainingForMonth(DateTime month) =>
      (dueForMonth(month) - paidInMonth(month)).clamp(0, double.maxFinite);

  /// How far through [month]'s salary the payments have got (0.0 – 1.0).
  double progressForMonth(DateTime month) {
    final due = dueForMonth(month);
    return due > 0 ? (paidInMonth(month) / due).clamp(0, 1) : 0;
  }

  /// Payment state for [month] — drives the status chip on the employee card.
  MonthPayStatus statusForMonth(DateTime month) {
    if (!isEmployedInMonth(month)) return MonthPayStatus.notEmployed;
    final paid = paidInMonth(month);
    if (paid <= 0.01) return MonthPayStatus.unpaid;
    return remainingForMonth(month) <= 0.01
        ? MonthPayStatus.paid
        : MonthPayStatus.partial;
  }

  /// Last payment date (if any).
  DateTime? get lastPaymentDate {
    if (payments.isEmpty) return null;
    return payments
        .reduce((a, b) => a.date.isAfter(b.date) ? a : b)
        .date;
  }

  // ── Serialization ─────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'employee_name': employeeName,
        'role': role,
        'type': type.name,
        'monthly_salary': monthlySalary,
        'total_paid': totalPaid,
        'manual_accrued': manualAccrued,
        'status': status.name,
        'start_date': startDate.toIso8601String(),
        'end_date': endDate?.toIso8601String(),
        'frequency': frequency.name,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'accruals': accruals.map((a) => a.toJson()).toList(),
      };

  factory Salary.fromJson(Map<String, dynamic> json) {
    return Salary(
      id: json['id'] as String? ?? '',
      employeeName: json['employee_name'] as String? ?? '',
      role: json['role'] as String?,
      type: SalaryType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => SalaryType.fullTime,
      ),
      monthlySalary:
          (json['monthly_salary'] as num?)?.toDouble() ?? 0,
      totalPaid: (json['total_paid'] as num?)?.toDouble() ?? 0,
      manualAccrued: (json['manual_accrued'] as num?)?.toDouble() ?? 0,
      status: SalaryStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => SalaryStatus.active,
      ),
      startDate: json['start_date'] != null
          ? DateTime.parse(json['start_date'] as String)
          : DateTime.now(),
      endDate: json['end_date'] != null
          ? DateTime.parse(json['end_date'] as String)
          : null,
      frequency: PaymentFrequency.values.firstWhere(
        (f) => f.name == json['frequency'],
        orElse: () => PaymentFrequency.monthly,
      ),
      notes: json['notes'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      payments: (json['payments'] as List<dynamic>?)
              ?.map((p) =>
                  SalaryPayment.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      accruals: (json['accruals'] as List<dynamic>?)
              ?.map((a) =>
                  SalaryAccrual.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Salary copyWith({
    String? id,
    String? employeeName,
    String? role,
    SalaryType? type,
    double? monthlySalary,
    double? totalPaid,
    double? manualAccrued,
    SalaryStatus? status,
    DateTime? startDate,
    DateTime? endDate,
    PaymentFrequency? frequency,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<SalaryPayment>? payments,
    List<SalaryAccrual>? accruals,
  }) {
    return Salary(
      id: id ?? this.id,
      employeeName: employeeName ?? this.employeeName,
      role: role ?? this.role,
      type: type ?? this.type,
      monthlySalary: monthlySalary ?? this.monthlySalary,
      totalPaid: totalPaid ?? this.totalPaid,
      manualAccrued: manualAccrued ?? this.manualAccrued,
      status: status ?? this.status,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      frequency: frequency ?? this.frequency,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      payments: payments ?? this.payments,
      accruals: accruals ?? this.accruals,
    );
  }
}

/// A salary accrual record (salary payable entry).
class SalaryAccrual {
  final String id;
  final double amount;
  final DateTime date;
  final String? note;
  final String? period;
  final String? transactionId;

  const SalaryAccrual({
    required this.id,
    required this.amount,
    required this.date,
    this.note,
    this.period,
    this.transactionId,
  });

  SalaryAccrual copyWith({String? transactionId}) => SalaryAccrual(
        id: id,
        amount: amount,
        date: date,
        note: note,
        period: period,
        transactionId: transactionId ?? this.transactionId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
        'period': period,
        'transaction_id': transactionId,
      };

  factory SalaryAccrual.fromJson(Map<String, dynamic> json) {
    return SalaryAccrual(
      id: json['id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      note: json['note'] as String?,
      period: json['period'] as String?,
      transactionId: json['transaction_id'] as String?,
    );
  }
}

/// A single salary payment record.
class SalaryPayment {
  final String id;
  final double amount;
  final DateTime date;
  final String? note;
  final String? period;
  final String? transactionId;

  const SalaryPayment({
    required this.id,
    required this.amount,
    required this.date,
    this.note,
    this.period,
    this.transactionId,
  });

  SalaryPayment copyWith({String? transactionId}) => SalaryPayment(
        id: id,
        amount: amount,
        date: date,
        note: note,
        period: period,
        transactionId: transactionId ?? this.transactionId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
        'period': period,
        'transaction_id': transactionId,
      };

  factory SalaryPayment.fromJson(Map<String, dynamic> json) {
    return SalaryPayment(
      id: json['id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      note: json['note'] as String?,
      period: json['period'] as String?,
      transactionId: json['transaction_id'] as String?,
    );
  }
}

// ── Enums ──────────────────────────────────────────────

/// Where an employee stands on a given month's salary.
enum MonthPayStatus {
  /// Nothing paid yet for the month.
  unpaid,

  /// Some paid, a balance still due.
  partial,

  /// Fully settled for the month.
  paid,

  /// Not on payroll that month (started later / already left).
  notEmployed;

  String get label {
    switch (this) {
      case unpaid:
        return 'Unpaid';
      case partial:
        return 'Partial';
      case paid:
        return 'Paid';
      case notEmployed:
        return 'Not employed';
    }
  }
}

enum SalaryType {
  fullTime,
  partTime,
  contractor,
  freelancer,
  intern,
  other;

  String get label {
    switch (this) {
      case fullTime:
        return 'Full-Time';
      case partTime:
        return 'Part-Time';
      case contractor:
        return 'Contractor';
      case freelancer:
        return 'Freelancer';
      case intern:
        return 'Intern';
      case other:
        return 'Other';
    }
  }

  String get icon {
    switch (this) {
      case fullTime:
        return '👔';
      case partTime:
        return '⏰';
      case contractor:
        return '📄';
      case freelancer:
        return '💻';
      case intern:
        return '🎓';
      case other:
        return '📋';
    }
  }
}

enum SalaryStatus {
  active,
  terminated,
  onLeave;

  String get label {
    switch (this) {
      case active:
        return 'Active';
      case terminated:
        return 'Terminated';
      case onLeave:
        return 'On Leave';
    }
  }
}

enum PaymentFrequency {
  weekly,
  biWeekly,
  monthly;

  String get label {
    switch (this) {
      case weekly:
        return 'Weekly';
      case biWeekly:
        return 'Bi-Weekly';
      case monthly:
        return 'Monthly';
    }
  }
}
