import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Keys (suffixes — prefixed with userId at runtime) ───────────────────────
const _kLayout = 'hub_layout_index';
const _kQuickActions = 'hub_show_quick_actions';
const _kInsightsBanner = 'hub_show_insights_banner';
const _kLowStock = 'hub_low_stock_alerts';
const _kPaymentDue = 'hub_payment_due_reminders';
const _kStatBadges = 'hub_show_stat_badges';
const _kDefaultTab = 'hub_default_tab';

// ─── State ───────────────────────────────────────────────────────────────────
class HubSettingsState {
  final int layoutIndex; // 0 = Grid, 1 = List
  final bool showQuickActions;
  final bool showInsightsBanner;
  final bool lowStockAlerts;
  final bool paymentDueReminders;
  final bool showStatBadges;
  final int defaultTabIndex; // 0 = Hub Overview, 1 = Inventory, 2 = Suppliers

  const HubSettingsState({
    this.layoutIndex = 1,
    this.showQuickActions = true,
    this.showInsightsBanner = true,
    this.lowStockAlerts = true,
    this.paymentDueReminders = true,
    this.showStatBadges = true,
    this.defaultTabIndex = 0,
  });

  HubSettingsState copyWith({
    int? layoutIndex,
    bool? showQuickActions,
    bool? showInsightsBanner,
    bool? lowStockAlerts,
    bool? paymentDueReminders,
    bool? showStatBadges,
    int? defaultTabIndex,
  }) {
    return HubSettingsState(
      layoutIndex: layoutIndex ?? this.layoutIndex,
      showQuickActions: showQuickActions ?? this.showQuickActions,
      showInsightsBanner: showInsightsBanner ?? this.showInsightsBanner,
      lowStockAlerts: lowStockAlerts ?? this.lowStockAlerts,
      paymentDueReminders: paymentDueReminders ?? this.paymentDueReminders,
      showStatBadges: showStatBadges ?? this.showStatBadges,
      defaultTabIndex: defaultTabIndex ?? this.defaultTabIndex,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────
class HubSettingsNotifier extends Notifier<HubSettingsState> {
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  bool get _isAuth => _uid != null;
  String _key(String base) => '${_uid!}_$base';

  @override
  HubSettingsState build() {
    // Load asynchronously and update state when ready
    _load();
    return const HubSettingsState();
  }

  Future<void> _load() async {
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    state = HubSettingsState(
      layoutIndex: prefs.getInt(_key(_kLayout)) ?? 1,
      showQuickActions: prefs.getBool(_key(_kQuickActions)) ?? true,
      showInsightsBanner: prefs.getBool(_key(_kInsightsBanner)) ?? true,
      lowStockAlerts: prefs.getBool(_key(_kLowStock)) ?? true,
      paymentDueReminders: prefs.getBool(_key(_kPaymentDue)) ?? true,
      showStatBadges: prefs.getBool(_key(_kStatBadges)) ?? true,
      defaultTabIndex: prefs.getInt(_key(_kDefaultTab)) ?? 0,
    );
  }

  Future<void> setLayout(int index) async {
    state = state.copyWith(layoutIndex: index);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(_kLayout), index);
  }

  Future<void> setShowQuickActions(bool value) async {
    state = state.copyWith(showQuickActions: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kQuickActions), value);
  }

  Future<void> setShowInsightsBanner(bool value) async {
    state = state.copyWith(showInsightsBanner: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kInsightsBanner), value);
  }

  Future<void> setLowStockAlerts(bool value) async {
    state = state.copyWith(lowStockAlerts: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kLowStock), value);
  }

  Future<void> setPaymentDueReminders(bool value) async {
    state = state.copyWith(paymentDueReminders: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kPaymentDue), value);
  }

  Future<void> setShowStatBadges(bool value) async {
    state = state.copyWith(showStatBadges: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kStatBadges), value);
  }

  Future<void> setDefaultTab(int index) async {
    state = state.copyWith(defaultTabIndex: index);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(_kDefaultTab), index);
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────
final hubSettingsProvider =
    NotifierProvider<HubSettingsNotifier, HubSettingsState>(() {
  return HubSettingsNotifier();
});
