import '../models/purchase_model.dart';

/// One line of a goods receipt, reduced to what allocation needs.
typedef ReceiptLine = ({
  String? productId,
  String? variantId,
  String name,
  int qty,
});

/// Whether receipt line [r] refers to the same thing as purchase line [p].
///
/// Prefers a precise product/variant match and falls back to name for custom
/// or manually-typed items (which carry no product id).
bool receiptMatchesItem(ReceiptLine r, PurchaseItem p) {
  if (p.productId != null && r.productId != null) {
    return r.productId == p.productId &&
        (p.variantId == null || r.variantId == null || r.variantId == p.variantId);
  }
  return r.name.toLowerCase().trim() == p.name.toLowerCase().trim();
}

/// Adds a goods receipt to a purchase's lines and returns the updated lines.
///
/// A purchase can legitimately hold SEVERAL lines of the same product (e.g.
/// three "Lever Belt" lines of 16, 11 and 6). The received quantity is spread
/// across those lines in order, each taking only what it still has room for,
/// and no line is ever pushed beyond what was ordered.
///
/// The previous implementation matched by name, took the first matching
/// receipt line, and added its FULL quantity to EVERY matching purchase line —
/// so one receipt of 16 landed on all three lines (16/16, 16/11, 16/6) and the
/// purchase reported 108 received out of 93 ordered.
List<PurchaseItem> applyReceiptToItems(
  List<PurchaseItem> items,
  List<ReceiptLine> receiptLines,
) =>
    _allocate(items, receiptLines, reverse: false);

/// Removes a goods receipt from a purchase's lines (used when a receipt is
/// deleted or edited). Quantities come off the LAST matching lines first,
/// mirroring how [applyReceiptToItems] fills them, and never below zero.
List<PurchaseItem> reverseReceiptFromItems(
  List<PurchaseItem> items,
  List<ReceiptLine> receiptLines,
) =>
    _allocate(items, receiptLines, reverse: true);

List<PurchaseItem> _allocate(
  List<PurchaseItem> items,
  List<ReceiptLine> receiptLines, {
  required bool reverse,
}) {
  // Work on a mutable copy of the received quantities.
  final received = [for (final i in items) i.receivedQty];

  for (final line in receiptLines) {
    // Sum duplicates of the same product within one receipt instead of
    // using only the first (another way quantities used to go missing).
    var remaining = line.qty;
    if (remaining <= 0) continue;

    final targets = <int>[];
    for (var i = 0; i < items.length; i++) {
      if (receiptMatchesItem(line, items[i])) targets.add(i);
    }
    if (targets.isEmpty) continue;

    // Fill forwards when receiving, drain backwards when reversing.
    final order = reverse ? targets.reversed.toList() : targets;
    for (final idx in order) {
      if (remaining <= 0) break;
      final item = items[idx];
      // Capacity is what the line can still take (or still give back).
      final capacity = reverse ? received[idx] : (item.qty - received[idx]);
      if (capacity <= 0) continue;
      final take = remaining < capacity ? remaining : capacity;
      received[idx] = reverse ? received[idx] - take : received[idx] + take;
      remaining -= take;
    }
    // Anything left over is a genuine over-receipt; it is deliberately dropped
    // rather than pushing a line past its ordered quantity.
  }

  return [
    for (var i = 0; i < items.length; i++)
      items[i].copyWith(receivedQty: received[i].clamp(0, items[i].qty)),
  ];
}
