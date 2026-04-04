import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/services/share_service.dart';
import '../../core/providers/export_providers.dart';
import '../cash_flow/providers/scheduled_transactions_provider.dart';
import '../cash_flow/widgets/add_recurring_sheet.dart';
import 'widgets/financial_period_sheet.dart';
import '../../shared/utils/money_utils.dart';
import '../../shared/models/category_data.dart';
import '../../shared/models/transaction_model.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/report_card.dart';
import 'widgets/chart_toggle.dart';
import 'dart:math' as math;

class CashFlowScreen extends ConsumerStatefulWidget {
  const CashFlowScreen({super.key});

  @override
  ConsumerState<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends ConsumerState<CashFlowScreen> {
  FinancialPeriodResult _period = FinancialPeriodResult(
    type: FinancialPeriodType.monthEnd,
    range: DateTimeRange(
      start: DateTime(DateTime.now().year, DateTime.now().month, 1),
      end: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59),
    ),
    label: DateFormat('MMMM yyyy').format(DateTime.now()),
  );
  /// false = In/Out bar chart, true = cumulative balance line chart
  bool _showBalanceTrend = false;

  DateTimeRange _getDateRange() => _period.range;

  Future<void> _openDatePicker() async {
    final result = await showFinancialPeriodSheet(context, current: _period);
    if (result == null) return;
    setState(() => _period = result);
  }

