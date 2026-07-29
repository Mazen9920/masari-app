import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/models/purchase_model.dart';
import 'package:revvo_app/shared/utils/receipt_allocation.dart';

PurchaseItem item(String name, int qty,
        {int received = 0, String? productId, String? variantId}) =>
    PurchaseItem(
      name: name,
      category: '',
      qty: qty,
      unitPrice: 100,
      receivedQty: received,
      productId: productId,
      variantId: variantId,
    );

ReceiptLine line(String name, int qty, {String? productId, String? variantId}) =>
    (productId: productId, variantId: variantId, name: name, qty: qty);

void main() {
  group('the 108-of-93 bug', () {
    // Real purchase: three separate lines of the SAME belt (16, 11, 6),
    // plus two other products. 93 ordered in total.
    List<PurchaseItem> purchase() => [
          item('Gym Pin', 50, productId: 'pin'),
          item('Lever Belt 13mm - RPE Original', 16, productId: 'belt13'),
          item('Lever Belt 13mm - RPE Original', 11, productId: 'belt13'),
          item('Lever Belt 13mm - RPE Original', 6, productId: 'belt13'),
          item('Lever Belt V2.0 - 10mm', 10, productId: 'belt10'),
        ];

    test('a full receipt fills every line exactly, never over', () {
      final out = applyReceiptToItems(purchase(), [
        line('Gym Pin', 50, productId: 'pin'),
        line('Lever Belt 13mm - RPE Original', 33, productId: 'belt13'),
        line('Lever Belt V2.0 - 10mm', 10, productId: 'belt10'),
      ]);
      expect(out.map((i) => i.receivedQty).toList(), [50, 16, 11, 6, 10]);
      final total = out.fold<int>(0, (s, i) => s + i.receivedQty);
      expect(total, 93); // was 108 before the fix
      expect(out.every((i) => i.receivedQty <= i.qty), isTrue);
    });

    test('a duplicated product is spread across lines, not copied onto each', () {
      // 16 belts received: first line takes all 16, others stay empty.
      final out = applyReceiptToItems(purchase(), [
        line('Lever Belt 13mm - RPE Original', 16, productId: 'belt13'),
      ]);
      expect(out[1].receivedQty, 16);
      expect(out[2].receivedQty, 0);
      expect(out[3].receivedQty, 0);
    });

    test('a partial receipt overflows into the next line of the same product', () {
      // 20 belts: 16 fills line one, the remaining 4 go to line two.
      final out = applyReceiptToItems(purchase(), [
        line('Lever Belt 13mm - RPE Original', 20, productId: 'belt13'),
      ]);
      expect(out[1].receivedQty, 16);
      expect(out[2].receivedQty, 4);
      expect(out[3].receivedQty, 0);
    });

    test('receiving more than ordered is capped, not recorded', () {
      final out = applyReceiptToItems(purchase(), [
        line('Lever Belt 13mm - RPE Original', 999, productId: 'belt13'),
      ]);
      expect(out[1].receivedQty, 16);
      expect(out[2].receivedQty, 11);
      expect(out[3].receivedQty, 6);
      expect(out.fold<int>(0, (s, i) => s + i.receivedQty), 33);
    });
  });

  group('successive receipts accumulate correctly', () {
    test('two part-deliveries add up without exceeding the order', () {
      var items = [
        item('Belt', 16, productId: 'b'),
        item('Belt', 11, productId: 'b'),
      ];
      items = applyReceiptToItems(items, [line('Belt', 10, productId: 'b')]);
      expect(items.map((i) => i.receivedQty).toList(), [10, 0]);

      items = applyReceiptToItems(items, [line('Belt', 12, productId: 'b')]);
      // 6 tops up the first line, 6 go to the second.
      expect(items.map((i) => i.receivedQty).toList(), [16, 6]);
    });
  });

  group('matching rules', () {
    test('same product but different variants do not cross-fill', () {
      final items = [
        item('Belt', 5, productId: 'b', variantId: 'black'),
        item('Belt', 5, productId: 'b', variantId: 'red'),
      ];
      final out = applyReceiptToItems(
          items, [line('Belt', 5, productId: 'b', variantId: 'red')]);
      expect(out[0].receivedQty, 0);
      expect(out[1].receivedQty, 5);
    });

    test('custom items with no product id match by name', () {
      final out = applyReceiptToItems(
          [item('Belts Bag', 44)], [line('belts bag', 44)]);
      expect(out.single.receivedQty, 44);
    });

    test('an unrelated receipt line changes nothing', () {
      final out =
          applyReceiptToItems([item('Belt', 5, productId: 'b')],
              [line('Chalk', 5, productId: 'chalk')]);
      expect(out.single.receivedQty, 0);
    });
  });

  group('reversal (deleting or editing a receipt)', () {
    test('removes exactly what was added', () {
      final start = [
        item('Belt', 16, productId: 'b'),
        item('Belt', 11, productId: 'b'),
      ];
      final received =
          applyReceiptToItems(start, [line('Belt', 20, productId: 'b')]);
      expect(received.map((i) => i.receivedQty).toList(), [16, 4]);

      final back =
          reverseReceiptFromItems(received, [line('Belt', 20, productId: 'b')]);
      expect(back.map((i) => i.receivedQty).toList(), [0, 0]);
    });

    test('never goes negative', () {
      final out = reverseReceiptFromItems(
          [item('Belt', 10, productId: 'b', received: 3)],
          [line('Belt', 99, productId: 'b')]);
      expect(out.single.receivedQty, 0);
    });

    test('drains the last line first, mirroring how it filled', () {
      final items = [
        item('Belt', 10, productId: 'b', received: 10),
        item('Belt', 10, productId: 'b', received: 4),
      ];
      final out =
          reverseReceiptFromItems(items, [line('Belt', 4, productId: 'b')]);
      expect(out.map((i) => i.receivedQty).toList(), [10, 0]);
    });
  });

  group('edge cases', () {
    test('zero-quantity receipt line is ignored', () {
      final out =
          applyReceiptToItems([item('Belt', 5, productId: 'b')],
              [line('Belt', 0, productId: 'b')]);
      expect(out.single.receivedQty, 0);
    });

    test('an already-full line is left alone', () {
      final out = applyReceiptToItems(
          [item('Belt', 5, productId: 'b', received: 5)],
          [line('Belt', 3, productId: 'b')]);
      expect(out.single.receivedQty, 5);
    });

    test('empty receipt leaves items untouched', () {
      final out = applyReceiptToItems([item('Belt', 5)], []);
      expect(out.single.receivedQty, 0);
    });
  });
}
