import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Centralised access to Firebase Remote Config values.
///
/// Call [init] once at app startup (splash screen). All getters read
/// from the activated snapshot so they are synchronous and fast.
class RemoteConfigService {
  RemoteConfigService._();

  static final _rc = FirebaseRemoteConfig.instance;
  static bool _initialised = false;

  // ── Defaults ──────────────────────────────────────
  @visibleForTesting
  static const defaults = <String, Object>{
    // Force-update min versions
    'min_version_ios': '1.0.0',
    'min_version_android': '1.0.0',

    // Feature flags
    'maintenance_mode': false,
    'shopify_enabled': true,
    'ai_reports_enabled': false,
    'show_paymob_ios': true,
    'max_free_products': 20,
    'max_free_transactions': 200,
    'paymob_monthly_price': '249 EGP',
    'paymob_yearly_price': '2390 EGP',
  };

  // ── Init ──────────────────────────────────────────
  /// Fetch & activate remote values. Safe to call more than once
  /// (subsequent calls are no-ops).
  static Future<void> init() async {
    if (_initialised) return;
    await _rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval:
          kReleaseMode ? const Duration(hours: 1) : const Duration(minutes: 5),
    ));
    await _rc.setDefaults(defaults);
    try {
      await _rc.fetchAndActivate();
    } catch (_) {
      // Offline or fetch failed — use cached / default values.
    }
    _initialised = true;
  }

  // ── Version strings ───────────────────────────────
  static String get minVersionIos => _rc.getString('min_version_ios');
  static String get minVersionAndroid => _rc.getString('min_version_android');

  // ── Feature flags ─────────────────────────────────
  static bool get maintenanceMode => _rc.getBool('maintenance_mode');
  static bool get shopifyEnabled => _rc.getBool('shopify_enabled');
  static bool get aiReportsEnabled => _rc.getBool('ai_reports_enabled');
  static bool get showPaymobIos => _rc.getBool('show_paymob_ios');

  // ── Limits ────────────────────────────────────────
  static int get maxFreeProducts => _rc.getInt('max_free_products');
  static int get maxFreeTransactions => _rc.getInt('max_free_transactions');

  // ── Pricing ───────────────────────────────────────
  static String get paymobMonthlyPrice => _rc.getString('paymob_monthly_price');
  static String get paymobYearlyPrice => _rc.getString('paymob_yearly_price');
}
