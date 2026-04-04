import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/services/shopify_sync_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../providers/shopify_connection_provider.dart';
import '../providers/shopify_sync_provider.dart';
import '../../../shared/models/shopify_connection_model.dart';
import '../../../shared/utils/safe_pop.dart';

/// Shopify connection settings screen.
///
/// - Enter shop domain → "Connect to Shopify" → OAuth in browser → callback
/// - Shows connection status, shop name, connected date
/// - Toggle sync order / sync inventory
/// - Disconnect with confirmation
class ShopifyConnectScreen extends ConsumerStatefulWidget {
  const ShopifyConnectScreen({super.key});

  @override
  ConsumerState<ShopifyConnectScreen> createState() =>
      _ShopifyConnectScreenState();
}

class _ShopifyConnectScreenState extends ConsumerState<ShopifyConnectScreen>
    with WidgetsBindingObserver {

  AppLocalizations get l10n => AppLocalizations.of(context)!;
  DateTime? _lastAutoRefreshAt;
  bool _redirectedToWizard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted) return;

    // Coming back from the browser after OAuth, the provider won't
    // auto-update because it uses a one-time Firestore read.
    // Refresh on resume to pick up the updated connection document.
    final now = DateTime.now();
    final last = _lastAutoRefreshAt;
    if (last != null && now.difference(last).inSeconds < 2) return;
    _lastAutoRefreshAt = now;

    ref.read(shopifyConnectionProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final asyncConn = ref.watch(shopifyConnectionProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: asyncConn.when(
                loading: () => _buildConnectForm(),
                error: (e, _) => _buildConnectForm(),
                data: (conn) {
                  if (conn == null ||
                      conn.isDisconnected ||
                      conn.hasError ||
                      conn.status == 'pending') {
                    return _buildConnectForm();
                  }
                  if (conn.isActive && !conn.setupCompleted) {
                    // OAuth succeeded but the wizard wasn't finished.
                    // Auto-redirect once so the user can resume.
                    if (!_redirectedToWizard) {
                      _redirectedToWizard = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          context.push(AppRoutes.shopifySetupWizard);
                        }
                      });
                    }
                    return const Center(
                        child: CircularProgressIndicator());
                  }
                  return _buildConnectedView(conn);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
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
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            color: AppColors.primaryNavy,
          ),
          const Spacer(),
          Text(
            l10n.shopifyTitle,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  // ── Not-connected CTA (directs to setup wizard) ────────

  Widget _buildConnectForm() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
      child: Column(
        children: [
          // Hero icon
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.shopifyPurple, Color(0xFF5B21B6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color:
                        AppColors.shopifyPurple.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.store_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
          ).animate().fadeIn(duration: 300.ms).scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1, 1),
              ),
          const SizedBox(height: 28),
          Text(
            l10n.shopifyConnectTitle,
            style: AppTypography.h2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 100.ms),
          const SizedBox(height: 10),
          Text(
            l10n.shopifyConnectSubtitle,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 150.ms),
          const SizedBox(height: 36),

          // Setup wizard button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.push(AppRoutes.shopifySetupWizard),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.shopifyPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor:
                    AppColors.shopifyPurple.withValues(alpha: 0.3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.rocket_launch_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    l10n.shopifyStartSetupWizard,
                    style: AppTypography.labelLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 200.ms),

          const SizedBox(height: 36),

          // Info cards
          _InfoCard(
            icon: Icons.sync_rounded,
            title: l10n.shopifyAlwaysOnOrderSync,
            description: l10n.shopifyAlwaysOnOrderSyncDesc,
          ).animate().fadeIn(duration: 250.ms, delay: 300.ms),
          const SizedBox(height: 10),
          _InfoCard(
            icon: Icons.inventory_2_rounded,
            title: l10n.shopifyOnDemandInventory,
            description: l10n.shopifyOnDemandInventoryDesc,
          ).animate().fadeIn(duration: 250.ms, delay: 350.ms),
          const SizedBox(height: 10),
          _InfoCard(
            icon: Icons.security_rounded,
            title: l10n.shopifySecureOAuth,
            description: l10n.shopifySecureOAuthDesc,
          ).animate().fadeIn(duration: 250.ms, delay: 400.ms),
          const SizedBox(height: 10),
          _InfoCard(
            icon: Icons.link_off_rounded,
            title: l10n.shopifyDisconnectAnytime,
            description: l10n.shopifyDisconnectAnytimeDesc,
          ).animate().fadeIn(duration: 250.ms, delay: 450.ms),
        ],
      ),
    );
  }

  // ── Connected view ──────────────────────────────────────

  Widget _buildConnectedView(ShopifyConnection conn) {
    final l10n = AppLocalizations.of(context)!;
    final dateFmt = DateFormat('MMM dd, yyyy');

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status card
          _StatusCard(connection: conn)
              .animate()
              .fadeIn(duration: 250.ms),
          const SizedBox(height: 20),

          // Connection info
          Text(
            l10n.shopifySectionConnection,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          _DetailCard(children: [
            _DetailRow(
              label: l10n.shopifyStore,
              value: conn.shopName,
              icon: Icons.store_rounded,
            ),
            _DetailRow(
              label: l10n.shopifyDomain,
              value: conn.shopDomain,
              icon: Icons.language_rounded,
            ),
            _DetailRow(
              label: l10n.shopifyConnectedLabel,
              value: dateFmt.format(conn.connectedAt),
              icon: Icons.calendar_today_rounded,
            ),
            if (conn.lastOrderSyncAt != null)
              _DetailRow(
                label: l10n.shopifyLastOrderSync,
                value: _timeAgo(l10n, conn.lastOrderSyncAt!),
                icon: Icons.sync_rounded,
              ),
            if (conn.lastInventorySyncAt != null)
              _DetailRow(
                label: l10n.shopifyLastInventorySync,
                value: _timeAgo(l10n, conn.lastInventorySyncAt!),
                icon: Icons.inventory_rounded,
              ),
          ]).animate().fadeIn(duration: 250.ms, delay: 60.ms),
          const SizedBox(height: 20),

          // Sync info (always-on)
          Text(
            l10n.shopifySectionSyncSettings,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          _DetailCard(children: [
            _SyncInfoRow(
              label: l10n.shopifyOrderSync,
              subtitle: l10n.shopifyOrderSyncDesc,
              status: l10n.shopifyAlwaysOn,
              statusColor: AppColors.success,
            ),
            Divider(
                color: AppColors.borderLight.withValues(alpha: 0.5),
                height: 1),
            InkWell(
              onTap: () => _showInventorySyncModePicker(conn),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16),
              ),
              child: _SyncInfoRow(
                label: l10n.shopifyInventorySync,
                subtitle: conn.inventorySyncMode == 'always'
                    ? l10n.shopifyInvAutoSyncDesc
                    : l10n.shopifyInvManualSyncDesc,
                status: conn.inventorySyncMode == 'always'
                    ? l10n.shopifyAlwaysOn
                    : l10n.shopifyOnDemand,
                statusColor: conn.inventorySyncMode == 'always'
                    ? AppColors.success
                    : AppColors.shopifyPurple,
              ),
            ),
          ]).animate().fadeIn(duration: 250.ms, delay: 120.ms),
          const SizedBox(height: 20),

          // Location picker
          Text(
            l10n.shopifySectionLocation,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          _LocationPicker(connection: conn)
              .animate()
              .fadeIn(duration: 250.ms, delay: 140.ms),
          const SizedBox(height: 20),

          // Quick actions
          Text(
            l10n.shopifySectionActions,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          _ActionButton(
            icon: Icons.link_rounded,
            label: l10n.shopifyProductMappings,
            subtitle: l10n.shopifyProductMappingsDesc,
            onTap: () =>
                context.push(AppRoutes.shopifyProductMappings),
          ).animate().fadeIn(duration: 250.ms, delay: 160.ms),
          const SizedBox(height: 8),
          _ActionButton(
            icon: Icons.download_rounded,
            label: l10n.shopifyReimportOrders,
            subtitle: l10n.shopifyReimportOrdersDesc,
            onTap: () => context.push(AppRoutes.shopifyImport),
          ).animate().fadeIn(duration: 250.ms, delay: 200.ms),
          const SizedBox(height: 8),
          _ActionButton(
            icon: Icons.sync_rounded,
            label: conn.inventorySyncMode == 'always'
                ? l10n.shopifyInvSyncAuto
                : l10n.shopifyInvSyncManual,
            subtitle: conn.inventorySyncMode == 'always'
                ? l10n.shopifyInvSyncAutoDesc
                : l10n.shopifyInvSyncManualDesc,
            onTap: () =>
                context.push(AppRoutes.shopifyInventorySync),
          ).animate().fadeIn(duration: 250.ms, delay: 240.ms),
          const SizedBox(height: 8),
          _ActionButton(
            icon: Icons.history_rounded,
            label: l10n.shopifySyncHistoryLabel,
            subtitle: l10n.shopifySyncHistoryDesc,
            onTap: () =>
                context.push(AppRoutes.shopifySyncHistory),
          ).animate().fadeIn(duration: 250.ms, delay: 280.ms),

          const SizedBox(height: 32),

          // Disconnect button
          Center(
            child: TextButton.icon(
              onPressed: () => _confirmDisconnect(conn),
              icon: const Icon(Icons.link_off_rounded, size: 18),
              label: Text(l10n.shopifyDisconnectButton),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.danger,
                textStyle: AppTypography.labelMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInventorySyncModePicker(ShopifyConnection conn) {
    final current = conn.inventorySyncMode;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Text(
                  AppLocalizations.of(ctx)!.shopifyInvSyncMode,
                  style: AppTypography.h3.copyWith(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: AppColors.borderLight.withValues(alpha: 0.5),
              ),
              _syncModeOption(
                ctx,
                title: AppLocalizations.of(ctx)!.shopifyModeAlwaysOn,
                subtitle:
                    AppLocalizations.of(ctx)!.shopifyModeAlwaysOnDesc,
                icon: Icons.sync_rounded,
                isSelected: current == 'always',
                onTap: () async {
                  Navigator.pop(ctx);
                  await _updateSyncMode('always');
                },
              ),
              _syncModeOption(
                ctx,
                title: AppLocalizations.of(ctx)!.shopifyModeOnDemand,
                subtitle:
                    AppLocalizations.of(ctx)!.shopifyModeOnDemandDesc,
                icon: Icons.touch_app_rounded,
                isSelected: current == 'on_demand',
                onTap: () async {
                  Navigator.pop(ctx);
                  await _updateSyncMode('on_demand');
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _syncModeOption(
    BuildContext ctx, {
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? AppColors.primaryNavy.withValues(alpha: 0.1)
                      : AppColors.backgroundLight,
                ),
                child: Icon(icon,
                    size: 20,
                    color: isSelected
                        ? AppColors.primaryNavy
                        : AppColors.textTertiary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
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
              if (isSelected)
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primaryNavy, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateSyncMode(String mode) async {
    HapticFeedback.mediumImpact();
    await ref.read(shopifyConnectionProvider.notifier).updateSettings(
      inventorySyncMode: mode,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mode == 'always'
              ? AppLocalizations.of(context)!.shopifyInvSyncSetAlwaysOn
              : AppLocalizations.of(context)!.shopifyInvSyncSetOnDemand,
        ),
        backgroundColor: AppColors.primaryNavy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Future<void> _confirmDisconnect(ShopifyConnection conn) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          l10n.shopifyDisconnectConfirm,
          style: AppTypography.h3.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          l10n.shopifyDisconnectMessage(conn.shopName),
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              l10n.cancel,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(l10n.shopifyDisconnectButton),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    HapticFeedback.mediumImpact();
    // Stop background sync timer before disconnecting
    ref.read(shopifySyncProvider.notifier).stopAlwaysSyncTimer();
    await ref.read(shopifyConnectionProvider.notifier).disconnect();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.shopifyDisconnected),
          backgroundColor: AppColors.primaryNavy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  String _timeAgo(AppLocalizations l10n, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return l10n.justNow;
    if (diff.inMinutes < 60) return l10n.shopifyTimeMinAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.shopifyTimeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.shopifyTimeDaysAgo(diff.inDays);
    return DateFormat('MMM dd').format(dt);
  }
}

// ═══════════════════════════════════════════════════════════
//  PRIVATE WIDGETS
// ═══════════════════════════════════════════════════════════

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF96BF48).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF5E8E3E)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final ShopifyConnection connection;

  const _StatusCard({required this.connection});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (connection.isActive) {
      statusColor = AppColors.success;
      statusLabel = l10n.shopifyStatusConnected;
      statusIcon = Icons.check_circle_rounded;
    } else if (connection.hasError) {
      statusColor = AppColors.danger;
      statusLabel = l10n.shopifyStatusError;
      statusIcon = Icons.error_rounded;
    } else {
      statusColor = AppColors.warning;
      statusLabel = l10n.shopifyStatusDisconnected;
      statusIcon = Icons.link_off_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColor.withValues(alpha: 0.08),
            statusColor.withValues(alpha: 0.02),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF96BF48),
                  const Color(0xFF5E8E3E),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.shopping_bag_rounded,
              size: 26,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connection.shopName,
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: AppTypography.labelSmall.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  final List<Widget> children;

  const _DetailCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: 12),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncInfoRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final String status;
  final Color statusColor;

  const _SyncInfoRow({
    required this.label,
    required this.subtitle,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon,
                    size: 20, color: AppColors.primaryNavy),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Location Picker ────────────────────────────────────────

class _LocationPicker extends ConsumerStatefulWidget {
  final ShopifyConnection connection;

  const _LocationPicker({required this.connection});

  @override
  ConsumerState<_LocationPicker> createState() =>
      _LocationPickerState();
}

class _LocationPickerState extends ConsumerState<_LocationPicker> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;
  List<Map<String, dynamic>>? _locations;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-fetch locations if none is set yet
    if (widget.connection.shopifyLocationId == null) {
      _fetchLocations(autoSelect: true);
    }
  }

  Future<void> _fetchLocations({bool autoSelect = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final syncSvc = ref.read(shopifySyncServiceProvider);
      final result = await syncSvc.fetchLocations();

      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        final locs = (result.data! as List)
            .cast<Map<String, dynamic>>();
        setState(() {
          _locations = locs;
          _loading = false;
        });

        // Auto-select first (primary) location if none set
        if (autoSelect &&
            locs.isNotEmpty &&
            widget.connection.shopifyLocationId == null) {
          final primary = locs.first;
          final id = primary['id'].toString();
          final name = (primary['name'] as String?) ?? 'Primary';
          await ref
              .read(shopifyConnectionProvider.notifier)
              .updateSettings(
                shopifyLocationId: id,
                shopifyLocationName: name,
              );
        }
      } else {
        setState(() {
          _loading = false;
          _error = result.error ?? 'Failed to fetch locations';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _pickLocation() async {
    if (_locations == null) await _fetchLocations();
    if (_locations == null || _locations!.isEmpty || !mounted) return;

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Text(
                      l10n.shopifySelectLocation,
                      style: AppTypography.h3.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              for (final loc in _locations!)
                ListTile(
                  leading: Icon(
                    Icons.location_on_rounded,
                    color: loc['id'].toString() ==
                            widget.connection.shopifyLocationId
                        ? AppColors.primaryNavy
                        : AppColors.textTertiary,
                  ),
                  title: Text(
                    (loc['name'] as String?) ?? 'Unnamed',
                    style: AppTypography.labelMedium.copyWith(
                      fontWeight: loc['id'].toString() ==
                              widget.connection.shopifyLocationId
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  subtitle: loc['address1'] != null
                      ? Text(
                          loc['address1'] as String,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        )
                      : null,
                  trailing: loc['id'].toString() ==
                          widget.connection.shopifyLocationId
                      ? const Icon(Icons.check_circle_rounded,
                          color: AppColors.primaryNavy, size: 20)
                      : null,
                  onTap: () => Navigator.pop(ctx, loc),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (picked != null && mounted) {
      final id = picked['id'].toString();
      final name = (picked['name'] as String?) ?? 'Unnamed';
      await ref
          .read(shopifyConnectionProvider.notifier)
          .updateSettings(
            shopifyLocationId: id,
            shopifyLocationName: name,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final conn = widget.connection;
    final hasLocation = conn.shopifyLocationId != null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _loading ? null : _pickLocation,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.borderLight.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hasLocation
                      ? AppColors.primaryNavy.withValues(alpha: 0.08)
                      : AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 20,
                  color: hasLocation
                      ? AppColors.primaryNavy
                      : AppColors.warning,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasLocation
                          ? (conn.shopifyLocationName ??
                              l10n.shopifyLocationSet)
                          : l10n.shopifyNoLocationSelected,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasLocation
                          ? l10n.shopifyTapToChangeLocation
                          : l10n.shopifySelectLocationToSync,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _error!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.danger,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryNavy,
                  ),
                )
              else
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
