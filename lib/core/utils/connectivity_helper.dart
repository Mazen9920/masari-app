import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Returns `true` when the device can actually reach the internet.
///
/// `connectivity_plus` only reports whether a network *interface* exists, and
/// on some platforms (notably macOS desktop and certain emulators) it can
/// report [ConnectivityResult.none] even when the device is online. To avoid
/// false "offline" states that block the whole app, we treat a reported
/// interface as online, and — when none is reported — fall back to a real
/// DNS reachability probe before declaring the device offline.
Future<bool> hasConnectivity() async {
  try {
    final results = await Connectivity().checkConnectivity();
    if (results.any((r) => r != ConnectivityResult.none)) {
      return true;
    }
  } catch (_) {
    // connectivity_plus threw (plugin issue on some platforms) — fall through
    // to the reachability probe rather than assuming offline.
  }
  return _probeReachable();
}

/// Lightweight DNS lookup to confirm real internet access. Cross-platform and
/// independent of the connectivity_plus interface report.
Future<bool> _probeReachable() async {
  for (final host in const ['cloudflare.com', 'google.com']) {
    try {
      final res = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      if (res.isNotEmpty && res.first.rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {
      // try next host
    }
  }
  return false;
}
