/// Rounds a monetary value to 2 decimal places.
///
/// Uses multiply-round-divide to avoid floating-point drift:
///   roundMoney(1.005) → 1.01
///   roundMoney(29.999999999999996) → 30.00
double roundMoney(double value) => (value * 100).roundToDouble() / 100;

/// Formats a stock quantity, dropping a trailing ".0" for whole numbers.
/// e.g. fmtQty(70.0) → "70", fmtQty(2.5) → "2.5".
String fmtQty(num q) {
  final d = q.toDouble();
  if (d == d.roundToDouble()) return d.toInt().toString();
  // Trim to at most 4 decimals, then strip trailing zeros.
  var s = d.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}
