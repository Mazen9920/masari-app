/// Environment configuration for the Masari app.
///
/// Controls API endpoints, feature flags, and logging based on
/// the current deployment target.
enum Environment {
  development,
  staging,
  production,
}

class AppConfig {
  static Environment _current = Environment.development;

  /// Set the environment (call early in main()).
  static void setEnvironment(Environment env) {
    _current = env;
  }

  static Environment get current => _current;

  // ── API ──────────────────────────────────────────
  static String get apiBaseUrl {
    switch (_current) {
      case Environment.development:
        return 'http://localhost:3000/api/v1';
      case Environment.staging:
        return 'https://staging-api.masari.app/v1';
      case Environment.production:
        return 'https://api.masari.app/v1';
    }
  }

  // ── Feature flags ────────────────────────────────
  static bool get enableLogging =>
      _current != Environment.production;

  static bool get showDebugBanner =>
      _current == Environment.development;

  static bool get enableCrashReporting =>
      _current != Environment.development;

  static bool get useMockData =>
      _current == Environment.development;

  // ── Timeouts ─────────────────────────────────────
  static Duration get apiTimeout {
    switch (_current) {
      case Environment.development:
        return const Duration(seconds: 60);
      case Environment.staging:
      case Environment.production:
        return const Duration(seconds: 30);
    }
  }

  // ── App info ─────────────────────────────────────
  static const String appName = 'Masari';
  static const String appVersion = '1.0.0';
  static const String buildNumber = '1';
}
