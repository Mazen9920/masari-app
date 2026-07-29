import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/models/transaction_model.dart';
import 'package:revvo_app/shared/utils/report_constants.dart';

/// A transaction typed in by hand — note `excludeFromPL` defaults to false,
/// which is exactly what made manual entries leak into the P&L.
Transaction manual(String categoryId, double amount) => Transaction(
      id: 'm',
      userId: 'u',
      title: 'manual entry',
      amount: amount,
      dateTime: DateTime(2026, 7, 1),
      categoryId: categoryId,
    );

void main() {
  _hidden();
  group('manually-entered collections must not become income', () {
    test('a hand-recorded Bosta cashout stays out of the P&L', () {
      // The sale already booked the revenue; the cashout is just collection.
      final t = manual('cat_bosta_cashout', 25000);
      expect(t.excludeFromPL, isFalse); // flag NOT set — the whole point
      expect(isPlTransaction(t), isFalse);
    });

    test('a hand-recorded gateway settlement stays out of the P&L', () {
      expect(isPlTransaction(manual('cat_gateway_settlement', 17850)), isFalse);
    });

    test('automated entries (flag set) are excluded too', () {
      final auto = Transaction(
        id: 'a',
        userId: 'u',
        title: 'auto',
        amount: 25000,
        dateTime: DateTime(2026, 7, 1),
        categoryId: 'cat_bosta_cashout',
        excludeFromPL: true,
      );
      expect(isPlTransaction(auto), isFalse);
    });
  });

  group('manually-entered payments must not become expenses', () {
    test('paying an accrued expense is not a second expense', () {
      // The cost hit the P&L when it was accrued.
      expect(isPlTransaction(manual('cat_accrued_payment', -15000)), isFalse);
    });

    test('paying a supplier buys inventory, it is not an expense', () {
      expect(isPlTransaction(manual('cat_supplier_payment', -50000)), isFalse);
    });

    test('capitalized manufacturing labour reaches P&L later as COGS', () {
      expect(isPlTransaction(manual('cat_manufacturing_cost', -10022)), isFalse);
    });
  });

  group('real P&L lines are still included', () {
    test('sales revenue', () {
      expect(isPlTransaction(manual('cat_sales_revenue', 1000)), isTrue);
    });
    test('COGS', () {
      expect(isPlTransaction(manual('cat_cogs', -300)), isTrue);
    });
    test('ordinary expenses', () {
      expect(isPlTransaction(manual('cat_marketing', -500)), isTrue);
      expect(isPlTransaction(manual('cat_rent', -2000)), isTrue);
      expect(isPlTransaction(manual('cat_salary_expense', -9000)), isTrue);
    });
    test('gateway FEES are a real cost and stay in the P&L', () {
      // Distinct from the settlement itself: the fee is money genuinely lost.
      expect(isPlTransaction(manual('cat_gateway_fees', -250)), isTrue);
    });
    test('accrued-expense recognition stays in the P&L', () {
      expect(isPlTransaction(manual('cat_accrued_expense', -5000)), isTrue);
    });
    test('genuine other income still counts', () {
      expect(isPlTransaction(manual('cat_income', 3000)), isTrue);
    });
  });

  group('the flag still works on its own', () {
    test('any category flagged excludeFromPL is skipped', () {
      final t = Transaction(
        id: 'f',
        userId: 'u',
        title: 'flagged',
        amount: -100,
        dateTime: DateTime(2026, 7, 1),
        categoryId: 'cat_marketing',
        excludeFromPL: true,
      );
      expect(isPlTransaction(t), isFalse);
    });
  });
}

// ── "P adjustment" write-offs ──────────────────────────────────────
// Real, non-cash losses that reduce profit AND appear in the P&L breakdown.
void _hidden() {
  group('P adjustment write-offs', () {
    test('DO count toward the P&L (they are a real loss)', () {
      expect(isPlTransaction(manual('cat_d_paymob', -1461.52)), isTrue);
    });

    test('are shown in the breakdown — not hidden', () {
      expect(plHiddenCats.contains('cat_d_paymob'), isFalse);
    });

    test('are NOT in plExcludedCats — that would stop them reducing profit', () {
      expect(plExcludedCats.contains('cat_d_paymob'), isFalse);
    });

    test('hiding and excluding are different things', () {
      // Nothing may be in both sets: excluded means "not profit", hidden means
      // "profit, just not itemised".
      expect(plHiddenCats.intersection(plExcludedCats), isEmpty);
    });
  });
}
