/// Manual balance-sheet entries that the user edits by hand.
/// Stored as a single Firestore document per user.
class BalanceSheetEntries {
  final double cashOnHand;
  final double unpaidInvoices;
  final double loans;
  final double unpaidSalaries;
  final double openingCapital;

  const BalanceSheetEntries({
    this.cashOnHand = 0,
    this.unpaidInvoices = 0,
    this.loans = 0,
    this.unpaidSalaries = 0,
    this.openingCapital = 0,
  });

  BalanceSheetEntries copyWith({
    double? cashOnHand,
    double? unpaidInvoices,
    double? loans,
    double? unpaidSalaries,
    double? openingCapital,
  }) {
    return BalanceSheetEntries(
      cashOnHand: cashOnHand ?? this.cashOnHand,
      unpaidInvoices: unpaidInvoices ?? this.unpaidInvoices,
      loans: loans ?? this.loans,
      unpaidSalaries: unpaidSalaries ?? this.unpaidSalaries,
      openingCapital: openingCapital ?? this.openingCapital,
    );
  }

  Map<String, dynamic> toJson() => {
        'cash_on_hand': cashOnHand,
        'unpaid_invoices': unpaidInvoices,
        'loans': loans,
        'unpaid_salaries': unpaidSalaries,
        'opening_capital': openingCapital,
      };

  factory BalanceSheetEntries.fromJson(Map<String, dynamic> json) {
    // 'bank_accounts' deliberately ignored for backward compatibility
    return BalanceSheetEntries(
      cashOnHand: (json['cash_on_hand'] as num?)?.toDouble() ?? 0,
      unpaidInvoices: (json['unpaid_invoices'] as num?)?.toDouble() ?? 0,
      loans: (json['loans'] as num?)?.toDouble() ?? 0,
      unpaidSalaries: (json['unpaid_salaries'] as num?)?.toDouble() ?? 0,
      openingCapital: (json['opening_capital'] as num?)?.toDouble() ?? 0,
    );
  }
}
