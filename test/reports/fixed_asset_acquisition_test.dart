import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/shared/models/fixed_asset_model.dart';
import 'package:revvo_app/shared/utils/fixed_asset_acquisition.dart';

void main() {
  final date = DateTime(2026, 4, 22);

  group('buildAssetAcquisitionTxn', () {
    test('is a cash outflow, excluded from P&L, in cat_fixed_assets', () {
      final txn = buildAssetAcquisitionTxn(
        txnId: 'txn-1',
        userId: 'user-1',
        assetName: 'Office furniture',
        purchasePrice: 7865,
        purchaseDate: date,
      );

      expect(txn.id, 'txn-1');
      expect(txn.userId, 'user-1');
      // Negative => cash leaves the ledger.
      expect(txn.amount, -7865);
      expect(txn.categoryId, 'cat_fixed_assets');
      // It's a cash→asset swap, not an expense: must not reduce profit.
      expect(txn.excludeFromPL, isTrue);
      expect(txn.dateTime, date);
      expect(txn.title, contains('Office furniture'));
    });

    test('amount exactly offsets the asset price (clean swap)', () {
      const price = 20000.0;
      final txn = buildAssetAcquisitionTxn(
        txnId: 't',
        userId: 'u',
        assetName: 'Air conditioners',
        purchasePrice: price,
        purchaseDate: date,
      );
      // asset NBV at purchase (+price) + cash txn (-price) == 0 net to equity.
      expect(price + txn.amount, 0);
    });
  });

  group('buildAssetAcquisitionEvent', () {
    test('links the asset to the cash transaction for cleanup on delete', () {
      final event = buildAssetAcquisitionEvent(
        eventId: 'evt-1',
        txnId: 'txn-1',
        purchasePrice: 7865,
        purchaseDate: date,
      );

      expect(event.type, AssetEventType.acquisition);
      expect(event.transactionId, 'txn-1');
      expect(event.amount, 7865);
      expect(event.date, date);
    });
  });

  group('AssetEventType.acquisition', () {
    test('has a label/icon and round-trips through JSON', () {
      expect(AssetEventType.acquisition.label, 'Acquisition');
      expect(AssetEventType.acquisition.icon, isNotEmpty);

      final json = AssetEvent(
        id: 'e',
        type: AssetEventType.acquisition,
        amount: 100,
        date: date,
        transactionId: 'tx',
      ).toJson();
      final back = AssetEvent.fromJson(json);
      expect(back.type, AssetEventType.acquisition);
      expect(back.transactionId, 'tx');
    });
  });
}
