import 'dart:async';
import 'dart:developer' as dev;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/bosta_connection_provider.dart';
import '../../../shared/models/bosta_connection_model.dart';
import '../../../shared/utils/safe_pop.dart';

/// Bosta shipping integration settings screen.
///
/// - Not connected: enter API key → "Connect to Bosta"
/// - Connected: status card, sync controls, actions
class BostaConnectScreen extends ConsumerStatefulWidget {
  const BostaConnectScreen({super.key});

  @override
  ConsumerState<BostaConnectScreen> createState() => _BostaConnectScreenState();
}

class _BostaConnectScreenState extends ConsumerState<BostaConnectScreen> {
  final _apiKeyController = TextEditingController();
  final _businessIdController = TextEditingController();
  bool _isConnecting = false;
  bool _isSyncing = false;
  bool _obscureKey = true;

  AppLocalizations get l10n => AppLocalizations.of(context)!;

  @override
  void dispose() {
    _apiKeyController.dispose();
    _businessIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncConn = ref.watch(bostaConnectionProvider);
    dev.log('build: asyncConn isLoading=${asyncConn.isLoading} hasValue=${asyncConn.hasValue} hasError=${asyncConn.hasError} value=${asyncConn.value?.status}', name: 'BostaUI');

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: asyncConn.when(
                loading: () {
                  final prev = asyncConn.value;
                  if (prev != null && prev.isActive) {
                    return _buildConnectedView(prev);
                  }
                  return const Center(child: CircularProgressIndicator());
                },
                error: (e, _) {
                  final prev = asyncConn.value;
                  if (prev != null && prev.isActive) {
                    return _buildConnectedView(prev);
                  }
                  return _buildConnectForm();
                },
                data: (conn) {
                  if (conn == null || conn.isDisconnected) {
                    return _buildConnectForm();
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
            color: AppColors.borderLight.withValues(alpha: 0.5),
          ),
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
            l10n.bostaTitle,
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

  // ── Not-connected: API key form ─────────────────────────

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
                  colors: [Color(0xFFE2342D), Color(0xFFC41E1A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE2342D).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_shipping_rounded,
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
            l10n.bostaConnectTitle,
            style: AppTypography.h2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 100.ms),
          const SizedBox(height: 10),
          Text(
            l10n.bostaConnectSubtitle,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 150.ms),
          const SizedBox(height: 36),

          // API key field
          _buildTextField(
            controller: _apiKeyController,
            label: l10n.bostaApiKeyLabel,
            hint: l10n.bostaApiKeyHint,
            obscure: _obscureKey,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureKey
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
              onPressed: () => setState(() => _obscureKey = !_obscureKey),
            ),
          ).animate().fadeIn(duration: 250.ms, delay: 200.ms),
          const SizedBox(height: 14),

          // Business ID field (optional)
          _buildTextField(
            controller: _businessIdController,
            label: l10n.bostaBusinessIdLabel,
            hint: l10n.bostaBusinessIdHint,
          ).animate().fadeIn(duration: 250.ms, delay: 250.ms),
          const SizedBox(height: 28),

          // Connect button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isConnecting ? null : _handleConnect,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE2342D),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 4,
                shadowColor: const Color(0xFFE2342D).withValues(alpha: 0.3),
              ),
              child: _isConnecting
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(l10n.bostaConnecting),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_shipping_rounded, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          l10n.bostaConnectButton,
                          style: AppTypography.labelLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ).animate().fadeIn(duration: 300.ms, delay: 300.ms),

          const SizedBox(height: 36),

