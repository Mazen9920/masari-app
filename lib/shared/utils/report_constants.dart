import '../models/transaction_model.dart';

/// Categories excluded from the Profit & Loss statement.
/// These represent investing / financing activities (balance-sheet movements),
/// not operating income or expenses.
const plExcludedCats = <String>{
  'cat_investments',
  'cat_loan_received',
  'cat_loan_repayment',
  'cat_equity_injection',
  'cat_owner_withdrawal',
};

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
    (t.categoryId == 'cat_supplier_payment' || !t.excludeFromPL);
