import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/models/purchase_model.dart';

// Accrual-basis position on a purchase: you only owe for goods RECEIVED; cash
// paid ahead of receipt is a prepayment (asset); billed-but-not-received is an
// open commitment. Mirrors the balance-sheet supplier payable / prepayment.
void main() {
  // A 100k bill for 50kg of material (2000/kg).
  Purchase bill({required int receivedQty, required double amountPaid}) {
    return Purchase(
      id: 'p1',
      userId: 'u',
      supplierId: 's1',
      supplierName: 'Acme',
      date: DateTime(2026, 6, 1),
      referenceNo: 'PO-1',
      items: [
        PurchaseItem(
          name: 'Material',
          category: 'raw',
          qty: 50,
          unitPrice: 2000,
          receivedQty: receivedQty,
        ),
      ],
      tax: 0,
      paymentStatus: amountPaid <= 0 ? 0 : 1,
      amountPaid: amountPaid,
      createdAt: DateTime(2026, 6, 1),
    );
  }

  group('Purchase accrual position', () {
    test('received 50kg, paid 20k → payable 80k, no prepaid, nothing on order',
        () {
      final p = bill(receivedQty: 50, amountPaid: 20000);
      expect(p.total, 100000);
      expect(p.totalReceivedValue, 100000);
      expect(p.accruedPayable, 80000);
      expect(p.supplierPrepayment, 0);
      expect(p.notYetReceivedValue, 0);
    });

    test('not received, paid 0 → owe nothing, 100k still on order', () {
      final p = bill(receivedQty: 0, amountPaid: 0);
      expect(p.accruedPayable, 0);
      expect(p.supplierPrepayment, 0);
      expect(p.notYetReceivedValue, 100000);
    });

    test('not received, paid 20k deposit → 20k prepaid, 100k on order, owe 0',
        () {
      final p = bill(receivedQty: 0, amountPaid: 20000);
      expect(p.accruedPayable, 0);
      expect(p.supplierPrepayment, 20000);
      expect(p.notYetReceivedValue, 100000);
    });

    test('partial receipt 25kg, paid 10k → payable 40k, 50k on order', () {
      final p = bill(receivedQty: 25, amountPaid: 10000);
      expect(p.totalReceivedValue, 50000);
      expect(p.accruedPayable, 40000); // 50k received − 10k paid
      expect(p.supplierPrepayment, 0);
      expect(p.notYetReceivedValue, 50000); // 100k billed − 50k received
    });

    test('due (total − paid) decomposes as payable + onOrder − prepaid', () {
      for (final p in [
        bill(receivedQty: 50, amountPaid: 20000),
        bill(receivedQty: 0, amountPaid: 20000),
        bill(receivedQty: 25, amountPaid: 60000),
      ]) {
        final due = p.total - p.amountPaid;
        expect(p.accruedPayable + p.notYetReceivedValue - p.supplierPrepayment,
            closeTo(due, 0.01));
      }
    });
  });
}