          // Info cards
          _InfoCard(
            icon: Icons.security_rounded,
            title: l10n.bostaInfoSecureKey,
            description: l10n.bostaInfoSecureKeyDesc,
          ).animate().fadeIn(duration: 250.ms, delay: 400.ms),
          const SizedBox(height: 10),
          _InfoCard(
            icon: Icons.auto_awesome_rounded,
            title: l10n.bostaInfoAutoExpense,
            description: l10n.bostaInfoAutoExpenseDesc,
          ).animate().fadeIn(duration: 250.ms, delay: 450.ms),
          const SizedBox(height: 10),
          _InfoCard(
            icon: Icons.link_rounded,
            title: l10n.bostaInfoSaleMatching,
            description: l10n.bostaInfoSaleMatchingDesc,
          ).animate().fadeIn(duration: 250.ms, delay: 500.ms),
          const SizedBox(height: 10),
          _InfoCard(
            icon: Icons.link_off_rounded,
            title: l10n.bostaInfoDisconnect,
            description: l10n.bostaInfoDisconnectDesc,
          ).animate().fadeIn(duration: 250.ms, delay: 550.ms),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: AppTypography.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTypography.bodyMedium.copyWith(
              color: AppColors.textTertiary,
            ),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: suffixIcon,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.borderLight),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.borderLight),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFFE2342D), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleConnect() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) return;

    dev.log('_handleConnect: starting with key length=${apiKey.length}', name: 'BostaUI');
    setState(() => _isConnecting = true);
    try {
      final result = await ref.read(bostaConnectionProvider.notifier).connect(
            apiKey: apiKey,
            businessId: _businessIdController.text.trim().isEmpty
                ? null
                : _businessIdController.text.trim(),
          );
      dev.log('_handleConnect: result.isSuccess=${result.isSuccess} error=${result.error}', name: 'BostaUI');
      if (!mounted) return;
      setState(() => _isConnecting = false);

      if (!result.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? l10n.bostaConnectionError),
            backgroundColor: AppColors.danger,
          ),
        );
      } else {
        dev.log('_handleConnect: success! current state=${ref.read(bostaConnectionProvider).value?.status}', name: 'BostaUI');
      }
    } catch (e, st) {
      dev.log('_handleConnect: UNCAUGHT EXCEPTION: $e\n$st', name: 'BostaUI');
      if (!mounted) return;
      setState(() => _isConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // ── Connected view ──────────────────────────────────────

  Widget _buildConnectedView(BostaConnection conn) {
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

          // Sync progress indicator (shows during active sync)
          if (_isSyncing && conn.syncProgress != null && !conn.syncProgress!.isDone)
            _SyncProgressBar(progress: conn.syncProgress!)
                .animate()
                .fadeIn(duration: 200.ms),

          const SizedBox(height: 20),

          // Connection info
          _sectionLabel(l10n.bostaSectionConnection),
          const SizedBox(height: 10),
          _DetailCard(children: [
            _DetailRow(
              label: l10n.bostaStatus,
              value: conn.isActive
                  ? l10n.bostaConnected
                  : conn.hasError
                      ? l10n.bostaConnectionError
                      : l10n.bostaNotConnected,
              icon: Icons.circle,
              valueColor: conn.isActive ? AppColors.success : AppColors.danger,
            ),
            _DetailRow(
              label: l10n.bostaConnectedSince,
              value: dateFmt.format(conn.connectedAt),
              icon: Icons.calendar_today_rounded,
            ),
            if (conn.lastSyncAt != null)
              _DetailRow(
                label: l10n.bostaLastSync,
                value: _timeAgo(conn.lastSyncAt!),
                icon: Icons.sync_rounded,
              ),
          ]).animate().fadeIn(duration: 250.ms, delay: 60.ms),
          const SizedBox(height: 20),

          // Sync section
          _sectionLabel(l10n.bostaSectionSync),
          const SizedBox(height: 10),
          _DetailCard(children: [
            _AutoSyncRow(
              label: l10n.bostaAutoSync,
              subtitle: l10n.bostaAutoSyncDesc,
              enabled: conn.autoSyncEnabled,
              onChanged: (val) => ref
                  .read(bostaConnectionProvider.notifier)
                  .updateAutoSync(val),
            ),
          ]).animate().fadeIn(duration: 250.ms, delay: 120.ms),
          const SizedBox(height: 20),

          // Actions
          _sectionLabel(l10n.bostaSectionActions),
          const SizedBox(height: 10),
          _ActionButton(
            icon: Icons.sync_rounded,
            label: l10n.bostaSyncNow,
            subtitle: l10n.bostaSyncNowDesc,
            isLoading: _isSyncing,
            onTap: _isSyncing ? null : () => _showSyncPeriodSheet(),
          ).animate().fadeIn(duration: 250.ms, delay: 160.ms),
          const SizedBox(height: 8),
          _ActionButton(
            icon: Icons.list_alt_rounded,
            label: l10n.bostaViewShipments,
            subtitle: l10n.bostaViewShipmentsDesc,
            onTap: () => context.push(AppRoutes.bostaShipments),
          ).animate().fadeIn(duration: 250.ms, delay: 200.ms),

          const SizedBox(height: 32),

          // Disconnect button
          Center(
            child: TextButton.icon(
              onPressed: () => _confirmDisconnect(),
              icon: const Icon(Icons.link_off_rounded, size: 18),
              label: Text(l10n.bostaDisconnectButton),
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

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.captionSmall.copyWith(
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        fontSize: 11,
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _handleSync({
    required bool fullSync,
    String? dateFrom,
    String? dateTo,
  }) async {
    setState(() => _isSyncing = true);
    final result = await ref
        .read(bostaConnectionProvider.notifier)
        .triggerSync(
          fullSync: fullSync,
          dateFrom: dateFrom,
          dateTo: dateTo,
        );
    if (!mounted) return;
    setState(() => _isSyncing = false);

    final data = result.data;
    final isComplete = data?['complete'] == true;
    final cataloged = (data?['cataloged'] as num?)?.toInt() ?? 0;
    final newExpenses = (data?['newExpenses'] as num?)?.toInt() ?? 0;
    final totalChecked = (data?['totalChecked'] as num?)?.toInt() ?? 0;

    final String message;
    if (result.isSuccess) {
      if (isComplete) {
        message = '$totalChecked checked · $cataloged cataloged · $newExpenses new expenses';
      } else {
        message = l10n.bostaSyncSuccess;
      }
    } else {
      message = result.error ?? l10n.bostaSyncFailed;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            result.isSuccess ? AppColors.success : AppColors.danger,
      ),
    );
  }

  void _showSyncPeriodSheet() {
    final now = DateTime.now();
    final fmt = DateFormat('yyyy-MM-dd');

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.bostaSyncPeriod,
                  style: AppTypography.h3.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _PeriodOption(
                  icon: Icons.schedule_rounded,
                  label: l10n.bostaSyncLast7Days,
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleSync(
                      fullSync: false,
                      dateFrom: fmt.format(now.subtract(const Duration(days: 7))),
                    );
                  },
                ),
                _PeriodOption(
                  icon: Icons.date_range_rounded,
                  label: l10n.bostaSyncLast30Days,
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleSync(
                      fullSync: false,
                      dateFrom: fmt.format(now.subtract(const Duration(days: 30))),
                    );
                  },
                ),
                _PeriodOption(
                  icon: Icons.calendar_month_rounded,
                  label: l10n.bostaSyncLast3Months,
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleSync(
                      fullSync: false,
                      dateFrom: fmt.format(DateTime(now.year, now.month - 3, now.day)),
                    );
                  },
                ),
                _PeriodOption(
                  icon: Icons.cloud_sync_rounded,
                  label: l10n.bostaSyncAllTime,
                  onTap: () {
                    Navigator.pop(ctx);
                    _handleSync(fullSync: true);
                  },
                ),
                const Divider(height: 1),
                _PeriodOption(
                  icon: Icons.edit_calendar_rounded,
                  label: l10n.bostaSyncCustomRange,
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickCustomRange();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: now.subtract(const Duration(days: 30)),
        end: now,
      ),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: AppColors.primaryNavy,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;

    final fmt = DateFormat('yyyy-MM-dd');
    _handleSync(
      fullSync: false,
      dateFrom: fmt.format(picked.start),
      dateTo: fmt.format(picked.end),
    );
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.bostaDisconnectConfirmTitle),
        content: Text(l10n.bostaDisconnectConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(l10n.bostaDisconnectButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(bostaConnectionProvider.notifier).disconnect();
  }
}

// ══════════════════════════════════════════════════════════════
// Private widget components
// ══════════════════════════════════════════════════════════════

const _bostaRed = Color(0xFFE2342D);

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
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _bostaRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: _bostaRed),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
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
  final BostaConnection connection;

  const _StatusCard({required this.connection});

  @override
  Widget build(BuildContext context) {
    final isActive = connection.isActive;
    final color = isActive ? AppColors.success : AppColors.danger;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              isActive
                  ? Icons.check_circle_rounded
                  : Icons.error_rounded,
              color: color,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? l10n.bostaConnected : l10n.bostaConnectionError,
                  style: AppTypography.labelLarge.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (connection.lastSyncResult != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _syncSummary(connection.lastSyncResult!),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _syncSummary(Map<String, dynamic> result) {
    final checked = result['totalChecked'] ?? 0;
    final expenses = result['newExpenses'] ?? 0;
    final cataloged = result['cataloged'] ?? 0;
    final complete = result['complete'] == true;
    final parts = <String>[];
    if (checked > 0) parts.add('$checked checked');
    if (cataloged > 0) parts.add('$cataloged cataloged');
    if (expenses > 0) parts.add('$expenses expenses');
    if (!complete) parts.add('partial');
    return parts.isEmpty ? 'No data' : parts.join(' · ');
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
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AppColors.borderLight.withValues(alpha: 0.5),
              ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: AppTypography.labelSmall.copyWith(
              color: valueColor ?? AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoSyncRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _AutoSyncRow({
    required this.label,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
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
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: enabled,
            onChanged: onChanged,
            activeTrackColor: _bostaRed,
          ),
        ],
      ),
    );
  }
}

class _PeriodOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PeriodOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, size: 22, color: AppColors.textSecondary),
      title: Text(label, style: AppTypography.bodyMedium),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: AppColors.textTertiary,
      ),
      onTap: onTap,
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.borderLight.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _bostaRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _bostaRed,
                        ),
                      )
                    : Icon(icon, size: 18, color: _bostaRed),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.labelMedium.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
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

