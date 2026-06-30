import 'money_utils.dart';

/// Result of the balance-sheet equity reconciliation.
class EquityReconciliation {
  /// The opening/contributed capital used (manual figure, or auto-derived).
  final double effectiveCapital;

  /// Pre-books retained earnings / accumulated deficit carried at the cutover
  /// (echoed back for the equity-section line). Kept distinct from
  /// [effectiveCapital] so contributed capital stays positive and any opening
  /// deficit (e.g. debt the business carried before tracking) shows on its own.
  final double openingRetainedEarnings;

  /// Independently-expected equity =
  /// capital + retained + current net income + owner contributions − withdrawals.
  final double expectedEquity;

  /// The real integrity gap = (assets − liabilities) − expected equity.
  /// 0 means the books reconcile; non-zero is a genuine unexplained difference
  /// (untracked cash, a missing entry, etc.). Always ~0 for auto-capital users
  /// by construction — only meaningful once a manual opening capital is pinned.
  final double unexplainedDifference;

  const EquityReconciliation({
    required this.effectiveCapital,
    this.openingRetainedEarnings = 0,
    required this.expectedEquity,
    required this.unexplainedDifference,
  });
}

/// Reconciles owner's equity against assets − liabilities.
///
/// Equity identity: `Equity = Capital + Retained Earnings + Current Net Income
/// + Owner Contributions − Owner Withdrawals`. When the user has not pinned a
/// manual opening capital, the capital is back-derived so the statement balances
/// by construction (owner flows are still shown on their own lines). When a
/// manual capital is set, any difference between net equity and the expected
/// equity surfaces as [EquityReconciliation.unexplainedDifference].
EquityReconciliation reconcileEquity({
  required double netEquity,
  required double openingCapital,
  required bool hasManualCapital,
  required double retainedEarnings,
  required double currentNetIncome,
  required double ownerContributions,
  required double ownerWithdrawals,
  double openingRetainedEarnings = 0,
}) {
  final autoCapital = roundMoney(netEquity -
      openingRetainedEarnings -
      retainedEarnings -
      currentNetIncome -
      ownerContributions +
      ownerWithdrawals);
  final effectiveCapital = hasManualCapital ? openingCapital : autoCapital;
  final expectedEquity = roundMoney(effectiveCapital +
      openingRetainedEarnings +
      retainedEarnings +
      currentNetIncome +
      ownerContributions -
      ownerWithdrawals);
  final unexplained = roundMoney(netEquity - expectedEquity);
  return EquityReconciliation(
    effectiveCapital: effectiveCapital,
    openingRetainedEarnings: openingRetainedEarnings,
    expectedEquity: expectedEquity,
    unexplainedDifference: unexplained,
  );
}
