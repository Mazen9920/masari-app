import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/product_model.dart';
import '../../shared/models/production_order_model.dart';
import '../../shared/utils/money_utils.dart';
import '../../l10n/app_localizations.dart';
import 'bom_economics.dart';
import 'manufacturing_widgets.dart';
import 'edit_bom_screen.dart';
import 'production_order_detail_screen.dart';
import 'production_planner_screen.dart';

/// Manufacturing hub — two tabs: Recipes (BOMs) and Production (runs / WIP).
class ManufacturingHubScreen extends ConsumerWidget {
  const ManufacturingHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            l10n.manufacturingTitle,
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          centerTitle: true,
          bottom: TabBar(
            labelColor: AppColors.primaryNavy,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.primaryNavy,
            tabs: [
              Tab(text: l10n.manufacturingRecipesTab),
              Tab(text: l10n.manufacturingProductionTab),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _RecipesTab(),
            _ProductionTab(),
          ],
        ),
      ),
    );
  }
}

// ─── Recipes tab ────────────────────────────────────────────────────────────
class _RecipesTab extends ConsumerStatefulWidget {
  const _RecipesTab();
  @override
  ConsumerState<_RecipesTab> createState() => _RecipesTabState();
}

enum _RecipeSort { margin, cost, name }

enum _RecipeFilter { all, hasRecipe, needsRecipe, belowCost }

class _RecipesTabState extends ConsumerState<_RecipesTab> {
  String _query = '';
  _RecipeSort _sort = _RecipeSort.margin;
  _RecipeFilter _filter = _RecipeFilter.all;
  // Bundles and drafts aren't manufacturable, so hide them by default.
  bool _hideBundles = true;
  bool _hideDrafts = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0.##');
    final allProducts = ref.watch(inventoryProvider).value ?? [];
    // Full non-material list (used to detect "no products at all").
    final finished = allProducts.where((p) => !p.isMaterial).toList();

    if (finished.isEmpty) {
      return _EmptyState(
        icon: Icons.receipt_long_rounded,
        message: l10n.bomProductsEmpty,
      );
    }

    // Hide bundles / drafts (not manufacturable). [allProducts] stays full so
    // material resolution in economics is unaffected.
    final hiddenCount = finished
        .where((p) =>
            (_hideBundles && isShopifyBundle(p)) ||
            (_hideDrafts && p.shopifyStatus == 'draft'))
        .length;
    final visible = finished.where((p) {
      if (_hideBundles && isShopifyBundle(p)) return false;
      if (_hideDrafts && p.shopifyStatus == 'draft') return false;
      return true;
    }).toList();

    // Precompute economics once per product.
    final econOf = <String, BomEconomics?>{
      for (final p in visible)
        p.id: BomEconomics.forProduct(p, allProducts,
            valuationMethod: ref.watch(appSettingsProvider).valuationMethod),
    };

    final q = _query.trim().toLowerCase();
    var items = visible
        .where((p) => q.isEmpty || p.name.toLowerCase().contains(q))
        .toList();

    // Filter.
    items = items.where((p) {
      final e = econOf[p.id];
      switch (_filter) {
        case _RecipeFilter.all:
          return true;
        case _RecipeFilter.hasRecipe:
          return p.hasBom;
        case _RecipeFilter.needsRecipe:
          return !p.hasBom;
        case _RecipeFilter.belowCost:
          return e != null && e.belowCost;
      }
    }).toList();

