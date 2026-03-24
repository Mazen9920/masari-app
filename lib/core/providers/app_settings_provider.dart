import 'dart:ui' show Locale;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';

// ─── Keys (suffixes — prefixed with userId at runtime) ───────────────────────
const _kCurrency   = 'settings_currency';
const _kLanguage   = 'settings_language';
const _kAutoBackup = 'settings_auto_backup';
const _kTier       = 'settings_tier';
const _kAutoTxnOnSupplierPayment = 'settings_auto_txn_supplier_payment';
const _kOpeningCashBalance = 'settings_opening_cash_balance';
const _kBusinessName  = 'settings_business_name';
const _kIndustry      = 'settings_industry';
const _kBusinessStage = 'settings_business_stage';
const _kMainGoal      = 'settings_main_goal';
const _kValuationMethod = 'settings_valuation_method';
const _kBreakdownEnabled = 'settings_breakdown_enabled';
const _kAutoUpdateStock = 'settings_auto_update_stock';
const _kDefaultUnit = 'settings_default_unit';
const _kLowStockAlerts = 'settings_low_stock_alerts';
const _kAlertThreshold = 'settings_alert_threshold';
const _kHideOutOfStock = 'settings_hide_out_of_stock';
const _kHideShopifyDrafts = 'settings_hide_shopify_drafts';

// ─── Subscription Tier ───────────────────────────────────────────────────────
enum SubscriptionTier {
  launch,
  growth,
  pro;

  /// Whether this tier is at least as high as [required].
  bool hasAccess(SubscriptionTier required) => index >= required.index;

  /// Whether this tier includes Shopify integration access.
  bool get hasShopifyAccess => this == SubscriptionTier.growth || this == SubscriptionTier.pro;

  /// Whether this tier is Growth or above.
  bool get isGrowthOrAbove => index >= SubscriptionTier.growth.index;

  /// Product limit for inventory. null = unlimited.
  int? get productLimit => this == SubscriptionTier.launch ? 20 : null;

  String get label => switch (this) {
    SubscriptionTier.launch => 'Launch',
    SubscriptionTier.growth => 'Growth',
    SubscriptionTier.pro    => 'Pro',
  };

  String get shortLabel => switch (this) {
    SubscriptionTier.launch => 'Launch',
    SubscriptionTier.growth => 'Growth',
    SubscriptionTier.pro    => 'Pro',
  };

  String localizedLabel(AppLocalizations l10n) => switch (this) {
    SubscriptionTier.launch => l10n.tierLaunch,
    SubscriptionTier.growth => l10n.tierGrowth,
    SubscriptionTier.pro    => l10n.tierPro,
  };
}

// ─── Growth-only feature identifiers ─────────────────────────────────────────
enum GrowthFeature {
  balanceSheet('Balance Sheet', 'Full balance sheet with assets, liabilities & equity tracking'),
  fullProfitLoss('Income Statement', 'Revenue, COGS, gross profit & operating expenses breakdown'),
  exportReports('Export Reports', 'Export & share your financial reports as PDF'),
  budgetLimits('Budget Limits', 'Set spending limits per category and track them'),
  purchasesSummary('Purchases Dashboard', 'Overview of all purchases with analytics'),
  paymentsSummary('Payments Dashboard', 'Overview of all supplier payments with analytics'),
  rawMaterials('Raw Materials', 'Track raw materials with scrap percentage & material types'),
  inventorySettings('Inventory Settings', 'Advanced inventory configuration & alerts'),
  stockMovements('Stock Movement History', 'Full history of all stock changes & movements'),
  recurringTransactions('Recurring Transactions', 'Schedule recurring income & expense entries'),
  aiChat('AI Insights', 'Get AI-powered financial analysis & advice'),
  hubSettings('Hub Customization', 'Customize your management hub layout & quick actions'),
  goodsReceiving('Goods Receiving', 'Track received items vs ordered & auto-update inventory'),
  salesSystem('Sales & COGS', 'Record sales, track cost of goods sold & gross profit'),
  supplierPaymentToggle('Payment Settings', 'Control whether supplier payments create transactions'),
  shopifyIntegration('Shopify Integration', 'Connect your Shopify store for two-way order and inventory sync'),
  manufacturingMode('Manufacturing Mode', 'Flag products as manufactured to decouple goods receipt from cost layers'),
  supplierManagement('Supplier Management', 'Track suppliers, record purchases & payments'),
  fullCashFlow('Full Cash Flow Analysis', 'GAAP operating, investing & financing breakdown with drill-down');

