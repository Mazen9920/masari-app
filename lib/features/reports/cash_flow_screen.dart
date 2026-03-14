import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/services/share_service.dart';
import '../../core/providers/export_providers.dart';
import '../cash_flow/providers/scheduled_transactions_provider.dart';
import '../cash_flow/widgets/add_recurring_sheet.dart';
import '../dashboard/providers/dashboard_state_provider.dart';
import '../dashboard/widgets/custom_date_range_picker.dart';
import '../../shared/utils/money_utils.dart';
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
  DashboardPeriod _selectedPeriod = DashboardPeriod.monthToDate;
  DateTimeRange? _customRange;
  bool _monthlyChart = true;

  DateTimeRange _getDateRange() {
    if (_selectedPeriod == DashboardPeriod.custom && _customRange != null) {
      return _customRange!;
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59, 59);
    switch (_selectedPeriod) {
      case DashboardPeriod.today:
        return DateTimeRange(start: DateTime(now.year, now.month, now.day), end: today);
      case DashboardPeriod.yesterday:
        final y = now.subtract(const Duration(days: 1));
        return DateTimeRange(start: DateTime(y.year, y.month, y.day), end: DateTime(y.year, y.month, y.day, 23, 59, 59));
      case DashboardPeriod.last7Days:
        return DateTimeRange(start: now.subtract(const Duration(days: 7)), end: today);
      case DashboardPeriod.last30Days:
        return DateTimeRange(start: now.subtract(const Duration(days: 30)), end: today);
      case DashboardPeriod.last90Days:
        return DateTimeRange(start: now.subtract(const Duration(days: 90)), end: today);
      case DashboardPeriod.last365Days:
        return DateTimeRange(start: now.subtract(const Duration(days: 365)), end: today);
      case DashboardPeriod.lastMonth:
        final lastMonth = DateTime(now.year, now.month - 1);
        return DateTimeRange(start: lastMonth, end: DateTime(now.year, now.month, 0, 23, 59, 59));
      case DashboardPeriod.last12Months:
        return DateTimeRange(start: DateTime(now.year - 1, now.month, now.day), end: today);
      case DashboardPeriod.lastYear:
        return DateTimeRange(start: DateTime(now.year - 1, 1, 1), end: DateTime(now.year - 1, 12, 31, 23, 59, 59));
      case DashboardPeriod.weekToDate:
        final weekday = now.weekday;
        return DateTimeRange(start: now.subtract(Duration(days: weekday - 1)), end: today);
      case DashboardPeriod.monthToDate:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: today);
      case DashboardPeriod.quarterToDate:
        final qStart = DateTime(now.year, ((now.month - 1) ~/ 3) * 3 + 1, 1);
        return DateTimeRange(start: qStart, end: today);
      case DashboardPeriod.yearToDate:
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: today);
      case DashboardPeriod.custom:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: today);
    }
  }

  Future<void> _openDatePicker() async {
    final result = await showDateRangeSheet(
      context,
      currentPeriod: _selectedPeriod,
    );
    if (result == null) return;
    setState(() {
      if (result.period != null) {
        _selectedPeriod = result.period!;
        _customRange = null;
      } else if (result.customRange != null) {
        _selectedPeriod = DashboardPeriod.custom;
        _customRange = result.customRange;
      }
    });
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
    final dateRange = _getDateRange();
    final periodTransactions = transactions.where((t) => 
      !t.dateTime.isBefore(dateRange.start) && !t.dateTime.isAfter(dateRange.end)
    ).toList();

    final double moneyIn = roundMoney(periodTransactions
        .where((t) => t.isIncome)
        .fold(0.0, (sum, t) => sum + t.amount.abs()));

    final double moneyOut = roundMoney(periodTransactions
        .where((t) => !t.isIncome)
        .fold(0.0, (sum, t) => sum + t.amount.abs()));

    // Calculate cash balance up to the end of the selected period (includes opening cash)
    final double currentCashBalance = roundMoney(openingCash + transactions
        .where((t) => !t.dateTime.isAfter(dateRange.end))
        .fold(
      0.0,
      (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs()),
    ));

    // Calculate previous period's balance for growth %
    final double prevCashBalance = roundMoney(openingCash + transactions
        .where((t) => t.dateTime.isBefore(dateRange.start))
        .fold(
      0.0,
      (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs()),
    ));

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
                      _buildOpeningCashCard(openingCash, fmt),
                      const SizedBox(height: 16),
                      _buildHeroCard(currentCashBalance, prevCashBalance, fmt),
                      const SizedBox(height: 16),
                      if (currentCashBalance < 5000) ...[
                        _buildAlertBanner(currentCashBalance),
                        const SizedBox(height: 16),
                      ],
                      _buildAIForecastCard(currentCashBalance, moneyIn, moneyOut, fmt),
                      const SizedBox(height: 16),
                      _buildKPICards(moneyIn, moneyOut, fmt),
                      const SizedBox(height: 16),
                      _buildChartSection(),
                      const SizedBox(height: 16),
                      _buildComingUpSection(fmt),
                      const SizedBox(height: 24),
                      _buildShareButton(),
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

  Widget _buildOpeningCashCard(double openingCash, NumberFormat fmt) {
    final currency = ref.watch(appSettingsProvider).currency;
    final hasOpeningCash = openingCash != 0;
    return GestureDetector(
      onTap: _showEditOpeningCashDialog,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: hasOpeningCash ? AppColors.chartGreenLight : const Color(0xFFFEFCE8),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: hasOpeningCash ? AppColors.badgeBgPositive : const Color(0xFFFEF08A),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: hasOpeningCash
                    ? AppColors.chartGreen.withValues(alpha: 0.1)
                    : AppColors.chartOrange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasOpeningCash ? Icons.account_balance_wallet_rounded : Icons.add_rounded,
                color: hasOpeningCash ? AppColors.chartGreen : AppColors.chartOrange,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context)!.openingCashBalance,
                    style: AppTypography.sectionTitle.copyWith(
                      fontSize: 13,
                      color: hasOpeningCash ? AppColors.badgeTextPositive : const Color(0xFF854D0E),
                    ),
                  ),
                  if (!hasOpeningCash)
                    Padding(
                      padding: const EdgeInsets.only(top: 1, bottom: 1),
                      child: Text(
                        'How much cash did you start with before using Masari?',
                        style: AppTypography.captionSmall.copyWith(
                          fontSize: 10,
                          color: const Color(0xFFA16207).withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    hasOpeningCash
                        ? '$currency ${fmt.format(openingCash)}'
                        : 'Tap to set your starting cash',
                    style: hasOpeningCash
                        ? AppTypography.metricSmall.copyWith(fontSize: 16, color: AppColors.badgeTextPositive)
                        : AppTypography.bodySmall.copyWith(fontSize: 12, color: const Color(0xFFA16207)),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.edit_rounded,
              size: 18,
              color: hasOpeningCash
                  ? AppColors.chartGreen.withValues(alpha: 0.5)
                  : AppColors.chartOrange.withValues(alpha: 0.5),
            ),
          ],
        ),
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
              'Enter the cash you had before you started tracking transactions in Masari.',
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
              'Cancel',
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
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }



  Widget _buildDateSelector() {
    final dateRange = _getDateRange();
    final label = _selectedPeriod == DashboardPeriod.custom
        ? '${DateFormat('MMM d').format(dateRange.start)} – ${DateFormat('MMM d').format(dateRange.end)}'
        : _selectedPeriod.name.replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m[0]}').trim();

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

  Widget _buildHeroCard(double balance, double prevBalance, NumberFormat fmt) {
    final currency = ref.watch(appSettingsProvider).currency;
    return ReportCard(
      padding: const EdgeInsets.all(24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.currentCashBalance,
                style: AppTypography.captionSmall.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: 8),
              Text(
                '$currency ${fmt.format(balance)}',
                style: AppTypography.metric.copyWith(fontSize: 32),
              ),
              const SizedBox(height: 12),
              Builder(builder: (_) {
                final growthPct = prevBalance == 0
                    ? (balance > 0 ? 100.0 : (balance < 0 ? -100.0 : 0.0))
                    : ((balance - prevBalance) / prevBalance.abs()) * 100;
                final isPositive = growthPct >= 0;
                return Row(
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
                            '${isPositive ? '+' : ''}${growthPct.toStringAsFixed(1)}%',
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
                      'vs last month',
                      style: AppTypography.captionSmall.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                );
              }),
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
                  'Your current balance is critically low. Consider reviewing upcoming expenses to avoid a negative balance.',
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

    final forecastText = expectedRemainingFlow >= 0 
      ? 'Based on your recent transaction patterns, you should reach a healthy ${ref.watch(appSettingsProvider).currency} ${fmt.format(forecastAmount)} by the end of the month.'
      : 'Based on your recent spending, your balance may dip to ${ref.watch(appSettingsProvider).currency} ${fmt.format(forecastAmount)} by month-end. Consider cutting back on expenses.';
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

  Widget _buildChartSection() {
    final transactions = ref.watch(transactionsProvider).value ?? [];
    
    // Generate data points
    List<double> dataPoints = [];
    List<String> labels = [];
    
    if (_monthlyChart) {
      for (int i = 5; i >= 0; i--) {
        final date = DateTime(DateTime.now().year, DateTime.now().month - i);
        final label = DateFormat('MMM').format(date);
        
        final periodTxs = transactions.where((t) => t.dateTime.year == date.year && t.dateTime.month == date.month);
        final netFlow = periodTxs.fold(0.0, (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs()));
        dataPoints.add(netFlow);
        labels.add(label);
      }
    } else {
      // Last 4 weeks
      for (int i = 3; i >= 0; i--) {
        final endDate = DateTime.now().subtract(Duration(days: 7 * i));
        final startDate = endDate.subtract(const Duration(days: 7));
        final label = DateFormat('MMM d').format(endDate);
        
        final periodTxs = transactions.where((t) => t.dateTime.isAfter(startDate.subtract(const Duration(milliseconds: 1))) && t.dateTime.isBefore(endDate.add(const Duration(days: 1))));
        final netFlow = periodTxs.fold(0.0, (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs()));
        dataPoints.add(netFlow);
        labels.add(label);
      }
    }
    
    final maxVal = dataPoints.isEmpty ? 1.0 : dataPoints.map((e) => e.abs()).reduce(math.max);
    final effectiveMax = maxVal == 0 ? 1.0 : maxVal;

    return ReportCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocalizations.of(context)!.cashMovement,
                style: AppTypography.sectionTitle.copyWith(fontSize: 14),
              ),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ChartToggle(
                  showChart: _monthlyChart,
                  onToggle: () => setState(() => _monthlyChart = !_monthlyChart),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Dynamic Bar Chart
          SizedBox(
            height: 120,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(dataPoints.length, (index) {
                final val = dataPoints[index];
                final isPositive = val >= 0;
                final heightFactor = (val.abs() / effectiveMax).clamp(0.05, 1.0);
                
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      width: 32,
                      height: 100 * heightFactor,
                      decoration: BoxDecoration(
                        color: isPositive ? AppColors.success : AppColors.danger,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels.map((lbl) => Text(lbl, style: const TextStyle(fontSize: 10, color: AppColors.textTertiary))).toList(),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 400.ms);
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
                'Coming Up',
                style: AppTypography.sectionTitle,
              ),
              GestureDetector(
                onTap: () {
                  context.pushNamed('ScheduledTransactionsScreen');
                },
                child: Text(
                  'Manage',
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
                  'No upcoming payments',
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
                ? 'Due today'
                : daysUntil == 1
                    ? 'Due tomorrow'
                    : 'Due in $daysUntil days';
            
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
                   'Invoiced',
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
        try {
          final reportSvc = ref.read(reportServiceProvider);
          final shareSvc = ref.read(shareServiceProvider);
          final settings = ref.read(appSettingsProvider);
          final txs = await ref.read(transactionsProvider.future);
          final range = _getDateRange();
          final bytes = await reportSvc.generateCashFlowPdf(
            transactions: txs,
            currency: settings.currency,
            periodStart: range.start,
            isMonthly: _monthlyChart,
            openingBalance: settings.openingCashBalance,
          );
          final label = '${DateFormat('MMMd').format(range.start)}_${DateFormat('MMMd').format(range.end)}';
          await shareSvc.sharePdf(bytes, 'CashFlow_$label.pdf', subject: 'Cash Flow Statement', origin: origin);
        } catch (e) {
          debugPrint('Cash Flow share error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.somethingWentWrong), backgroundColor: Colors.red));
          }
        }
      },
      icon: const Icon(Icons.ios_share_rounded, size: 18),
      label: const Text('Share Summary'),
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
