import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/navigation/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/fixed_asset_model.dart';
import '../../shared/utils/safe_pop.dart';
import 'package:go_router/go_router.dart';

/// Comprehensive Fixed Assets dashboard showing total cost, net book value,
/// accumulated depreciation, all assets, and depreciation breakdown.
class FixedAssetsDashboardScreen extends ConsumerStatefulWidget {
  const FixedAssetsDashboardScreen({super.key});

  @override
  ConsumerState<FixedAssetsDashboardScreen> createState() =>
      _FixedAssetsDashboardScreenState();
}

class _FixedAssetsDashboardScreenState
    extends ConsumerState<FixedAssetsDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _fmt = NumberFormat('#,##0.00', 'en');
  final _dateFmt = DateFormat('MMM d, yyyy');

  // ── Filters ──
  String _statusFilter = 'all'; // all / active / disposed / sold
  String _categoryFilter = 'all'; // all / category name

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Computed helpers ──

  List<FixedAsset> _filtered(List<FixedAsset> all) {
    return all.where((a) {
      if (_statusFilter != 'all' && a.status.name != _statusFilter) return false;
      if (_categoryFilter != 'all' && a.category.name != _categoryFilter) return false;
      return true;
    }).toList();
  }

  double _totalCost(List<FixedAsset> assets) =>
      assets.fold(0.0, (s, a) => s + a.purchasePrice);

  double _totalNBV(List<FixedAsset> assets) =>
      assets.fold(0.0, (s, a) => s + a.netBookValue);

  double _totalAccDep(List<FixedAsset> assets) =>
      assets.fold(0.0, (s, a) => s + a.accumulatedDepreciation);

  double _totalMonthlyDep(List<FixedAsset> assets) =>
      assets.where((a) => a.status == FixedAssetStatus.active).fold(0.0, (s, a) => s + a.monthlyDepreciation);

  Map<FixedAssetCategory, List<FixedAsset>> _byCategory(List<FixedAsset> assets) {
    final map = <FixedAssetCategory, List<FixedAsset>>{};
    for (final a in assets) {
      map.putIfAbsent(a.category, () => []).add(a);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(fixedAssetsProvider);
    final settings = ref.watch(appSettingsProvider);
    final currency = settings.currency;
    final activeAssets = assets.where((a) => a.status == FixedAssetStatus.active).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppColors.primaryNavy,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 20),
              onPressed: () => context.safePop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                onPressed: () => context.push(AppRoutes.addFixedAsset),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1B4F72), Color(0xFF2E86C1)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 56, 24, 60),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fixed Assets',
                            style: AppTypography.metricSmall
                                .copyWith(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          '$currency ${_fmt.format(_totalNBV(activeAssets))}',
                          style: AppTypography.metric
                              .copyWith(color: Colors.white, fontSize: 28),
                        ),
                        const SizedBox(height: 2),
                        Text('Net Book Value',
                            style: AppTypography.caption
                                .copyWith(color: Colors.white60)),
                        const Spacer(),
                        Row(
                          children: [
                            _heroStat('Total Cost',
                                '$currency ${_fmt.format(_totalCost(activeAssets))}'),
                            const SizedBox(width: 24),
                            _heroStat('Accum. Depr.',
                                '$currency ${_fmt.format(_totalAccDep(activeAssets))}'),
                            const SizedBox(width: 24),
                            _heroStat('Assets', '${activeAssets.length}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelStyle: AppTypography.labelMedium,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Assets'),
                Tab(text: 'Depreciation'),
                Tab(text: 'History'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(assets, activeAssets, currency),
            _buildAssetsTab(assets, currency),
            _buildDepreciationTab(activeAssets, currency),
            _buildHistoryTab(assets, currency),
          ],
        ),
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTypography.caption.copyWith(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: AppTypography.labelMedium.copyWith(color: Colors.white, fontSize: 13)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 1: OVERVIEW
  // ═══════════════════════════════════════════════════════

  Widget _buildOverviewTab(
      List<FixedAsset> all, List<FixedAsset> active, String currency) {
    final disposed = all.where((a) => a.status != FixedAssetStatus.active).toList();
    final catBreakdown = _byCategory(active);
    final monthlyDep = _totalMonthlyDep(active);
    final annualDep = monthlyDep * 12;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // KPI Cards
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                'Total Assets',
                '${all.length}',
                Icons.business_center_rounded,
                AppColors.chartBlue,
                subtitle: '${active.length} active · ${disposed.length} disposed/sold',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                'Monthly Depr.',
                '$currency ${_fmt.format(monthlyDep)}',
                Icons.trending_down_rounded,
                AppColors.chartOrange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _kpiCard(
                'Annual Depr.',
                '$currency ${_fmt.format(annualDep)}',
                Icons.calendar_month_rounded,
                AppColors.chartRed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Category breakdown
        _sectionTitle('By Category'),
        const SizedBox(height: 8),
        if (catBreakdown.isEmpty)
          _emptyState('No active assets yet')
        else
          ...catBreakdown.entries.map((e) {
            final catAssets = e.value;
            final catNBV = _totalNBV(catAssets);
            final catCost = _totalCost(catAssets);
            final pct = catCost > 0 ? catNBV / catCost : 0.0;
            return _categoryRow(
              '${e.key.icon} ${e.key.label}',
              '${catAssets.length} assets',
              '$currency ${_fmt.format(catNBV)}',
              pct,
            );
          }),

        const SizedBox(height: 20),

        // Depreciation health
        _sectionTitle('Depreciation Health'),
        const SizedBox(height: 8),
        ..._buildDepreciationHealth(active, currency),
      ].animate(interval: 50.ms).fadeIn(duration: 300.ms).slideY(begin: 0.02),
    );
  }

  List<Widget> _buildDepreciationHealth(List<FixedAsset> active, String currency) {
    final fullyDepreciated = active.where((a) => a.isFullyDepreciated).length;
    final nearEnd = active.where((a) => !a.isFullyDepreciated && a.remainingLifeMonths <= 6).length;
    final healthy = active.length - fullyDepreciated - nearEnd;

    return [
      _healthRow(Icons.check_circle_rounded, AppColors.chartGreen,
          'Healthy', '$healthy assets', 'More than 6 months remaining'),
      _healthRow(Icons.warning_rounded, AppColors.chartOrange,
          'Near End of Life', '$nearEnd assets', '6 months or less remaining'),
      _healthRow(Icons.cancel_rounded, AppColors.chartRed,
          'Fully Depreciated', '$fullyDepreciated assets', 'Zero remaining value'),
    ];
  }

  Widget _healthRow(IconData icon, Color color, String label, String count, String sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.labelMedium),
                Text(sub,
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
          Text(count,
              style: AppTypography.labelMedium.copyWith(color: color)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 2: ASSETS LIST
  // ═══════════════════════════════════════════════════════

  Widget _buildAssetsTab(List<FixedAsset> all, String currency) {
    final filtered = _filtered(all);

    return Column(
      children: [
        // Filter bar
        _buildAssetFilters(all),
        // Count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text('${filtered.length} asset${filtered.length == 1 ? '' : 's'}',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textTertiary)),
              const Spacer(),
              if (_statusFilter != 'all' || _categoryFilter != 'all')
                GestureDetector(
                  onTap: () => setState(() {
                    _statusFilter = 'all';
                    _categoryFilter = 'all';
                  }),
                  child: Text('Clear',
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.chartBlue, fontSize: 12)),
                ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _emptyState('No assets match filters')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) =>
                      _assetTile(filtered[i], currency),
                ),
        ),
      ],
    );
  }

  Widget _buildAssetFilters(List<FixedAsset> all) {
    final categories = all.map((a) => a.category).toSet().toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          // Status chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', _statusFilter == 'all',
                    () => setState(() => _statusFilter = 'all')),
                _filterChip('Active', _statusFilter == 'active',
                    () => setState(() => _statusFilter = 'active')),
                _filterChip('Disposed', _statusFilter == 'disposed',
                    () => setState(() => _statusFilter = 'disposed')),
                _filterChip('Sold', _statusFilter == 'sold',
                    () => setState(() => _statusFilter = 'sold')),
                _filterChip('Impaired', _statusFilter == 'impaired',
                    () => setState(() => _statusFilter = 'impaired')),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Category chips
          if (categories.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('All Categories', _categoryFilter == 'all',
                      () => setState(() => _categoryFilter = 'all')),
                  ...categories.map((c) => _filterChip(
                      '${c.icon} ${c.label}',
                      _categoryFilter == c.name,
                      () => setState(() => _categoryFilter = c.name))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _assetTile(FixedAsset asset, String currency) {
    final depPct = asset.purchasePrice > 0
        ? asset.accumulatedDepreciation / asset.purchasePrice
        : 0.0;

    return GestureDetector(
      onTap: () => _showAssetDetail(asset, currency),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _categoryColor(asset.category).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(asset.category.icon, style: const TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(asset.name,
                          style: AppTypography.labelMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${asset.category.label} · ${_dateFmt.format(asset.purchaseDate)}',
                              style: AppTypography.caption
                                  .copyWith(color: AppColors.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (asset.status != FixedAssetStatus.active) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: asset.status == FixedAssetStatus.sold
                                    ? AppColors.chartOrange.withValues(alpha: 0.12)
                                    : AppColors.chartRed.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(asset.status.label,
                                  style: AppTypography.caption.copyWith(
                                    color: asset.status == FixedAssetStatus.sold
                                        ? AppColors.chartOrange
                                        : AppColors.chartRed,
                                    fontSize: 10,
                                  )),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$currency ${_fmt.format(asset.netBookValue)}',
                        style: AppTypography.labelMedium),
                    Text('NBV',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textTertiary, fontSize: 10)),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textTertiary),
              ],
            ),
            const SizedBox(height: 10),
            // Depreciation progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: depPct.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: Colors.grey.shade100,
                valueColor: AlwaysStoppedAnimation(
                  asset.isFullyDepreciated
                      ? AppColors.chartRed
                      : asset.remainingLifeMonths <= 6
                          ? AppColors.chartOrange
                          : AppColors.chartGreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 3: DEPRECIATION
  // ═══════════════════════════════════════════════════════

  Widget _buildDepreciationTab(List<FixedAsset> active, String currency) {
    final monthlyDep = _totalMonthlyDep(active);

    // Build next-12-months depreciation schedule
    final schedule = <_MonthDep>[];
    final now = DateTime.now();
    for (int i = 0; i < 12; i++) {
      final month = DateTime(now.year, now.month + i, 1);
      double dep = 0;
      for (final a in active) {
        if (a.isFullyDepreciated) continue;
        final monthsFromPurchase = (month.year - a.purchaseDate.year) * 12 +
            (month.month - a.purchaseDate.month);
        if (monthsFromPurchase >= 0 && monthsFromPurchase < a.usefulLifeMonths) {
          dep += a.monthlyDepreciation;
        }
      }
      schedule.add(_MonthDep(month: month, amount: dep));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // Summary card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Depreciation Summary',
                  style: AppTypography.labelMedium.copyWith(fontSize: 15)),
              const SizedBox(height: 12),
              _depSummaryRow('Total Cost', _totalCost(active), currency,
                  AppColors.chartBlue),
              _depSummaryRow('Accumulated Depreciation', _totalAccDep(active),
                  currency, AppColors.chartOrange),
              _depSummaryRow('Net Book Value', _totalNBV(active), currency,
                  AppColors.chartGreen),
              const Divider(height: 20),
              _depSummaryRow('Monthly Expense', monthlyDep, currency,
                  AppColors.chartRed),
              _depSummaryRow(
                  'Annual Expense', monthlyDep * 12, currency, AppColors.chartRed),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 12-month schedule
        _sectionTitle('12-Month Schedule'),
        const SizedBox(height: 8),
        ...schedule.map((m) => _scheduleRow(m, currency)),

        const SizedBox(height: 20),

        // Per-asset depreciation
        _sectionTitle('Per-Asset Breakdown'),
        const SizedBox(height: 8),
        if (active.isEmpty)
          _emptyState('No active assets')
        else
          ...active.map((a) => _assetDepRow(a, currency)),
      ].animate(interval: 40.ms).fadeIn(duration: 300.ms),
    );
  }

  Widget _depSummaryRow(String label, double amount, String currency, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
          ),
          Text('$currency ${_fmt.format(amount)}',
              style: AppTypography.labelMedium),
        ],
      ),
    );
  }

  Widget _scheduleRow(_MonthDep m, String currency) {
    final monthFmt = DateFormat('MMM yyyy');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today_rounded,
              size: 16, color: AppColors.chartOrange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(monthFmt.format(m.month),
                style: AppTypography.bodyMedium),
          ),
          Text('$currency ${_fmt.format(m.amount)}',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.chartOrange)),
        ],
      ),
    );
  }

  Widget _assetDepRow(FixedAsset a, String currency) {
    final pct = a.purchasePrice > 0
        ? a.accumulatedDepreciation / a.purchasePrice
        : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(a.category.icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(a.name,
                    style: AppTypography.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Text('${(pct * 100).toStringAsFixed(0)}%',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniStat('Cost', '$currency ${_fmt.format(a.purchasePrice)}'),
              _miniStat('Accum.', '$currency ${_fmt.format(a.accumulatedDepreciation)}'),
              _miniStat('NBV', '$currency ${_fmt.format(a.netBookValue)}'),
              _miniStat('Mo. Dep.', '$currency ${_fmt.format(a.monthlyDepreciation)}'),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation(
                a.isFullyDepreciated
                    ? AppColors.chartRed
                    : a.remainingLifeMonths <= 6
                        ? AppColors.chartOrange
                        : AppColors.chartGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTypography.caption
                  .copyWith(color: AppColors.textTertiary, fontSize: 10)),
          Text(value,
              style: AppTypography.caption.copyWith(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 4: HISTORY
  // ═══════════════════════════════════════════════════════

  Widget _buildHistoryTab(List<FixedAsset> all, String currency) {
    // Sort by date — most recent first
    final sorted = List<FixedAsset>.from(all)
      ..sort((a, b) => b.purchaseDate.compareTo(a.purchaseDate));

    // Group by month
    final grouped = <String, List<FixedAsset>>{};
    final monthFmt = DateFormat('MMMM yyyy');
    for (final a in sorted) {
      final key = monthFmt.format(a.purchaseDate);
      grouped.putIfAbsent(key, () => []).add(a);
    }

    if (sorted.isEmpty) {
      return _emptyState('No assets recorded yet');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(entry.key,
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.textTertiary, fontSize: 13)),
          ),
          ...entry.value.map((a) => _historyTile(a, currency)),
          const SizedBox(height: 8),
        ],
      ].animate(interval: 40.ms).fadeIn(duration: 300.ms),
    );
  }

  Widget _historyTile(FixedAsset asset, String currency) {
    return GestureDetector(
      onTap: () => _showAssetDetail(asset, currency),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.chartBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(asset.category.icon, style: const TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(asset.name,
                      style: AppTypography.labelMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    'Purchased ${_dateFmt.format(asset.purchaseDate)}',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$currency ${_fmt.format(asset.purchasePrice)}',
                    style: AppTypography.labelMedium),
                Text('Cost',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary, fontSize: 10)),
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

  // ═══════════════════════════════════════════════════════
  // DETAIL BOTTOM SHEET
  // ═══════════════════════════════════════════════════════

  void _showAssetDetail(FixedAsset asset, String currency) {
    final depPct = asset.purchasePrice > 0
        ? (asset.accumulatedDepreciation / asset.purchasePrice * 100)
        : 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _categoryColor(asset.category).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(asset.category.icon,
                          style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(asset.name,
                            style: AppTypography.metricSmall.copyWith(fontSize: 17)),
                        Text(asset.category.label,
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                  _statusBadge(asset.status),
                ],
              ),
              const SizedBox(height: 20),

              // Depreciation visual
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Depreciation',
                            style: AppTypography.labelMedium),
                        Text('${depPct.toStringAsFixed(1)}%',
                            style: AppTypography.labelMedium
                                .copyWith(color: AppColors.chartOrange)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (depPct / 100).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(
                          asset.isFullyDepreciated
                              ? AppColors.chartRed
                              : asset.remainingLifeMonths <= 6
                                  ? AppColors.chartOrange
                                  : AppColors.chartGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _depDetail('Cost', '$currency ${_fmt.format(asset.purchasePrice)}'),
                        _depDetail('Accum.', '$currency ${_fmt.format(asset.accumulatedDepreciation)}'),
                        _depDetail('NBV', '$currency ${_fmt.format(asset.netBookValue)}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Details grid
              _detailRow('Purchase Date', _dateFmt.format(asset.purchaseDate)),
              _detailRow('Useful Life', '${asset.usefulLifeMonths} months (${(asset.usefulLifeMonths / 12).toStringAsFixed(1)} years)'),
              _detailRow('Remaining Life', '${asset.remainingLifeMonths} months'),
              _detailRow('Depreciation Method', asset.depreciationMethod.label),
              _detailRow('Salvage Value', '$currency ${_fmt.format(asset.salvageValue)}'),
              _detailRow('Monthly Depreciation', '$currency ${_fmt.format(asset.monthlyDepreciation)}'),
              if (asset.description != null && asset.description!.isNotEmpty)
                _detailRow('Description', asset.description!),
              if (asset.notes != null && asset.notes!.isNotEmpty)
                _detailRow('Notes', asset.notes!),
              if (asset.disposalDate != null)
                _detailRow('Disposal Date', _dateFmt.format(asset.disposalDate!)),
              if (asset.disposalPrice != null)
                _detailRow('Disposal Price', '$currency ${_fmt.format(asset.disposalPrice!)}'),
              if (asset.status == FixedAssetStatus.sold && asset.disposalPrice != null)
                _detailRow(
                  asset.disposalGainLoss >= 0 ? 'Gain on Sale' : 'Loss on Sale',
                  '$currency ${_fmt.format(asset.disposalGainLoss.abs())}',
                ),
              if (asset.impairmentLoss > 0)
                _detailRow('Impairment Loss', '$currency ${_fmt.format(asset.impairmentLoss)}'),

              const SizedBox(height: 16),

              // Asset action buttons (for active / impaired assets)
              if (asset.status == FixedAssetStatus.active ||
                  asset.status == FixedAssetStatus.impaired) ...[
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showSellSheet(asset, currency);
                        },
                        icon: const Icon(Icons.sell_rounded, size: 16),
                        label: const Text('Sell'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.chartGreen,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showDisposeSheet(asset, currency);
                        },
                        icon: const Icon(Icons.delete_forever_rounded, size: 16),
                        label: const Text('Write Off'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.chartRed,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showImpairmentSheet(asset, currency);
                    },
                    icon: const Icon(Icons.warning_amber_rounded, size: 16),
                    label: const Text('Record Impairment / Partial Damage'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.chartOrange,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 10),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        context.push(AppRoutes.editFixedAsset,
                            extra: {'asset': asset});
                      },
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Edit'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryNavy,
                        side: BorderSide(color: AppColors.primaryNavy.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmDelete(ctx, asset),
                      icon: const Icon(Icons.delete_rounded, size: 18),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.chartRed,
                        side: BorderSide(color: AppColors.chartRed.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),

              // Event history
              if (asset.events.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Event History',
                    style: AppTypography.labelMedium.copyWith(fontSize: 13)),
                const SizedBox(height: 8),
                ...asset.events.reversed.map((e) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Text(e.type.icon, style: const TextStyle(fontSize: 14)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${e.type.label} · ${_dateFmt.format(e.date)}',
                                    style: AppTypography.bodyMedium),
                                if (e.note != null && e.note!.isNotEmpty)
                                  Text(e.note!,
                                      style: AppTypography.caption.copyWith(
                                          color: AppColors.textTertiary,
                                          fontSize: 10)),
                              ],
                            ),
                          ),
                          Text('$currency ${_fmt.format(e.amount)}',
                              style: AppTypography.labelMedium.copyWith(
                                  color: e.type == AssetEventType.sale
                                      ? AppColors.chartGreen
                                      : AppColors.chartRed,
                                  fontSize: 12)),
                        ],
                      ),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext sheetCtx, FixedAsset asset) {
    showDialog(
      context: sheetCtx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Delete Asset'),
        content: Text('Are you sure you want to delete "${asset.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dCtx);
              Navigator.pop(sheetCtx);
              await ref.read(fixedAssetsProvider.notifier).remove(asset.id);
            },
            child: Text('Delete',
                style: TextStyle(color: AppColors.chartRed)),
          ),
        ],
      ),
    );
  }

  // ── Sell sheet ─────────────────────────────────────────

  void _showSellSheet(FixedAsset asset, String currency) {
    final priceCtrl = TextEditingController(
        text: asset.netBookValue.toStringAsFixed(2));
    final noteCtrl = TextEditingController();
    DateTime saleDate = DateTime.now();
    final dateFmt = DateFormat('MMM d, yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Sell Asset',
                    style: AppTypography.metricSmall.copyWith(fontSize: 17)),
                Text(
                    '${asset.name} · NBV: $currency ${_fmt.format(asset.netBookValue)}',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary)),
                const SizedBox(height: 16),

                Text('Sale Price',
                    style: AppTypography.labelMedium.copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    filled: true,
                    fillColor: const Color(0xFFF8F9FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),

                Text('Sale Date',
                    style: AppTypography.labelMedium.copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: saleDate,
                      firstDate: asset.purchaseDate,
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setSheetState(() => saleDate = d);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(dateFmt.format(saleDate),
                              style: AppTypography.bodyMedium),
                        ),
                        const Icon(Icons.calendar_today_rounded,
                            size: 18, color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Text('Note (optional)',
                    style: AppTypography.labelMedium.copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    hintText: 'Sale note',
                    filled: true,
                    fillColor: const Color(0xFFF8F9FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final price =
                          double.tryParse(priceCtrl.text.trim()) ?? 0;
                      if (price < 0) return;
                      await ref
                          .read(fixedAssetsProvider.notifier)
                          .sellAsset(
                            asset.id,
                            price,
                            saleDate,
                            noteCtrl.text.trim().isEmpty
                                ? null
                                : noteCtrl.text.trim(),
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.chartGreen,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Confirm Sale'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Dispose / Write Off sheet ──────────────────────────

  void _showDisposeSheet(FixedAsset asset, String currency) {
    final noteCtrl = TextEditingController();
    DateTime dispDate = DateTime.now();
    final dateFmt = DateFormat('MMM d, yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Write Off / Dispose Asset',
                    style: AppTypography.metricSmall.copyWith(fontSize: 17)),
                Text(
                    '${asset.name} · NBV: $currency ${_fmt.format(asset.netBookValue)}',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.chartRed.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_rounded,
                          size: 18, color: AppColors.chartRed),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This will write off the remaining book value of $currency ${_fmt.format(asset.netBookValue)} as a loss.',
                          style: AppTypography.caption.copyWith(
                              color: AppColors.chartRed, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Text('Disposal Date',
                    style: AppTypography.labelMedium.copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: dispDate,
                      firstDate: asset.purchaseDate,
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setSheetState(() => dispDate = d);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(dateFmt.format(dispDate),
                              style: AppTypography.bodyMedium),
                        ),
                        const Icon(Icons.calendar_today_rounded,
                            size: 18, color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Text('Reason (optional)',
                    style: AppTypography.labelMedium.copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. Fully damaged, scrapped',
                    filled: true,
                    fillColor: const Color(0xFFF8F9FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await ref
                          .read(fixedAssetsProvider.notifier)
                          .disposeAsset(
                            asset.id,
                            dispDate,
                            noteCtrl.text.trim().isEmpty
                                ? null
                                : noteCtrl.text.trim(),
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.chartRed,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Confirm Write Off'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Impairment / Partial Damage sheet ──────────────────

  void _showImpairmentSheet(FixedAsset asset, String currency) {
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime impDate = DateTime.now();
    final dateFmt = DateFormat('MMM d, yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Record Impairment',
                    style: AppTypography.metricSmall.copyWith(fontSize: 17)),
                Text(
                    '${asset.name} · NBV: $currency ${_fmt.format(asset.netBookValue)}',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary)),
                if (asset.impairmentLoss > 0)
                  Text(
                      'Previous impairments: $currency ${_fmt.format(asset.impairmentLoss)}',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.chartOrange, fontSize: 11)),
                const SizedBox(height: 16),

                Text('Impairment Amount',
                    style: AppTypography.labelMedium.copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: amtCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    filled: true,
                    fillColor: const Color(0xFFF8F9FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),

                Text('Date',
                    style: AppTypography.labelMedium.copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: impDate,
                      firstDate: asset.purchaseDate,
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setSheetState(() => impDate = d);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(dateFmt.format(impDate),
                              style: AppTypography.bodyMedium),
                        ),
                        const Icon(Icons.calendar_today_rounded,
                            size: 18, color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Text('Description',
                    style: AppTypography.labelMedium.copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    hintText: 'e.g. Water damage to motor',
                    filled: true,
                    fillColor: const Color(0xFFF8F9FA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      final amt =
                          double.tryParse(amtCtrl.text.trim()) ?? 0;
                      if (amt <= 0) return;
                      if (amt > asset.netBookValue) return;
                      await ref
                          .read(fixedAssetsProvider.notifier)
                          .recordImpairment(
                            asset.id,
                            amt,
                            impDate,
                            noteCtrl.text.trim().isEmpty
                                ? null
                                : noteCtrl.text.trim(),
                          );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.chartOrange,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Record Impairment'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _depDetail(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: AppTypography.labelMedium.copyWith(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label,
              style: AppTypography.caption
                  .copyWith(color: AppColors.textTertiary, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: AppTypography.caption
                    .copyWith(color: AppColors.textTertiary)),
          ),
          Expanded(
            child: Text(value, style: AppTypography.bodyMedium),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(FixedAssetStatus status) {
    final Color color;
    switch (status) {
      case FixedAssetStatus.active:
        color = AppColors.chartGreen;
      case FixedAssetStatus.disposed:
        color = AppColors.chartRed;
      case FixedAssetStatus.sold:
        color = AppColors.chartOrange;
      case FixedAssetStatus.impaired:
        color = AppColors.chartPurple;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(status.label,
          style: AppTypography.caption.copyWith(color: color, fontSize: 11)),
    );
  }

  // ═══════════════════════════════════════════════════════
  // SHARED WIDGETS
  // ═══════════════════════════════════════════════════════

  Widget _kpiCard(String title, String value, IconData icon, Color color,
      {String? subtitle}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
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
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary)),
                const SizedBox(height: 2),
                Text(value,
                    style: AppTypography.metricSmall.copyWith(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textTertiary, fontSize: 10)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(title,
        style: AppTypography.labelMedium
            .copyWith(color: AppColors.textSecondary, fontSize: 13));
  }

  Widget _categoryRow(String label, String count, String value, double pct) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTypography.labelMedium),
                    Text(count,
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              Text(value, style: AppTypography.labelMedium),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: Colors.grey.shade100,
              valueColor: const AlwaysStoppedAnimation(AppColors.chartBlue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryNavy : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppColors.primaryNavy
                  : Colors.grey.shade300,
            ),
          ),
          child: Text(label,
              style: AppTypography.caption.copyWith(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontSize: 12,
              )),
        ),
      ),
    );
  }

  Widget _emptyState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            Icon(Icons.business_center_outlined,
                size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(msg,
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }

  Color _categoryColor(FixedAssetCategory cat) {
    switch (cat) {
      case FixedAssetCategory.equipment:
        return AppColors.chartBlue;
      case FixedAssetCategory.furniture:
        return AppColors.chartOrange;
      case FixedAssetCategory.vehicle:
        return AppColors.chartGreen;
      case FixedAssetCategory.computer:
        return AppColors.chartPurple;
      case FixedAssetCategory.machinery:
        return AppColors.chartRed;
      case FixedAssetCategory.building:
        return AppColors.primaryNavy;
      case FixedAssetCategory.land:
        return const Color(0xFF059669);
      case FixedAssetCategory.other:
        return Colors.grey;
    }
  }
}

class _MonthDep {
  final DateTime month;
  final double amount;
  const _MonthDep({required this.month, required this.amount});
}
