import 'package:connectivity_plus/connectivity_plus.dart';

/// Returns `true` when the device reports at least one active network
/// interface (Wi-Fi, mobile data, ethernet, etc.).
///
/// This is a *reachability* check — it does NOT guarantee internet access
/// (e.g. captive portal). Callers should still handle timeouts gracefully.
Future<bool> hasConnectivity() async {
  final results = await Connectivity().checkConnectivity();
  return results.any((r) => r != ConnectivityResult.none);
}
