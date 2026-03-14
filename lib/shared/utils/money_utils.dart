/// Rounds a monetary value to 2 decimal places.
///
/// Uses multiply-round-divide to avoid floating-point drift:
///   roundMoney(1.005) → 1.01
///   roundMoney(29.999999999999996) → 30.00
double roundMoney(double value) => (value * 100).roundToDouble() / 100;