  const GrowthFeature(this.displayName, this.description);
  final String displayName;
  final String description;

  String localizedDisplayName(AppLocalizations l10n) => switch (this) {
    GrowthFeature.balanceSheet          => l10n.featureBalanceSheet,
    GrowthFeature.fullProfitLoss        => l10n.featureIncomeStatement,
    GrowthFeature.exportReports         => l10n.featureExportReports,
    GrowthFeature.budgetLimits          => l10n.featureBudgetLimits,
    GrowthFeature.purchasesSummary      => l10n.featurePurchasesDashboard,
    GrowthFeature.paymentsSummary       => l10n.featurePaymentsDashboard,
    GrowthFeature.rawMaterials          => l10n.featureRawMaterials,
    GrowthFeature.inventorySettings     => l10n.featureInventorySettings,
    GrowthFeature.stockMovements        => l10n.featureStockMovements,
    GrowthFeature.recurringTransactions => l10n.featureRecurringTransactions,
    GrowthFeature.aiChat                => l10n.featureAiInsights,
    GrowthFeature.hubSettings           => l10n.featureHubCustomization,
    GrowthFeature.goodsReceiving        => l10n.featureGoodsReceiving,
    GrowthFeature.salesSystem           => l10n.featureSalesCogs,
    GrowthFeature.supplierPaymentToggle => l10n.featurePaymentSettings,
    GrowthFeature.shopifyIntegration    => l10n.featureShopifyIntegration,
    GrowthFeature.manufacturingMode     => l10n.featureManufacturingMode,
    GrowthFeature.supplierManagement    => l10n.featureSupplierManagement,
    GrowthFeature.fullCashFlow          => l10n.featureFullCashFlow,
  };

  String localizedDescription(AppLocalizations l10n) => switch (this) {
    GrowthFeature.balanceSheet          => l10n.featureBalanceSheetDesc,
    GrowthFeature.fullProfitLoss        => l10n.featureIncomeStatementDesc,
    GrowthFeature.exportReports         => l10n.featureExportReportsDesc,
    GrowthFeature.budgetLimits          => l10n.featureBudgetLimitsDesc,
    GrowthFeature.purchasesSummary      => l10n.featurePurchasesDashboardDesc,
    GrowthFeature.paymentsSummary       => l10n.featurePaymentsDashboardDesc,
    GrowthFeature.rawMaterials          => l10n.featureRawMaterialsDesc,
    GrowthFeature.inventorySettings     => l10n.featureInventorySettingsDesc,
    GrowthFeature.stockMovements        => l10n.featureStockMovementsDesc,
    GrowthFeature.recurringTransactions => l10n.featureRecurringTransactionsDesc,
    GrowthFeature.aiChat                => l10n.featureAiInsightsDesc,
    GrowthFeature.hubSettings           => l10n.featureHubCustomizationDesc,
    GrowthFeature.goodsReceiving        => l10n.featureGoodsReceivingDesc,
    GrowthFeature.salesSystem           => l10n.featureSalesCogsDesc,
    GrowthFeature.supplierPaymentToggle => l10n.featurePaymentSettingsDesc,
    GrowthFeature.shopifyIntegration    => l10n.featureShopifyIntegrationDesc,
    GrowthFeature.manufacturingMode     => l10n.featureManufacturingModeDesc,
    GrowthFeature.supplierManagement    => l10n.featureSupplierManagementDesc,
    GrowthFeature.fullCashFlow          => l10n.featureFullCashFlowDesc,
  };
}

