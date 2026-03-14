import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Keys (suffixes — prefixed with userId at runtime) ───────────────────────
const _kAppLock    = 'security_app_lock';
const _kBiometrics = 'security_biometrics';

// ─── State ───────────────────────────────────────────────────────────────────
class SecuritySettingsState {
  final bool appLock;
  final bool biometrics;

  const SecuritySettingsState({
    this.appLock    = false,
    this.biometrics = false,
  });

  SecuritySettingsState copyWith({bool? appLock, bool? biometrics}) {
    return SecuritySettingsState(
      appLock:    appLock    ?? this.appLock,
      biometrics: biometrics ?? this.biometrics,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────
class SecuritySettingsNotifier extends Notifier<SecuritySettingsState> {
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  bool get _isAuth => _uid != null;
  String _key(String base) => '${_uid!}_$base';

  @override
  SecuritySettingsState build() {
    _load();
    return const SecuritySettingsState();
  }

  Future<void> _load() async {
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    state = SecuritySettingsState(
      appLock:    prefs.getBool(_key(_kAppLock))    ?? false,
      biometrics: prefs.getBool(_key(_kBiometrics)) ?? false,
    );
  }

  Future<void> setAppLock(bool value) async {
    state = state.copyWith(appLock: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kAppLock), value);
  }

  Future<void> setBiometrics(bool value) async {
    state = state.copyWith(biometrics: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kBiometrics), value);
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────
final securitySettingsProvider =
    NotifierProvider<SecuritySettingsNotifier, SecuritySettingsState>(() {
  return SecuritySettingsNotifier();
});
