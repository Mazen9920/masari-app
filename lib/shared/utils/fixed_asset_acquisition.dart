import '../models/fixed_asset_model.dart';
import '../models/transaction_model.dart';

/// Helpers that keep a fixed-asset *purchase* in sync with the cash ledger.
///
/// Buying an asset is a cash→asset swap, not an expense: cash goes down, the
/// asset (net book value) goes up by the same amount, and the P&L is untouched
/// (depreciation hits the P&L later, over the asset's life). Previously adding
/// an asset only created the asset record and never deducted cash, so the
/// balance sheet overstated assets and the gap fell into the equity plug. These
/// helpers build the matching, P&L-excluded cash-outflow transaction and the
/// acquisition event that links them.

/// The cash-outflow transaction for a fixed-asset cash purchase.
/// Negative amount (cash out), `cat_fixed_assets`, excluded from the P&L.
Transaction buildAssetAcquisitionTxn({
  required String txnId,
  required String userId,
  required String assetName,
  required double purchasePrice,
  required DateTime purchaseDate,
}) {
  return Transaction(
    id: txnId,
    userId: userId,
    title: 'Asset Purchase – $assetName',
    amount: -purchasePrice,
    dateTime: purchaseDate,
    categoryId: 'cat_fixed_assets',
    note: 'Cash outflow for fixed-asset purchase',
    excludeFromPL: true,
  );
}

/// The acquisition event recorded on the asset, linking it to [txnId] so that
/// deleting the asset also removes the cash-outflow transaction.
AssetEvent buildAssetAcquisitionEvent({
  required String eventId,
  required String txnId,
  required double purchasePrice,
  required DateTime purchaseDate,
}) {
  return AssetEvent(
    id: eventId,
    type: AssetEventType.acquisition,
    amount: purchasePrice,
    date: purchaseDate,
    note: 'Cash purchase',
    transactionId: txnId,
  );
}
