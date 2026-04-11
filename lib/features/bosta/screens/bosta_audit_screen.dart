import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/bosta_audit_provider.dart';
import '../../../core/providers/bosta_connection_provider.dart';
import '../../../shared/models/bosta_shipment_model.dart';
import '../../../shared/utils/safe_pop.dart';
import '../../reports/widgets/financial_period_sheet.dart';

/// Standalone Bosta Accrual Audit screen.
///
/// Shows a summary dashboard (total estimates, adjustments, net actual,
/// running average) plus a per-shipment audit list with filter chips.
class BostaAuditScreen extends ConsumerStatefulWidget {
  const BostaAuditScreen({super.key});

  @override
  ConsumerState<BostaAuditScreen> createState() => _BostaAuditScreenState();
}

class _BostaAuditScreenState extends ConsumerState<BostaAuditScreen> {
  BostaAuditFilter _filter = BostaAuditFilter.all;
  FinancialPeriodResult? _period;
  BostaAuditSort _sort = BostaAuditSort.fulfillment;
  bool _isSyncing = false;
  Timer? _countdownTimer;
  Duration _timeUntilSync = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateCountdown();
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateCountdown(),
    );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    final now = DateTime.now().toUtc();
    // Next sync at 21:59 UTC (11:59 PM Egypt)
    var next = DateTime.utc(now.year, now.month, now.day, 21, 59);
    if (now.isAfter(next)) {
      next = next.add(const Duration(days: 1));
    }
    setState(() => _timeUntilSync = next.difference(now));
  }

  Future<void> _triggerSync() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    HapticFeedback.mediumImpact();
    try {
      final result = await ref
          .read(bostaConnectionProvider.notifier)
          .triggerSync();
      if (mounted) {
        ref.invalidate(bostaAuditStatsProvider);
        ref.invalidate(bostaAuditListProvider(_filter));
        final isSuccess = result.isSuccess;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isSuccess ? 'Sync complete' : 'Sync failed'),
            backgroundColor:
                isSuccess ? AppColors.success : AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final asyncStats = ref.watch(bostaAuditStatsProvider);
    final asyncList = ref.watch(bostaAuditListProvider(_filter));

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, l10n),
            _buildSyncBar(l10n),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(bostaAuditStatsProvider);
                  ref.invalidate(bostaAuditListProvider(_filter));
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Period Label ──
                      if (_period != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GestureDetector(
                            onTap: () => setState(() => _period = null),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.accentOrange
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.accentOrange
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _period!.label,
                                    style: AppTypography.labelSmall.copyWith(
                                      color: AppColors.accentOrange,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(Icons.close_rounded,
                                      size: 14,
                                      color: AppColors.accentOrange),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // ── Summary Dashboard ──
                      asyncStats.when(
                        loading: () => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        error: (e, _) => Text('Error: $e'),
                        data: (stats) => _buildDashboard(l10n, stats),
                      ),
                      const SizedBox(height: 24),

                      // ── Filter Chips ──
                      _buildFilterChips(l10n),
                      const SizedBox(height: 10),

                      // ── Sort Chips ──
                      _buildSortChips(l10n),
                      const SizedBox(height: 16),

                      // ── Per-Shipment List ──
                      asyncList.when(
                        loading: () => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        error: (e, _) => Text('Error: $e'),
                        data: (shipments) =>
                            _buildShipmentList(context, l10n, shipments),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
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
            l10n.bostaAuditTitle,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () async {
              HapticFeedback.selectionClick();
              final result = await showFinancialPeriodSheet(
                context,
                current: _period,
              );
              if (result != null) {
                setState(() => _period = result);
              }
            },
            icon: Icon(
              _period != null
                  ? Icons.date_range_rounded
                  : Icons.calendar_month_rounded,
              size: 22,
            ),
            color: _period != null
                ? AppColors.accentOrange
                : AppColors.primaryNavy,
          ),
        ],
      ),
    );
  }

  // ── Sync Bar ────────────────────────────────────────────

  Widget _buildSyncBar(AppLocalizations l10n) {
    final conn = ref.watch(bostaConnectionProvider).value;
    final lastSync = conn?.lastSyncAt;
    final hours = _timeUntilSync.inHours;
    final minutes = _timeUntilSync.inMinutes.remainder(60);
    final seconds = _timeUntilSync.inSeconds.remainder(60);
    final countdown =
        '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy.withValues(alpha: 0.03),
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderLight.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          // Left: Last sync + countdown
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lastSync != null)
                  Text(
                    '${l10n.bostaLastSync}: ${DateFormat('MMM dd, hh:mm a').format(lastSync.toLocal())}',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 9,
                    ),
                  ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '${l10n.bostaNextSync}: $countdown',
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Right: Sync Now button
          SizedBox(
            height: 32,
            child: FilledButton.icon(
              onPressed: _isSyncing ? null : _triggerSync,
              icon: _isSyncing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync_rounded, size: 14),
              label: Text(
                _isSyncing ? l10n.bostaSyncing : l10n.bostaSyncNow,
                style: const TextStyle(fontSize: 11),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dashboard ───────────────────────────────────────────

  Widget _buildDashboard(AppLocalizations l10n, BostaAuditStats stats) {
    final feeFmt = NumberFormat('#,##0.00');
    return Column(
      children: [
        // 2×2 stat grid
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: l10n.bostaTotalEstimates,
                value: 'EGP ${feeFmt.format(stats.totalEstimates)}',
                icon: Icons.calculate_rounded,
                color: const Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: l10n.bostaTotalAdjustments,
                value: 'EGP ${feeFmt.format(stats.totalAdjustments)}',
                icon: Icons.swap_vert_rounded,
                color: stats.totalAdjustments >= 0
                    ? AppColors.success
                    : AppColors.danger,
              ),
            ),
          ],
        ).animate().fadeIn(duration: 250.ms),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: l10n.bostaNetActual,
                value: 'EGP ${feeFmt.format(stats.netActual)}',
                icon: Icons.account_balance_wallet_rounded,
                color: AppColors.primaryNavy,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: l10n.bostaRunningAverage,
                value: 'EGP ${feeFmt.format(stats.runningAverage)}',
                icon: Icons.trending_up_rounded,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ).animate().fadeIn(duration: 250.ms, delay: 60.ms),
        const SizedBox(height: 16),

        // Count indicators
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              _CountIndicator(
                label: l10n.bostaFullyReconciled,
                count: stats.reconciledCount,
                color: AppColors.success,
              ),
              const SizedBox(width: 8),
              _CountIndicator(
                label: l10n.bostaEstimateOnly,
                count: stats.estimateOnlyCount,
                color: const Color(0xFF3B82F6),
              ),
              const SizedBox(width: 8),
              _CountIndicator(
                label: l10n.bostaPendingEstimate,
                count: stats.pendingEstimateCount,
                color: AppColors.warning,
              ),
            ],
          ),
        ).animate().fadeIn(duration: 250.ms, delay: 120.ms),
      ],
    );
  }

  // ── Filter Chips ────────────────────────────────────────

  Widget _buildFilterChips(AppLocalizations l10n) {
    final filters = [
      (BostaAuditFilter.all, l10n.bostaFilterAll),
      (BostaAuditFilter.reconciled, l10n.bostaFilterReconciled),
      (BostaAuditFilter.estimateOnly, l10n.bostaFilterEstimateOnly),
      (BostaAuditFilter.pending, l10n.bostaPending),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (filter, label) in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filter = filter),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: _filter == filter
                        ? AppColors.primaryNavy
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _filter == filter
                          ? AppColors.primaryNavy
                          : AppColors.borderLight,
                    ),
                  ),
                  child: Text(
                    label,
                    style: AppTypography.captionSmall.copyWith(
                      color: _filter == filter
                          ? Colors.white
                          : AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Sort Chips ────────────────────────────────────────

  Widget _buildSortChips(AppLocalizations l10n) {
    final sorts = [
      (BostaAuditSort.fulfillment, l10n.bostaSortFulfillment),
      (BostaAuditSort.settlement, l10n.bostaSortSettlement),
      (BostaAuditSort.adjustment, l10n.bostaSortAdjustment),
    ];
    return Row(
      children: [
        Icon(Icons.sort_rounded, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        for (final (sort, label) in sorts)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () => setState(() => _sort = sort),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _sort == sort
                      ? AppColors.primaryNavy.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _sort == sort
                        ? AppColors.primaryNavy.withValues(alpha: 0.3)
                        : AppColors.borderLight.withValues(alpha: 0.5),
                  ),
                ),
                child: Text(
                  label,
                  style: AppTypography.captionSmall.copyWith(
                    color: _sort == sort
                        ? AppColors.primaryNavy
                        : AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Per-Shipment List ───────────────────────────────────

  Widget _buildShipmentList(
    BuildContext context,
    AppLocalizations l10n,
    List<BostaShipment> shipments,
  ) {
    // Apply date range filter (client-side)
    var filtered = shipments;
    if (_period != null) {
      final range = _period!.range;
      filtered = shipments.where((s) {
        final date = s.bostaCreatedAt ?? s.syncedAt;
        if (date == null) return false;
        return !date.isBefore(range.start) && !date.isAfter(range.end);
      }).toList();
    }

    // Apply sort
    switch (_sort) {
      case BostaAuditSort.fulfillment:
        filtered.sort((a, b) {
          final da = a.bostaCreatedAt ?? a.syncedAt;
          final db = b.bostaCreatedAt ?? b.syncedAt;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
      case BostaAuditSort.settlement:
        filtered.sort((a, b) {
          final da = a.depositedAt;
          final db = b.depositedAt;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
      case BostaAuditSort.adjustment:
        filtered.sort((a, b) {
          final adjA = _adjustmentAbs(a);
          final adjB = _adjustmentAbs(b);
          return adjB.compareTo(adjA); // largest adjustment first
        });
    }

    if (filtered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Text(
            l10n.bostaShipmentsEmpty,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < filtered.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _AuditShipmentTile(
              shipment: filtered[i],
              onTap: () => context.push(
                AppRoutes.bostaShipmentDetail,
                extra: {'shipment': filtered[i]},
              ),
            ).animate().fadeIn(
                  duration: 200.ms,
                  delay: (i.clamp(0, 20) * 20).ms,
                ),
          ),
      ],
    );
  }

  double _adjustmentAbs(BostaShipment s) {
    final est = s.estimatedFee ?? 0;
    final act = s.totalFees;
    if (act == null || act <= 0) return 0;
    return (act - est).abs();
  }
}

// ══════════════════════════════════════════════════════════════
// Private widgets
// ══════════════════════════════════════════════════════════════

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CountIndicator extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountIndicator({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$count',
                style: AppTypography.labelSmall.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _AuditShipmentTile extends StatelessWidget {
  final BostaShipment shipment;
  final VoidCallback onTap;

  const _AuditShipmentTile({required this.shipment, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final feeFmt = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('MMM dd');

    final estimated = shipment.estimatedFee ?? 0;
    final actual = shipment.totalFees;
    final hasActual = actual != null && actual > 0;
    final adjustment = hasActual ? (actual - estimated) : 0.0;

    final stateColor = _stateColor(shipment.state);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.borderLight.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            // State badge
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: stateColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_stateIcon(shipment.state),
                  size: 18, color: stateColor),
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shipment.trackingNumber,
                    style: AppTypography.labelSmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      // Fulfillment date
                      if (shipment.bostaCreatedAt != null) ...[
                        Icon(Icons.calendar_today_rounded,
                            size: 10, color: AppColors.textTertiary),
                        const SizedBox(width: 3),
                        Text(
                          dateFmt.format(shipment.bostaCreatedAt!),
                          style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Status badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: shipment.isReconciled
                              ? AppColors.success.withValues(alpha: 0.1)
                              : shipment.estimateRecorded
                                  ? const Color(0xFF3B82F6)
                                      .withValues(alpha: 0.1)
                                  : AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          shipment.isReconciled
                              ? '✓'
                              : shipment.estimateRecorded
                                  ? 'Est.'
                                  : '?',
                          style: AppTypography.captionSmall.copyWith(
                            color: shipment.isReconciled
                                ? AppColors.success
                                : shipment.estimateRecorded
                                    ? const Color(0xFF3B82F6)
                                    : AppColors.warning,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Fee columns
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Estimated
                Text(
                  estimated > 0 ? feeFmt.format(estimated) : '-',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                ),
                // Actual
                Text(
                  hasActual ? feeFmt.format(actual) : '-',
                  style: AppTypography.labelSmall.copyWith(
                    color: hasActual
                        ? AppColors.textPrimary
                        : AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // Adjustment
                if (hasActual)
                  Text(
                    adjustment.abs() < 0.01
                        ? '±0'
                        : '${adjustment > 0 ? '+' : ''}${feeFmt.format(adjustment)}',
                    style: AppTypography.captionSmall.copyWith(
                      color: adjustment.abs() < 0.01
                          ? AppColors.textTertiary
                          : adjustment > 0
                              ? AppColors.danger
                              : AppColors.success,
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  static Color _stateColor(int state) {
    return switch (state) {
      45 => AppColors.success,
      60 => AppColors.danger,
      46 => AppColors.warning,
      _ => AppColors.textTertiary,
    };
  }

  static IconData _stateIcon(int state) {
    return switch (state) {
      45 => Icons.check_circle_rounded,
      60 => Icons.undo_rounded,
      46 => Icons.assignment_return_rounded,
      _ => Icons.local_shipping_rounded,
    };
  }
}