    // Sort: products without a recipe always sink to the bottom.
    items.sort((a, b) {
      if (a.hasBom != b.hasBom) return a.hasBom ? -1 : 1;
      final ea = econOf[a.id];
      final eb = econOf[b.id];
      switch (_sort) {
        case _RecipeSort.margin:
          return (eb?.marginPct ?? -1e9).compareTo(ea?.marginPct ?? -1e9);
        case _RecipeSort.cost:
          return (ea?.unitCost ?? 1e9).compareTo(eb?.unitCost ?? 1e9);
        case _RecipeSort.name:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    });

    // Summary across visible products that have a BOM and a selling price.
    final econs = visible
        .where((p) => p.hasBom)
        .map((p) => econOf[p.id])
        .whereType<BomEconomics>()
        .where((e) => e.hasSellingPrice)
        .toList();
    final avgMargin = econs.isEmpty
        ? null
        : roundMoney(
            econs.fold<double>(0, (s, e) => s + e.marginPct) / econs.length);
    final recipeCount = visible.where((p) => p.hasBom).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              isDense: true,
              hintText: l10n.mfgSearchProducts,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: AppColors.borderLight.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ),
        // Filter chips
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              MfgChip(
                  label: l10n.mfgFilterAll,
                  selected: _filter == _RecipeFilter.all,
                  onTap: () => setState(() => _filter = _RecipeFilter.all)),
              const SizedBox(width: 8),
              MfgChip(
                  label: l10n.mfgFilterHasRecipe,
                  selected: _filter == _RecipeFilter.hasRecipe,
                  onTap: () =>
                      setState(() => _filter = _RecipeFilter.hasRecipe)),
              const SizedBox(width: 8),
              MfgChip(
                  label: l10n.mfgFilterNeedsRecipe,
                  selected: _filter == _RecipeFilter.needsRecipe,
                  onTap: () =>
                      setState(() => _filter = _RecipeFilter.needsRecipe)),
              const SizedBox(width: 8),
              MfgChip(
                  icon: Icons.trending_down_rounded,
                  label: l10n.mfgFilterBelowCost,
                  selected: _filter == _RecipeFilter.belowCost,
                  onTap: () =>
                      setState(() => _filter = _RecipeFilter.belowCost)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Sort row + summary
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  avgMargin != null
                      ? '$recipeCount ${l10n.mfgRecipes} · ${l10n.mfgAvgMargin} ${avgMargin.toStringAsFixed(0)}%'
                      : '$recipeCount ${l10n.mfgRecipes}',
                  style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600),
                ),
              ),
              _visibilityMenu(l10n, hiddenCount),
              const SizedBox(width: 2),
              Icon(Icons.swap_vert_rounded,
                  size: 15, color: AppColors.textTertiary),
              const SizedBox(width: 2),
              DropdownButton<_RecipeSort>(
                value: _sort,
                isDense: true,
                underline: const SizedBox.shrink(),
                style: AppTypography.captionSmall
                    .copyWith(color: AppColors.textPrimary),
                items: [
                  DropdownMenuItem(
                      value: _RecipeSort.margin,
                      child: Text(l10n.mfgSortMargin)),
                  DropdownMenuItem(
                      value: _RecipeSort.cost, child: Text(l10n.mfgSortCost)),
                  DropdownMenuItem(
                      value: _RecipeSort.name, child: Text(l10n.mfgSortName)),
                ],
                onChanged: (v) =>
                    setState(() => _sort = v ?? _RecipeSort.margin),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _EmptyState(
                  icon: Icons.filter_list_off_rounded,
                  message: l10n.mfgNoResults)
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _ProductBomTile(
                    product: items[i],
                    econ: econOf[items[i].id],
                    currency: currency,
                    fmt: fmt,
                  ),
                ),
        ),
      ],
    );
  }

  /// Popup with per-type visibility toggles for bundles / drafts.
  Widget _visibilityMenu(AppLocalizations l10n, int hiddenCount) {
    final active = _hideBundles || _hideDrafts;
    return PopupMenuButton<String>(
      tooltip: l10n.mfgVisibility,
      position: PopupMenuPosition.under,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) => setState(() {
        if (v == 'bundles') _hideBundles = !_hideBundles;
        if (v == 'drafts') _hideDrafts = !_hideDrafts;
      }),
      itemBuilder: (ctx) => [
        CheckedPopupMenuItem<String>(
          value: 'bundles',
          checked: _hideBundles,
          child: Text(l10n.mfgHideBundles),
        ),
        CheckedPopupMenuItem<String>(
          value: 'drafts',
          checked: _hideDrafts,
          child: Text(l10n.mfgHideDrafts),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
            size: 16,
            color: active ? AppColors.primaryNavy : AppColors.textTertiary,
          ),
          if (active && hiddenCount > 0) ...[
            const SizedBox(width: 2),
            Text('$hiddenCount',
                style: AppTypography.captionSmall.copyWith(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w700,
                    fontSize: 10)),
          ],
        ],
      ),
    );
  }
}