// ─── State ───────────────────────────────────────────────────────────────────
class AppSettingsState {
  final String currency;   // e.g. 'EGP'
  final String language;   // e.g. 'English'
  final bool   autoBackup;
  final SubscriptionTier tier;
  final bool   autoCreateTransactionOnSupplierPayment;
  final double openingCashBalance;
  final String businessName;
  final String industry;
  final String businessStage;
  final String mainGoal;
  final String valuationMethod; // 'fifo', 'lifo', or 'average'
  final bool   breakdownEnabled; // whether breakdown/selling options is active
  final bool   autoUpdateStock; // auto-decrease stock on sales
  final String defaultUnit; // default unit for new items
  final bool   lowStockAlerts; // show low stock alerts
  final int    alertThreshold; // notify when stock below this
  final bool   hideOutOfStock; // hide out-of-stock from main list
  final bool   hideShopifyDrafts; // hide Shopify drafted products

  const AppSettingsState({
    this.currency   = 'EGP',
    this.language   = 'English',
    this.autoBackup = true,
    this.tier       = SubscriptionTier.launch,
    this.autoCreateTransactionOnSupplierPayment = true,
    this.openingCashBalance = 0.0,
    this.businessName  = '',
    this.industry      = '',
    this.businessStage = '',
    this.mainGoal      = '',
    this.valuationMethod = 'fifo',
    this.breakdownEnabled = false,
    this.autoUpdateStock = true,
    this.defaultUnit = 'pcs',
    this.lowStockAlerts = true,
    this.alertThreshold = 10,
    this.hideOutOfStock = false,
    this.hideShopifyDrafts = false,
  });

  /// Quick check: does the current tier have access to the [required] tier?
  bool hasAccess(SubscriptionTier required) => tier.hasAccess(required);

  /// Check if a specific growth feature is available.
  /// All Growth features (including Shopify) require [SubscriptionTier.growth].
  bool isUnlocked(GrowthFeature feature) {
    return tier.isGrowthOrAbove;
  }

