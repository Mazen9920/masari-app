import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/core/services/remote_config_service.dart';

/// Guard against accidental changes to Remote Config defaults.
/// These values must match what is published in the Firebase Console.
void main() {
  group('RemoteConfigService.defaults', () {
    test('contains exactly 10 keys', () {
      expect(RemoteConfigService.defaults.length, 10);
    });

    test('version defaults match Console values', () {
      expect(RemoteConfigService.defaults['min_version_ios'], '1.0.0');
      expect(RemoteConfigService.defaults['min_version_android'], '1.0.0');
    });

    test('feature flag defaults match Console values', () {
      expect(RemoteConfigService.defaults['maintenance_mode'], false);
      expect(RemoteConfigService.defaults['shopify_enabled'], true);
      expect(RemoteConfigService.defaults['ai_reports_enabled'], false);
      expect(RemoteConfigService.defaults['show_paymob_ios'], true);
    });

    test('limit defaults match Console values', () {
      expect(RemoteConfigService.defaults['max_free_products'], 20);
      expect(RemoteConfigService.defaults['max_free_transactions'], 200);
    });

    test('pricing defaults match Console values', () {
      expect(RemoteConfigService.defaults['paymob_monthly_price'], '249 EGP');
      expect(RemoteConfigService.defaults['paymob_yearly_price'], '2390 EGP');
    });

    test('all keys use snake_case naming', () {
      for (final key in RemoteConfigService.defaults.keys) {
        expect(key, matches(RegExp(r'^[a-z][a-z0-9_]*$')),
            reason: '$key should be snake_case');
      }
    });
  });
}