class _ProductBomTile extends StatelessWidget {
  final Product product;
  final BomEconomics? econ;
  final String currency;
  final NumberFormat fmt;
  const _ProductBomTile({
    required this.product,
    required this.econ,
    required this.currency,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final count = product.manufacturingBom?.components.length ?? 0;
    final hasBom = econ != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => EditBomScreen(productId: product.id),
        )),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: product.color.withValues(alpha: 0.12),
                    child: Icon(product.icon, color: product.color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        if (hasBom)
                          Text(
                            '$count ${l10n.mfgMaterialsWord} · '
                            '${l10n.mfgUnitCostShort} $currency ${fmt.format(econ!.unitCost)}',
                            style: AppTypography.captionSmall
                                .copyWith(color: AppColors.textSecondary),
                          )
                        else
                          Text(l10n.defineBom,
                              style: AppTypography.captionSmall
                                  .copyWith(color: AppColors.accentOrange)),
                        if (hasBom && econ!.maxProducible > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${l10n.mfgMaxFromStock}: ${econ!.maxProducible} ${l10n.mfgUnits}',
                            style: AppTypography.captionSmall
                                .copyWith(color: AppColors.textTertiary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (hasBom && econ!.hasSellingPrice)
                    _marginBadge(econ!, l10n)
                  else
                    Icon(
                      hasBom
                          ? Icons.chevron_right_rounded
                          : Icons.add_circle_outline_rounded,
                      color: AppColors.textTertiary,
                    ),
                ],
              ),
              if (hasBom && econ!.unitCost > 0) ...[
                const SizedBox(height: 10),
                CostCompositionBar(
                  materials: econ!.materialsPerUnit,
                  labor: econ!.laborPerUnit,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _marginBadge(BomEconomics e, AppLocalizations l10n) {
    final color = e.belowCost
        ? AppColors.danger
        : e.marginPct >= 40
            ? AppColors.success
            : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('${e.marginPct.toStringAsFixed(0)}%',
              style: AppTypography.labelMedium
                  .copyWith(color: color, fontWeight: FontWeight.w800)),
          Text(l10n.mfgMargin,
              style: AppTypography.captionSmall
                  .copyWith(color: color, fontSize: 9)),
        ],
      ),
    );
  }
}

// ─── Production tab ──────────────────────────────────────────────────────────
class _ProductionTab extends ConsumerStatefulWidget {
  const _ProductionTab();
  @override
  ConsumerState<_ProductionTab> createState() => _ProductionTabState();
}

