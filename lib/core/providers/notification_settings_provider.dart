import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Keys (suffixes — prefixed with userId at runtime) ───────────────────────
const _kPush             = 'notif_push';
const _kEmail            = 'notif_email';
const _kLowStock         = 'notif_low_stock';
const _kPaymentReminders = 'notif_payment_reminders';
const _kWeeklyDigest     = 'notif_weekly_digest';
const _kMonthlyReport    = 'notif_monthly_report';

// ─── State ───────────────────────────────────────────────────────────────────
class NotificationSettingsState {
  final bool pushNotifications;
  final bool emailNotifications;
  final bool lowStockAlerts;
  final bool paymentReminders;
  final bool weeklyDigest;
  final bool monthlyReport;

  const NotificationSettingsState({
    this.pushNotifications  = true,
    this.emailNotifications = false,
    this.lowStockAlerts     = true,
    this.paymentReminders   = true,
    this.weeklyDigest       = true,
    this.monthlyReport      = false,
  });

  NotificationSettingsState copyWith({
    bool? pushNotifications,
    bool? emailNotifications,
    bool? lowStockAlerts,
    bool? paymentReminders,
    bool? weeklyDigest,
    bool? monthlyReport,
  }) {
    return NotificationSettingsState(
      pushNotifications:  pushNotifications  ?? this.pushNotifications,
      emailNotifications: emailNotifications ?? this.emailNotifications,
      lowStockAlerts:     lowStockAlerts     ?? this.lowStockAlerts,
      paymentReminders:   paymentReminders   ?? this.paymentReminders,
      weeklyDigest:       weeklyDigest       ?? this.weeklyDigest,
      monthlyReport:      monthlyReport      ?? this.monthlyReport,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────
class NotificationSettingsNotifier extends Notifier<NotificationSettingsState> {
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  bool get _isAuth => _uid != null;
  String _key(String base) => '${_uid!}_$base';

  @override
  NotificationSettingsState build() {
    _load();
    return const NotificationSettingsState();
  }

  Future<void> _load() async {
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    state = NotificationSettingsState(
      pushNotifications:  prefs.getBool(_key(_kPush))             ?? true,
      emailNotifications: prefs.getBool(_key(_kEmail))            ?? false,
      lowStockAlerts:     prefs.getBool(_key(_kLowStock))         ?? true,
      paymentReminders:   prefs.getBool(_key(_kPaymentReminders)) ?? true,
      weeklyDigest:       prefs.getBool(_key(_kWeeklyDigest))     ?? true,
      monthlyReport:      prefs.getBool(_key(_kMonthlyReport))    ?? false,
    );
  }

  Future<void> _persist() async {
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kPush),             state.pushNotifications);
    await prefs.setBool(_key(_kEmail),            state.emailNotifications);
    await prefs.setBool(_key(_kLowStock),         state.lowStockAlerts);
    await prefs.setBool(_key(_kPaymentReminders), state.paymentReminders);
    await prefs.setBool(_key(_kWeeklyDigest),     state.weeklyDigest);
    await prefs.setBool(_key(_kMonthlyReport),    state.monthlyReport);
  }

  Future<void> setPush(bool v) async {
    state = state.copyWith(pushNotifications: v);
    await _persist();
  }

  Future<void> setEmail(bool v) async {
    state = state.copyWith(emailNotifications: v);
    await _persist();
  }

  Future<void> setLowStock(bool v) async {
    state = state.copyWith(lowStockAlerts: v);
    await _persist();
  }

  Future<void> setPaymentReminders(bool v) async {
    state = state.copyWith(paymentReminders: v);
    await _persist();
  }

  Future<void> setWeeklyDigest(bool v) async {
    state = state.copyWith(weeklyDigest: v);
    await _persist();
  }

  Future<void> setMonthlyReport(bool v) async {
    state = state.copyWith(monthlyReport: v);
    await _persist();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────
final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettingsState>(
        () {
  return NotificationSettingsNotifier();
});