class _SyncProgressBar extends StatefulWidget {
  final BostaSyncProgress progress;

  const _SyncProgressBar({required this.progress});

  @override
  State<_SyncProgressBar> createState() => _SyncProgressBarState();
}

class _SyncProgressBarState extends State<_SyncProgressBar> {
  late final Stopwatch _stopwatch;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _stopwatch = Stopwatch()..start();
    // Tick every second to update elapsed time
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final progress = widget.progress;

    final phaseLabel = switch (progress.phase) {
      'catalog' => l10n.bostaSyncPhaseCatalog,
      'settlement' => l10n.bostaSyncPhaseSettlement,
      'stats' => l10n.bostaSyncPhaseStats,
      _ => l10n.bostaSyncing,
    };

    // Compute elapsed from server data or local stopwatch
    final elapsed = progress.elapsedMs > 0
        ? Duration(milliseconds: progress.elapsedMs)
        : _stopwatch.elapsed;

    final estRemaining = progress.estimatedSecondsRemaining;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _bostaRed.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _bostaRed.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _bostaRed,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  phaseLabel,
                  style: AppTypography.labelSmall.copyWith(
                    color: _bostaRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // Elapsed timer
              Text(
                _formatDuration(elapsed),
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [const FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.progressPercent > 0
                  ? progress.progressPercent
                  : null,
              backgroundColor: _bostaRed.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(_bostaRed),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (progress.isSettlement && progress.settlementTotal > 0)
                Text(
                  '${progress.settlementDone}/${progress.settlementTotal} shipments',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                )
              else if (progress.processedCount > 0)
                Text(
                  '${progress.processedCount} checked',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                )
              else
                const SizedBox.shrink(),
              if (estRemaining > 0)
                Text(
                  '~${_formatDuration(Duration(seconds: estRemaining))} remaining',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                    fontFeatures: [const FontFeature.tabularFigures()],
                  ),
                ),
              if (progress.newExpenses > 0)
                Text(
                  '${progress.newExpenses} expenses',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.success,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