class _ProductionTabState extends ConsumerState<_ProductionTab> {
  ProductionStatus? _filter; // null = all
  bool _newestFirst = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0.##');
    final ordersAsync = ref.watch(productionOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryNavy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.startProduction),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const ProductionPlannerScreen(),
        )),
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _EmptyState(
          icon: Icons.error_outline_rounded,
          message: '$e',
        ),
        data: (orders) {
          final now = DateTime.now();
          final inProgress = orders.where((o) => o.isInProgress).toList();
          // WIP asset = materials consumed; finishing is the pending (not-yet-
          // incurred) cost shown alongside for the committed-cost picture.
          final matWip = roundMoney(
              inProgress.fold<double>(0, (s, o) => s + o.wipValue));
          final finWip = roundMoney(inProgress.fold<double>(
              0, (s, o) => s + o.pendingFinishingCost));
          final wip = matWip;
          final unitsInProduction =
              inProgress.fold<double>(0, (s, o) => s + o.remainingQty);
          final doneThisMonth = orders.where((o) =>
              o.status == ProductionStatus.completed &&
              o.completedAt != null &&
              o.completedAt!.year == now.year &&
              o.completedAt!.month == now.month);
          final doneUnits =
              doneThisMonth.fold<double>(0, (s, o) => s + o.quantity);
          final doneValue = roundMoney(
              doneThisMonth.fold<double>(0, (s, o) => s + o.totalCost));
          final avgUnitCost =
              doneUnits > 0 ? roundMoney(doneValue / doneUnits) : 0.0;

          final visible = (_filter == null
              ? List<ProductionOrder>.from(orders)
              : orders.where((o) => o.status == _filter).toList())
            ..sort((a, b) => _newestFirst
                ? b.startedAt.compareTo(a.startedAt)
                : a.startedAt.compareTo(b.startedAt));

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              // ── Production overview ──
              _overviewCard(
                context: context,
                l10n: l10n,
                currency: currency,
                fmt: fmt,
                wip: wip,
                materials: matWip,
                finishing: finWip,
                activeRuns: inProgress.length,
                unitsInProduction: unitsInProduction,
              ),
              const SizedBox(height: 10),
              // ── This-month KPIs ──
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      icon: Icons.check_circle_rounded,
                      iconColor: AppColors.success,
                      label: l10n.mfgCompletedUnits,
                      value: fmtQty(doneUnits),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statCard(
                      icon: Icons.payments_rounded,
                      iconColor: AppColors.primaryNavy,
                      label: l10n.mfgThisMonth,
                      value: '$currency ${fmt.format(doneValue)}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statCard(
                      icon: Icons.sell_rounded,
                      iconColor: AppColors.accentOrange,
                      label: l10n.mfgAvgUnitCost,
                      value: '$currency ${fmt.format(avgUnitCost)}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Units-produced trend (last 6 months).
              if (orders.any((o) => o.isCompleted)) ...[
                _unitsTrendCard(context, l10n, orders),
                const SizedBox(height: 16),
              ],
              // Filter chips + sort toggle
              if (orders.isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _filterChip(null, l10n.mfgFilterAll, orders.length),
                            const SizedBox(width: 8),
                            _filterChip(ProductionStatus.inProgress,
                                l10n.statusInProgress, inProgress.length),
                            const SizedBox(width: 8),
                            _filterChip(
                                ProductionStatus.completed,
                                l10n.statusCompleted,
                                orders
                                    .where((o) =>
                                        o.status == ProductionStatus.completed)
                                    .length),
                            const SizedBox(width: 8),
                            _filterChip(
                                ProductionStatus.cancelled,
                                l10n.statusCancelled,
                                orders
                                    .where((o) =>
                                        o.status == ProductionStatus.cancelled)
                                    .length),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: _newestFirst
                          ? l10n.mfgSortNewest
                          : l10n.mfgSortOldest,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _newestFirst
                              ? Icons.south_rounded
                              : Icons.north_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () =>
                            setState(() => _newestFirst = !_newestFirst),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              if (orders.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: _EmptyState(
                    icon: Icons.factory_outlined,
                    message: l10n.noProductionOrders,
                  ),
                )
              else if (visible.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 32),
                  child: _EmptyState(
                    icon: Icons.filter_list_off_rounded,
                    message: l10n.noProductionOrders,
                  ),
                )
              else
                ...visible.map((o) => _ProductionOrderTile(
                      order: o,
                      currency: currency,
                      fmt: fmt,
                    )),
            ],
          );
        },
      ),
    );
  }

  /// Production overview hero: total WIP value, a materials-vs-finishing
  /// composition bar, and headline metrics (active runs, units in production,
  /// finishing owed).
  Widget _overviewCard({
    required BuildContext context,
    required AppLocalizations l10n,
    required String currency,
    required NumberFormat fmt,
    required double wip,
    required double materials,
    required double finishing,
    required int activeRuns,
    required double unitsInProduction,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.precision_manufacturing_rounded,
                    size: 18, color: AppColors.primaryNavy),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.mfgProductionOverview.toUpperCase(),
                        style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            fontSize: 10)),
                    const SizedBox(height: 2),
                    Text('$activeRuns ${l10n.wipActiveRuns}',
                        style: AppTypography.captionSmall
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$currency ${fmt.format(wip)}',
                      style: AppTypography.h2.copyWith(
                          color: AppColors.primaryNavy,
                          fontWeight: FontWeight.w800)),
                  Text(l10n.workInProgress,
                      style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textTertiary, fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          CostCompositionBar(
              materials: materials, labor: finishing, height: 10, showLegend: true),
          const SizedBox(height: 14),
          Divider(height: 1, color: AppColors.borderLight.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  l10n.wipUnitsInProduction,
                  fmtQty(unitsInProduction),
                  AppColors.primaryNavy,
                ),
              ),
              Container(
                  width: 1,
                  height: 28,
                  color: AppColors.borderLight.withValues(alpha: 0.6)),
              Expanded(
                child: _miniStat(
                  l10n.wipFinishingOwed,
                  '$currency ${fmt.format(finishing)}',
                  AppColors.accentOrange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: AppTypography.captionSmall
                .copyWith(color: AppColors.textTertiary, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        Text(value,
            style: AppTypography.labelMedium
                .copyWith(color: color, fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }

  /// Compact bar chart of finished units per month over the last 6 months.
  Widget _unitsTrendCard(
      BuildContext context, AppLocalizations l10n, List<ProductionOrder> orders) {
    final now = DateTime.now();
    final buckets = <DateTime, double>{};
    for (int i = 5; i >= 0; i--) {
      buckets[DateTime(now.year, now.month - i, 1)] = 0;
    }
    for (final o in orders) {
      if (!o.isCompleted || o.completedAt == null) continue;
      final key = DateTime(o.completedAt!.year, o.completedAt!.month, 1);
      if (buckets.containsKey(key)) {
        buckets[key] = buckets[key]! + o.quantity;
      }
    }
    final entries = buckets.entries.toList();
    final maxV = entries.fold<double>(
        1, (m, e) => e.value > m ? e.value : m);
    const chartH = 64.0;
    final monthFmt = DateFormat.MMM();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded,
                  size: 16, color: AppColors.primaryNavy),
              const SizedBox(width: 8),
              Text(l10n.mfgUnitsProduced,
                  style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(l10n.mfgLast6Months,
                  style: AppTypography.captionSmall
                      .copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 0; i < entries.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          entries[i].value > 0
                              ? fmtQty(entries[i].value)
                              : '',
                          style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textSecondary,
                              fontSize: 10,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          height: ((entries[i].value / maxV) * chartH)
                              .clamp(3.0, chartH),
                          decoration: BoxDecoration(
                            color: i == entries.length - 1
                                ? AppColors.accentOrange
                                : AppColors.primaryNavy
                                    .withValues(alpha: 0.85),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5)),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(monthFmt.format(entries[i].key),
                            style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textTertiary, fontSize: 10)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(height: 8),
          Text(label,
              style: AppTypography.captionSmall
                  .copyWith(color: AppColors.textSecondary, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(value,
              style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _filterChip(ProductionStatus? status, String label, int count) {
    final selected = _filter == status;
    return GestureDetector(
      onTap: () => setState(() => _filter = status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryNavy : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? AppColors.primaryNavy
                  : AppColors.borderLight.withValues(alpha: 0.7)),
        ),
        child: Text(
          '$label ($count)',
          style: AppTypography.captionSmall.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ProductionOrderTile extends StatelessWidget {
  final ProductionOrder order;
  final String currency;
  final NumberFormat fmt;
  const _ProductionOrderTile({
    required this.order,
    required this.currency,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (label, color) = switch (order.status) {
      ProductionStatus.inProgress => (l10n.statusInProgress, AppColors.warning),
      ProductionStatus.completed => (l10n.statusCompleted, AppColors.success),
      ProductionStatus.cancelled =>
        (l10n.statusCancelled, AppColors.textTertiary),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        // Left status accent.
        boxShadow: const [],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProductionOrderDetailScreen(orderId: order.id),
        )),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${order.quantity} × ${order.variantName}',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${order.productName} · ${DateFormat.yMMMd().format(order.startedAt)}',
                      style: AppTypography.captionSmall
                          .copyWith(color: AppColors.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (order.isPartiallyReceived) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${order.completedQty} / ${order.quantity} ${l10n.mfgReceived}',
                        style: AppTypography.captionSmall.copyWith(
                            color: AppColors.primaryNavy,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      style: AppTypography.captionSmall.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currency ${fmt.format(order.totalCost)}',
                    style: AppTypography.captionSmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 56, color: AppColors.textTertiary.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
