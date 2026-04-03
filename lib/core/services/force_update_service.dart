import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'remote_config_service.dart';

class ForceUpdateService {
  /// Returns `true` when the installed app version is older than the
  /// minimum required version from Remote Config.
  static Future<bool> isUpdateRequired() async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version; // e.g. "1.2.0"

    final String minVersion;
    if (!kIsWeb && Platform.isIOS) {
      minVersion = RemoteConfigService.minVersionIos;
    } else {
      minVersion = RemoteConfigService.minVersionAndroid;
    }

    return compareVersions(current, minVersion) < 0;
  }

  /// Standard semver compare: returns negative if [a] < [b].
  /// Exposed for testing.
  @visibleForTesting
  static int compareVersions(String a, String b) {
    final pa = a.split('.').map(int.tryParse).toList();
    final pb = b.split('.').map(int.tryParse).toList();
    for (var i = 0; i < 3; i++) {
      final va = i < pa.length ? (pa[i] ?? 0) : 0;
      final vb = i < pb.length ? (pb[i] ?? 0) : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  /// Store link for the current platform.
  static String get storeUrl {
    if (!kIsWeb && Platform.isIOS) {
      return 'https://apps.apple.com/app/id$_kAppStoreId';
    }
    return 'https://play.google.com/store/apps/details?id=com.revvo.app';
  }
}

/// Fill after App Store submission.
const _kAppStoreId = '';
