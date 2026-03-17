import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/services/share_service.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/utils/money_utils.dart';
import 'package:go_router/go_router.dart';
import '../../core/navigation/app_router.dart';
import '../../shared/models/category_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/export_providers.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/financial_period_sheet.dart';
import 'widgets/report_card.dart';
import 'widgets/chart_toggle.dart';

class ProfitLossScreen extends ConsumerStatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  ConsumerState<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends ConsumerState<ProfitLossScreen> {
  // State
  FinancialPeriodResult _period = FinancialPeriodResult(
    type: FinancialPeriodType.monthEnd,
    range: DateTimeRange(
      start: DateTime(DateTime.now().year, DateTime.now().month, 1),
      end: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59),
    ),
    label: DateFormat('MMMM yyyy').format(DateTime.now()),
  );
  bool _showTrend = false;

  @override
  void initState() {
    super.initState();
    // Reports need the full dataset, not just the first page.
    Future.microtask(() {
      ref.read(transactionsProvider.notifier).loadAll();
    });
  }

  DateTimeRange _getDateRange() => _period.range;

  Future<void> _openDatePicker() async {
    final result = await showFinancialPeriodSheet(context, current: _period);
    if (result == null) return;
    setState(() => _period = result);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en');
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(appSettingsProvider).currency;

    // Fetch live data — distinguish loading / error / empty
    final txnState = ref.watch(transactionsProvider);
    final isLoadingTxns = txnState.isLoading && !txnState.hasValue;
    final txnError = txnState.hasError && !txnState.hasValue ? txnState.error : null;
    final transactions = txnState.value ?? [];

    // Get date range for the selected period
    final dateRange = _getDateRange();

    // Categories excluded from P&L (CF investing activities / BS only)
    const plExcludedCats = {
      'cat_investments',
      'cat_loan_received',
      'cat_loan_repayment',
      'cat_equity_injection',
      'cat_owner_withdrawal',
    };

    // Filter transactions (exclude P&L-excluded items like supplier payments)
    final filteredTransactions = transactions.where((tx) {
      if (tx.excludeFromPL || plExcludedCats.contains(tx.categoryId)) return false;
      return !tx.dateTime.isBefore(dateRange.start) && !tx.dateTime.isAfter(dateRange.end);
    }).toList();

    // Previous period comparison
    final periodDuration = dateRange.end.difference(dateRange.start);
    final prevEnd = dateRange.start.subtract(const Duration(seconds: 1));
    final prevStart = prevEnd.subtract(periodDuration);
    double prevRevenue = 0;
    double prevExpenses = 0;
    for (final tx in transactions) {
      if (tx.excludeFromPL || plExcludedCats.contains(tx.categoryId)) continue;
      if (tx.dateTime.isBefore(prevStart) || tx.dateTime.isAfter(prevEnd)) continue;
      if (tx.isIncome) {
        prevRevenue += tx.amount.abs();
      } else {
        prevExpenses += tx.amount.abs();
      }
    }
    final double prevNetProfit = roundMoney(prevRevenue - prevExpenses);

    // ── Income Statement Grouping ──
    double salesRevenue = 0;
    double cogs = 0;
    double otherIncome = 0;
    double operatingExpenses = 0;

    final Map<String, double> revenueByCategory = {};
    final Map<String, double> cogsByCategory = {};
    final Map<String, double> opexByCategory = {};

    for (final tx in filteredTransactions) {
      final amt = tx.amount.abs();
      if (tx.categoryId == 'cat_sales_revenue') {
        // Use signed amount: refunds are negative and should reduce revenue
        salesRevenue += tx.amount;
        revenueByCategory[tx.categoryId] = (revenueByCategory[tx.categoryId] ?? 0) + tx.amount;
      } else if (tx.categoryId == 'cat_cogs') {
        cogs += amt;
        cogsByCategory[tx.categoryId] = (cogsByCategory[tx.categoryId] ?? 0) + amt;
      } else if (tx.isIncome) {
        otherIncome += amt;
        revenueByCategory[tx.categoryId] = (revenueByCategory[tx.categoryId] ?? 0) + amt;
      } else {
        operatingExpenses += amt;
        opexByCategory[tx.categoryId] = (opexByCategory[tx.categoryId] ?? 0) + amt;
      }
    }

    final double totalRevenue = roundMoney(salesRevenue + otherIncome);
    final double grossProfit = roundMoney(salesRevenue - cogs);
    final double calculatedNetProfit = roundMoney(grossProfit + otherIncome - operatingExpenses);

    List<_BreakdownItem> buildBreakdownItems(
        Map<String, double> map, double total, List<Color> palette) {
      if (total == 0) return [];
      var entries = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final topEntries = entries.take(5).toList();
      int i = 0;
      final items = topEntries.map((e) {
        final color = palette[i++ % palette.length];
        String catName = CategoryData.findById(e.key).name;
        
        return _BreakdownItem(
          label: catName,
          amount: e.value,
          color: color,
          percentage: total > 0 ? e.value / total : 0,
        );
      }).toList();
      // Add "Other" bucket if there are more than 5 categories
      if (entries.length > 5) {
        final otherTotal = entries.skip(5).fold(0.0, (sum, e) => sum + e.value);
        items.add(_BreakdownItem(
          label: l10n.other,
          amount: otherTotal,
          color: const Color(0xFF6B7280),
          percentage: total > 0 ? otherTotal / total : 0,
        ));
      }
      return items;
    }

    // Distinct color palettes per P&L section
    const revenueColors = [Color(0xFF10B981), Color(0xFF34D399), Color(0xFF6EE7B7), Color(0xFF059669), Color(0xFF047857)];
    const cogsColors    = [Color(0xFFEF4444), Color(0xFFF87171), Color(0xFFFCA5A5), Color(0xFFDC2626), Color(0xFFB91C1C)];
    const opexColors    = [Color(0xFF3B82F6), Color(0xFF60A5FA), Color(0xFF93C5FD), Color(0xFF2563EB), Color(0xFF8B5CF6)];

    final revenueItems = buildBreakdownItems(revenueByCategory, totalRevenue, revenueColors);
    final cogsItems = buildBreakdownItems(cogsByCategory, cogs, cogsColors);
    final opexItems = buildBreakdownItems(opexByCategory, operatingExpenses, opexColors);

    final isGrowth = ref.watch(isGrowthProvider);
    final hasData = filteredTransactions.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: RefreshIndicator(
            onRefresh: () => ref.read(transactionsProvider.notifier).refreshAll(),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 100 + MediaQuery.of(context).padding.bottom),
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              child: Column(
              children: [
                // Period Selector
                _buildPeriodSelector(),
                const SizedBox(height: 20),

                // Loading state
                if (isLoadingTxns)
                  _buildLoadingState()
                // Error state
                else if (txnError != null)
                  _buildErrorState(txnError)
                // Empty state
                else if (!hasData)
                  _buildEmptyState()
                else ...[
                  // Dynamic Insight Banner
                  _buildInsightBanner(totalRevenue, cogs + operatingExpenses, calculatedNetProfit, currency, fmt, prevNetProfit: prevNetProfit)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .slideY(begin: 0.1, end: 0, curve: Curves.easeOut),
                  const SizedBox(height: 20),

                  // KPI Row
                  _buildKPIRow(fmt, currency, totalRevenue, salesRevenue, grossProfit, calculatedNetProfit),
                  const SizedBox(height: 20),

                  // Funnel Chart (Growth only)
                  if (isGrowth) ...[
                    _buildFunnelChart(fmt, currency, totalRevenue, cogs, grossProfit, operatingExpenses, calculatedNetProfit, transactions)
                        .animate()
                        .fadeIn(duration: 400.ms, delay: 100.ms)
                        .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),
                    const SizedBox(height: 20),
                  ],

                  // Revenue Breakdown
                  if (revenueItems.isNotEmpty) ...[
                    _buildBreakdownSection(
                      title: l10n.revenueSources,
                      items: revenueItems,
                      fmt: fmt,
                      currency: currency,
                    ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                    const SizedBox(height: 16),
                  ],

                  // COGS Breakdown
                  if (cogsItems.isNotEmpty) ...[
                    _buildBreakdownSection(
                      title: l10n.costOfGoodsSold,
                      items: cogsItems,
                      fmt: fmt,
                      currency: currency,
                    ).animate().fadeIn(duration: 400.ms, delay: 250.ms),
                    const SizedBox(height: 16),
                  ],

                  // Operating Expenses Breakdown
                  if (opexItems.isNotEmpty) ...[
                    _buildBreakdownSection(
                      title: l10n.operatingExpenses,
                      items: opexItems,
                      fmt: fmt,
                      currency: currency,
                    ).animate().fadeIn(duration: 400.ms, delay: 300.ms),
                    const SizedBox(height: 20),
                  ],

                  // Net Profit Summary
                  _buildNetProfitCard(fmt, currency, calculatedNetProfit)
                      .animate()
                      .fadeIn(duration: 400.ms, delay: 400.ms)
                      .slideY(begin: 0.05, end: 0, curve: Curves.easeOut),

                  if (isGrowth) ...[
                    const SizedBox(height: 20),
                    _buildSharePill(),
                  ],
                ],
              ],
            ),
          ),
          ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  WIDGETS
  // ═══════════════════════════════════════════════════════

  Widget _buildPeriodSelector() {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _openDatePicker();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.base),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              _period.label,
              style: AppTypography.labelMedium.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more_rounded,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 80),
      child: Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: AppColors.chartBlue,
        ),
      ),
    );
  }

  Widget _buildErrorState(Object error) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline_rounded, size: 28, color: AppColors.danger),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.failedToLoadTransactions,
            style: AppTypography.labelLarge.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.pullDownToRetry,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final currency = ref.watch(appSettingsProvider).currency;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        // Zeroed KPI cards — shows report structure
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                label: l10n.revenue,
                amount: '0',
                currency: currency,
                accentColor: AppColors.chartGreen.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildKPICard(
                label: l10n.grossProfit,
                amount: '0',
                currency: currency,
                accentColor: AppColors.chartBlue.withValues(alpha: 0.35),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildKPICard(
                label: l10n.netProfit,
                amount: '0',
                currency: currency,
                accentColor: AppColors.accentOrange.withValues(alpha: 0.35),
                isPrimary: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Skeleton income statement
        ReportCard(
          child: Column(
            children: [
              _buildEmptyFunnelRow(l10n.revenue, AppColors.chartGreen, 1.0),
              const SizedBox(height: 12),
              _buildEmptyFunnelRow(l10n.costOfGoodsSold, AppColors.danger, 0.0),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              _buildEmptyFunnelRow(l10n.grossProfit, AppColors.chartBlue, 0.0),
              const SizedBox(height: 12),
              _buildEmptyFunnelRow(l10n.operatingExpenses, AppColors.accentOrange, 0.0),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              _buildEmptyFunnelRow(l10n.netProfit, const Color(0xFF7C3AED), 0.0),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Empty illustration + CTA
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.accentOrange.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.trending_up_rounded,
            size: 28,
            color: AppColors.accentOrange.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.noActivityForThisPeriod,
          style: AppTypography.labelLarge.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.recordSaleOrExpense,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => context.push(AppRoutes.addTransaction),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(l10n.addTransaction),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
            foregroundColor: Colors.white,
            minimumSize: const Size(200, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildEmptyFunnelRow(String label, Color color, double widthFactor) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: 13,
            ),
          ),
        ),
        Text(
          '—',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }



  Widget _buildInsightBanner(double revenue, double expenses, double netProfit, String currency, NumberFormat fmt, {double? prevNetProfit}) {
    final isProfit = netProfit >= 0;
    final l10n = AppLocalizations.of(context)!;

    String headline;
    String body;

    if (isProfit && netProfit > 0) {
      final margin = revenue > 0 ? (netProfit / revenue * 100).toStringAsFixed(1) : '0';
      headline = l10n.plYouEarned(currency, fmt.format(netProfit));
      body = l10n.plProfitMarginBody(margin);
    } else if (netProfit == 0) {
      headline = l10n.breakingEven;
      body = l10n.plBreakingEvenBody;
    } else {
      headline = l10n.plYouLost(currency, fmt.format(netProfit.abs()));
      body = l10n.plLossBody;
    }

    // Period-over-period comparison
    String? comparison;
    if (prevNetProfit != null && prevNetProfit != 0) {
      final change = netProfit - prevNetProfit;
      final pct = (change / prevNetProfit.abs() * 100).toStringAsFixed(0);
      if (change > 0) {
        comparison = l10n.plUpVsPrevious(pct);
      } else if (change < 0) {
        comparison = l10n.plDownVsPrevious(pct.replaceFirst('-', ''));
      }
    } else if (prevNetProfit != null && prevNetProfit == 0 && netProfit != 0) {
      comparison = l10n.noActivityInPreviousPeriod;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isProfit ? AppColors.chartGreenLight : AppColors.chartRedLight,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isProfit ? AppColors.badgeBgPositive : AppColors.badgeBgNegative,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Icon(
              isProfit ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              color: isProfit ? AppColors.chartGreen : AppColors.chartRed,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: AppTypography.labelMedium.copyWith(
                    color: isProfit ? AppColors.badgeTextPositive : AppColors.badgeTextNegative,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AppTypography.bodySmall.copyWith(
                    color: (isProfit ? AppColors.badgeTextPositive : AppColors.badgeTextNegative).withValues(alpha: 0.8),
                    height: 1.4,
                  ),
                ),
                if (comparison != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    comparison,
                    style: AppTypography.badge.copyWith(
                      fontSize: 11,
                      color: (isProfit ? AppColors.badgeTextPositive : AppColors.badgeTextNegative).withValues(alpha: 0.7),
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

  Widget _buildKPIRow(NumberFormat fmt, String currency, double revenue, double salesRevenue, double grossProfit, double netProfit) {
    final l10n = AppLocalizations.of(context)!;
    final grossMargin = salesRevenue > 0 ? (grossProfit / salesRevenue * 100) : 0.0;
    final netMargin = revenue > 0 ? (netProfit / revenue * 100) : 0.0;

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildKPICard(
                  label: l10n.revenue,
                  amount: fmt.format(revenue),
                  currency: currency,
                  accentColor: AppColors.chartGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKPICard(
                  label: l10n.grossProfit,
                  amount: fmt.format(grossProfit),
                  currency: currency,
                  accentColor: AppColors.chartBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildKPICard(
                  label: l10n.netProfit,
                  amount: fmt.format(netProfit),
                  currency: currency,
                  accentColor: AppColors.accentOrange,
                  isPrimary: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildRatioCard(
                  label: l10n.grossMargin,
                  value: grossMargin,
                  accentColor: AppColors.chartBlue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildRatioCard(
                  label: l10n.netMargin,
                  value: netMargin,
                  accentColor: AppColors.accentOrange,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRatioCard({
    required String label,
    required double value,
    required Color accentColor,
  }) {
    final isNegative = value < 0;
    final displayColor = isNegative ? AppColors.danger : accentColor;
    return ReportCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label.toUpperCase(),
                  style: AppTypography.badge.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 6),
                Text(
                  '${value.toStringAsFixed(1)}%',
                  style: AppTypography.metricSmall.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: displayColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: (value.abs() / 100).clamp(0.0, 1.0),
                  strokeWidth: 4,
                  backgroundColor: displayColor.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(displayColor),
                ),
                Icon(
                  isNegative ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                  size: 16,
                  color: displayColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKPICard({
    required String label,
    required String amount,
    required String currency,
    required Color accentColor,
    bool isPrimary = false,
  }) {
    return ReportCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTypography.badge.copyWith(
              color: isPrimary ? AppColors.accentOrange : AppColors.textTertiary,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.visible,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '$currency $amount',
              style: AppTypography.metricSmall.copyWith(
                fontSize: 14,
                color: isPrimary ? AppColors.accentOrange : AppColors.textPrimary,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 3,
            width: 28,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFunnelChart(NumberFormat fmt, String currency, double rev, double cogsAmt, double grossProfitAmt, double opexAmt, double net, List<Transaction> allTx) {
    return ReportCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _showTrend ? AppLocalizations.of(context)!.sixMonthTrend : AppLocalizations.of(context)!.incomeStatement,
                style: AppTypography.sectionTitle,
              ),
              ChartToggle(
                showChart: _showTrend,
                onToggle: () => setState(() => _showTrend = !_showTrend),
                firstIcon: Icons.filter_list_rounded,
                secondIcon: Icons.show_chart_rounded,
              ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedCrossFade(
            firstChild: _buildFunnelBody(fmt, currency, rev, cogsAmt, grossProfitAmt, opexAmt, net),
            secondChild: _buildTrendChart(fmt, allTx),
            crossFadeState: _showTrend
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: 300.ms,
          ),
        ],
      ),
    );
  }

  Widget _buildFunnelBody(NumberFormat fmt, String currency, double rev, double cogsAmt, double grossProfitAmt, double opexAmt, double net) {
    final l10n = AppLocalizations.of(context)!;
    final maxVal = rev > 0 ? rev : 1.0;
    return Column(
      children: [
        _buildFunnelItem(
          icon: Icons.arrow_downward_rounded,
          iconColor: AppColors.chartGreen,
          iconBg: AppColors.chartGreenLight,
          label: l10n.revenue,
          amount: rev,
          barColor: AppColors.chartGreen,
          barWidthFactor: 1.0,
          fmt: fmt, currency: currency,
        ),
        const SizedBox(height: 10),
        _buildFunnelItem(
          icon: Icons.inventory_2_rounded,
          iconColor: AppColors.chartOrange,
          iconBg: AppColors.chartOrangeLight,
          label: l10n.costOfGoodsSold,
          amount: -cogsAmt,
          barColor: AppColors.chartOrange,
          barWidthFactor: (cogsAmt / maxVal).clamp(0.0, 1.0),
          fmt: fmt, currency: currency,
        ),
        const SizedBox(height: 10),
        _buildFunnelItem(
          icon: Icons.trending_up_rounded,
          iconColor: AppColors.chartBlue,
          iconBg: AppColors.chartBlueLight,
          label: l10n.grossProfit,
          amount: grossProfitAmt,
          barColor: AppColors.chartBlue,
          barWidthFactor: (grossProfitAmt.abs() / maxVal).clamp(0.0, 1.0),
          fmt: fmt, currency: currency,
        ),
        const SizedBox(height: 10),
        _buildFunnelItem(
          icon: Icons.arrow_upward_rounded,
          iconColor: AppColors.chartRed,
          iconBg: AppColors.chartRedLight,
          label: l10n.operatingExp,
          amount: -opexAmt,
          barColor: AppColors.chartRed,
          barWidthFactor: (opexAmt / maxVal).clamp(0.0, 1.0),
          fmt: fmt, currency: currency,
        ),
        const SizedBox(height: 10),
        _buildFunnelItem(
          icon: Icons.savings_rounded,
          iconColor: AppColors.accentOrange,
          iconBg: AppColors.accentOrange.withValues(alpha: 0.1),
          label: l10n.netProfit,
          amount: net,
          barColor: AppColors.accentOrange,
          barWidthFactor: (net.abs() / maxVal).clamp(0.0, 1.0),
          fmt: fmt, currency: currency,
          isProfit: true,
        ),
      ],
    );
  }

  Widget _buildTrendChart(NumberFormat fmt, List<Transaction> allTx) {
    // Calculate last 6 months net profit
    final now = DateTime.now();
    final data = <Map<String, dynamic>>[];
    
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final nextMonth = DateTime(now.year, now.month - i + 1, 1);
      double revenue = 0;
      double expense = 0;
      for (final tx in allTx) {
        if (tx.excludeFromPL) continue;
        if (!tx.dateTime.isBefore(month) && tx.dateTime.isBefore(nextMonth)) {
          if (tx.isIncome) {
            revenue += tx.amount.abs();
          } else {
            expense += tx.amount.abs();
          }
        }
      }
      data.add({
        'month': DateFormat('MMM').format(month),
        'amount': revenue - expense,
      });
    }

    double maxAmount = 1.0;
    for (final d in data) {
      if ((d['amount'] as double).abs() > maxAmount) maxAmount = (d['amount'] as double).abs();
    }

    return SizedBox(
      height: 180,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: data.map((d) {
          final amount = d['amount'] as double;
          final heightFactor = (amount.abs() / maxAmount).clamp(0.0, 1.0);
          final isCurrent = d == data.last;

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isCurrent)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryNavy,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        d['month'] as String,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .moveY(begin: 0, end: -3, duration: 1.seconds, curve: Curves.easeInOut),

                  TweenAnimationBuilder<double>(
                    duration: 600.ms,
                    curve: Curves.easeOutBack,
                    tween: Tween(begin: 0, end: heightFactor),
                    builder: (context, val, _) {
                      return Container(
                        width: 28,
                        height: 120 * val,
                        decoration: BoxDecoration(
                          color: amount < 0
                              ? AppColors.chartRed.withValues(alpha: 0.8)
                              : (isCurrent ? AppColors.accentOrange : const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  if (!isCurrent)
                    Text(
                      d['month'] as String,
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                        letterSpacing: 0,
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFunnelItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String label,
    required double amount,
    required Color barColor,
    required double barWidthFactor,
    required NumberFormat fmt,
    required String currency,
    bool isProfit = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label,
                      style: AppTypography.bodySmall.copyWith(
                        color: isProfit ? AppColors.accentOrange : AppColors.textSecondary,
                        fontWeight: isProfit ? FontWeight.w700 : FontWeight.w500,
                      )),
                  Text(
                    '${amount < 0 ? "-" : ""}$currency ${fmt.format(amount.abs())}',
                    style: AppTypography.labelSmall.copyWith(
                      color: isProfit ? AppColors.accentOrange : AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LayoutBuilder(builder: (context, constraints) {
                return Stack(
                  children: [
                    Container(
                      height: 24,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: barColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    AnimatedContainer(
                      duration: 800.ms,
                      curve: Curves.easeOutQuart,
                      height: 24,
                      width: constraints.maxWidth * barWidthFactor,
                      decoration: BoxDecoration(
                        color: barColor.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownSection({
    required String title,
    required List<_BreakdownItem> items,
    required NumberFormat fmt,
    required String currency,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: AppTypography.sectionTitle.copyWith(fontSize: 14)),
        ),
        ReportCard(
          child: Column(
            children: items.map((item) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _navigateToCategoryTransactions(item.label);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(color: item.color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.label,
                                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                            Text(
                              '$currency ${fmt.format(item.amount)}',
                              style: AppTypography.labelSmall.copyWith(color: AppColors.textPrimary),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.textTertiary),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: item.percentage,
                            backgroundColor: AppColors.backgroundLight,
                            valueColor: AlwaysStoppedAnimation(item.color),
                            minHeight: 5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _navigateToCategoryTransactions(String category) {
    // Construct filter for selected category
    final filter = TransactionFilter(
        type: TransactionType.all,
        amountRange: const RangeValues(0, 1000000), // Wide range
        selectedCategories: {category},
    );

    context.pushNamed(
      'TransactionsListScreen',
      extra: {
        'pageTitle': '$category Transactions',
        'showBackButton': true,
        'initialFilter': filter,
      },
    );
  }

  Widget _buildNetProfitCard(NumberFormat fmt, String currency, double netProfit) {
    final isPositive = netProfit >= 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPositive ? AppColors.chartGreenLight : AppColors.chartRedLight,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isPositive ? AppColors.badgeBgPositive : AppColors.badgeBgNegative,
        ),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.netProfit,
                  style: AppTypography.badge.copyWith(
                    fontSize: 11,
                    color: isPositive ? AppColors.badgeTextPositive : AppColors.badgeTextNegative,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$currency ${fmt.format(netProfit)}',
                  style: AppTypography.metric,
                ),
              ],
            ),
          ),
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(
              isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
              size: 18,
              color: isPositive ? AppColors.chartGreen : AppColors.chartRed,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSharePill() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () async {
          HapticFeedback.lightImpact();
          final origin = ShareService.originFrom(context);
          final l10n = AppLocalizations.of(context)!;
          final reportSvc = ref.read(reportServiceProvider);
          final shareSvc = ref.read(shareServiceProvider);
          final settings = ref.read(appSettingsProvider);
          final txs = await ref.read(transactionsProvider.future);
          final range = _getDateRange();
          try {
            final bytes = await reportSvc.generatePnlPdf(
              l10n: l10n,
              transactions: txs,
              currency: settings.currency,
              periodStart: range.start,
              isMonthly: _period.type == FinancialPeriodType.monthEnd,
            );
            final label = '${range.start.day}_${range.start.month}_${range.start.year}'
                '_to_${range.end.day}_${range.end.month}_${range.end.year}';
            await shareSvc.sharePdf(bytes, 'PnL_$label.pdf',
                subject: 'Profit & Loss Statement', origin: origin);
          } catch (e) {
            debugPrint('P&L share error: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context)!.somethingWentWrong),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
        icon: const Icon(Icons.ios_share_rounded, size: 16),
        label: Text(AppLocalizations.of(context)!.shareReport, style: const TextStyle(fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryNavy,
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: AppColors.primaryNavy.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  HELPERS
// ═══════════════════════════════════════════════════════

class _BreakdownItem {
  final String label;
  final double amount;
  final Color color;
  final double percentage;

  _BreakdownItem({
    required this.label,
    required this.amount,
    required this.color,
    required this.percentage,
  });
}
