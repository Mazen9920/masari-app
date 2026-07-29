import '../models/transaction_model.dart';

/// Categories excluded from the Profit & Loss statement.
/// These represent investing / financing activities (balance-sheet movements),
/// not operating income or expenses.
///
/// Membership here is what keeps them out of the P&L — NOT the per-transaction
/// `excludeFromPL` flag. Automated code sets that flag, but a transaction typed
/// in by hand does not, so relying on the flag alone let a manually-recorded
/// cashout or settlement land in the P&L as income and double-count revenue
/// that was already recognized at the sale.
const plExcludedCats = <String>{
  'cat_investments',
  'cat_loan_received',
  'cat_loan_repayment',
  'cat_equity_injection',
  'cat_owner_withdrawal',
  'cat_salary_payment',
  'cat_asset_sale',

  // ── Collections of revenue already recognized at the sale ──
  // Cash arriving for goods already invoiced is a receivable → cash swap, not
  // new income. Counting it would book the same sale twice.
  'cat_bosta_cashout',
  'cat_gateway_settlement',

  // ── Payments settling a cost already expensed ──
  // The expense hit the P&L when it was accrued; paying it only moves cash.
  'cat_accrued_payment',

  // ── Balance-sheet spending, not an expense ──
  // Paying a supplier buys inventory (an asset); capitalized manufacturing
  // labour reaches the P&L later, as COGS, when the finished goods sell.
  'cat_supplier_payment',
  'cat_manufacturing_cost',
};

/// Categories that COUNT toward the P&L totals but are kept out of the
/// on-screen category breakdown.
///
/// Unlike [plExcludedCats] these DO change net profit — they are real costs,
/// just not itemised in the app's P&L chart. Currently empty: every P&L cost is
/// shown. Add an id here to total it without listing it (it stays visible in
/// the CSV / P&L exports and the transactions list either way).
const plHiddenCats = <String>{};

/// Sale-linked transaction categories (accrual entries).
/// These are excluded from bank-balance cash flow and replaced by
/// `sale.amountPaid` to reflect actual cash received.
const saleTxnCats = <String>{
  'cat_sales_revenue',
  'cat_cogs',
  'cat_shipping',
};

/// Whether [t] should be included in P&L calculations.
///
/// Excludes transactions flagged `excludeFromPL` and those in
/// non-operating categories ([plExcludedCats]).
bool isPlTransaction(Transaction t) =>
    !t.excludeFromPL && !plExcludedCats.contains(t.categoryId);

/// Whether [t] represents a real cash movement for the Cash Flow statement.
///
/// Excludes `cat_cogs` (non-cash accrual entry) and transactions flagged
/// `excludeFromPL` — **except** `cat_supplier_payment` which is a real cash
/// outflow even though it's excluded from P&L.
bool isCashFlowTransaction(Transaction t) =>
    t.categoryId != 'cat_cogs' &&
    (t.categoryId == 'cat_supplier_payment' ||
        // Capitalized manufacturing labor: excluded from P&L (it flows to COGS
        // when the finished good is sold) but is a real cash outflow now.
        t.categoryId == 'cat_manufacturing_cost' ||
        !t.excludeFromPL);
