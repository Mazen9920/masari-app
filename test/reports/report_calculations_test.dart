import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/models/transaction_model.dart';
import 'package:revvo_app/shared/models/balance_sheet_entries.dart';
import 'package:revvo_app/shared/models/category_data.dart';
import 'package:revvo_app/shared/utils/money_utils.dart';
import 'package:revvo_app/shared/utils/report_constants.dart';

// ────────────────────────────────────────────────────────
//  Test helpers
// ────────────────────────────────────────────────────────

Transaction _tx({
  required double amount,
  required String categoryId,
  DateTime? dateTime,
  bool excludeFromPL = false,
}) {
  return Transaction(
    id: 'tx_${Object().hashCode}',
    userId: 'u1',
    title: 'Test',
    amount: amount,
    dateTime: dateTime ?? DateTime(2025, 6, 15),
    categoryId: categoryId,
    excludeFromPL: excludeFromPL,
  );
}

// P&L aggregation: mirrors the logic in balance_sheet_screen.dart / profit_loss_screen.dart
double _computeNetIncome(List<Transaction> txs) {
  return roundMoney(txs
      .where((t) => !t.excludeFromPL && !plExcludedCats.contains(t.categoryId))
      .fold(0.0, (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs())));
}

// Cash-flow GAAP aggregation: mirrors cash_flow_screen.dart
Map<CashFlowType, double> _computeGaapCashFlow(List<Transaction> txs) {
  double operating = 0, investing = 0, financing = 0;
  for (final t in txs) {
    final signed = t.isIncome ? t.amount.abs() : -t.amount.abs();
    switch (cashFlowTypeFor(t.categoryId)) {
      case CashFlowType.operating:
        operating += signed;
      case CashFlowType.investing:
        investing += signed;
      case CashFlowType.financing:
        financing += signed;
    }
  }
  return {
    CashFlowType.operating: roundMoney(operating),
    CashFlowType.investing: roundMoney(investing),
    CashFlowType.financing: roundMoney(financing),
  };
}

