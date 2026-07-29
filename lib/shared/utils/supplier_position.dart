import '../models/purchase_model.dart';
import 'money_utils.dart';

/// A supplier's accrual-basis position.
typedef SupplierPosition = ({
  /// Owed for goods RECEIVED but not yet paid, net of unapplied credits.
  double payable,

  /// Cash paid ahead of receipt — an asset.
  double prepaid,

  /// Billed but not yet received: an open commitment, neither asset nor debt.
  double onOrder,
  double billed,
  double received,

  /// Cash applied to purchases.
  double paid,

  /// Payments recorded against the supplier but not applied to any purchase.
  double unappliedCredits,
});

/// Computes a supplier's position from their purchases and any payment credits
/// that have not been applied to a specific purchase.
///
/// [unappliedCredits] matters: a payment recorded against the supplier but not
/// attached to a purchase is still money that has left the business. Ignoring
/// it overstates what is owed — the supplier detail screen already netted it
/// off while the accrual figures did not, so the same supplier showed two
/// different debts (32,855 vs 22,855 for one real case).
///
/// Credits reduce the payable first; anything left over becomes a prepayment,
/// because cash paid beyond the value of goods received is an asset.
SupplierPosition computeSupplierPosition(
  Iterable<Purchase> purchases, {
  double unappliedCredits = 0,
}) {
  double payable = 0, prepaid = 0, onOrder = 0, billed = 0, received = 0, paid = 0;
  for (final p in purchases) {
    payable += p.accruedPayable;
    prepaid += p.supplierPrepayment;
    onOrder += p.notYetReceivedValue;
    billed += p.total;
    received += p.totalReceivedValue;
    paid += p.amountPaid;
  }

  final credits = unappliedCredits < 0 ? 0.0 : unappliedCredits;
  final appliedToPayable = credits < payable ? credits : payable;
  payable -= appliedToPayable;
  prepaid += credits - appliedToPayable; // surplus is a deposit

  return (
    payable: roundMoney(payable),
    prepaid: roundMoney(prepaid),
    onOrder: roundMoney(onOrder),
    billed: roundMoney(billed),
    received: roundMoney(received),
    paid: roundMoney(paid + credits), // credits are cash out too
    unappliedCredits: roundMoney(credits),
  );
}
