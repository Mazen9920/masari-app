// Books-start cutover helpers.
//
// Bosta cashouts can predate the day a business actually started keeping its
// books in the app. Counting those pre-tracking deposits (with none of the
// pre-tracking spending that consumed them) hugely overstates "Cash & Bank".
// The cutover excludes cashouts before booksStartDate; their net effect is
// captured once in the opening cash balance.

/// 'YYYY-MM-DD' comparison key for the books-start date, or null for no cutover
/// (legacy: count everything).
String? booksStartKey(DateTime? booksStartDate) =>
    booksStartDate?.toIso8601String().substring(0, 10);

/// Whether a cashout dated [dateStr] (an ISO string like '2026-03-15T...') is
/// on or after the books-start cutoff [startKey]. With no cutoff, everything
/// counts. Undated cashouts are excluded once a cutoff is set (they can't be
/// placed in the tracked window).
bool cashoutOnOrAfterStart(String dateStr, String? startKey) {
  if (startKey == null) return true;
  if (dateStr.isEmpty) return false;
  return dateStr.compareTo(startKey) >= 0;
}

/// Whether a cashout dated [dateStr] is on or before the as-of day [asOfKey]
/// ('YYYY-MM-DD'). Compares date-only so a same-day cashout (whose stored value
/// carries a time component, e.g. '2026-06-29T12:00') is NOT wrongly excluded.
bool cashoutOnOrBeforeAsOf(String dateStr, String asOfKey) {
  if (dateStr.isEmpty) return true;
  final key = dateStr.length >= 10 ? dateStr.substring(0, 10) : dateStr;
  return key.compareTo(asOfKey) <= 0;
}

/// Sum of cashout amounts within the books window: on/after [startKey] (the
/// cutover) and on/before [asOfKey] (same-day inclusive). Each element is the
/// cashout (amount, ISO-date) pair. The **single source of truth** for the
/// cutover'd cashout total used by the Balance Sheet, Cash & Bank dashboard,
/// and Cash Flow statement, so they can't compute cashouts differently.
double windowedCashoutTotal(
  Iterable<({double amount, String date})> cashouts, {
  String? startKey,
  required String asOfKey,
}) {
  var sum = 0.0;
  for (final c in cashouts) {
    if (cashoutOnOrAfterStart(c.date, startKey) &&
        cashoutOnOrBeforeAsOf(c.date, asOfKey)) {
      sum += c.amount;
    }
  }
  return sum;
}