  AppSettingsState copyWith({
    String? currency,
    String? language,
    bool?   autoBackup,
    SubscriptionTier? tier,
    bool?   autoCreateTransactionOnSupplierPayment,
    double? openingCashBalance,
    String? businessName,
    String? industry,
    String? businessStage,
    String? mainGoal,
    String? valuationMethod,
    bool?   breakdownEnabled,
    bool?   autoUpdateStock,
    String? defaultUnit,
    bool?   lowStockAlerts,
    int?    alertThreshold,
    bool?   hideOutOfStock,
    bool?   hideShopifyDrafts,
  }) {
    return AppSettingsState(
      currency:   currency   ?? this.currency,
      language:   language   ?? this.language,
      autoBackup: autoBackup ?? this.autoBackup,
      tier:       tier       ?? this.tier,
      autoCreateTransactionOnSupplierPayment:
          autoCreateTransactionOnSupplierPayment ??
          this.autoCreateTransactionOnSupplierPayment,
      openingCashBalance: openingCashBalance ?? this.openingCashBalance,
      businessName:  businessName  ?? this.businessName,
      industry:      industry      ?? this.industry,
      businessStage: businessStage ?? this.businessStage,
      mainGoal:      mainGoal      ?? this.mainGoal,
      valuationMethod: valuationMethod ?? this.valuationMethod,
      breakdownEnabled: breakdownEnabled ?? this.breakdownEnabled,
      autoUpdateStock: autoUpdateStock ?? this.autoUpdateStock,
      defaultUnit: defaultUnit ?? this.defaultUnit,
      lowStockAlerts: lowStockAlerts ?? this.lowStockAlerts,
      alertThreshold: alertThreshold ?? this.alertThreshold,
      hideOutOfStock: hideOutOfStock ?? this.hideOutOfStock,
      hideShopifyDrafts: hideShopifyDrafts ?? this.hideShopifyDrafts,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────
class AppSettingsNotifier extends Notifier<AppSettingsState> {
  /// Returns the current user's UID, or null if not authenticated.
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Whether the user is authenticated.
  bool get _isAuth => _uid != null;

  /// Prefix a key with the user UID for per-account isolation.
  String _key(String base) => '${_uid!}_$base';

  @override
  AppSettingsState build() {
    _load();
    return const AppSettingsState();
  }

  Future<void> _load() async {
    if (!_isAuth) return; // Not authenticated — keep defaults
    final prefs = await SharedPreferences.getInstance();
    String tierName = prefs.getString(_key(_kTier)) ?? 'launch';

    // Also check Firestore for the authoritative tier (e.g. set by CF)
    String valuationMethod = prefs.getString(_key(_kValuationMethod)) ?? 'fifo';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        if (data['subscription_tier'] != null) {
          final fsTier = data['subscription_tier'] as String;
          // Firestore is authoritative; update local if different
          if (fsTier != tierName) {
            tierName = fsTier;
            await prefs.setString(_key(_kTier), fsTier);
          }
        }
        if (data['valuation_method'] != null) {
          final fsVal = data['valuation_method'] as String;
          if (fsVal != valuationMethod) {
            valuationMethod = fsVal;
            await prefs.setString(_key(_kValuationMethod), fsVal);
          }
        }
      }
    } catch (_) {
      // Firestore read failed; use local SharedPreferences value
    }

    state = AppSettingsState(
      currency:   prefs.getString(_key(_kCurrency))   ?? 'EGP',
      language:   prefs.getString(_key(_kLanguage))   ?? 'English',
      autoBackup: prefs.getBool(_key(_kAutoBackup))   ?? true,
      tier: SubscriptionTier.values.firstWhere(
        (t) => t.name == tierName,
        orElse: () => SubscriptionTier.launch,
      ),
      autoCreateTransactionOnSupplierPayment:
          prefs.getBool(_key(_kAutoTxnOnSupplierPayment)) ?? true,
      openingCashBalance: prefs.getDouble(_key(_kOpeningCashBalance)) ?? 0.0,
      businessName:  prefs.getString(_key(_kBusinessName))  ?? '',
      industry:      prefs.getString(_key(_kIndustry))      ?? '',
      businessStage: prefs.getString(_key(_kBusinessStage)) ?? '',
      mainGoal:      prefs.getString(_key(_kMainGoal))      ?? '',
      valuationMethod: valuationMethod,
      breakdownEnabled: prefs.getBool(_key(_kBreakdownEnabled)) ?? false,
      autoUpdateStock: prefs.getBool(_key(_kAutoUpdateStock)) ?? true,
      defaultUnit: prefs.getString(_key(_kDefaultUnit)) ?? 'pcs',
      lowStockAlerts: prefs.getBool(_key(_kLowStockAlerts)) ?? true,
      alertThreshold: prefs.getInt(_key(_kAlertThreshold)) ?? 10,
      hideOutOfStock: prefs.getBool(_key(_kHideOutOfStock)) ?? false,
      hideShopifyDrafts: prefs.getBool(_key(_kHideShopifyDrafts)) ?? false,
    );
  }

  Future<void> setCurrency(String currency) async {
    state = state.copyWith(currency: currency);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(_kCurrency), currency);
  }

