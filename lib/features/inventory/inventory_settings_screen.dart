import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/app_router.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../l10n/app_localizations.dart';
import '../shopify/providers/shopify_connection_provider.dart';
import '../shopify/providers/shopify_sync_provider.dart';

class InventorySettingsScreen extends ConsumerStatefulWidget {
  const InventorySettingsScreen({super.key});

  @override
  ConsumerState<InventorySettingsScreen> createState() =>
      _InventorySettingsScreenState();
}

class _InventorySettingsScreenState extends ConsumerState<InventorySettingsScreen> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;
  bool _autoUpdateStock = false;
  bool _lowStockAlerts = true;
  bool _hideOutOfStock = false;
  bool _breakdownEnabled = false;
  bool _hideShopifyDrafts = false;
  bool _hideShopifyBundles = false;

  String _defaultUnit = 'pcs';
  String _valuationMethod = 'FIFO (Default)';
  String _currency = 'EGP';
  final _thresholdController = TextEditingController(text: '10');

  static const _units = ['pcs', 'kg', 'liters', 'meters', 'boxes'];
  static const _valuations = ['FIFO (Default)', 'Average Cost', 'LIFO'];
  static const _currencies = ['EGP', 'USD', 'EUR', 'SAR'];

  static const _valuationToKey = {
    'FIFO (Default)': 'fifo',
    'Average Cost': 'average',
    'LIFO': 'lifo',
  };
  static const _keyToValuation = {
    'fifo': 'FIFO (Default)',
    'average': 'Average Cost',
    'lifo': 'LIFO',
  };

  @override
  void initState() {
    super.initState();
    final s = ref.read(appSettingsProvider);
    _autoUpdateStock = s.autoUpdateStock;
    _lowStockAlerts = s.lowStockAlerts;
    _hideOutOfStock = s.hideOutOfStock;
    _breakdownEnabled = s.breakdownEnabled;
    _hideShopifyDrafts = s.hideShopifyDrafts;
    _hideShopifyBundles = s.hideShopifyBundles;
    _defaultUnit = _units.contains(s.defaultUnit) ? s.defaultUnit : 'pcs';
    _currency = _currencies.contains(s.currency) ? s.currency : 'EGP';
    _valuationMethod = _keyToValuation[s.valuationMethod] ?? 'FIFO (Default)';
    _thresholdController.text = s.alertThreshold.toString();
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    super.dispose();
  }

  void _save() {
    HapticFeedback.mediumImpact();
    final notifier = ref.read(appSettingsProvider.notifier);
    notifier.setAutoUpdateStock(_autoUpdateStock);
    notifier.setLowStockAlerts(_lowStockAlerts);
    notifier.setAlertThreshold(int.tryParse(_thresholdController.text) ?? 10);
    notifier.setHideOutOfStock(_hideOutOfStock);
    notifier.setBreakdownEnabled(_breakdownEnabled);
    notifier.setHideShopifyDrafts(_hideShopifyDrafts);
    notifier.setHideShopifyBundles(_hideShopifyBundles);
    notifier.setDefaultUnit(_defaultUnit);
    notifier.setValuationMethod(_valuationToKey[_valuationMethod] ?? 'fifo');
    notifier.setCurrency(_currency);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.settingsSaved),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStockManagement(),
                    const SizedBox(height: 24),
                    _buildAlertsSection(),
                    const SizedBox(height: 24),
                    _buildConfigurationSection(),
                    const SizedBox(height: 24),
                    _buildAdvancedSection(),
                    const SizedBox(height: 24),
                    _buildShopifySyncSection(),
                    const SizedBox(height: 28),
                    _buildSaveButton(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, size: 24),
            color: AppColors.primaryNavy,
          ),
          const SizedBox(width: 4),
          Text(
            l10n.inventorySettings,
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  SECTION HEADER
  // ═══════════════════════════════════════════════════
  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.captionSmall.copyWith(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          fontSize: 11,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  STOCK MANAGEMENT
  // ═══════════════════════════════════════════════════
  Widget _buildStockManagement() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.stockManagement),
        _card(
          children: [
            _toggleRow(
              title: l10n.autoUpdateStock,
              subtitle: l10n.autoUpdateStockDesc,
              value: _autoUpdateStock,
              onChanged: (v) => setState(() => _autoUpdateStock = v),
            ),
            const SizedBox(height: 12),
            _divider(),
            const SizedBox(height: 12),
            _tapRow(
              title: l10n.unitOfMeasure,
              subtitle: l10n.defaultUnitDesc,
              trailing: _defaultUnit,
              onTap: () => _showPicker(
                l10n.unitOfMeasureTitle,
                _units,
                _defaultUnit,
                (v) => setState(() => _defaultUnit = v),
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 300.ms);
  }

  // ═══════════════════════════════════════════════════
  //  ALERTS & NOTIFICATIONS
  // ═══════════════════════════════════════════════════
  Widget _buildAlertsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.alertsAndNotifications),
        _card(
          children: [
            _toggleRow(
              title: l10n.lowStockAlerts,
              value: _lowStockAlerts,
              onChanged: (v) => setState(() => _lowStockAlerts = v),
            ),
            _divider(),
            // Threshold
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.alertThreshold,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.borderLight.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          l10n.notifyWhenStockBelow,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 48,
                          child: TextField(
                            controller: _thresholdController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(
                                    color:
                                        AppColors.borderLight),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: BorderSide(
                                    color: AppColors.borderLight),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(6),
                                borderSide: const BorderSide(
                                    color: AppColors.accentOrange,
                                    width: 1.5),
                              ),
                            ),
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.primaryNavy,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.units,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 50.ms);
  }

  // ═══════════════════════════════════════════════════
  //  CONFIGURATION
  // ═══════════════════════════════════════════════════
  Widget _buildConfigurationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.configurationSection),
        _card(
          children: [
            _navRow(
              icon: Icons.category_rounded,
              iconBg: const Color(0xFFEFF6FF),
              iconColor: const Color(0xFF2563EB),
              title: l10n.manageCategories,
              subtitle: l10n.manageCategoriesDesc,
              onTap: () {
                HapticFeedback.lightImpact();
                context.push(AppRoutes.categories);
              },
            ),
            _divider(),
            _navRow(
              icon: Icons.local_shipping_rounded,
              iconBg: const Color(0xFFF3E8FF),
              iconColor: const Color(0xFF9333EA),
              title: l10n.manageSuppliers,
              subtitle: l10n.manageSuppliersDesc,
              onTap: () {
                HapticFeedback.lightImpact();
                context.push(AppRoutes.suppliers);
              },
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 100.ms);
  }

  // ═══════════════════════════════════════════════════
  //  ADVANCED
  // ═══════════════════════════════════════════════════
  Widget _buildAdvancedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.advancedSection),
        _card(
          children: [
            // Valuation method
            _tapRow(
              title: l10n.valuationMethod,
              subtitle: _valuationDescription(_valuationMethod),
              trailing: _valuationMethod.replaceAll(' (Default)', ''),
              onTap: () => _showValuationPicker(),
            ),
            _divider(),
            // Currency
            _tapRow(
              title: l10n.currencyLabel,
              subtitle: l10n.currencyDesc,
              trailing: _currency,
              onTap: () => _showPicker(
                l10n.currencyTitle,
                _currencies,
                _currency,
                (v) => setState(() => _currency = v),
              ),
            ),
            _divider(),
            // Breakdown feature
            _toggleRow(
              title: l10n.productBreakdown,
              subtitle: l10n.productBreakdownDesc,
              value: _breakdownEnabled,
              onChanged: (v) => setState(() => _breakdownEnabled = v),
            ),
            _divider(),
            // Hide out-of-stock
            _toggleRow(
              title: l10n.hideOutOfStockItems,
              subtitle: l10n.hideOutOfStockDesc,
              value: _hideOutOfStock,
              onChanged: (v) => setState(() => _hideOutOfStock = v),
            ),
          ],
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 150.ms);
  }

  // ═══════════════════════════════════════════════════
  //  SHOPIFY SYNC
  // ═══════════════════════════════════════════════════
  Widget _buildShopifySyncSection() {
    final asyncConn = ref.watch(shopifyConnectionProvider);
    final conn = asyncConn.value;
    if (conn == null || !conn.isActive) return const SizedBox.shrink();

    final syncEnabled = conn.syncInventoryEnabled;
    final isAlwaysOn = conn.inventorySyncMode == 'always';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(l10n.shopifySync),
        _card(
          children: [
            // Hide drafted products toggle
            _toggleRow(
              title: l10n.hideDraftedProducts,
              subtitle: l10n.hideDraftedProductsDesc,
              value: _hideShopifyDrafts,
              onChanged: (v) => setState(() => _hideShopifyDrafts = v),
            ),
            _divider(),
            // Hide bundle products toggle
            _toggleRow(
              title: l10n.hideShopifyBundles,
              subtitle: l10n.hideShopifyBundlesDesc,
              value: _hideShopifyBundles,
              onChanged: (v) => setState(() => _hideShopifyBundles = v),
            ),
            _divider(),
            // Inventory sync toggle
            _toggleRow(
              title: l10n.inventorySyncLabel,
              subtitle: l10n.syncStockWithShopify,
              value: syncEnabled,
              onChanged: (v) async {
                HapticFeedback.mediumImpact();
                await ref
                    .read(shopifyConnectionProvider.notifier)
                    .updateSettings(syncInventoryEnabled: v);
                if (!v) {
                  ref.read(shopifySyncProvider.notifier).stopAlwaysSyncTimer();
                } else if (conn.inventorySyncMode == 'always') {
                  ref.read(shopifySyncProvider.notifier).restartAlwaysSyncTimer();
                }
              },
            ),
            if (syncEnabled) ...[
              _divider(),
              // Sync mode selection
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.syncModeLabel,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.chooseHowSync,
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSyncModeCard(
                      icon: Icons.sync_rounded,
                      iconColor: const Color(0xFF16A34A),
                      iconBg: const Color(0xFFDCFCE7),
                      title: l10n.alwaysOnLabel,
                      subtitle: l10n.alwaysOnDesc,
                      selected: isAlwaysOn,
                      onTap: () => _setSyncMode('always'),
                    ),
                    const SizedBox(height: 8),
                    _buildSyncModeCard(
                      icon: Icons.touch_app_rounded,
                      iconColor: const Color(0xFF2563EB),
                      iconBg: const Color(0xFFDBEAFE),
                      title: l10n.onDemandLabel,
                      subtitle: l10n.onDemandDesc,
                      selected: !isAlwaysOn,
                      onTap: () => _setSyncMode('on_demand'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 175.ms);
  }

  Widget _buildSyncModeCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? iconBg.withValues(alpha: 0.4)
              : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? iconColor.withValues(alpha: 0.5)
                : AppColors.borderLight.withValues(alpha: 0.5),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.labelMedium.copyWith(
                      color: selected
                          ? AppColors.primaryNavy
                          : AppColors.textPrimary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded,
                  color: iconColor, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _setSyncMode(String mode) async {
    HapticFeedback.mediumImpact();
    await ref
        .read(shopifyConnectionProvider.notifier)
        .updateSettings(inventorySyncMode: mode);
    if (mode == 'always') {
      ref.read(shopifySyncProvider.notifier).restartAlwaysSyncTimer();
    } else {
      ref.read(shopifySyncProvider.notifier).stopAlwaysSyncTimer();
    }
  }

  String _valuationDescription(String method) {
    return switch (method) {
      'FIFO (Default)' => l10n.fifoDescription,
      'LIFO'           => l10n.lifoDescription,
      'Average Cost'   => l10n.averageCostDescription,
      _                => '',
    };
  }

  void _showValuationPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.valuationMethodTitle,
                      style: AppTypography.h3.copyWith(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textTertiary, size: 22),
                    ),
                  ],
                ),
              ),
              Divider(
                  height: 1,
                  color: AppColors.borderLight.withValues(alpha: 0.5)),
              ..._valuations.map((val) {
                final selected = val == _valuationMethod;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() => _valuationMethod = val);
                      HapticFeedback.lightImpact();
                      Navigator.pop(ctx);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  val,
                                  style: AppTypography.labelMedium.copyWith(
                                    color: selected
                                        ? AppColors.primaryNavy
                                        : AppColors.textPrimary,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _valuationDescription(val),
                                  style: AppTypography.captionSmall.copyWith(
                                    color: AppColors.textTertiary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (selected)
                            const Icon(Icons.check_rounded,
                                color: AppColors.accentOrange, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  SAVE BUTTON
  // ═══════════════════════════════════════════════════
  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _save,
        icon: const Icon(Icons.save_rounded, size: 20),
        label: Text(
          l10n.saveChanges,
          style: AppTypography.labelMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryNavy,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: AppColors.primaryNavy.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 200.ms);
  }

  // ═══════════════════════════════════════════════════
  //  REUSABLE WIDGETS
  // ═══════════════════════════════════════════════════

  Widget _card({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: children),
      ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        color: AppColors.borderLight.withValues(alpha: 0.5),
      );

  // ── Toggle row ───────────────────────────────
  Widget _toggleRow({
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              onChanged(!value);
            },
            child: AnimatedContainer(
              duration: 200.ms,
              width: 48,
              height: 26,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(50),
                color: value ? AppColors.accentOrange : const Color(0xFFCCCCCC),
              ),
              child: AnimatedAlign(
                duration: 200.ms,
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tap row (navigate) ───────────────────────
  Widget _tapRow({
    required String title,
    String? subtitle,
    required String trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                trailing,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Nav row (icon + label + chevron) ─────────
  Widget _navRow({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Dropdown row ─────────────────────────────
  // ignore: unused_element
  Widget _dropdownRow({
    required String title,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.5)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                icon: const Icon(Icons.expand_more_rounded,
                    color: AppColors.textTertiary, size: 18),
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                items: items
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(e),
                        ))
                    .toList(),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Picker bottom sheet ──────────────────────
  void _showPicker(
    String title,
    List<String> options,
    String current,
    ValueChanged<String> onSelect,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: AppTypography.h3.copyWith(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textTertiary, size: 22),
                    ),
                  ],
                ),
              ),
              Divider(
                  height: 1,
                  color: AppColors.borderLight.withValues(alpha: 0.5)),
              ...options.map((opt) {
                final selected = opt == current;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      onSelect(opt);
                      HapticFeedback.lightImpact();
                      Navigator.pop(ctx);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              opt,
                              style: AppTypography.labelMedium.copyWith(
                                color: selected
                                    ? AppColors.primaryNavy
                                    : AppColors.textPrimary,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (selected)
                            const Icon(Icons.check_rounded,
                                color: AppColors.accentOrange, size: 20),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