void main() {
  // ═══════════════════════════════════════════════════════
  //  1. CashFlowType mapping
  // ═══════════════════════════════════════════════════════

  group('CashFlowType mapping', () {
    test('investments map to investing', () {
      expect(cashFlowTypeFor('cat_investments'), CashFlowType.investing);
    });

    test('operating categories map correctly', () {
      for (final id in [
        'cat_income',
        'cat_sales_revenue',
        'cat_cogs',
        'cat_groceries',
        'cat_transport',
        'cat_bills',
        'cat_health',
        'cat_other',
        'cat_uncategorized',
        'cat_shipping',
        'cat_tax_payable',
      ]) {
        expect(cashFlowTypeFor(id), CashFlowType.operating, reason: id);
      }
    });

    test('unknown / custom categories default to operating', () {
      expect(cashFlowTypeFor('custom_xyz'), CashFlowType.operating);
      expect(cashFlowTypeFor(''), CashFlowType.operating);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  2. P&L aggregation
  // ═══════════════════════════════════════════════════════

  group('P&L net income', () {
    test('basic income minus expenses', () {
      final txs = [
        _tx(amount: 1000, categoryId: 'cat_sales_revenue'),
        _tx(amount: -400, categoryId: 'cat_cogs'),
        _tx(amount: -100, categoryId: 'cat_shipping'),
      ];
      expect(_computeNetIncome(txs), 500.0);
    });

    test('excludes cat_investments from P&L', () {
      final txs = [
        _tx(amount: 1000, categoryId: 'cat_income'),
        _tx(amount: 5000, categoryId: 'cat_investments'),
      ];
      // investments should be excluded, net = 1000 only
      expect(_computeNetIncome(txs), 1000.0);
    });

    test('excludes transactions with excludeFromPL flag', () {
      final txs = [
        _tx(amount: 500, categoryId: 'cat_income'),
        _tx(amount: 200, categoryId: 'cat_income', excludeFromPL: true),
      ];
      expect(_computeNetIncome(txs), 500.0);
    });

    test('handles empty transaction list', () {
      expect(_computeNetIncome([]), 0.0);
    });

    test('handles all-expense scenario (negative net income)', () {
      final txs = [
        _tx(amount: -300, categoryId: 'cat_groceries'),
        _tx(amount: -200, categoryId: 'cat_transport'),
      ];
      expect(_computeNetIncome(txs), -500.0);
    });

    test('precision: avoids floating-point drift', () {
      // 0.1 + 0.2 = 0.30000000000000004 in IEEE 754
      final txs = [
        _tx(amount: 0.1, categoryId: 'cat_income'),
        _tx(amount: 0.2, categoryId: 'cat_income'),
      ];
      expect(_computeNetIncome(txs), 0.3);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  3. Cash flow GAAP aggregation
  // ═══════════════════════════════════════════════════════

  group('GAAP cash flow classification', () {
    test('all operating if no investment categories', () {
      final txs = [
        _tx(amount: 500, categoryId: 'cat_sales_revenue'),
        _tx(amount: -200, categoryId: 'cat_cogs'),
      ];
      final result = _computeGaapCashFlow(txs);
      expect(result[CashFlowType.operating], 300.0);
      expect(result[CashFlowType.investing], 0.0);
      expect(result[CashFlowType.financing], 0.0);
    });

    test('investments go to investing bucket', () {
      final txs = [
        _tx(amount: 1000, categoryId: 'cat_income'),
        _tx(amount: 5000, categoryId: 'cat_investments'),
        _tx(amount: -300, categoryId: 'cat_groceries'),
      ];
      final result = _computeGaapCashFlow(txs);
      expect(result[CashFlowType.operating], 700.0);
      expect(result[CashFlowType.investing], 5000.0);
      expect(result[CashFlowType.financing], 0.0);
    });

    test('negative investing (investment purchase)', () {
      final txs = [
        _tx(amount: -2000, categoryId: 'cat_investments'),
      ];
      final result = _computeGaapCashFlow(txs);
      expect(result[CashFlowType.investing], -2000.0);
    });

    test('empty transactions', () {
      final result = _computeGaapCashFlow([]);
      expect(result[CashFlowType.operating], 0.0);
      expect(result[CashFlowType.investing], 0.0);
      expect(result[CashFlowType.financing], 0.0);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  4. Retained earnings computation
  // ═══════════════════════════════════════════════════════

  group('Retained earnings (accumulated prior P&L)', () {
    test('split into retained earnings vs current period', () {
      final periodStart = DateTime(2025, 6, 1);
      final periodEnd = DateTime(2025, 6, 30, 23, 59, 59);

      final txs = [
        // Prior period (Q1)
        _tx(amount: 2000, categoryId: 'cat_sales_revenue', dateTime: DateTime(2025, 3, 15)),
        _tx(amount: -800, categoryId: 'cat_cogs', dateTime: DateTime(2025, 3, 15)),
        // Current period (June)
        _tx(amount: 1000, categoryId: 'cat_sales_revenue', dateTime: DateTime(2025, 6, 15)),
        _tx(amount: -300, categoryId: 'cat_cogs', dateTime: DateTime(2025, 6, 15)),
        // Investment (excluded from P&L regardless of period)
        _tx(amount: 5000, categoryId: 'cat_investments', dateTime: DateTime(2025, 4, 1)),
      ];

      final plEligible = txs
          .where((t) => !t.dateTime.isAfter(periodEnd))
          .where((t) => !t.excludeFromPL && !plExcludedCats.contains(t.categoryId));

      final retainedEarnings = roundMoney(plEligible
          .where((t) => t.dateTime.isBefore(periodStart))
          .fold(0.0, (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs())));

      final currentPeriodNet = roundMoney(plEligible
          .where((t) => !t.dateTime.isBefore(periodStart))
          .fold(0.0, (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs())));

      expect(retainedEarnings, 1200.0); // 2000 - 800
      expect(currentPeriodNet, 700.0); // 1000 - 300
    });

    test('no prior transactions yields zero retained earnings', () {
      final periodStart = DateTime(2025, 1, 1);
      final txs = [
        _tx(amount: 500, categoryId: 'cat_income', dateTime: DateTime(2025, 1, 15)),
      ];

      final plEligible = txs
          .where((t) => !t.excludeFromPL && !plExcludedCats.contains(t.categoryId));

      final retainedEarnings = roundMoney(plEligible
          .where((t) => t.dateTime.isBefore(periodStart))
          .fold(0.0, (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs())));

      expect(retainedEarnings, 0.0);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  5. Balance sheet equity equation
  // ═══════════════════════════════════════════════════════

  group('Balance sheet equity equation', () {
    test('Assets = Liabilities + Equity', () {
      final bankBalance = 5000.0;
      final bs = BalanceSheetEntries(
        cashOnHand: 500,
        unpaidInvoices: 200,
        loans: 1500,
        unpaidSalaries: 300,
        openingCapital: 1000,
      );

      final inventoryValue = 3000.0;
      final accountsReceivable = 800.0;
      final supplierAdvancePayments = 100.0;
      final suppliersOwing = 600.0;

      final totalAssets = roundMoney(bankBalance + bs.cashOnHand + bs.unpaidInvoices +
          inventoryValue + accountsReceivable + supplierAdvancePayments);
      final totalLiabilities = roundMoney(suppliersOwing + bs.loans + bs.unpaidSalaries);
      final netEquity = roundMoney(totalAssets - totalLiabilities);

      expect(totalAssets, 9600.0);
      expect(totalLiabilities, 2400.0);
      expect(netEquity, 7200.0);
      expect((totalAssets - totalLiabilities - netEquity).abs() < 0.01, true);
    });

    test('equity breakdown: openingCapital + retainedEarnings + currentPeriodNetIncome', () {
      final openingCapital = 2000.0;
      final retainedEarnings = 3000.0;
      final currentPeriodNetIncome = 1500.0;
      final computedEquity = openingCapital + retainedEarnings + currentPeriodNetIncome;

      // In a balanced state, netEquity from A-L should equal computed equity
      expect(computedEquity, 6500.0);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  6. BalanceSheetEntries model
  // ═══════════════════════════════════════════════════════

  group('BalanceSheetEntries', () {
    test('default constructor has all zeroes', () {
      const bs = BalanceSheetEntries();
      expect(bs.cashOnHand, 0);
      expect(bs.unpaidInvoices, 0);
      expect(bs.loans, 0);
      expect(bs.unpaidSalaries, 0);
      expect(bs.openingCapital, 0);
    });

    test('copyWith preserves untouched fields', () {
      const bs = BalanceSheetEntries(
        cashOnHand: 200,
        loans: 300,
        openingCapital: 1000,
      );
      final updated = bs.copyWith(cashOnHand: 500);
      expect(updated.cashOnHand, 500);
      expect(updated.loans, 300);
      expect(updated.openingCapital, 1000);
    });

    test('toJson / fromJson round-trip', () {
      const original = BalanceSheetEntries(
        cashOnHand: 200,
        unpaidInvoices: 300,
        loans: 400,
        unpaidSalaries: 50,
        openingCapital: 5000,
      );
      final json = original.toJson();
      final restored = BalanceSheetEntries.fromJson(json);

      expect(restored.cashOnHand, original.cashOnHand);
      expect(restored.unpaidInvoices, original.unpaidInvoices);
      expect(restored.loans, original.loans);
      expect(restored.unpaidSalaries, original.unpaidSalaries);
      expect(restored.openingCapital, original.openingCapital);
    });

    test('fromJson handles missing openingCapital (backward compat)', () {
      final json = {
        'bank_accounts': 100.0,
        'cash_on_hand': 50.0,
        'unpaid_invoices': 0.0,
        'loans': 200.0,
        'unpaid_salaries': 0.0,
        // no 'opening_capital' key
      };
      final bs = BalanceSheetEntries.fromJson(json);
      expect(bs.openingCapital, 0.0);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  7. roundMoney utility
  // ═══════════════════════════════════════════════════════

  group('roundMoney', () {
    test('rounds to 2 decimal places', () {
      expect(roundMoney(1.006), 1.01);
      expect(roundMoney(1.004), 1.0);
      expect(roundMoney(99.999), 100.0);
    });

    test('handles negative values', () {
      expect(roundMoney(-1.006), -1.01);
      expect(roundMoney(-0.001), 0.0);
    });

    test('handles zero', () {
      expect(roundMoney(0), 0.0);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  8. Edge cases
  // ═══════════════════════════════════════════════════════

  group('Edge cases', () {
    test('division-by-zero safety: zero equity means zero pct', () {
      // Mirrors the .clamp(-1.0, 1.0) guard in balance_sheet_screen.dart
      const netEquity = 0.0;
      const amount = 100.0;
      final pct = netEquity != 0 ? (amount / netEquity).clamp(-1.0, 1.0) : 0.0;
      expect(pct, 0.0);
    });

    test('very large transaction amounts do not overflow', () {
      final txs = [
        _tx(amount: 1e12, categoryId: 'cat_income'),
        _tx(amount: -5e11, categoryId: 'cat_cogs'),
      ];
      expect(_computeNetIncome(txs), 5e11);
    });

    test('GAAP totals equal total cash flow', () {
      final txs = [
        _tx(amount: 1000, categoryId: 'cat_income'),
        _tx(amount: 500, categoryId: 'cat_investments'),
        _tx(amount: -200, categoryId: 'cat_groceries'),
        _tx(amount: -300, categoryId: 'cat_investments'),
      ];
      final gaap = _computeGaapCashFlow(txs);
      final totalGaap = gaap.values.fold(0.0, (s, v) => s + v);
      final totalDirect = roundMoney(txs.fold(
          0.0, (s, t) => s + (t.isIncome ? t.amount.abs() : -t.amount.abs())));
      expect(roundMoney(totalGaap), totalDirect);
    });
  });

  // ═══════════════════════════════════════════════════════
  //  9. Auto-balance equity (Opening Capital auto-derive)
  // ═══════════════════════════════════════════════════════

  group('Auto-balance equity', () {
    // Mirrors the logic added in balance_sheet_screen.dart:
    //   autoOpeningCapital = netEquity - retainedEarnings - currentPeriodNetIncome
    //   effectiveCapital = hasManualCapital ? manual : autoOpeningCapital
    //   reconAdjustment = netEquity - (effectiveCapital + retainedEarnings + currentPeriodNetIncome)

    test('auto-derived capital balances the equation when no manual override', () {
      const netEquity = 7200.0;
      const retainedEarnings = 3000.0;
      const currentPeriodNetIncome = 1500.0;
      const manualCapital = 0.0; // default — not set

      final autoCapital = roundMoney(netEquity - retainedEarnings - currentPeriodNetIncome);
      final effectiveCapital = manualCapital != 0 ? manualCapital : autoCapital;
      final adjustment = roundMoney(netEquity - (effectiveCapital + retainedEarnings + currentPeriodNetIncome));

      expect(autoCapital, 2700.0);
      expect(effectiveCapital, 2700.0);
      expect(adjustment, 0.0); // perfectly balanced
    });

    test('manual override shows adjustment line', () {
      const netEquity = 7200.0;
      const retainedEarnings = 3000.0;
      const currentPeriodNetIncome = 1500.0;
      const manualCapital = 2000.0; // user override — differs from auto

      final autoCapital = roundMoney(netEquity - retainedEarnings - currentPeriodNetIncome);
      final effectiveCapital = manualCapital != 0 ? manualCapital : autoCapital;
      final adjustment = roundMoney(netEquity - (effectiveCapital + retainedEarnings + currentPeriodNetIncome));

      expect(autoCapital, 2700.0);
      expect(effectiveCapital, 2000.0); // user's value
      expect(adjustment, 700.0); // makes up the difference
    });

    test('equity always balances: capital + retained + netIncome + adjustment = netEquity', () {
      const netEquity = 5000.0;
      const retainedEarnings = 1200.0;
      const currentPeriodNetIncome = 800.0;
      const manualCapital = 1500.0;

      final effectiveCapital = manualCapital != 0 ? manualCapital : roundMoney(netEquity - retainedEarnings - currentPeriodNetIncome);
      final adjustment = roundMoney(netEquity - (effectiveCapital + retainedEarnings + currentPeriodNetIncome));

      expect(effectiveCapital + retainedEarnings + currentPeriodNetIncome + adjustment, netEquity);
    });

    test('negative netEquity works correctly', () {
      const netEquity = -500.0;
      const retainedEarnings = 200.0;
      const currentPeriodNetIncome = -100.0;

      final autoCapital = roundMoney(netEquity - retainedEarnings - currentPeriodNetIncome);
      final adjustment = roundMoney(netEquity - (autoCapital + retainedEarnings + currentPeriodNetIncome));

      expect(autoCapital, -600.0); // negative — liabilities exceed assets minus past earnings
      expect(adjustment, 0.0);
    });

    test('all zeros means zero capital and zero adjustment', () {
      const netEquity = 0.0;
      const retainedEarnings = 0.0;
      const currentPeriodNetIncome = 0.0;

      final autoCapital = roundMoney(netEquity - retainedEarnings - currentPeriodNetIncome);
      expect(autoCapital, 0.0);
      // Edge: manualCapital=0 is treated as "not set", so effectiveCapital = auto = 0
      final effectiveCapital = 0.0 != 0 ? 0.0 : autoCapital;
      expect(effectiveCapital, 0.0);
    });
  });
}
