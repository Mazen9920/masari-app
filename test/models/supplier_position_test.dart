import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/models/purchase_model.dart';
import 'package:revvo_app/shared/utils/supplier_position.dart';

Purchase purchase({
  required int qty,
  required double unitPrice,
  int receivedQty = 0,
  double amountPaid = 0,
  int paymentStatus = 0,
}) =>
    Purchase(
      id: 'p$qty$unitPrice$receivedQty',
      userId: 'u',
      supplierId: 's1',
      supplierName: 'Hassan',
      date: DateTime(2026, 7, 24),
      items: [
        PurchaseItem(
          name: 'Finishing',
          category: 'Manufacturing',
          qty: qty,
          unitPrice: unitPrice,
          receivedQty: receivedQty,
        ),
      ],
      amountPaid: amountPaid,
      paymentStatus: paymentStatus,
      createdAt: DateTime(2026, 7, 24),
    );

void main() {
  group('the two-different-answers bug', () {
    test('an unapplied payment reduces what is owed', () {
      // Real case: 32,855 of finishing received, nothing marked paid on the
      // purchases, but a 10,000 payment sits unapplied. True debt is 22,855.
      final pos = computeSupplierPosition(
        [purchase(qty: 100, unitPrice: 328.55, receivedQty: 100)],
        unappliedCredits: 10000,
      );
      expect(pos.received, 32855);
      expect(pos.payable, 22855);
      expect(pos.unappliedCredits, 10000);
    });

    test('without credits the payable is the full received value', () {
      final pos = computeSupplierPosition(
        [purchase(qty: 100, unitPrice: 328.55, receivedQty: 100)],
      );
      expect(pos.payable, 32855);
    });
  });

  group('credit surplus becomes a prepayment', () {
    test('credits beyond the payable are an asset, not negative debt', () {
      final pos = computeSupplierPosition(
        [purchase(qty: 10, unitPrice: 100, receivedQty: 10)], // 1,000 received
        unappliedCredits: 2500,
      );
      expect(pos.payable, 0);       // never negative
      expect(pos.prepaid, 1500);    // 2,500 − 1,000
    });

    test('payable never goes below zero', () {
      final pos = computeSupplierPosition(
        [purchase(qty: 1, unitPrice: 50, receivedQty: 1)],
        unappliedCredits: 999999,
      );
      expect(pos.payable, 0);
    });

    test('a negative credit figure is ignored, not added', () {
      final pos = computeSupplierPosition(
        [purchase(qty: 10, unitPrice: 100, receivedQty: 10)],
        unappliedCredits: -500,
      );
      expect(pos.payable, 1000);
    });
  });

  group('accrual basis — you only owe for what arrived', () {
    test('goods not received are on order, not a payable', () {
      final pos = computeSupplierPosition([
        purchase(qty: 100, unitPrice: 100, receivedQty: 0), // nothing arrived
      ]);
      expect(pos.payable, 0);
      expect(pos.onOrder, 10000);
      expect(pos.received, 0);
    });

    test('part-received bills owe only for the received part', () {
      final pos = computeSupplierPosition([
        purchase(qty: 100, unitPrice: 100, receivedQty: 40),
      ]);
      expect(pos.received, 4000);
      expect(pos.payable, 4000);
      expect(pos.onOrder, 6000);
    });

    test('paying ahead of receipt is a prepayment', () {
      final pos = computeSupplierPosition([
        purchase(
            qty: 100,
            unitPrice: 100,
            receivedQty: 0,
            amountPaid: 3300,
            paymentStatus: 2),
      ]);
      expect(pos.prepaid, 3300);
      expect(pos.payable, 0);
    });

    test('received and fully paid leaves nothing owed', () {
      final pos = computeSupplierPosition([
        purchase(
            qty: 1,
            unitPrice: 10022,
            receivedQty: 1,
            amountPaid: 10022,
            paymentStatus: 2),
      ]);
      expect(pos.payable, 0);
      expect(pos.prepaid, 0);
    });
  });

  group('aggregation across several purchases', () {
    test('sums correctly and applies credits to the total', () {
      final pos = computeSupplierPosition([
        purchase(qty: 1, unitPrice: 10022, receivedQty: 1, amountPaid: 10022, paymentStatus: 2),
        purchase(qty: 44, unitPrice: 75, receivedQty: 44, amountPaid: 3300, paymentStatus: 2),
        purchase(qty: 100, unitPrice: 45, receivedQty: 100),  // 4,500 unpaid
        purchase(qty: 60, unitPrice: 45, receivedQty: 60),    // 2,700 unpaid
      ], unappliedCredits: 1000);
      expect(pos.received, 10022 + 3300 + 4500 + 2700);
      expect(pos.payable, 4500 + 2700 - 1000);
      expect(pos.paid, 10022 + 3300 + 1000); // credits count as cash out
    });

    test('no purchases and no credits is all zeros', () {
      final pos = computeSupplierPosition([]);
      expect(pos.payable, 0);
      expect(pos.prepaid, 0);
      expect(pos.billed, 0);
    });

    test('a credit with no purchases is a pure prepayment', () {
      final pos = computeSupplierPosition([], unappliedCredits: 5000);
      expect(pos.payable, 0);
      expect(pos.prepaid, 5000);
    });
  });
}
