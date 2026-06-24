import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/bosta_shipments_provider.dart';
import '../../../shared/models/bosta_shipment_model.dart';
import '../../../shared/utils/safe_pop.dart';

/// Bosta shipments list screen.
///
/// Shows all synced Bosta deliveries with filters for
/// settled/pending and matched/unlinked. Supports search by tracking number.
class BostaShipmentsScreen extends ConsumerStatefulWidget {
  const BostaShipmentsScreen({super.key});

  @override
  ConsumerState<BostaShipmentsScreen> createState() =>
      _BostaShipmentsScreenState();
}

class _BostaShipmentsScreenState extends ConsumerState<BostaShipmentsScreen> {
  final _searchCtrl = TextEditingController();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final asyncShipments = ref.watch(bostaShipmentsProvider);
    final stats = ref.watch(bostaShipmentStatsProvider);
    final filter = ref.watch(bostaShipmentFilterProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, l10n),
            if (_showSearch) _buildSearchBar(),
            _buildStatsBar(context, l10n, stats),
            _buildFilterChips(context, l10n, ref, filter),
            Expanded(
              child: asyncShipments.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
                  child: Text(
                    e.toString(),
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.danger),
                  ),
                ),
                data: (shipments) {
                  // Client-side search filter
                  final query = _searchCtrl.text.trim().toLowerCase();
                  final filtered = query.isEmpty
                      ? shipments
                      : shipments
                          .where((s) =>
                              s.trackingNumber.toLowerCase().contains(query) ||
                              (s.businessReference?.toLowerCase().contains(query) ?? false))
                          .toList();

                  if (filtered.isEmpty) {
                    return _buildEmptyState(l10n, isSearch: query.isNotEmpty);
                  }
                  final notifier = ref.read(bostaShipmentsProvider.notifier);
                  return RefreshIndicator(
                    onRefresh: () async =>
                        ref.invalidate(bostaShipmentsProvider),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollEndNotification &&
                            notification.metrics.extentAfter < 200 &&
                            notifier.hasMore &&
                            !notifier.isLoadingMore) {
                          notifier.loadMore();
                        }
                        return false;
                      },
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                        itemCount: filtered.length + (notifier.hasMore && query.isEmpty ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i >= filtered.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          return _ShipmentTile(
                            shipment: filtered[i],
                            searchQuery: query,
                            onTap: () => context.push(
                              AppRoutes.bostaShipmentDetail,
                              extra: {'shipment': filtered[i]},
                            ),
                          )
                              .animate()
                              .fadeIn(
                                duration: 200.ms,
                                delay: (i.clamp(0, 20) * 20).ms,
                              );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            l10n.bostaShipmentsTitle,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchCtrl.clear();
              }
            }),
            icon: Icon(
              _showSearch ? Icons.search_off_rounded : Icons.search_rounded,
              size: 22,
            ),
            color: _showSearch ? _bostaRed : AppColors.primaryNavy,
          ),
          IconButton(
            onPressed: () => context.push(AppRoutes.bostaAudit),
            icon: const Icon(Icons.fact_check_rounded, size: 22),
            color: AppColors.primaryNavy,
            tooltip: l10n.bostaAuditTitle,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: Colors.white,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Search tracking # or order ref…',
          hintStyle: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () => setState(() => _searchCtrl.clear()),
                )
              : null,
          filled: true,
          fillColor: AppColors.backgroundLight,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        style: AppTypography.bodySmall.copyWith(fontSize: 13),
      ),
    );
  }

  Widget _buildStatsBar(
    BuildContext context,
    AppLocalizations l10n,
    BostaShipmentStats stats,
  ) {
    const currency = 'EGP';
    final fmt = NumberFormat('#,##0.00');
    final matchPct = stats.total > 0
        ? (stats.matchedCount / stats.total * 100).toStringAsFixed(0)
        : '0';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      color: Colors.white,
      child: Column(
        children: [
          Row(
            children: [
              _StatChip(
                label: l10n.bostaStatsTotal,
                value: '${stats.total}',
                color: AppColors.primaryNavy,
              ),
              const SizedBox(width: 12),
              _StatChip(
                label: l10n.bostaStatsMatched,
                value: '${stats.matchedCount}',
                color: AppColors.success,
              ),
              const SizedBox(width: 12),
              _StatChip(
                label: l10n.bostaStatsUnlinked,
                value: '${stats.unlinkedCount}',
                color: AppColors.warning,
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    l10n.bostaStatsTotalFees,
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                  Text(
                    '$currency ${fmt.format(stats.totalFees)}',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Match rate progress bar
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: stats.total > 0
                        ? stats.matchedCount / stats.total
                        : 0,
                    minHeight: 4,
                    backgroundColor: AppColors.borderLight,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.success),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$matchPct% matched',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(
    BuildContext context,
    AppLocalizations l10n,
    WidgetRef ref,
    BostaShipmentFilter filter,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterChip(
              label: l10n.bostaFilterAll,
              selected:
                  filter.settledOnly == null && filter.matchedOnly == null,
              onTap: () => ref
                  .read(bostaShipmentFilterProvider.notifier)
                  .reset(),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: l10n.bostaFilterSettled,
              selected: filter.settledOnly == true,
              onTap: () => ref
                  .read(bostaShipmentFilterProvider.notifier)
                  .update(const BostaShipmentFilter(settledOnly: true)),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: l10n.bostaFilterPending,
              selected: filter.settledOnly == false,
              onTap: () => ref
                  .read(bostaShipmentFilterProvider.notifier)
                  .update(const BostaShipmentFilter(settledOnly: false)),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: l10n.bostaFilterMatched,
              selected: filter.matchedOnly == true,
              onTap: () => ref
                  .read(bostaShipmentFilterProvider.notifier)
                  .update(const BostaShipmentFilter(matchedOnly: true)),
            ),
            const SizedBox(width: 8),
            _FilterChip(
              label: l10n.bostaFilterUnlinked,
              selected: filter.matchedOnly == false,
              onTap: () => ref
                  .read(bostaShipmentFilterProvider.notifier)
                  .update(const BostaShipmentFilter(matchedOnly: false)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, {bool isSearch = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSearch ? Icons.search_off_rounded : Icons.local_shipping_outlined,
            size: 64,
            color: AppColors.textTertiary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            isSearch ? 'No matching shipments' : l10n.bostaShipmentsEmpty,
            style: AppTypography.h3.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isSearch
                ? 'Try a different tracking # or order reference'
                : l10n.bostaShipmentsEmptyDesc,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Private widgets
// ══════════════════════════════════════════════════════════════

const _bostaRed = Color(0xFFE2342D);

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
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
          label,
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textTertiary,
            fontSize: 10,
          ),
        ),
        Text(
          value,
          style: AppTypography.labelLarge.copyWith(
            color: color,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _bostaRed : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _bostaRed : AppColors.borderLight,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ShipmentTile extends StatelessWidget {
  final BostaShipment shipment;
  final VoidCallback onTap;
  final String searchQuery;

  const _ShipmentTile({
    required this.shipment,
    required this.onTap,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dateFmt = DateFormat('MMM dd');
    final feeFmt = NumberFormat('#,##0.00');

    final stateColor = _stateColor(shipment.state);
    final hasFees = shipment.totalFees != null && shipment.totalFees! > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                // State badge
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: stateColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _stateIcon(shipment.state),
                    size: 20,
                    color: stateColor,
                  ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _highlightText(
                        shipment.trackingNumber,
                        searchQuery,
                        AppTypography.labelMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: stateColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              shipment.stateValue,
                              style: AppTypography.captionSmall.copyWith(
                                color: stateColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          if (shipment.matched)
                            Icon(Icons.link_rounded,
                                size: 12, color: AppColors.success),
                          if (!shipment.matched)
                            Text(
                              l10n.bostaUnlinked,
                              style: AppTypography.captionSmall.copyWith(
                                color: AppColors.warning,
                                fontSize: 10,
                              ),
                            ),
                          if (shipment.depositedAt != null)
                            Text(
                              dateFmt.format(shipment.depositedAt!),
                              style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Fees
                if (hasFees)
                  Text(
                    'EGP ${feeFmt.format(shipment.totalFees)}',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Text(
                    l10n.bostaPending,
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _highlightText(String text, String query, TextStyle style) {
    if (query.isEmpty) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final idx = lowerText.indexOf(lowerQuery);
    if (idx < 0) {
      return Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return Text.rich(
      TextSpan(children: [
        if (idx > 0) TextSpan(text: text.substring(0, idx), style: style),
        TextSpan(
          text: text.substring(idx, idx + query.length),
          style: style.copyWith(
            backgroundColor: _bostaRed.withValues(alpha: 0.15),
            color: _bostaRed,
          ),
        ),
        if (idx + query.length < text.length)
          TextSpan(text: text.substring(idx + query.length), style: style),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Color _stateColor(int state) {
    return switch (state) {
      45 => AppColors.success,   // Delivered
      60 => AppColors.danger,    // RTO
      46 => AppColors.warning,   // Returned
      _ => AppColors.textSecondary,
    };
  }

  IconData _stateIcon(int state) {
    return switch (state) {
      45 => Icons.check_circle_rounded,   // Delivered
      60 => Icons.undo_rounded,           // RTO
      46 => Icons.assignment_return_rounded, // Returned
      _ => Icons.local_shipping_rounded,
    };
  }
}
