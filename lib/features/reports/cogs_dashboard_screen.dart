import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/repository_providers.dart';
import '../../shared/models/sale_model.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/product_model.dart';
import '../../shared/utils/money_utils.dart';
import '../../l10n/app_localizations.dart';
import '../sales/widgets/edit_cogs_dialog.dart';
import 'cogs_analytics.dart';
import 'widgets/financial_period_sheet.dart';

/// COGS analysis dashboard — makes sure cost of goods sold is 100% recorded,
/// accurate and correct. Surfaces orders missing COGS, items missing cost, cost
/// price changes, the COGS ledger, a sales-vs-ledger reconciliation, and a
/// period summary with by-product breakdown.
class CogsDashboardScreen extends ConsumerStatefulWidget {
  const CogsDashboardScreen({super.key});

  @override
  ConsumerState<CogsDashboardScreen> createState() =>
      _CogsDashboardScreenState();
}

class _CogsDashboardScreenState extends ConsumerState<CogsDashboardScreen> {
  bool _loadingAll = true;
  // Period-scoped data fetched directly (one range query each) — fast, and it
  // never touches the shared transactions/sales providers. Integrity checks are
  // scoped to the selected period, so they match the date picker and don't drag
  // in unrelated months (e.g. February's migration COGS).
  List<Sale> _sales = const [];
  List<Transaction> _txns = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loadingAll = true);
    final start = _period.range.start;
    final end = _period.range.end;
    final salesRes = await ref
        .read(saleRepositoryProvider)
        .getSalesInRange(start: start, end: end);
    final txnRes = await ref
        .read(transactionRepositoryProvider)
        .getTransactionsInRange(start: start, end: end);
    if (!mounted) return;
    setState(() {
      _sales = salesRes.data ?? const [];
      _txns = txnRes.data ?? const [];
      _loadingAll = false;
    });
  }

  FinancialPeriodResult _period = FinancialPeriodResult(
    type: FinancialPeriodType.monthEnd,
    range: DateTimeRange(
      start: DateTime(DateTime.now().year, DateTime.now().month, 1),
      end: DateTime(DateTime.now().year, DateTime.now().month,
          DateTime.now().day, 23, 59, 59),
    ),
    label: DateFormat('MMMM yyyy').format(DateTime.now()),
  );

  Future<void> _pickPeriod() async {
    final res = await showFinancialPeriodSheet(context, current: _period);
    if (res != null && mounted) {
      setState(() => _period = res);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyProvider);
    final fmt = NumberFormat('#,##0.##');

    final allSales = _sales;
    final allTxns = _txns;
    final products = ref.watch(filteredInventoryProvider).value ?? const [];

    final start = _period.range.start;
    final end = _period.range.end;

    // ── Period summary — COGS & revenue come from the cat_cogs / cat_sales
    // ledger (authoritative; sale.totalCogs is 0 for imported/historical sales
    // whose item cost wasn't captured, which made prior months read zero). ──
    final periodCogs = periodLedgerCogs(allTxns, start, end);
    final periodRevenue = periodLedgerRevenue(allTxns, start, end);
    final periodGross = roundMoney(periodRevenue - periodCogs);
    final marginPct = periodRevenue > 0 ? periodGross / periodRevenue * 100 : 0.0;
    final cogsPct = periodRevenue > 0 ? periodCogs / periodRevenue * 100 : 0.0;

    final periodCogsTxns = allTxns
        .where((t) => t.categoryId == 'cat_cogs')
        .where((t) => !t.dateTime.isBefore(start) && !t.dateTime.isAfter(end))
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    // ── Integrity (scoped to the selected period — matches the date picker) ──
    // Ledger-authoritative: an order is "missing COGS" only if it has no
    // cat_cogs ledger entry (not merely a zero sale.totalCogs).
    final ordersMissingCogs = findOrdersMissingCogs(allSales, allTxns)
      ..sort((a, b) => b.date.compareTo(a.date));
    final missingCostProducts = <Product>[];
    var missingCostVariants = 0;
    for (final p in products) {
      final zero = p.variants.where((v) => v.costPrice <= 0).length;
      if (zero > 0) {
        missingCostProducts.add(p);
        missingCostVariants += zero;
      }
    }
    final recon = reconcileCogs(allSales, allTxns);
    // Products whose cost has changed (cost layers span more than one price).
    final costChanged = _costChangedProducts(products);

    final issueCount = ordersMissingCogs.length +
        (missingCostVariants > 0 ? 1 : 0) +
        (recon.matches ? 0 : 1);

    // ── By product (period COGS share) — sales-item based (the ledger has no
    // per-product split). Falls back gracefully when item cost is unavailable.
    final periodSales = allSales
        .where((s) => s.orderStatus != OrderStatus.cancelled)
        .where((s) => !s.date.isBefore(start) && !s.date.isAfter(end))
        .toList();
    final byProduct = <String, ({double cogs, double revenue, double qty})>{};
    for (final s in periodSales) {
      for (final i in s.items) {
        final cur = byProduct[i.productName];
        byProduct[i.productName] = (
          cogs: (cur?.cogs ?? 0) + i.lineCogs,
          revenue: (cur?.revenue ?? 0) + i.lineTotal,
          qty: (cur?.qty ?? 0) + i.quantity,
        );
      }
    }
    final productRows = byProduct.entries.toList()
      ..sort((a, b) => b.value.cogs.compareTo(a.value.cogs));
    final maxProductCogs = productRows.isEmpty
        ? 1.0
        : productRows.first.value.cogs.clamp(1.0, double.infinity);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(l10n.cogsAnalysisTitle,
            style: AppTypography.labelMedium.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: _pickPeriod,
            icon: const Icon(Icons.calendar_today_rounded, size: 15),
            label: Text(_period.label,
                style: AppTypography.captionSmall
                    .copyWith(fontWeight: FontWeight.w700)),
            style: TextButton.styleFrom(foregroundColor: AppColors.primaryNavy),
          ),
        ],
      ),
      body: _loadingAll
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _integrityBanner(l10n, issueCount),
          const SizedBox(height: 12),
          _summaryHero(l10n, currency, fmt, periodCogs, periodGross,
              periodRevenue, marginPct, cogsPct),
          const SizedBox(height: 16),
          _sectionLabel(l10n.cogsIntegrityChecks),
          const SizedBox(height: 8),
          _ordersMissingCogsCard(l10n, currency, fmt, ordersMissingCogs),
          const SizedBox(height: 8),
          _missingCostCard(l10n, missingCostVariants, missingCostProducts.length),
          const SizedBox(height: 8),
          _reconCard(l10n, currency, fmt, recon),
          if (costChanged.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionLabel(l10n.cogsPriceChanges),
            const SizedBox(height: 8),
            _costChangesCard(l10n, currency, fmt, costChanged),
          ],
          if (productRows.isNotEmpty) ...[
            const SizedBox(height: 16),
            _sectionLabel(l10n.cogsByProduct),
            const SizedBox(height: 8),
            _byProductCard(l10n, currency, fmt, productRows, maxProductCogs),
          ],
          const SizedBox(height: 16),
          _sectionLabel(l10n.cogsTransactions),
          const SizedBox(height: 8),
          _txnsCard(l10n, currency, fmt, periodCogsTxns, allSales),
        ],
      ),
    );
  }

  // ── Integrity banner ──
  Widget _integrityBanner(AppLocalizations l10n, int issues) {
    final ok = issues == 0;
    final color = ok ? const Color(0xFF16A34A) : AppColors.accentOrange;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.verified_rounded : Icons.warning_amber_rounded,
              color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ok ? l10n.cogsAllRecorded : l10n.cogsIssuesFound(issues),
              style: AppTypography.bodySmall.copyWith(
                  color: color, fontWeight: FontWeight.w700, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary hero ──
  Widget _summaryHero(
      AppLocalizations l10n,
      String currency,
      NumberFormat fmt,
      double cogs,
      double gross,
      double revenue,
      double marginPct,
      double cogsPct) {
    final cogsFlex = revenue <= 0 ? 1 : (cogs / revenue * 1000).round();
    final grossFlex = revenue <= 0 ? 0 : (gross / revenue * 1000).round().clamp(0, 1000000);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryNavy, Color(0xFF1B2A4A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: AppColors.primaryNavy.withValues(alpha: 0.25),
              blurRadius: 18,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.cogsTotal.toUpperCase(),
              style: AppTypography.captionSmall.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  fontSize: 10)),
          const SizedBox(height: 4),
          Text('$currency ${fmt.format(cogs)}',
              style: AppTypography.displayMedium.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w800, height: 1.0)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 10,
              child: revenue <= 0
                  ? Container(color: Colors.white.withValues(alpha: 0.2))
                  : Row(children: [
                      Expanded(
                          flex: cogsFlex,
                          child: Container(color: AppColors.accentOrange)),
                      if (grossFlex > 0)
                        Expanded(
                            flex: grossFlex,
                            child: Container(
                                color:
                                    const Color(0xFF34D399).withValues(alpha: 0.9))),
                    ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _heroStat(l10n.cogsGrossMargin,
                      '${marginPct.toStringAsFixed(1)}%')),
              Expanded(
                  child: _heroStat(
                      l10n.cogsOfRevenue, '${cogsPct.toStringAsFixed(1)}%')),
              Expanded(
                  child: _heroStat(l10n.cogsGrossProfit,
                      '$currency ${fmt.format(gross)}')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: AppTypography.labelMedium
                  .copyWith(color: Colors.white, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(label,
              style: AppTypography.captionSmall.copyWith(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      );

  // ── Orders missing COGS ──
  Widget _ordersMissingCogsCard(AppLocalizations l10n, String currency,
      NumberFormat fmt, List<Sale> orders) {
    final ok = orders.isEmpty;
    return _issueCard(
      ok: ok,
      icon: Icons.receipt_long_rounded,
      title: l10n.cogsOrdersMissing,
      countLabel: ok ? l10n.cogsNoneFound : '${orders.length}',
      child: ok
          ? null
          : Column(
              children: [
                for (final s in orders.take(8))
                  InkWell(
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) =>
                          EditCogsDialog(sale: s, currency: currency),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    s.customerName?.isNotEmpty == true
                                        ? s.customerName!
                                        : '#${s.id.substring(0, s.id.length.clamp(0, 6))}',
                                    style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                Text(
                                    '${DateFormat.yMMMd().format(s.date)} · ${s.items.length} ${l10n.cogsItems}',
                                    style: AppTypography.captionSmall.copyWith(
                                        color: AppColors.textTertiary)),
                              ],
                            ),
                          ),
                          Text('$currency ${fmt.format(s.netRevenue)}',
                              style: AppTypography.captionSmall.copyWith(
                                  color: AppColors.textSecondary)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.accentOrange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(l10n.cogsFix,
                                style: AppTypography.captionSmall.copyWith(
                                    color: AppColors.accentOrange,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10)),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (orders.length > 8)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(l10n.cogsAndMore(orders.length - 8),
                        style: AppTypography.captionSmall
                            .copyWith(color: AppColors.textTertiary)),
                  ),
              ],
            ),
    );
  }

  // ── Items missing cost (links to MissingCostScreen) ──
  Widget _missingCostCard(
      AppLocalizations l10n, int variants, int productCount) {
    final ok = variants == 0;
    return InkWell(
      onTap: ok ? null : () => context.pushNamed('MissingCostScreen'),
      borderRadius: BorderRadius.circular(14),
      child: _issueCard(
        ok: ok,
        icon: Icons.sell_rounded,
        title: l10n.cogsItemsMissingCost,
        countLabel: ok ? l10n.cogsNoneFound : '$variants',
        trailing: ok
            ? null
            : const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppColors.accentOrange),
        child: ok
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(l10n.cogsItemsMissingCostHint(productCount),
                    style: AppTypography.captionSmall
                        .copyWith(color: AppColors.textSecondary, height: 1.3)),
              ),
      ),
    );
  }

  // ── Reconciliation ──
  Widget _reconCard(AppLocalizations l10n, String currency, NumberFormat fmt,
      CogsRecon recon) {
    return _issueCard(
      ok: recon.matches,
      icon: Icons.balance_rounded,
      title: l10n.cogsReconciliation,
      countLabel: recon.matches
          ? l10n.cogsMatched
          : '$currency ${fmt.format(recon.diff)}',
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          children: [
            _kv(l10n.cogsFromSales, '$currency ${fmt.format(recon.salesCogs)}'),
            const SizedBox(height: 4),
            _kv(l10n.cogsRecordedLedger,
                '$currency ${fmt.format(recon.recordedCogs)}'),
          ],
        ),
      ),
    );
  }

  // ── Cost changes ──
  Widget _costChangesCard(AppLocalizations l10n, String currency,
      NumberFormat fmt, List<_CostChange> changes) {
    return _card(
      child: Column(
        children: [
          for (final c in changes.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(c.name,
                        style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Text('$currency ${fmt.format(c.minCost)}',
                      style: AppTypography.captionSmall
                          .copyWith(color: AppColors.textTertiary)),
                  Icon(
                      c.latest >= c.oldest
                          ? Icons.arrow_forward_rounded
                          : Icons.arrow_forward_rounded,
                      size: 12,
                      color: AppColors.textTertiary),
                  Text('$currency ${fmt.format(c.maxCost)}',
                      style: AppTypography.captionSmall.copyWith(
                          color: c.latest > c.oldest
                              ? AppColors.danger
                              : const Color(0xFF16A34A),
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── By product ──
  Widget _byProductCard(
      AppLocalizations l10n,
      String currency,
      NumberFormat fmt,
      List<MapEntry<String, ({double cogs, double revenue, double qty})>> rows,
      double maxCogs) {
    return _card(
      child: Column(
        children: [
          for (final e in rows.take(12))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(e.key,
                            style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('$currency ${fmt.format(roundMoney(e.value.cogs))}',
                          style: AppTypography.labelMedium.copyWith(
                              color: AppColors.accentOrange,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (e.value.cogs / maxCogs).clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor:
                                AppColors.borderLight.withValues(alpha: 0.4),
                            valueColor: const AlwaysStoppedAnimation(
                                AppColors.accentOrange),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                          '${fmtQty(e.value.qty)} ${l10n.cogsUnits} · ${e.value.revenue > 0 ? ((e.value.revenue - e.value.cogs) / e.value.revenue * 100).toStringAsFixed(0) : '—'}%',
                          style: AppTypography.captionSmall
                              .copyWith(color: AppColors.textTertiary)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── COGS transactions ──
  Widget _txnsCard(AppLocalizations l10n, String currency, NumberFormat fmt,
      List<Transaction> txns, List<Sale> sales) {
    if (txns.isEmpty) {
      return _card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(l10n.cogsNoTransactions,
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textTertiary)),
          ),
        ),
      );
    }
    return _card(
      child: Column(
        children: [
          for (final t in txns.take(15))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.inventory_2_outlined,
                        size: 14, color: AppColors.accentOrange),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.title,
                            style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        Text(DateFormat.yMMMd().format(t.dateTime),
                            style: AppTypography.captionSmall
                                .copyWith(color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                  Text('$currency ${fmt.format(t.amount.abs())}',
                      style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── shared widgets ──
  Widget _issueCard({
    required bool ok,
    required IconData icon,
    required String title,
    required String countLabel,
    Widget? child,
    Widget? trailing,
  }) {
    final color = ok ? const Color(0xFF16A34A) : AppColors.accentOrange;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(countLabel,
                    style: AppTypography.captionSmall.copyWith(
                        color: color, fontWeight: FontWeight.w800)),
              ),
              if (trailing != null) ...[const SizedBox(width: 4), trailing],
            ],
          ),
          ?child,
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
        child: child,
      );

  Widget _kv(String k, String v) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k,
              style: AppTypography.captionSmall
                  .copyWith(color: AppColors.textSecondary)),
          Text(v,
              style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        ],
      );

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text.toUpperCase(),
            style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                fontSize: 11)),
      );

  // Products whose cost layers span more than one unit cost (cost has changed).
  List<_CostChange> _costChangedProducts(List<Product> products) {
    final out = <_CostChange>[];
    for (final p in products) {
      double? lo, hi, oldest, latest;
      for (final v in p.variants) {
        final layers = v.effectiveCostLayers;
        if (layers.length < 2) continue;
        final sorted = List.of(layers)..sort((a, b) => a.date.compareTo(b.date));
        for (final l in sorted) {
          lo = lo == null ? l.unitCost : (l.unitCost < lo ? l.unitCost : lo);
          hi = hi == null ? l.unitCost : (l.unitCost > hi ? l.unitCost : hi);
        }
        oldest ??= sorted.first.unitCost;
        latest = sorted.last.unitCost;
      }
      if (lo != null && hi != null && (hi - lo).abs() > 0.01) {
        out.add(_CostChange(
            name: p.name,
            minCost: lo,
            maxCost: hi,
            oldest: oldest ?? lo,
            latest: latest ?? hi));
      }
    }
    out.sort((a, b) => (b.maxCost - b.minCost).compareTo(a.maxCost - a.minCost));
    return out;
  }
}

class _CostChange {
  final String name;
  final double minCost;
  final double maxCost;
  final double oldest;
  final double latest;
  const _CostChange({
    required this.name,
    required this.minCost,
    required this.maxCost,
    required this.oldest,
    required this.latest,
  });
}
