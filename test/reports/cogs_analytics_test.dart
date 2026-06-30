import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/features/reports/cogs_analytics.dart';
import 'package:revvo_app/shared/models/sale_model.dart';
import 'package:revvo_app/shared/models/transaction_model.dart';

Sale sale({
  required String id,
  required double unitPrice,
  required double costPrice,
  double qty = 1,
  OrderStatus status = OrderStatus.confirmed,
}) {
  return Sale(
    id: id,
    userId: 'u',
    date: DateTime(2026, 6, 1),
    orderStatus: status,
    items: [
      SaleItem(
        productName: 'Widget',
        quantity: qty,
        unitPrice: unitPrice,
        costPrice: costPrice,
      ),
    ],
  );
}

Transaction cogsTxn(String saleId, double cogs, {DateTime? on}) => Transaction(
      id: 'sale_cogs_$saleId',
      userId: 'u',
      title: 'COGS',
      amount: -cogs,
      dateTime: on ?? DateTime(2026, 6, 1),
      categoryId: 'cat_cogs',
      saleId: saleId,
    );

Transaction revenueTxn(String saleId, double rev, {DateTime? on}) => Transaction(
      id: 'sale_rev_$saleId',
      userId: 'u',
      title: 'Revenue',
      amount: rev,
      dateTime: on ?? DateTime(2026, 6, 1),
      categoryId: 'cat_sales_revenue',
      saleId: saleId,
    );

void main() {
  group('saleIsMissingCogs', () {
    test('revenue but no cost → missing', () {
      expect(saleIsMissingCogs(sale(id: 's1', unitPrice: 100, costPrice: 0)),
          isTrue);
    });
    test('cost recorded → not missing', () {
      expect(saleIsMissingCogs(sale(id: 's2', unitPrice: 100, costPrice: 60)),
          isFalse);
    });
    test('cancelled order → ignored', () {
      expect(
          saleIsMissingCogs(sale(
              id: 's3',
              unitPrice: 100,
              costPrice: 0,
              status: OrderStatus.cancelled)),
          isFalse);
    });
    test('no revenue → not flagged', () {
      expect(saleIsMissingCogs(sale(id: 's4', unitPrice: 0, costPrice: 0)),
          isFalse);
    });
  });

  group('reconcileCogs', () {
    test('sales COGS matches recorded ledger COGS', () {
      final sales = [
        sale(id: 's1', unitPrice: 100, costPrice: 60),
        sale(id: 's2', unitPrice: 200, costPrice: 120),
      ];
      final txns = [cogsTxn('s1', 60), cogsTxn('s2', 120)];
      final r = reconcileCogs(sales, txns);
      expect(r.salesCogs, 180);
      expect(r.recordedCogs, 180);
      expect(r.matches, isTrue);
      expect(r.diff, 0);
    });

    test('missing ledger entry surfaces as a positive diff', () {
      final sales = [
        sale(id: 's1', unitPrice: 100, costPrice: 60),
        sale(id: 's2', unitPrice: 200, costPrice: 120),
      ];
      final txns = [cogsTxn('s1', 60)]; // s2's COGS never posted
      final r = reconcileCogs(sales, txns);
      expect(r.salesCogs, 180);
      expect(r.recordedCogs, 60);
      expect(r.diff, 120);
      expect(r.matches, isFalse);
    });

    test('cancelled-order COGS excluded from both sides (no phantom gap)', () {
      final kept = sale(id: 's1', unitPrice: 100, costPrice: 60);
      final cancelled = sale(
          id: 's2',
          unitPrice: 100,
          costPrice: 60,
          status: OrderStatus.cancelled);
      final txns = [
        cogsTxn('s1', 60), // kept order's cost (-60)
        cogsTxn('s2', 60), // cancelled order's cost still in the ledger (-60)
        Transaction(
          id: 'rev2',
          userId: 'u',
          title: 'COGS reversal',
          amount: 60, // +60 reversal for the cancelled order
          dateTime: DateTime(2026, 6, 2),
          categoryId: 'cat_cogs',
          saleId: 's2',
        ),
      ];
      final r = reconcileCogs([kept, cancelled], txns);
      expect(r.salesCogs, 60); // only the kept order
      expect(r.recordedCogs, 60); // cancelled order's COGS excluded entirely
      expect(r.matches, isTrue); // → no phantom gap from cancellations
    });

    test('cancelled sales excluded from sales COGS', () {
      final sales = [
        sale(id: 's1', unitPrice: 100, costPrice: 60),
        sale(
            id: 's2',
            unitPrice: 200,
            costPrice: 120,
            status: OrderStatus.cancelled),
      ];
      final r = reconcileCogs(sales, [cogsTxn('s1', 60)]);
      expect(r.salesCogs, 60);
      expect(r.matches, isTrue);
    });
  });

  group('findOrdersMissingCogs (ledger-authoritative)', () {
    test('sale with no item cost but a ledger COGS entry is NOT missing', () {
      // Historical/imported sale: item costPrice 0 (sale.totalCogs == 0) but a
      // cat_cogs ledger entry exists. saleIsMissingCogs would false-positive;
      // findOrdersMissingCogs must not flag it.
      final s = sale(id: 's1', unitPrice: 100, costPrice: 0);
      expect(saleIsMissingCogs(s), isTrue); // sale-record view (unreliable)
      expect(findOrdersMissingCogs([s], [cogsTxn('s1', 60)]), isEmpty);
    });

    test('sale with revenue and no ledger COGS is flagged', () {
      final s = sale(id: 's2', unitPrice: 100, costPrice: 0);
      expect(findOrdersMissingCogs([s], const []), [s]);
    });

    test('zero-amount ledger entry still counts as missing', () {
      final s = sale(id: 's3', unitPrice: 100, costPrice: 0);
      expect(findOrdersMissingCogs([s], [cogsTxn('s3', 0)]), [s]);
    });

    test('cancelled orders ignored', () {
      final s = sale(
          id: 's4',
          unitPrice: 100,
          costPrice: 0,
          status: OrderStatus.cancelled);
      expect(findOrdersMissingCogs([s], const []), isEmpty);
    });
  });

  group('period ledger figures', () {
    final txns = [
      cogsTxn('a', 60, on: DateTime(2026, 5, 10)),
      revenueTxn('a', 100, on: DateTime(2026, 5, 10)),
      cogsTxn('b', 120, on: DateTime(2026, 6, 10)),
      revenueTxn('b', 200, on: DateTime(2026, 6, 10)),
    ];

    test('periodLedgerCogs slices by month (May reads from the ledger)', () {
      expect(
          periodLedgerCogs(txns, DateTime(2026, 5, 1), DateTime(2026, 5, 31)),
          60);
      expect(
          periodLedgerCogs(txns, DateTime(2026, 6, 1), DateTime(2026, 6, 30)),
          120);
    });

    test('periodLedgerRevenue slices by month', () {
      expect(
          periodLedgerRevenue(
              txns, DateTime(2026, 5, 1), DateTime(2026, 5, 31)),
          100);
    });
  });
}