  @override
  void initState() {
    super.initState();
    // Reports need the full dataset, not just the first page.
    Future.microtask(() {
      ref.read(transactionsProvider.notifier).loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider).value ?? [];
    final fmt = NumberFormat('#,##0', 'en');
    final openingCash = ref.watch(appSettingsProvider).openingCashBalance;
    
    // Calculate Money In / Out for selected period
    // Exclude cat_cogs — COGS is a non-cash accrual P&L entry.
    // The actual cash outflow for inventory is recorded as cat_supplier_payment.
    // Exclude excludeFromPL transactions — these are unpaid/partial sale revenue;
    // no cash was received, so they must not appear in cash flow.
    final dateRange = _getDateRange();
    final periodTransactions = transactions.where((t) => 
      !t.dateTime.isBefore(dateRange.start) && !t.dateTime.isAfter(dateRange.end)
        && t.categoryId != 'cat_cogs'
        && !t.excludeFromPL
    ).toList();

    final double moneyIn = roundMoney(periodTransactions
        .where((t) => t.isIncome)
        .fold(0.0, (sum, t) => sum + t.amount.abs()));

    final double moneyOut = roundMoney(periodTransactions
        .where((t) => !t.isIncome)
        .fold(0.0, (sum, t) => sum + t.amount.abs()));

    // GAAP classification: Operating / Investing / Financing with category breakdown
    final Map<CashFlowType, Map<String, double>> activityBreakdown = {
      CashFlowType.operating: {},
      CashFlowType.investing: {},
      CashFlowType.financing: {},
    };
    for (final t in periodTransactions) {
      final signed = t.isIncome ? t.amount.abs() : -t.amount.abs();
      final type = cashFlowTypeFor(t.categoryId);
      activityBreakdown[type]!
          .update(t.categoryId, (v) => v + signed, ifAbsent: () => signed);
    }
    final operatingNet = roundMoney(
        activityBreakdown[CashFlowType.operating]!.values.fold(0.0, (a, b) => a + b));
    final investingNet = roundMoney(
        activityBreakdown[CashFlowType.investing]!.values.fold(0.0, (a, b) => a + b));
    final financingNet = roundMoney(
        activityBreakdown[CashFlowType.financing]!.values.fold(0.0, (a, b) => a + b));

    // Net Cash Flow for the period = Operating + Investing + Financing
    final double netCashFlow = roundMoney(operatingNet + investingNet + financingNet);

    // Period Opening Balance = user-set seed + all cash transactions BEFORE period start
    // (excludes cat_cogs — non-cash accrual entry)
    // (excludes excludeFromPL — unpaid sale revenue is not cash)
    final double periodOpeningBalance = roundMoney(openingCash + transactions
        .where((t) => t.dateTime.isBefore(dateRange.start) && t.categoryId != 'cat_cogs' && !t.excludeFromPL)
        .fold(
      0.0,
      (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs()),
    ));

    // Closing Balance = Opening Balance + Net Cash Flow (standard accounting identity)
    final double closingBalance = roundMoney(periodOpeningBalance + netCashFlow);

    final isGrowth = ref.watch(tierProvider).isGrowthOrAbove;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => ref.read(transactionsProvider.notifier).refreshAll(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              padding: const EdgeInsets.only(bottom: 150), // Increase padding
              child: Column(
              children: [
                const SizedBox(height: 24),
                _buildDateSelector(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // === CASH FLOW STATEMENT ===
                      // 1. Opening Balance
                      _buildPeriodOpeningBalanceCard(periodOpeningBalance, openingCash, fmt),
                      const SizedBox(height: 16),
                      // 2. Money In / Money Out KPIs
                      _buildKPICards(moneyIn, moneyOut, fmt),
                      const SizedBox(height: 16),

                      if (isGrowth) ...[
                        // 3. GAAP Activity Breakdown → Net Cash Flow (Growth+)
                        _buildActivitiesBreakdown(activityBreakdown, operatingNet, investingNet, financingNet, fmt),
                        const SizedBox(height: 16),
                        // 4. Closing Balance = Opening + Net Cash Flow
                        _buildClosingBalanceCard(closingBalance, periodOpeningBalance, fmt),
                        const SizedBox(height: 16),
                        // Low-cash alert
                        if (moneyOut > 0 && closingBalance < moneyOut * 0.1 && closingBalance >= 0) ...[
                          _buildAlertBanner(closingBalance),
                          const SizedBox(height: 16),
                        ],
                        // AI Forecast (Growth+)
                        _buildAIForecastCard(closingBalance, moneyIn, moneyOut, fmt),
                        const SizedBox(height: 16),
                      ] else ...[
                        // Launch: simple net cash flow card
                        _buildNetCashFlowCard(
                          netCashFlow, fmt,
                          ref.watch(appSettingsProvider).currency,
                          AppLocalizations.of(context)!,
                        ),
                        const SizedBox(height: 16),
                      ],

                      _buildChartSection(),
                      const SizedBox(height: 16),

                      if (isGrowth) ...[
                        _buildComingUpSection(fmt),
                        const SizedBox(height: 24),
                        _buildShareButton(),
                      ] else ...[
                        _buildCashFlowUpgradeBanner(),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ),
          
          // AI button placeholder — disabled
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  WIDGETS
  // ═══════════════════════════════════════════════════════

  Widget _buildPeriodOpeningBalanceCard(double periodOpening, double seedCash, NumberFormat fmt) {
    final currency = ref.watch(appSettingsProvider).currency;
    final l10n = AppLocalizations.of(context)!;
    return ReportCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.chartBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.chartBlue, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.openingBalance,
                  style: AppTypography.sectionTitle.copyWith(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '$currency ${fmt.format(periodOpening)}',
                  style: AppTypography.metricSmall.copyWith(fontSize: 18),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _showEditOpeningCashDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_rounded, size: 14, color: AppColors.textTertiary),
                  const SizedBox(width: 4),
                  Text(
                    '$currency ${fmt.format(seedCash)}',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  void _showEditOpeningCashDialog() {
    final settings = ref.read(appSettingsProvider);
    final controller = TextEditingController(
      text: settings.openingCashBalance != 0
          ? settings.openingCashBalance.toStringAsFixed(0)
          : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          AppLocalizations.of(context)!.openingCashBalance,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.openingCashDialogDesc,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '${settings.currency} ',
                prefixStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                hintText: '0',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
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
                  borderSide: const BorderSide(color: AppColors.primaryNavy, width: 1.5),
                ),
              ),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(context)!.cancel,
              style: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w600),
            ),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.replaceAll(',', '')) ?? 0.0;
              ref.read(appSettingsProvider.notifier).setOpeningCashBalance(value);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(AppLocalizations.of(context)!.save, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }



  Widget _buildDateSelector() {
    final label = _period.label;

    return Center(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          _openDatePicker();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(50),
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
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClosingBalanceCard(double closing, double opening, NumberFormat fmt) {
    final currency = ref.watch(appSettingsProvider).currency;
    final l10n = AppLocalizations.of(context)!;
    final isPositive = closing >= opening;
    final changePct = opening == 0
        ? (closing > 0 ? 100.0 : (closing < 0 ? -100.0 : 0.0))
        : ((closing - opening) / opening.abs()) * 100;

    return ReportCard(
      padding: const EdgeInsets.all(24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.closingBalance,
                style: AppTypography.captionSmall.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: 8),
              Text(
                '$currency ${fmt.format(closing)}',
                style: AppTypography.metric.copyWith(fontSize: 32),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isPositive ? AppColors.badgeBgPositive : AppColors.badgeBgNegative,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isPositive ? Icons.trending_up : Icons.trending_down,
                          size: 14,
                          color: isPositive ? AppColors.badgeTextPositive : AppColors.badgeTextNegative,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${changePct >= 0 ? '+' : ''}${changePct.toStringAsFixed(1)}%',
                          style: AppTypography.badge.copyWith(
                            fontSize: 12,
                            color: isPositive ? AppColors.badgeTextPositive : AppColors.badgeTextNegative,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.vsOpeningBalance,
                    style: AppTypography.captionSmall.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            right: -24,
            bottom: -24,
            child: Opacity(
              opacity: 0.5,
              child: SvgSparklinePlaceholder(width: 140, height: 80),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildAlertBanner(double balance) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.chartOrangeLight,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.chartOrange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.accentOrange, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.lowCashAlert,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accentOrangeDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppLocalizations.of(context)!.lowCashAlertBody,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.accentOrangeDark.withValues(alpha: 0.8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms);
  }

  Widget _buildAIForecastCard(double balance, double monthlyIn, double monthlyOut, NumberFormat fmt) {
    // Calculate remaining expected flow (simple: assume same daily rate for rest of month)
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final daysPassed = now.day;
    final daysRemaining = daysInMonth - daysPassed;
    final dailyNetRate = daysPassed > 0 ? (monthlyIn - monthlyOut) / daysPassed : 0.0;
    final expectedRemainingFlow = dailyNetRate * daysRemaining;
    final forecastAmount = balance + expectedRemainingFlow;

    final currency = ref.watch(appSettingsProvider).currency;
    final forecastText = expectedRemainingFlow >= 0 
      ? AppLocalizations.of(context)!.forecastPositive(currency, fmt.format(forecastAmount))
      : AppLocalizations.of(context)!.forecastNegative(currency, fmt.format(forecastAmount));
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Blur Glow Effect placeholder
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.accentOrange.withValues(alpha: 0.2), blurRadius: 40)],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, color: AppColors.accentOrange, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.aiForecastComingSoon,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                    fontFamily: 'Inter',
                  ),
                  children: [
                    TextSpan(text: forecastText),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
  }

  Widget _buildKPICards(double moneyIn, double moneyOut, NumberFormat fmt) {
    final currency = ref.watch(appSettingsProvider).currency;
    return Row(
      children: [
        Expanded(
          child: _buildKPICard(
            label: AppLocalizations.of(context)!.moneyIn,
            amount: moneyIn,
            color: AppColors.chartGreen,
            fmt: fmt,
            currency: currency,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKPICard(
            label: AppLocalizations.of(context)!.moneyOut,
            amount: moneyOut,
            color: AppColors.chartRed,
            fmt: fmt,
            currency: currency,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 300.ms);
  }

  Widget _buildKPICard({
    required String label,
    required double amount,
    required Color color,
    required NumberFormat fmt,
    required String currency,
  }) {
    return ReportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.badge.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$currency ${fmt.format(amount)}',
            style: AppTypography.metricSmall,
          ),
        ],
      ),
    );
  }

  Widget _buildActivitiesBreakdown(
    Map<CashFlowType, Map<String, double>> breakdown,
    double operatingNet,
    double investingNet,
    double financingNet,
    NumberFormat fmt,
  ) {
    final currency = ref.watch(appSettingsProvider).currency;
    final l10n = AppLocalizations.of(context)!;
    final netCashFlow = roundMoney(operatingNet + investingNet + financingNet);

    return Column(
      children: [
        // Section note
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            l10n.gaapCashFlowNote,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
        ),

        // Operating Activities
        _buildActivitySection(
          title: l10n.operatingActivities,
          netLabel: l10n.netOperatingCashFlow,
          icon: Icons.storefront_rounded,
          color: AppColors.chartBlue,
          categoryMap: breakdown[CashFlowType.operating]!,
          net: operatingNet,
          fmt: fmt,
          currency: currency,
          l10n: l10n,
        ),
        const SizedBox(height: 12),

        // Investing Activities
        _buildActivitySection(
          title: l10n.investingActivities,
          netLabel: l10n.netInvestingCashFlow,
          icon: Icons.trending_up_rounded,
          color: AppColors.chartOrange,
          categoryMap: breakdown[CashFlowType.investing]!,
          net: investingNet,
          fmt: fmt,
          currency: currency,
          l10n: l10n,
        ),
        const SizedBox(height: 12),

        // Financing Activities
        _buildActivitySection(
          title: l10n.financingActivities,
          netLabel: l10n.netFinancingCashFlow,
          icon: Icons.account_balance_rounded,
          color: AppColors.chartGreen,
          categoryMap: breakdown[CashFlowType.financing]!,
          net: financingNet,
          fmt: fmt,
          currency: currency,
          l10n: l10n,
        ),
        const SizedBox(height: 12),

        // Net Cash Flow summary
        _buildNetCashFlowCard(netCashFlow, fmt, currency, l10n),
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 350.ms);
  }

  Widget _buildActivitySection({
    required String title,
    required String netLabel,
    required IconData icon,
    required Color color,
    required Map<String, double> categoryMap,
    required double net,
    required NumberFormat fmt,
    required String currency,
    required AppLocalizations l10n,
  }) {
    final isPositive = net >= 0;
    // Sort categories by absolute value descending
    final sorted = categoryMap.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    return ReportCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          initiallyExpanded: categoryMap.isNotEmpty,
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${isPositive ? '+' : ''}$currency ${fmt.format(net)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isPositive ? AppColors.chartGreen : AppColors.chartRed,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
            ],
          ),
          children: [
            if (sorted.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Text(
                  l10n.noDataForPeriod,
                  style: AppTypography.captionSmall.copyWith(color: AppColors.textTertiary),
                ),
              )
            else ...[
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...sorted.map((e) {
                final catData = CategoryData.findById(e.key);
                final amount = roundMoney(e.value);
                final isInflow = amount >= 0;
                final maxAbs = sorted.first.value.abs();
                final barFraction = maxAbs > 0 ? (amount.abs() / maxAbs).clamp(0.0, 1.0) : 0.0;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _navigateToCategory(e.key, catData.localizedName(l10n)),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: catData.displayColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  catData.localizedName(l10n),
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              Text(
                                '${isInflow ? '+' : ''}$currency ${fmt.format(amount)}',
                                style: AppTypography.labelSmall.copyWith(
                                  color: isInflow ? AppColors.chartGreen : AppColors.chartRed,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.textTertiary),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: barFraction,
                              backgroundColor: AppColors.backgroundLight,
                              valueColor: AlwaysStoppedAnimation(
                                isInflow ? AppColors.chartGreen : AppColors.chartRed,
                              ),
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        netLabel,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    Text(
                      '${isPositive ? '+' : ''}$currency ${fmt.format(net)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: isPositive ? AppColors.chartGreen : AppColors.chartRed,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNetCashFlowCard(double net, NumberFormat fmt, String currency, AppLocalizations l10n) {
    final isPositive = net >= 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPositive ? AppColors.chartGreenLight : AppColors.chartRedLight,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(
          color: isPositive ? AppColors.badgeBgPositive : AppColors.badgeBgNegative,
        ),
      ),
      child: Row(
        children: [
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.netCashFlow,
                  style: AppTypography.badge.copyWith(
                    fontSize: 11,
                    color: isPositive ? AppColors.badgeTextPositive : AppColors.badgeTextNegative,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${isPositive ? '+' : ''}$currency ${fmt.format(net)}',
                  style: AppTypography.metricSmall.copyWith(
                    color: isPositive ? AppColors.badgeTextPositive : AppColors.badgeTextNegative,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToCategory(String categoryId, String displayName) {
    HapticFeedback.lightImpact();
    final filter = TransactionFilter(
      type: TransactionType.all,
      amountRange: const RangeValues(0, 1000000),
      selectedCategories: {categoryId},
    );
    context.pushNamed(
      'TransactionsListScreen',
      extra: {
        'pageTitle': '$displayName Transactions',
        'showBackButton': true,
        'initialFilter': filter,
      },
    );
  }

  Widget _buildCashFlowUpgradeBanner() {
    final l10n = AppLocalizations.of(context)!;
    return ReportCard(
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accentOrange.withValues(alpha: 0.15),
                  AppColors.accentOrange.withValues(alpha: 0.05),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.analytics_rounded, color: AppColors.accentOrange, size: 28),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.featureFullCashFlow,
            style: AppTypography.sectionTitle.copyWith(fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.featureFullCashFlowDesc,
            style: AppTypography.captionSmall.copyWith(color: AppColors.textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _upgradeBadge(l10n.operatingActivities),
              _upgradeBadge(l10n.investingActivities),
              _upgradeBadge(l10n.financingActivities),
              _upgradeBadge(l10n.closingBalance),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/profile/subscription'),
              icon: const Icon(Icons.rocket_launch_rounded, size: 18),
              label: Text(l10n.upgradeToGrowth),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 500.ms);
  }

  Widget _upgradeBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: AppTypography.captionSmall.copyWith(
          color: AppColors.accentOrange,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildChartSection() {
    final transactions = ref.watch(transactionsProvider).value ?? [];
    final openingCash = ref.watch(appSettingsProvider).openingCashBalance;
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(appSettingsProvider).currency;

    // Build 6 monthly buckets
    final List<_ChartBucket> buckets = [];
    for (int i = 5; i >= 0; i--) {
      final date = DateTime(DateTime.now().year, DateTime.now().month - i);
      final periodTxs = transactions.where((t) =>
          t.dateTime.year == date.year &&
          t.dateTime.month == date.month &&
          t.categoryId != 'cat_cogs');
      double inflow = 0, outflow = 0;
      for (final t in periodTxs) {
        if (t.isIncome) {
          inflow += t.amount.abs();
        } else {
          outflow += t.amount.abs();
        }
      }
      buckets.add(_ChartBucket(
        label: DateFormat('MMM').format(date),
        inflow: roundMoney(inflow),
        outflow: roundMoney(outflow),
        month: date,
      ));
    }

    // Compute cumulative balance at end of each bucket month
    for (int i = 0; i < buckets.length; i++) {
      final monthEnd = DateTime(buckets[i].month.year, buckets[i].month.month + 1, 0, 23, 59, 59);
      buckets[i].cumulativeBalance = roundMoney(openingCash + transactions
          .where((t) => !t.dateTime.isAfter(monthEnd) && t.categoryId != 'cat_cogs')
          .fold(0.0, (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs())));
    }

    return ReportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _showBalanceTrend ? l10n.closingBalance : l10n.cashMovement,
                style: AppTypography.sectionTitle.copyWith(fontSize: 14),
              ),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ChartToggle(
                  showChart: _showBalanceTrend,
                  onToggle: () => setState(() => _showBalanceTrend = !_showBalanceTrend),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Chart
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: _showBalanceTrend
                ? _buildBalanceTrendChart(buckets, currency)
                : _buildInOutBarChart(buckets, currency),
          ),

          const SizedBox(height: 16),

          // Legend
          if (!_showBalanceTrend)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legendDot(AppColors.chartGreen, l10n.moneyIn),
                const SizedBox(width: 20),
                _legendDot(AppColors.chartRed, l10n.moneyOut),
              ],
            ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 400.ms);
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: AppTypography.captionSmall.copyWith(color: AppColors.textTertiary)),
      ],
    );
  }

  // ── In/Out grouped bar chart ──────────────────────────
  Widget _buildInOutBarChart(List<_ChartBucket> buckets, String currency) {
    final maxVal = buckets.fold<double>(0, (m, b) => math.max(m, math.max(b.inflow, b.outflow)));
    final safeMax = maxVal == 0 ? 1000.0 : maxVal * 1.15;

    return SizedBox(
      key: const ValueKey('bar'),
      height: 180,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: safeMax,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.primaryNavy,
              tooltipBorderRadius: BorderRadius.circular(8),
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final b = buckets[group.x];
                final isIn = rodIndex == 0;
                return BarTooltipItem(
                  '${isIn ? '+' : '-'}$currency ${NumberFormat.compact().format(isIn ? b.inflow : b.outflow)}',
                  TextStyle(
                    color: isIn ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: safeMax / 4,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.borderLight,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: safeMax / 4,
                getTitlesWidget: (value, _) {
                  if (value == 0) return const SizedBox.shrink();
                  return Text(
                    _shortNum(value),
                    style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, _) {
                  final i = value.toInt();
                  if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      buckets[i].label,
                      style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: List.generate(buckets.length, (i) {
            final b = buckets[i];
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: b.inflow == 0 ? 0 : b.inflow,
                  color: AppColors.chartGreen,
                  width: 12,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
                BarChartRodData(
                  toY: b.outflow == 0 ? 0 : b.outflow,
                  color: AppColors.chartRed,
                  width: 12,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
              ],
            );
          }),
        ),
        duration: const Duration(milliseconds: 400),
      ),
    );
  }

  // ── Cumulative balance line chart ─────────────────────
  Widget _buildBalanceTrendChart(List<_ChartBucket> buckets, String currency) {
    final spots = List.generate(
      buckets.length,
      (i) => FlSpot(i.toDouble(), buckets[i].cumulativeBalance),
    );

    final allVals = buckets.map((b) => b.cumulativeBalance);
    final minVal = allVals.isEmpty ? 0.0 : allVals.reduce(math.min);
    final maxVal = allVals.isEmpty ? 1000.0 : allVals.reduce(math.max);
    final range = maxVal - minVal;
    final safeMin = minVal - range * 0.1;
    final safeMax = maxVal + range * 0.1;
    final interval = range == 0 ? 250.0 : range / 4;

    final color = minVal >= 0 ? AppColors.chartBlue : AppColors.chartOrange;

    return SizedBox(
      key: const ValueKey('line'),
      height: 180,
      child: LineChart(
        LineChartData(
          minY: safeMin,
          maxY: safeMax,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: interval,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppColors.borderLight,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                interval: interval,
                getTitlesWidget: (value, _) {
                  return Text(
                    _shortNum(value),
                    style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, _) {
                  final i = value.toInt();
                  if (i < 0 || i >= buckets.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      buckets[i].label,
                      style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.primaryNavy,
              tooltipBorderRadius: BorderRadius.circular(8),
              getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                '$currency ${NumberFormat.compact().format(s.y)}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
              )).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: color,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                  radius: 3,
                  color: Colors.white,
                  strokeWidth: 2,
                  strokeColor: color,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color.withValues(alpha: 0.2),
                    color.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
          // Zero line when balance goes negative
          extraLinesData: minVal < 0
              ? ExtraLinesData(horizontalLines: [
                  HorizontalLine(
                    y: 0,
                    color: AppColors.textTertiary.withValues(alpha: 0.3),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ])
              : const ExtraLinesData(),
        ),
        duration: const Duration(milliseconds: 400),
      ),
    );
  }

  static String _shortNum(double v) {
    final abs = v.abs();
    final sign = v < 0 ? '-' : '';
    if (abs >= 1000000) return '$sign${(abs / 1000000).toStringAsFixed(1)}M';
    if (abs >= 1000) return '$sign${(abs / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }

  Widget _buildComingUpSection(NumberFormat fmt) {
    final scheduled = ref.watch(scheduledTransactionsProvider);
    // Sort by next due date
    final sorted = List.of(scheduled)..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
    // Take top 3
    final upcoming = sorted.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12, right: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.of(context)!.comingUp,
                style: AppTypography.sectionTitle,
              ),
              GestureDetector(
                onTap: () {
                  context.pushNamed('ScheduledTransactionsScreen');
                },
                child: Text(
                  AppLocalizations.of(context)!.manage,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryNavy,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (upcoming.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              children: [
                Icon(Icons.calendar_today_rounded, color: AppColors.textTertiary, size: 32),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.noUpcomingPayments,
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ...upcoming.map((t) {
            // Calculate progress (mock logic for now: days passed / 30)
            // Real logic requires "last paid date"
            final daysUntil = t.nextDueDate.difference(DateTime.now()).inDays;
            final progress = (30 - daysUntil).clamp(0, 30) / 30.0;
            final countdownText = daysUntil <= 0
                ? AppLocalizations.of(context)!.dueToday
                : daysUntil == 1
                    ? AppLocalizations.of(context)!.dueTomorrow
                    : AppLocalizations.of(context)!.dueInDays(daysUntil);
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildUpcomingItem(
                title: t.title,
                subtitle: countdownText,
                amount: t.amount,
                color: t.isIncome ? Colors.green : Colors.orange,
                icon: t.isIncome ? Icons.monetization_on_rounded : Icons.payment_rounded,
                progress: t.isActive ? progress : 0, 
                progressColor: t.isIncome ? Colors.green : Colors.orange,
                fmt: fmt,
                isIncome: t.isIncome,
                onTap: () {
                  showModalBottomSheet(
  useRootNavigator: true,
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => AddRecurringSheet(transaction: t),
                  );
                },
              ),
            );
          }),
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 500.ms);
  }

  Widget _buildUpcomingItem({
    required String title,
    required String subtitle,
    required double amount,
    required Color color,
    required IconData icon,
    required double progress, // 0 to 1
    required Color progressColor,
    required NumberFormat fmt,
    bool isIncome = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
           BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isIncome ? '+' : ''} ${ref.watch(appSettingsProvider).currency} ${fmt.format(amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isIncome ? AppColors.chartGreen : AppColors.textPrimary,
                ),
              ),
              if (!isIncome) ...[
                const SizedBox(height: 6),
                Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: progressColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                 const SizedBox(height: 6),
                 Text(
                   AppLocalizations.of(context)!.invoiced,
                   style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                 )
              ]
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _buildShareButton() {
    return TextButton.icon(
      onPressed: () async {
        HapticFeedback.lightImpact();
        final origin = ShareService.originFrom(context);
        final l10n = AppLocalizations.of(context)!;
        try {
          final reportSvc = ref.read(reportServiceProvider);
          final shareSvc = ref.read(shareServiceProvider);
          final settings = ref.read(appSettingsProvider);
          final txs = await ref.read(transactionsProvider.future);
          final range = _getDateRange();
          final bytes = await reportSvc.generateCashFlowPdf(
            l10n: l10n,
            transactions: txs,
            currency: settings.currency,
            periodStart: range.start,
            periodEnd: range.end,
            isMonthly: true,
            openingBalance: settings.openingCashBalance,
          );
          final label = '${DateFormat('MMMd').format(range.start)}_${DateFormat('MMMd').format(range.end)}';
          await shareSvc.sharePdf(bytes, 'CashFlow_$label.pdf', subject: 'Cash Flow Statement', origin: origin);
        } catch (e) {
          if (kDebugMode) debugPrint('Cash Flow share error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.somethingWentWrong), backgroundColor: Colors.red));
          }
        }
      },
      icon: const Icon(Icons.ios_share_rounded, size: 18),
      label: Text(AppLocalizations.of(context)!.shareSummary),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textTertiary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  PAINTERS
// ═══════════════════════════════════════════════════════

class SvgSparklinePlaceholder extends StatelessWidget {
  final double width;
  final double height;

  const SvgSparklinePlaceholder({super.key, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.chartBlue.withValues(alpha: 0.2)
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;
      
    final path = Path();
    path.moveTo(0, size.height * 0.8);
    path.quadraticBezierTo(size.width * 0.2, size.height * 0.7, size.width * 0.4, size.height * 0.6);
    path.quadraticBezierTo(size.width * 0.8, size.height * 0.4, size.width, size.height * 0.2);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AbstractChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path();
    path.moveTo(0, h * 0.8);
    path.cubicTo(w * 0.2, h * 0.9, w * 0.2, h * 0.4, w * 0.4, h * 0.5);
    path.cubicTo(w * 0.6, h * 0.6, w * 0.6, h * 0.2, w * 0.8, h * 0.3);
    path.lineTo(w, h * 0.1);
    
    // Gradient fill
    final fillPath = Path.from(path);
    fillPath.lineTo(w, h);
    fillPath.lineTo(0, h);
    fillPath.close();

    final paintFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.accentOrange.withValues(alpha: 0.2),
          AppColors.accentOrange.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, paintFill);

    // Stroke
    final paintStroke = Paint()
      ..color = AppColors.accentOrange
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, paintStroke);

    // Points
    final pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final pointBorder = Paint()
      ..color = AppColors.accentOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final p1 = Offset(w * 0.4, h * 0.5);
    final p2 = Offset(w * 0.8, h * 0.3);

    canvas.drawCircle(p1, 3, pointPaint);
    canvas.drawCircle(p1, 3, pointBorder);

    canvas.drawCircle(p2, 3, pointPaint);
    canvas.drawCircle(p2, 3, pointBorder);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChartBucket {
  final String label;
  final double inflow;
  final double outflow;
  final DateTime month;
  double cumulativeBalance = 0;

  _ChartBucket({
    required this.label,
    required this.inflow,
    required this.outflow,
    required this.month,
  });
}
