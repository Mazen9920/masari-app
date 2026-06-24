import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../providers/shopify_sync_provider.dart';
import '../../../shared/utils/safe_pop.dart';
import '../../../l10n/app_localizations.dart';

/// Import Shopify orders screen.
///
/// - Date range picker (max 3 months back)
/// - Preview: "Found 47 orders to import"
/// - "Import" button with progress bar
/// - Shows import results: X imported, Y skipped, Z errors
class ShopifyImportScreen extends ConsumerStatefulWidget {
  const ShopifyImportScreen({super.key});

  @override
  ConsumerState<ShopifyImportScreen> createState() =>
      _ShopifyImportScreenState();
}

class _ShopifyImportScreenState extends ConsumerState<ShopifyImportScreen> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;
  late DateTime _fromDate;
  late DateTime _toDate;

  /// Tracks elapsed time for the ETA calculation.
  DateTime? _importStartedAt;

  @override
  void initState() {
    super.initState();
    _toDate = DateTime.now();
    _fromDate = _toDate.subtract(const Duration(days: 30));
  }

  @override
  Widget build(BuildContext context) {
    final syncStatus = ref.watch(shopifySyncProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hero
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.primaryNavy.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.download_rounded,
                          size: 30,
                          color: AppColors.primaryNavy,
                        ),
                      ),
                    ).animate().fadeIn(duration: 250.ms),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                         l10n.shopifyImportTitle,
                        style: AppTypography.h2.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ).animate().fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                         l10n.shopifyImportSubtitle,
                        textAlign: TextAlign.center,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ).animate().fadeIn(duration: 250.ms, delay: 100.ms),

                    const SizedBox(height: 32),

                    // Date range section
                    Text(
                      l10n.dateRangeSection,
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _DatePickerTile(
                            label: l10n.from,
                            date: _fromDate,
                            onTap: syncStatus.isSyncing
                                ? null
                                : () => _pickDate(isFrom: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _DatePickerTile(
                            label: l10n.to,
                            date: _toDate,
                            onTap: syncStatus.isSyncing
                                ? null
                                : () => _pickDate(isFrom: false),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(duration: 250.ms, delay: 150.ms),

                    const SizedBox(height: 12),
                    _RangeInfo(from: _fromDate, to: _toDate),

                    const SizedBox(height: 24),

                    // ── Live progress panel ───────────────
                    if (syncStatus.isSyncing)
                      _ImportProgressPanel(
                        status: syncStatus,
                        startedAt: _importStartedAt,
                      ),

                    // ── Result banner ─────────────────────
                    if (syncStatus.phase == SyncPhase.success ||
                        syncStatus.phase == SyncPhase.error) ...[
                      _ResultBanner(status: syncStatus),
                      const SizedBox(height: 16),
                    ],

                    const SizedBox(height: 8),

                    // Import button
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: syncStatus.isSyncing ? null : _onImport,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: syncStatus.isSyncing
                                ? AppColors.textTertiary
                                : AppColors.primaryNavy,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: syncStatus.isSyncing
                                ? null
                                : [
                                    BoxShadow(
                                      color: AppColors.primaryNavy
                                          .withValues(alpha: 0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Center(
                            child: syncStatus.isSyncing
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Importing…',
                                        style:
                                            AppTypography.labelMedium.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.download_rounded,
                                          color: Colors.white, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.importOrders,
                                        style:
                                            AppTypography.labelLarge.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ).animate().fadeIn(duration: 250.ms, delay: 200.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            l10n.importOrders,
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

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primaryNavy,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
      } else {
        _toDate = picked;
        if (_fromDate.isAfter(_toDate)) _fromDate = _toDate;
      }
    });
  }

  void _onImport() {
    HapticFeedback.mediumImpact();
    setState(() => _importStartedAt = DateTime.now());
    ref.read(shopifySyncProvider.notifier).importHistorical(
          from: _fromDate,
          to: _toDate,
        );
  }
}

// ═══════════════════════════════════════════════════════════
//  PRIVATE WIDGETS
// ═══════════════════════════════════════════════════════════

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback? onTap;

  const _DatePickerTile({
    required this.label,
    required this.date,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM dd, yyyy');

    return GestureDetector(
      onTap: onTap != null
          ? () {
              HapticFeedback.lightImpact();
              onTap!();
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
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
            Text(
              label,
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 16, color: AppColors.primaryNavy),
                const SizedBox(width: 8),
                Text(
                  fmt.format(date),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RangeInfo extends StatelessWidget {
  final DateTime from;
  final DateTime to;

  const _RangeInfo({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    final days = to.difference(from).inDays;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.primaryNavy),
          const SizedBox(width: 8),
          Text(
             AppLocalizations.of(context)!.shopifyRangeDays(days),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultBanner extends StatelessWidget {
  final SyncStatus status;

  const _ResultBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isError = status.phase == SyncPhase.error;
    final fmtNum = NumberFormat('#,###', 'en');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError
            ? AppColors.danger.withValues(alpha: 0.06)
            : AppColors.success.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isError
              ? AppColors.danger.withValues(alpha: 0.2)
              : AppColors.success.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 24,
                color: isError ? AppColors.danger : AppColors.success,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isError ? l10n.shopifyImportFailed : l10n.importComplete,
                  style: AppTypography.labelMedium.copyWith(
                    color: isError ? AppColors.danger : AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (!isError && status.importTotal > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                _ResultStat(
                  label: 'Imported',
                  value: fmtNum.format(status.importImported),
                  color: AppColors.success,
                ),
                const SizedBox(width: 16),
                _ResultStat(
                  label: 'Skipped',
                  value: fmtNum.format(status.importSkipped),
                  color: AppColors.textTertiary,
                ),
                if (status.importErrors > 0) ...[
                  const SizedBox(width: 16),
                  _ResultStat(
                    label: 'Errors',
                    value: fmtNum.format(status.importErrors),
                    color: AppColors.danger,
                  ),
                ],
              ],
            ),
          ],
          if (isError && status.errorDetail != null) ...[
            const SizedBox(height: 8),
            Text(
              status.errorDetail!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1);
  }
}

// ═══════════════════════════════════════════════════════════
//  LIVE PROGRESS PANEL
// ═══════════════════════════════════════════════════════════

class _ImportProgressPanel extends StatelessWidget {
  final SyncStatus status;
  final DateTime? startedAt;

  const _ImportProgressPanel({required this.status, this.startedAt});

  @override
  Widget build(BuildContext context) {
    final total = status.importTotal;
    final processed = status.importProcessed;
    final progress = total > 0 ? processed / total : 0.0;
    final fmtNum = NumberFormat('#,###', 'en');

    // ETA calculation
    String? eta;
    if (startedAt != null && processed > 0 && total > processed) {
      final elapsed = DateTime.now().difference(startedAt!);
      final msPerOrder = elapsed.inMilliseconds / processed;
      final remaining = ((total - processed) * msPerOrder / 1000).round();
      if (remaining > 60) {
        eta = '~${(remaining / 60).ceil()} min left';
      } else if (remaining > 0) {
        eta = '~${remaining}s left';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phase label + ETA
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.secondaryBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status.importPhase ?? 'Working…',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (eta != null)
                Text(
                  eta,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),

          if (total > 0) ...[
            const SizedBox(height: 16),

            // Counter: "142 / 1,204 orders"
            Row(
              children: [
                Text(
                  fmtNum.format(processed),
                  style: AppTypography.h2.copyWith(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                  ),
                ),
                Text(
                  ' / ${fmtNum.format(total)}',
                  style: AppTypography.h3.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'orders',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: AppColors.borderLight.withValues(alpha: 0.5),
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.secondaryBlue),
              ),
            ),

            const SizedBox(height: 4),

            // Percentage
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${(progress * 100).toStringAsFixed(1)}%',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Breakdown row: Imported | Skipped | Errors
            Row(
              children: [
                _CounterChip(
                  label: 'Imported',
                  count: status.importImported,
                  color: AppColors.success,
                ),
                const SizedBox(width: 8),
                _CounterChip(
                  label: 'Skipped',
                  count: status.importSkipped,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 8),
                if (status.importErrors > 0)
                  _CounterChip(
                    label: 'Errors',
                    count: status.importErrors,
                    color: AppColors.danger,
                  ),
              ],
            ),

            // Current order
            if (status.currentOrder != null) ...[
              const SizedBox(height: 10),
              Text(
                'Current: ${status.currentOrder}',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ],
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}

class _CounterChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CounterChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _ResultStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: AppTypography.h3.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        Text(
          label,
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textTertiary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