  Future<void> setLanguage(String language) async {
    state = state.copyWith(language: language);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(_kLanguage), language);
  }

  Future<void> setAutoBackup(bool value) async {
    state = state.copyWith(autoBackup: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kAutoBackup), value);
  }

  Future<void> setTier(SubscriptionTier tier) async {
    // Always keep supplier-payment → transaction sync ON.
    // The transactions are created with excludeFromPL so they
    // don't affect the P&L but remain visible for tracking.
    state = state.copyWith(
      tier: tier,
      autoCreateTransactionOnSupplierPayment: true,
    );
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(_kTier), tier.name);
    await prefs.setBool(_key(_kAutoTxnOnSupplierPayment), true);

    // Persist to Firestore so Cloud Functions can validate the tier
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({'subscription_tier': tier.name}, SetOptions(merge: true));
    } catch (_) {
      // Firestore write is best-effort; local state is already set
    }
  }

  Future<void> setAutoCreateTransactionOnSupplierPayment(bool value) async {
    state = state.copyWith(autoCreateTransactionOnSupplierPayment: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kAutoTxnOnSupplierPayment), value);
  }

  Future<void> setOpeningCashBalance(double value) async {
    state = state.copyWith(openingCashBalance: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key(_kOpeningCashBalance), value);
  }

  Future<void> setBusinessName(String value) async {
    state = state.copyWith(businessName: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(_kBusinessName), value);
  }

  Future<void> setIndustry(String value) async {
    state = state.copyWith(industry: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(_kIndustry), value);
  }

  Future<void> setBusinessStage(String value) async {
    state = state.copyWith(businessStage: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(_kBusinessStage), value);
  }

  Future<void> setMainGoal(String value) async {
    state = state.copyWith(mainGoal: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(_kMainGoal), value);
  }

  Future<void> setValuationMethod(String value) async {
    state = state.copyWith(valuationMethod: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(_kValuationMethod), value);
    // Also sync to Firestore so Cloud Functions can read it
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({'valuation_method': value}, SetOptions(merge: true));
    } catch (_) {
      // Best-effort; local state already set
    }
  }

  Future<void> setBreakdownEnabled(bool value) async {
    state = state.copyWith(breakdownEnabled: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kBreakdownEnabled), value);
  }

  Future<void> setAutoUpdateStock(bool value) async {
    state = state.copyWith(autoUpdateStock: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kAutoUpdateStock), value);
  }

  Future<void> setDefaultUnit(String value) async {
    state = state.copyWith(defaultUnit: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(_kDefaultUnit), value);
  }

  Future<void> setLowStockAlerts(bool value) async {
    state = state.copyWith(lowStockAlerts: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kLowStockAlerts), value);
  }

  Future<void> setAlertThreshold(int value) async {
    state = state.copyWith(alertThreshold: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(_kAlertThreshold), value);
  }

  Future<void> setHideOutOfStock(bool value) async {
    state = state.copyWith(hideOutOfStock: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kHideOutOfStock), value);
  }

  Future<void> setHideShopifyDrafts(bool value) async {
    state = state.copyWith(hideShopifyDrafts: value);
    if (!_isAuth) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(_kHideShopifyDrafts), value);
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────
final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettingsState>(() {
  return AppSettingsNotifier();
});

/// Convenience provider that exposes just the selected currency code (e.g. 'EGP').
final currencyProvider = Provider<String>((ref) {
  return ref.watch(appSettingsProvider).currency;
});

/// Maps the stored language name to a [Locale] for MaterialApp.
final localeProvider = Provider<Locale>((ref) {
  final lang = ref.watch(appSettingsProvider).language;
  return switch (lang) {
    'العربية' => const Locale('ar'),
    _         => const Locale('en'),
  };
});

/// Convenience provider that exposes the current subscription tier.
final tierProvider = Provider<SubscriptionTier>((ref) {
  return ref.watch(appSettingsProvider).tier;
});

/// Quick check: is a Growth feature available to the current user?
final isGrowthProvider = Provider<bool>((ref) {
  return ref.watch(tierProvider).isGrowthOrAbove;
});

/// Quick check: does the current user have Shopify integration access?
final hasShopifyAccessProvider = Provider<bool>((ref) {
  return ref.watch(tierProvider).hasShopifyAccess;
});
