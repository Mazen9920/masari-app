/// Manual balance-sheet entries that the user edits by hand.
/// Stored as a single Firestore document per user.
class BalanceSheetEntries {
  final double cashOnHand;
  final double unpaidInvoices;
  final double loans;
  final double unpaidSalaries;
  final double openingCapital;
  final bool hasSetCapital;

  /// Accumulated retained earnings (or deficit, if negative) the business
  /// carried at the books-start cutover — i.e. profit/loss and pre-books debt
  /// from before tracking began. Kept SEPARATE from [openingCapital] so the
  /// equity section can show contributed capital (positive) distinctly from a
  /// pre-books deficit (GAAP "retained earnings (accumulated deficit)"), instead
  /// of blending them into one possibly-negative "capital" figure.
  final double openingRetainedEarnings;

  /// Cash/bank balance at the books-start cutover. Source of truth for the
  /// "Cash & Bank" opening figure (Firestore-persisted, auditable, device-
  /// independent — supersedes the legacy device-local SharedPreferences value).
  final double openingCashBalance;

  /// The date the books start in the app. Cashouts (and any pre-tracking
  /// activity) BEFORE this date are excluded from the cash balance — their net
  /// effect is captured once in [openingCashBalance]. Null = no cutover (count
  /// everything, legacy behaviour).
  final DateTime? booksStartDate;

  const BalanceSheetEntries({
    this.cashOnHand = 0,
    this.unpaidInvoices = 0,
    this.loans = 0,
    this.unpaidSalaries = 0,
    this.openingCapital = 0,
    this.hasSetCapital = false,
    this.openingCashBalance = 0,
    this.openingRetainedEarnings = 0,
    this.booksStartDate,
  });

  BalanceSheetEntries copyWith({
    double? cashOnHand,
    double? unpaidInvoices,
    double? loans,
    double? unpaidSalaries,
    double? openingCapital,
    bool? hasSetCapital,
    double? openingCashBalance,
    double? openingRetainedEarnings,
    DateTime? booksStartDate,
  }) {
    return BalanceSheetEntries(
      cashOnHand: cashOnHand ?? this.cashOnHand,
      unpaidInvoices: unpaidInvoices ?? this.unpaidInvoices,
      loans: loans ?? this.loans,
      unpaidSalaries: unpaidSalaries ?? this.unpaidSalaries,
      openingCapital: openingCapital ?? this.openingCapital,
      hasSetCapital: hasSetCapital ?? this.hasSetCapital,
      openingCashBalance: openingCashBalance ?? this.openingCashBalance,
      openingRetainedEarnings:
          openingRetainedEarnings ?? this.openingRetainedEarnings,
      booksStartDate: booksStartDate ?? this.booksStartDate,
    );
  }

  Map<String, dynamic> toJson() => {
        'cash_on_hand': cashOnHand,
        'unpaid_invoices': unpaidInvoices,
        'loans': loans,
        'unpaid_salaries': unpaidSalaries,
        'opening_capital': openingCapital,
        'has_set_capital': hasSetCapital,
        'opening_cash_balance': openingCashBalance,
        'opening_retained_earnings': openingRetainedEarnings,
        if (booksStartDate != null)
          'books_start_date': booksStartDate!.toIso8601String(),
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
      openingCashBalance:
          (json['opening_cash_balance'] as num?)?.toDouble() ?? 0,
      openingRetainedEarnings:
          (json['opening_retained_earnings'] as num?)?.toDouble() ?? 0,
      booksStartDate: json['books_start_date'] != null
          ? DateTime.tryParse(json['books_start_date'] as String)
          : null,
    );
  }
}
