import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/models/transaction_model.dart';
import 'package:revvo_app/shared/utils/cf_engine.dart';

Transaction txn({
  required String id,
  required String categoryId,
  required double amount,
  String? saleId,
  bool excludeFromPL = false,
  DateTime? date,
}) =>
    Transaction(
      id: id,
      userId: 'u',
      title: id,
      amount: amount,
      dateTime: date ?? DateTime(2026, 3, 1),
      categoryId: categoryId,
      saleId: saleId,
      excludeFromPL: excludeFromPL,
    );

void main() {
  group('CF-user cash filter — COGS is never cash', () {
    test('cat_cogs WITHOUT a sale_id is excluded (the migration-COGS leak)', () {
      final cogs = txn(id: 'mig-1', categoryId: 'cat_cogs', amount: -500);
      expect(cogs.saleId, isNull);
      expect(isCfUserCashTransaction(cogs), isFalse);
      expect(isNonCfUserCashTransaction(cogs), isFalse);
    });

    test('cat_cogs WITH a sale_id is still excluded', () {
      final cogs =
          txn(id: 'c2', categoryId: 'cat_cogs', amount: -500, saleId: 's1');
      expect(isCfUserCashTransaction(cogs), isFalse);
    });

    test('direct cash sale (sales_revenue, no sale_id) STILL counts as cash',
        () {
      // Real direct cash sales must remain in the cash balance.
      final rev = txn(id: 'r1', categoryId: 'cat_sales_revenue', amount: 1000);
      expect(rev.saleId, isNull);
      expect(isCfUserCashTransaction(rev), isTrue);
    });

    test('Bosta sale revenue (with sale_id) is excluded (cash via cashouts)',
        () {
      final rev = txn(
          id: 'r2', categoryId: 'cat_sales_revenue', amount: 1000, saleId: 's');
      expect(isCfUserCashTransaction(rev), isFalse);
    });

    test('gateway settlement counts as cash IN despite excludeFromPL', () {
      // Paymob etc. settling to the bank is a real cash inflow; revenue was
      // already booked at the sale, so it's excluded from P&L but is cash.
      final s = txn(
          id: 'gw',
          categoryId: 'cat_gateway_settlement',
          amount: 5000,
          excludeFromPL: true);
      expect(isCfUserCashTransaction(s), isTrue);
      expect(cashImpact(s, isCfUser: true), 5000);
    });

    test('accrued-expense recognition is NOT cash (non-cash accrual)', () {
      final e =
          txn(id: 'ae', categoryId: 'cat_accrued_expense', amount: -3000);
      expect(isCfUserCashTransaction(e), isFalse);
      expect(cashImpact(e, isCfUser: true), isNull);
    });

    test('accrued-expense payment IS cash out despite excludeFromPL', () {
      final p = txn(
          id: 'ap',
          categoryId: 'cat_accrued_payment',
          amount: -3000,
          excludeFromPL: true);
      expect(isCfUserCashTransaction(p), isTrue);
      expect(cashImpact(p, isCfUser: true), -3000);
    });

    test('a FLAGGED cashout txn is not cash — it came via totalCashouts', () {
      // Mirrors a payout already counted in the cashout total; counting the
      // transaction too would bank the same money twice.
      final c = txn(
          id: 'co',
          categoryId: 'cat_bosta_cashout',
          amount: 25000,
          excludeFromPL: true);
      expect(isCfUserCashTransaction(c), isFalse);
      expect(cashImpact(c, isCfUser: true), isNull);
    });

    test('an UNFLAGGED cashout IS cash — the sync never captured it', () {
      // Recorded by hand precisely because it is missing from the synced
      // cashouts, so dropping it would lose real money from the balance.
      final c = txn(id: 'co2', categoryId: 'cat_bosta_cashout', amount: 3499);
      expect(c.excludeFromPL, isFalse);
      expect(isCfUserCashTransaction(c), isTrue);
      expect(cashImpact(c, isCfUser: true), 3499);
    });

    test('flagged cashouts are not double-counted in the closing balance', () {
      final cash = computeClosingCash(
        openingCash: 0,
        transactions: [
          txn(
              id: 'co',
              categoryId: 'cat_bosta_cashout',
              amount: 25000,
              excludeFromPL: true),
          txn(id: 'exp', categoryId: 'cat_marketing', amount: -5000),
        ],
        asOf: DateTime(2026, 12, 31),
        isCfUser: true,
        totalCashouts: 25000,
      );
      // 25,000 collected once + 5,000 spent — not 50,000 collected.
      expect(cash, 20000);
    });

    test('supplier payment still counts as a cash outflow', () {
      final sp = txn(
          id: 'sp',
          categoryId: 'cat_supplier_payment',
          amount: -2000,
          excludeFromPL: true);
      expect(isCfUserCashTransaction(sp), isTrue);
    });
  });

  group('cashImpact — single source of truth for filter + sign', () {
    test('COGS returns null (excluded)', () {
      expect(cashImpact(txn(id: 'c', categoryId: 'cat_cogs', amount: -50),
              isCfUser: true),
          isNull);
    });
    test('positive amount is income even when is_income flag would be false', () {
      // The model derives income from amount > 0, so a direct cash sale counts
      // as +amount regardless of any stored flag.
      final rev = txn(id: 'r', categoryId: 'cat_sales_revenue', amount: 1000);
      expect(cashImpact(rev, isCfUser: true), 1000);
    });
    test('expense is a negative impact', () {
      final sp = txn(
          id: 's',
          categoryId: 'cat_supplier_payment',
          amount: -2000,
          excludeFromPL: true);
      expect(cashImpact(sp, isCfUser: true), -2000);
    });
    test('sums to the same as computeClosingCash', () {
      final txns = [
        txn(id: 'rev', categoryId: 'cat_sales_revenue', amount: 1000),
        txn(id: 'cogs', categoryId: 'cat_cogs', amount: -300),
        txn(id: 'exp', categoryId: 'cat_marketing', amount: -200),
      ];
      final viaImpact = txns.fold<double>(
          0, (s, t) => s + (cashImpact(t, isCfUser: true) ?? 0));
      final viaEngine = computeClosingCash(
            openingCash: 0,
            transactions: txns,
            asOf: DateTime(2026, 12, 31),
            isCfUser: true,
            totalCashouts: 0,
          );
      expect(viaImpact, viaEngine); // 1000 - 200 = 800 (COGS excluded)
      expect(viaEngine, 800);
    });
  });

  group('computeClosingCash drops the COGS leak', () {
    test('unlinked COGS no longer reduces the cash balance', () {
      final txns = [
        txn(id: 'rev', categoryId: 'cat_sales_revenue', amount: 1000),
        txn(id: 'mig', categoryId: 'cat_cogs', amount: -300), // leak before fix
        txn(
            id: 'exp',
            categoryId: 'cat_marketing',
            amount: -200),
      ];
      final cash = computeClosingCash(
        openingCash: 0,
        transactions: txns,
        asOf: DateTime(2026, 12, 31),
        isCfUser: true,
        totalCashouts: 5000,
      );
      // 0 opening + 5000 cashouts + 1000 cash sale - 200 marketing
      // (the -300 COGS must NOT be subtracted).
      expect(cash, 5800);
    });
  });
}
