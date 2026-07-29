import 'package:cloud_firestore/cloud_firestore.dart';
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
const _kSales            = 'notif_sales';
const _kShopifyOrders    = 'notif_shopify_orders';
const _kBilling          = 'notif_billing';
const _kDeliveries       = 'notif_deliveries';
const _kInsights         = 'notif_insights';
const _kDataIntegrity    = 'notif_data_integrity';

// ─── State ───────────────────────────────────────────────────────────────────
class NotificationSettingsState {
  final bool pushNotifications;
  final bool emailNotifications;
  final bool lowStockAlerts;
  final bool paymentReminders;
  final bool weeklyDigest;
  final bool monthlyReport;
  final bool salesNotifications;
  final bool shopifyOrderNotifications;
  final bool billingNotifications;
  final bool deliveryAlerts;
  final bool insightAlerts;
  final bool dataIntegrityAlerts;

  const NotificationSettingsState({
    this.pushNotifications         = true,
    this.emailNotifications        = false,
    this.lowStockAlerts            = true,
    this.paymentReminders          = true,
    this.weeklyDigest              = true,
    this.monthlyReport             = false,
    this.salesNotifications        = true,
    this.shopifyOrderNotifications = true,
    this.billingNotifications      = true,
    this.deliveryAlerts            = true,
    this.insightAlerts             = true,
    this.dataIntegrityAlerts       = true,
  });

  NotificationSettingsState copyWith({
    bool? pushNotifications,
    bool? emailNotifications,
    bool? lowStockAlerts,
    bool? paymentReminders,
    bool? weeklyDigest,
    bool? monthlyReport,
    bool? salesNotifications,
    bool? shopifyOrderNotifications,
    bool? billingNotifications,
    bool? deliveryAlerts,
    bool? insightAlerts,
    bool? dataIntegrityAlerts,
  }) {
    return NotificationSettingsState(
      pushNotifications:         pushNotifications         ?? this.pushNotifications,
      emailNotifications:        emailNotifications        ?? this.emailNotifications,
      lowStockAlerts:            lowStockAlerts            ?? this.lowStockAlerts,
      paymentReminders:          paymentReminders          ?? this.paymentReminders,
      weeklyDigest:              weeklyDigest              ?? this.weeklyDigest,
      monthlyReport:             monthlyReport             ?? this.monthlyReport,
      salesNotifications:        salesNotifications        ?? this.salesNotifications,
      shopifyOrderNotifications: shopifyOrderNotifications ?? this.shopifyOrderNotifications,
      billingNotifications:      billingNotifications      ?? this.billingNotifications,
      deliveryAlerts:            deliveryAlerts            ?? this.deliveryAlerts,
      insightAlerts:             insightAlerts             ?? this.insightAlerts,
      dataIntegrityAlerts:       dataIntegrityAlerts       ?? this.dataIntegrityAlerts,
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
      pushNotifications:         prefs.getBool(_key(_kPush))             ?? true,
      emailNotifications:        prefs.getBool(_key(_kEmail))            ?? false,
      lowStockAlerts:            prefs.getBool(_key(_kLowStock))         ?? true,
      paymentReminders:          prefs.getBool(_key(_kPaymentReminders)) ?? true,
      weeklyDigest:              prefs.getBool(_key(_kWeeklyDigest))     ?? true,
      monthlyReport:             prefs.getBool(_key(_kMonthlyReport))    ?? false,
      salesNotifications:        prefs.getBool(_key(_kSales))            ?? true,
      shopifyOrderNotifications: prefs.getBool(_key(_kShopifyOrders))    ?? true,
      billingNotifications:      prefs.getBool(_key(_kBilling))          ?? true,
      deliveryAlerts:            prefs.getBool(_key(_kDeliveries))       ?? true,
      insightAlerts:             prefs.getBool(_key(_kInsights))         ?? true,
      dataIntegrityAlerts:       prefs.getBool(_key(_kDataIntegrity))    ?? true,
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
    await prefs.setBool(_key(_kSales),            state.salesNotifications);
    await prefs.setBool(_key(_kShopifyOrders),    state.shopifyOrderNotifications);
    await prefs.setBool(_key(_kBilling),          state.billingNotifications);
    await prefs.setBool(_key(_kDeliveries),       state.deliveryAlerts);
    await prefs.setBool(_key(_kInsights),         state.insightAlerts);
    await prefs.setBool(_key(_kDataIntegrity),    state.dataIntegrityAlerts);

    // Sync to Firestore so backend can respect preferences
    _syncToFirestore();
  }

  /// Writes notification preferences to the user doc so Cloud Functions
  /// can check them before sending push notifications.
  Future<void> _syncToFirestore() async {
    if (!_isAuth) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid!).set({
        'notification_prefs': {
          'push':             state.pushNotifications,
          'sales':            state.salesNotifications,
          'shopify_orders':   state.shopifyOrderNotifications,
          'billing':          state.billingNotifications,
          'low_stock':        state.lowStockAlerts,
          'payment_reminders': state.paymentReminders,
          'recurring':        true, // always on for recurring transactions
          'deliveries':       state.deliveryAlerts,
          'insights':         state.insightAlerts,
          'data_integrity':   state.dataIntegrityAlerts,
          // Server-sent digest — must live in Firestore or the weekly job
          // can't respect the toggle (it was local-only before).
          'weekly_digest':    state.weeklyDigest,
        },
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort — local prefs still work via SharedPreferences
    }
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

  Future<void> setSales(bool v) async {
    state = state.copyWith(salesNotifications: v);
    await _persist();
  }

  Future<void> setShopifyOrders(bool v) async {
    state = state.copyWith(shopifyOrderNotifications: v);
    await _persist();
  }

  Future<void> setBilling(bool v) async {
    state = state.copyWith(billingNotifications: v);
    await _persist();
  }

  Future<void> setDeliveries(bool v) async {
    state = state.copyWith(deliveryAlerts: v);
    await _persist();
  }

  Future<void> setInsights(bool v) async {
    state = state.copyWith(insightAlerts: v);
    await _persist();
  }

  Future<void> setDataIntegrity(bool v) async {
    state = state.copyWith(dataIntegrityAlerts: v);
    await _persist();
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────
final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettingsState>(
        () {
  return NotificationSettingsNotifier();
});
