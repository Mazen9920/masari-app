/// Manual balance-sheet entries that the user edits by hand.
/// Stored as a single Firestore document per user.
class BalanceSheetEntries {
  final double bankAccounts;
  final double cashOnHand;
  final double unpaidInvoices;
  final double loans;
  final double unpaidSalaries;

  const BalanceSheetEntries({
    this.bankAccounts = 0,
    this.cashOnHand = 0,
    this.unpaidInvoices = 0,
    this.loans = 0,
    this.unpaidSalaries = 0,
  });

  BalanceSheetEntries copyWith({
    double? bankAccounts,
    double? cashOnHand,
    double? unpaidInvoices,
    double? loans,
    double? unpaidSalaries,
  }) {
    return BalanceSheetEntries(
      bankAccounts: bankAccounts ?? this.bankAccounts,
      cashOnHand: cashOnHand ?? this.cashOnHand,
      unpaidInvoices: unpaidInvoices ?? this.unpaidInvoices,
      loans: loans ?? this.loans,
      unpaidSalaries: unpaidSalaries ?? this.unpaidSalaries,
    );
  }

  Map<String, dynamic> toJson() => {
        'bank_accounts': bankAccounts,
        'cash_on_hand': cashOnHand,
        'unpaid_invoices': unpaidInvoices,
        'loans': loans,
        'unpaid_salaries': unpaidSalaries,
      };

  factory BalanceSheetEntries.fromJson(Map<String, dynamic> json) {
    return BalanceSheetEntries(
      bankAccounts: (json['bank_accounts'] as num?)?.toDouble() ?? 0,
      cashOnHand: (json['cash_on_hand'] as num?)?.toDouble() ?? 0,
      unpaidInvoices: (json['unpaid_invoices'] as num?)?.toDouble() ?? 0,
      loans: (json['loans'] as num?)?.toDouble() ?? 0,
      unpaidSalaries: (json['unpaid_salaries'] as num?)?.toDouble() ?? 0,
    );
  }
}
