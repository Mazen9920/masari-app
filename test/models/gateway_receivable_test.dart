import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/models/gateway_receivable_model.dart';
import 'package:revvo_app/shared/models/transaction_model.dart';
import 'package:revvo_app/shared/utils/cf_engine.dart';

GatewaySettlement settle(double amount,
        {double fee = 0, DateTime? date, String id = 's1'}) =>
    GatewaySettlement(
        id: id, amount: amount, fee: fee, date: date ?? DateTime(2026, 6, 10));

GatewayReceivable gw({
  double pending = 10000,
  int? settlementDays,
  double? feePercent,
  List<GatewaySettlement> settlements = const [],
  List<GatewayCollection> collections = const [],
  DateTime? createdAt,
}) =>
    GatewayReceivable(
      id: 'g1',
      gatewayName: 'Paymob',
      pendingBalance: pending,
      settlementDays: settlementDays,
      feePercent: feePercent,
      settlements: settlements,
      collections: collections,
      createdAt: createdAt ?? DateTime(2026, 6, 1),
    );

void main() {
  group('fees — the overstated-cash bug', () {
    test('net is gross minus fee', () {
      final s = settle(10000, fee: 250);
      expect(s.netAmount, 9750);
    });

    test('no fee means net equals gross', () {
      expect(settle(10000).netAmount, 10000);
    });

    test('fee never pushes net below zero', () {
      expect(settle(100, fee: 500).netAmount, 0);
    });

    test('per-settlement fee rate', () {
      expect(settle(10000, fee: 250).feeRate, 2.5);
    });

    test('zero-amount settlement does not divide by zero', () {
      expect(settle(0, fee: 0).feeRate, 0);
    });
  });

  group('account totals', () {
    final r = gw(pending: 5000, settlements: [
      settle(10000, fee: 250, id: 'a'),
      settle(6000, fee: 150, id: 'b'),
    ]);

    test('gross cleared', () => expect(r.totalSettled, 16000));
    test('fees kept by the gateway', () => expect(r.totalFees, 400));
    test('cash actually banked is net', () {
      expect(r.totalCashReceived, 15600); // 9,750 + 5,850
    });
    test('effective fee rate across all payouts', () {
      expect(r.effectiveFeeRate, closeTo(2.5, 0.001));
    });
  });

  group('cash-flow treatment', () {
    test('settlement cash counts as cash IN despite excludeFromPL', () {
      final t = Transaction(
        id: 'c',
        userId: 'u',
        title: 'settle',
        amount: 9750,
        dateTime: DateTime(2026, 6, 10),
        categoryId: 'cat_gateway_settlement',
        excludeFromPL: true,
      );
      expect(cashImpact(t, isCfUser: true), 9750);
    });

    test('the fee is NOT cash — it never reached the bank', () {
      // The settlement's cash entry is already net; counting the fee as a
      // cash outflow too would deduct it twice.
      final fee = Transaction(
        id: 'f',
        userId: 'u',
        title: 'fees',
        amount: -250,
        dateTime: DateTime(2026, 6, 10),
        categoryId: 'cat_gateway_fees',
      );
      expect(isCfUserCashTransaction(fee), isFalse);
      expect(cashImpact(fee, isCfUser: true), isNull);
    });

    test('gross + fee together equal the receivable cleared', () {
      final s = settle(10000, fee: 250);
      expect(s.netAmount + s.fee, s.amount);
    });
  });

  group('settlement ageing', () {
    test('no cycle set is never flagged overdue', () {
      expect(gw().settlementOverdue, isFalse);
    });

    test('a cleared balance is never overdue', () {
      expect(gw(pending: 0, settlementDays: 2).settlementOverdue, isFalse);
    });

    test('money held past the cycle is flagged', () {
      final r = gw(
        pending: 5000,
        settlementDays: 2,
        settlements: [
          settle(1000, date: DateTime.now().subtract(const Duration(days: 9)))
        ],
      );
      expect(r.daysSinceLastSettlement, 9);
      expect(r.settlementOverdue, isTrue);
    });

    test('recently settled is not flagged', () {
      final r = gw(
        pending: 5000,
        settlementDays: 7,
        settlements: [
          settle(1000, date: DateTime.now().subtract(const Duration(days: 1)))
        ],
      );
      expect(r.settlementOverdue, isFalse);
    });

    test('never settled measures from account creation', () {
      final r = gw(
        pending: 5000,
        settlementDays: 2,
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      );
      expect(r.daysSinceLastSettlement, isNull);
      expect(r.settlementOverdue, isTrue);
    });
  });

  group('collections', () {
    test('sum what the gateway collected', () {
      final r = gw(collections: [
        GatewayCollection(id: 'c1', amount: 3000, date: DateTime(2026, 6, 2)),
        GatewayCollection(id: 'c2', amount: 2000, date: DateTime(2026, 6, 3)),
      ]);
      expect(r.totalCollected, 5000);
      expect(r.lastCollectionDate, DateTime(2026, 6, 3));
    });
  });

  group('progress and state', () {
    test('progress is settled over everything ever held', () {
      final r = gw(pending: 5000, settlements: [settle(5000)]);
      expect(r.progressPct, 0.5);
    });
    test('nothing held yet does not divide by zero', () {
      expect(gw(pending: 0).progressPct, 0);
    });
    test('cleared when nothing is pending', () {
      expect(gw(pending: 0).isCleared, isTrue);
      expect(gw(pending: 10).isCleared, isFalse);
    });
  });

  group('serialization round-trip', () {
    test('keeps fees, cycle and collections', () {
      final r = gw(
        pending: 4000,
        settlementDays: 2,
        feePercent: 2.5,
        settlements: [settle(6000, fee: 150)],
        collections: [
          GatewayCollection(id: 'c1', amount: 1000, date: DateTime(2026, 6, 5))
        ],
      );
      final back = GatewayReceivable.fromJson(r.toJson());
      expect(back.settlementDays, 2);
      expect(back.feePercent, 2.5);
      expect(back.settlements.single.fee, 150);
      expect(back.settlements.single.netAmount, 5850);
      expect(back.collections.single.amount, 1000);
    });
  });
}
