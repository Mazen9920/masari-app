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
  final _maxRange = const Duration(days: 90);

  @override
  void initState() {
    super.initState();
    _toDate = DateTime.now();
    _fromDate = _toDate.subtract(const Duration(days: 30));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                         'Import Shopify Orders',
                        style: AppTypography.h2.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ).animate().fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                         'Import historical orders from your Shopify store.\nMaximum 3 months back.',
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
                    SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _DatePickerTile(
                            label: l10n.from,
                            date: _fromDate,
                            onTap: () => _pickDate(isFrom: true),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _DatePickerTile(
                            label: l10n.to,
                            date: _toDate,
                            onTap: () => _pickDate(isFrom: false),
                          ),
                        ),
                      ],
                    ).animate().fadeIn(duration: 250.ms, delay: 150.ms),

                    const SizedBox(height: 12),
                    _RangeInfo(from: _fromDate, to: _toDate),

                    const SizedBox(height: 32),

                    // Import button
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: syncStatus.isSyncing
                            ? null
                            : _onImport,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
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
                                        child:
                                            CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        syncStatus.message ??
                                            'Importing…',
                                        style: AppTypography
                                            .labelMedium
                                            .copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                          Icons.download_rounded,
                                          color: Colors.white,
                                          size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.importOrders,
                                        style: AppTypography
                                            .labelLarge
                                            .copyWith(
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

                    // Progress bar
                    if (syncStatus.isSyncing) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: syncStatus.progress,
                          minHeight: 6,
                          backgroundColor:
                              AppColors.borderLight.withValues(alpha: 0.5),
                          valueColor:
                              const AlwaysStoppedAnimation(
                                  AppColors.secondaryBlue),
                        ),
                      ),
                    ],

                    // Result message
                    if (syncStatus.phase == SyncPhase.success ||
                        syncStatus.phase == SyncPhase.error) ...[
                      const SizedBox(height: 20),
                      _ResultBanner(status: syncStatus),
                    ],
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
      final l10n = AppLocalizations.of(context)!;
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
    final earliest =
        DateTime.now().subtract(_maxRange);
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: earliest,
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
        // Ensure to is not before from
        if (_toDate.isBefore(_fromDate)) {
          _toDate = _fromDate;
        }
        // Ensure range doesn't exceed 3 months
        if (_toDate.difference(_fromDate) > _maxRange) {
          _toDate = _fromDate.add(_maxRange);
        }
      } else {
        _toDate = picked;
        if (_fromDate.isAfter(_toDate)) {
          _fromDate = _toDate;
        }
        if (_toDate.difference(_fromDate) > _maxRange) {
          _fromDate = _toDate.subtract(_maxRange);
        }
      }
    });
  }

  void _onImport() {
    HapticFeedback.mediumImpact();
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
  final VoidCallback onTap;

  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat( 'MMM dd, yyyy');

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
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
                Icon(Icons.calendar_today_rounded,
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
          Icon(Icons.info_outline_rounded,
              size: 16, color: AppColors.primaryNavy),
          const SizedBox(width: 8),
          Text(
             'Range: $days day${days == 1 ? '' : 's'}',
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
      child: Row(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isError ? 'Import Failed' : l10n.importComplete,
                  style: AppTypography.labelMedium.copyWith(
                    color: isError ? AppColors.danger : AppColors.success,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status.message ?? status.errorDetail ?? '',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1);
  }
}
