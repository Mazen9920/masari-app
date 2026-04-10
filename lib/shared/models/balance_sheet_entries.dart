/// Manual balance-sheet entries that the user edits by hand.
/// Stored as a single Firestore document per user.
class BalanceSheetEntries {
  final double cashOnHand;
  final double unpaidInvoices;
  final double loans;
  final double unpaidSalaries;
  final double openingCapital;
  final bool hasSetCapital;

  const BalanceSheetEntries({
    this.cashOnHand = 0,
    this.unpaidInvoices = 0,
    this.loans = 0,
    this.unpaidSalaries = 0,
    this.openingCapital = 0,
    this.hasSetCapital = false,
  });

  BalanceSheetEntries copyWith({
    double? cashOnHand,
    double? unpaidInvoices,
    double? loans,
    double? unpaidSalaries,
    double? openingCapital,
    bool? hasSetCapital,
  }) {
    return BalanceSheetEntries(
      cashOnHand: cashOnHand ?? this.cashOnHand,
      unpaidInvoices: unpaidInvoices ?? this.unpaidInvoices,
      loans: loans ?? this.loans,
      unpaidSalaries: unpaidSalaries ?? this.unpaidSalaries,
      openingCapital: openingCapital ?? this.openingCapital,
      hasSetCapital: hasSetCapital ?? this.hasSetCapital,
    );
  }

  Map<String, dynamic> toJson() => {
        'cash_on_hand': cashOnHand,
        'unpaid_invoices': unpaidInvoices,
        'loans': loans,
        'unpaid_salaries': unpaidSalaries,
        'opening_capital': openingCapital,
        'has_set_capital': hasSetCapital,
      };

  factory BalanceSheetEntries.fromJson(Map<String, dynamic> json) {
    // 'bank_accounts' deliberately ignored for backward compatibility
    final capital = (json['opening_capital'] as num?)?.toDouble() ?? 0;
    return BalanceSheetEntries(
      cashOnHand: (json['cash_on_hand'] as num?)?.toDouble() ?? 0,
      unpaidInvoices: (json['unpaid_invoices'] as num?)?.toDouble() ?? 0,
      loans: (json['loans'] as num?)?.toDouble() ?? 0,
      unpaidSalaries: (json['unpaid_salaries'] as num?)?.toDouble() ?? 0,
      openingCapital: capital,
      // Backward compat: if has_set_capital not in doc, infer from non-zero capital
      hasSetCapital: json['has_set_capital'] as bool? ?? capital != 0,
    );
  }
}
