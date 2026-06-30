import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/utils/books_cutover.dart';
import 'package:revvo_app/shared/models/balance_sheet_entries.dart';

void main() {
  group('booksStartKey', () {
    test('null when no cutover set', () {
      expect(booksStartKey(null), isNull);
    });
    test('formats as YYYY-MM-DD', () {
      expect(booksStartKey(DateTime(2026, 1, 1)), '2026-01-01');
    });
  });

  group('cashoutOnOrAfterStart', () {
    const start = '2026-01-01';
    test('no cutover → everything counts', () {
      expect(cashoutOnOrAfterStart('2025-05-01T00:00:00Z', null), isTrue);
      expect(cashoutOnOrAfterStart('', null), isTrue);
    });
    test('pre-cutover 2025 cashout is excluded', () {
      expect(cashoutOnOrAfterStart('2025-12-31T10:00:00Z', start), isFalse);
    });
    test('cashout on the cutover day is included', () {
      expect(cashoutOnOrAfterStart('2026-01-01T08:00:00Z', start), isTrue);
    });
    test('post-cutover cashout is included', () {
      expect(cashoutOnOrAfterStart('2026-03-15T12:00:00Z', start), isTrue);
    });
    test('undated cashout excluded once a cutover is set', () {
      expect(cashoutOnOrAfterStart('', start), isFalse);
    });
  });

  group('cashoutOnOrBeforeAsOf (same-day inclusion)', () {
    const asOf = '2026-06-29';
    test('same-day timestamped cashout IS included', () {
      // The bug: a same-day cashout carries a time component, so a raw string
      // compare ('2026-06-29T12:00' <= '2026-06-29') is false. Must be true.
      expect(cashoutOnOrBeforeAsOf('2026-06-29T12:00:00Z', asOf), isTrue);
    });
    test('future cashout is excluded', () {
      expect(cashoutOnOrBeforeAsOf('2026-06-30T00:00:00Z', asOf), isFalse);
    });
    test('past cashout (date-only) is included', () {
      expect(cashoutOnOrBeforeAsOf('2026-03-01', asOf), isTrue);
    });
  });

  group('windowedCashoutTotal', () {
    final cashouts = [
      (amount: 100.0, date: '2025-12-15T00:00:00Z'), // pre-cutover
      (amount: 200.0, date: '2026-01-10T00:00:00Z'),
      (amount: 300.0, date: '2026-06-29T12:00:00Z'), // same-day as asOf
      (amount: 400.0, date: '2026-07-01T00:00:00Z'), // future
    ];
    test('sums only within [start, asOf], same-day inclusive', () {
      final total = windowedCashoutTotal(cashouts,
          startKey: '2026-01-01', asOfKey: '2026-06-29');
      expect(total, 500.0); // 200 + 300; excludes 2025 and the future one
    });
    test('no cutover counts everything up to asOf', () {
      final total =
          windowedCashoutTotal(cashouts, startKey: null, asOfKey: '2026-06-29');
      expect(total, 600.0); // 100 + 200 + 300
    });
  });

  group('BalanceSheetEntries persists the new fields', () {
    test('round-trips opening cash + books-start date', () {
      final e = BalanceSheetEntries(
        openingCashBalance: 31702,
        booksStartDate: DateTime(2026, 1, 1),
      );
      final back = BalanceSheetEntries.fromJson(e.toJson());
      expect(back.openingCashBalance, 31702);
      expect(back.booksStartDate, DateTime(2026, 1, 1));
    });
    test('defaults are safe (0 / null) for legacy docs', () {
      final back = BalanceSheetEntries.fromJson({'cash_on_hand': 5});
      expect(back.openingCashBalance, 0);
      expect(back.booksStartDate, isNull);
    });
  });
}
