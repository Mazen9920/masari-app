import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/core/services/force_update_service.dart';

void main() {
  group('ForceUpdateService.compareVersions', () {
    test('equal versions return 0', () {
      expect(ForceUpdateService.compareVersions('1.0.0', '1.0.0'), 0);
      expect(ForceUpdateService.compareVersions('2.3.4', '2.3.4'), 0);
    });

    test('current < min returns negative', () {
      expect(ForceUpdateService.compareVersions('1.0.0', '1.0.1'), isNegative);
      expect(ForceUpdateService.compareVersions('1.0.0', '1.1.0'), isNegative);
      expect(ForceUpdateService.compareVersions('1.0.0', '2.0.0'), isNegative);
      expect(ForceUpdateService.compareVersions('1.9.9', '2.0.0'), isNegative);
    });

    test('current > min returns positive', () {
      expect(ForceUpdateService.compareVersions('1.0.1', '1.0.0'), isPositive);
      expect(ForceUpdateService.compareVersions('1.1.0', '1.0.0'), isPositive);
      expect(ForceUpdateService.compareVersions('2.0.0', '1.9.9'), isPositive);
    });

    test('major takes precedence over minor and patch', () {
      expect(ForceUpdateService.compareVersions('2.0.0', '1.99.99'), isPositive);
      expect(ForceUpdateService.compareVersions('1.99.99', '2.0.0'), isNegative);
    });

    test('minor takes precedence over patch', () {
      expect(ForceUpdateService.compareVersions('1.2.0', '1.1.99'), isPositive);
      expect(ForceUpdateService.compareVersions('1.1.99', '1.2.0'), isNegative);
    });

    test('handles short version strings', () {
      expect(ForceUpdateService.compareVersions('1.0', '1.0.0'), 0);
      expect(ForceUpdateService.compareVersions('1', '1.0.0'), 0);
      expect(ForceUpdateService.compareVersions('2', '1.9.9'), isPositive);
    });

    test('handles non-numeric segments gracefully', () {
      // Non-numeric segments parsed as 0
      expect(ForceUpdateService.compareVersions('1.0.0', '1.0.abc'), 0);
    });

    test('handles empty strings', () {
      // Empty = all zeros
      expect(ForceUpdateService.compareVersions('', ''), 0);
      expect(ForceUpdateService.compareVersions('1.0.0', ''), isPositive);
      expect(ForceUpdateService.compareVersions('', '1.0.0'), isNegative);
    });

    test('ignores segments beyond major.minor.patch', () {
      // Implementation only compares first 3 segments
      expect(ForceUpdateService.compareVersions('1.0.0.0', '1.0.0'), 0);
      expect(ForceUpdateService.compareVersions('1.0.0.1', '1.0.0'), 0);
      expect(ForceUpdateService.compareVersions('1.0.0', '1.0.0.1'), 0);
    });

    test('leading zeros in segments', () {
      expect(ForceUpdateService.compareVersions('01.02.03', '1.2.3'), 0);
    });
  });
}
