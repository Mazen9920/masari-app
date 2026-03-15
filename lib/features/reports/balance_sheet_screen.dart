import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/services/share_service.dart';
import '../../core/providers/export_providers.dart';
import '../../shared/models/sale_model.dart';
import '../../shared/utils/money_utils.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/report_card.dart';
import 'widgets/chart_toggle.dart';

class BalanceSheetScreen extends ConsumerStatefulWidget {
  const BalanceSheetScreen({super.key});

  @override
  ConsumerState<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends ConsumerState<BalanceSheetScreen> {
  bool _showTrend = false;

  @override
  void initState() {
    super.initState();
    // Reports need the full dataset, not just the first page.
    Future.microtask(() {
      ref.read(inventoryProvider.notifier).loadAll();
      ref.read(salesProvider.notifier).loadAll();
      ref.read(transactionsProvider.notifier).loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en');

    // Persisted manual entries from Firestore
    final bs = ref.watch(balanceSheetEntriesProvider);

    // Real Data from Providers
    final inventoryProducts = ref.watch(inventoryProvider).value ?? [];
    final purchases = ref.watch(purchasesProvider);
    final sales = ref.watch(salesProvider).value ?? [];
    final allTransactions = ref.watch(transactionsProvider).value ?? [];

    // Bank balance = opening cash + all transaction flows (auto-computed from CF)
    final openingCash = ref.watch(appSettingsProvider).openingCashBalance;
    final double bankBalance = roundMoney(openingCash + allTransactions.fold(
      0.0,
      (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs()),
    ));

    final double inventoryValue = roundMoney(inventoryProducts.fold(0.0, (sum, p) => sum + p.totalCostValue));

    // Supplier payable = received goods value minus amount paid (accrual basis)
    final double suppliersOwing = roundMoney(purchases.fold(0.0, (sum, p) {
      final receivedValue = p.totalReceivedValue;
      final paid = p.amountPaid;
      return sum + (receivedValue - paid).clamp(0.0, double.maxFinite);
    }));

    // Supplier advance payments = paid ahead of receiving goods (a prepaid asset)
    final double supplierAdvancePayments = roundMoney(purchases.fold(0.0, (sum, p) {
      final receivedValue = p.totalReceivedValue;
      final paid = p.amountPaid;
      return sum + (paid - receivedValue).clamp(0.0, double.maxFinite);
    }));

    // Accounts receivable = outstanding from active (non-cancelled) sales
    final double accountsReceivable = roundMoney(sales
        .where((s) => s.orderStatus != OrderStatus.cancelled)
        .fold(0.0, (sum, s) => sum + s.outstanding));

    // Totals
    final double totalAssets = roundMoney(bankBalance + bs.cashOnHand + bs.unpaidInvoices + inventoryValue + accountsReceivable + supplierAdvancePayments);
    final double totalLiabilities = roundMoney(suppliersOwing + bs.loans + bs.unpaidSalaries);
    final double netEquity = roundMoney(totalAssets - totalLiabilities);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                ref.read(inventoryProvider.notifier).refreshAll(),
                ref.read(salesProvider.notifier).refreshAll(),
              ]);
            },
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 100 + MediaQuery.of(context).padding.bottom),
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              child: Column(
              children: [
                // Header / Trend Toggle
                _buildHeaderControls(),
                const SizedBox(height: 16),

                // Net Equity / Trend Section
                 AnimatedCrossFade(
                  firstChild: _buildNetEquitySection(fmt, netEquity, totalAssets, totalLiabilities),
                  secondChild: _buildTrendChart(fmt),
                  crossFadeState: _showTrend ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: 300.ms,
                ),
                const SizedBox(height: 24),

                // Assets (What You Own)
                _buildCollapsibleSection(
                  title: AppLocalizations.of(context)!.whatYouOwn,
                  subtitle: AppLocalizations.of(context)!.totalAssets,
                  amount: totalAssets,
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: AppColors.chartBlue,
                  iconBg: AppColors.chartBlueLight,
                  items: [
                    _SheetItem(
                      label: AppLocalizations.of(context)!.bankAccounts,
                      amount: bankBalance,
                      icon: Icons.account_balance_rounded,
                      pct: (totalAssets > 0) ? bankBalance / totalAssets : 0,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.cashOnHand,
                      amount: bs.cashOnHand,
                      icon: Icons.payments_rounded,
                      pct: (totalAssets > 0) ? bs.cashOnHand / totalAssets : 0,
                      onTap: () => _showEditDialog(AppLocalizations.of(context)!.cashOnHand, bs.cashOnHand, (v) {
                        ref.read(balanceSheetEntriesProvider.notifier).update(bs.copyWith(cashOnHand: v));
                      }),
                      isEditable: true,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.inventory,
                      amount: inventoryValue,
                      icon: Icons.inventory_2_rounded,
                      pct: (totalAssets > 0) ? inventoryValue / totalAssets : 0,
                      onTap: () => context.push('/manage/inventory'),
                      showChevron: true,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.otherReceivables,
                      amount: bs.unpaidInvoices,
                      icon: Icons.receipt_long_rounded,
                      pct: (totalAssets > 0) ? bs.unpaidInvoices / totalAssets : 0,
                      onTap: () => _showEditDialog(AppLocalizations.of(context)!.otherReceivables, bs.unpaidInvoices, (v) {
                        ref.read(balanceSheetEntriesProvider.notifier).update(bs.copyWith(unpaidInvoices: v));
                      }),
                      isEditable: true,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.salesReceivables,
                      amount: accountsReceivable,
                      icon: Icons.request_quote_rounded,
                      pct: (totalAssets > 0) ? accountsReceivable / totalAssets : 0,
                      onTap: () => context.push('/sales'),
                      showChevron: true,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.supplierPrepayments,
                      amount: supplierAdvancePayments,
                      icon: Icons.schedule_send_rounded,
                      pct: (totalAssets > 0) ? supplierAdvancePayments / totalAssets : 0,
                      onTap: () => context.push('/manage/suppliers'),
                      showChevron: true,
                    ),
                  ],
                  fmt: fmt,
                  isAssets: true,
                ).animate().fadeIn(duration: 400.ms, delay: 100.ms),
                const SizedBox(height: 16),

                // Liabilities (What You Owe)
                _buildCollapsibleSection(
                  title: AppLocalizations.of(context)!.whatYouOwe,
                  subtitle: AppLocalizations.of(context)!.totalLiabilities,
                  amount: totalLiabilities,
                  icon: Icons.money_off_rounded,
                  iconColor: AppColors.chartRed,
                  iconBg: AppColors.chartRedLight,
                  items: [
                    _SheetItem(
                      label: AppLocalizations.of(context)!.supplierPayable,
                      amount: suppliersOwing,
                      icon: Icons.local_shipping_rounded,
                      pct: (totalLiabilities > 0) ? suppliersOwing / totalLiabilities : 0,
                       onTap: () => context.push('/manage/suppliers'),
                      showChevron: true,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.loans,
                      amount: bs.loans,
                      icon: Icons.credit_card_rounded,
                      pct: (totalLiabilities > 0) ? bs.loans / totalLiabilities : 0,
                       onTap: () => _showEditDialog(AppLocalizations.of(context)!.loans, bs.loans, (v) {
                        ref.read(balanceSheetEntriesProvider.notifier).update(bs.copyWith(loans: v));
                       }),
                       isEditable: true,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.unpaidSalaries,
                      amount: bs.unpaidSalaries,
                      icon: Icons.people_rounded,
                      pct: (totalLiabilities > 0) ? bs.unpaidSalaries / totalLiabilities : 0,
                      onTap: () => _showEditDialog(AppLocalizations.of(context)!.unpaidSalaries, bs.unpaidSalaries, (v) {
                        ref.read(balanceSheetEntriesProvider.notifier).update(bs.copyWith(unpaidSalaries: v));
                      }),
                      isEditable: true,
                    ),
                  ],
                  fmt: fmt,
                  isAssets: false,
                ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                const SizedBox(height: 16),

                // Owner's Equity (Assets − Liabilities)
                _buildCollapsibleSection(
                  title: AppLocalizations.of(context)!.ownersEquity,
                  subtitle: AppLocalizations.of(context)!.netWorth,
                  amount: netEquity,
                  icon: Icons.diamond_rounded,
                  iconColor: AppColors.chartGreen,
                  iconBg: AppColors.chartGreenLight,
                  items: [
                    _SheetItem(
                      label: AppLocalizations.of(context)!.totalAssets,
                      amount: totalAssets,
                      icon: Icons.account_balance_wallet_rounded,
                      pct: (totalAssets > 0) ? 1.0 : 0,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.lessTotalLiabilities,
                      amount: -totalLiabilities,
                      icon: Icons.remove_circle_outline_rounded,
                      pct: (totalAssets > 0) ? totalLiabilities / totalAssets : 0,
                    ),
                  ],
                  fmt: fmt,
                  isAssets: true,
                ).animate().fadeIn(duration: 400.ms, delay: 250.ms),

                // Accounting equation check
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.chartGreenLight, Color(0xFFD1FAE5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.badgeBgPositive),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.elasticOut,
                          builder: (_, value, child) => Transform.scale(
                            scale: value,
                            child: child,
                          ),
                          child: const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.badgeTextPositive),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)!.accountingEquationBalanced,
                          style: AppTypography.badge.copyWith(
                            fontSize: 12,
                            color: AppColors.badgeTextPositive,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // AI Insight
                _buildAIInsightCard(totalAssets, totalLiabilities, netEquity)
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 300.ms)
                    .scale(begin: const Offset(0.95, 0.95)),

                const SizedBox(height: 24),

                // Download Button (inline)
                _buildDownloadButton()
                    .animate()
                    .fadeIn(duration: 400.ms, delay: 400.ms)
                    .slideY(begin: 0.2, end: 0, curve: Curves.easeOutBack),
              ],
            ),
          ),
          ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  WIDGETS
  // ═══════════════════════════════════════════════════════

  Widget _buildHeaderControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ChartToggle(
          showChart: _showTrend,
          onToggle: () => setState(() => _showTrend = !_showTrend),
        ),
      ],
    );
  }

  Widget _buildTrendChart(NumberFormat fmt) {
    // Calculate historical Net Equity Trend based on transactions
    final transactions = ref.watch(transactionsProvider).value ?? [];
    final bs = ref.watch(balanceSheetEntriesProvider);

    // Compute bank balance from CF (opening cash + all transaction flows)
    final openingCash = ref.watch(appSettingsProvider).openingCashBalance;
    final double bankBalance = transactions.fold(
      openingCash,
      (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs()),
    );

    final baseAssets = bankBalance + bs.cashOnHand + bs.unpaidInvoices;
    final baseLiabilities = bs.loans + bs.unpaidSalaries;
    // We will calculate backwards: Current Net Equity - net change per month
    
    // Get inventory value and purchase-based supplier payable
    final inventoryProducts = ref.watch(inventoryProvider).value ?? [];
    final purchases = ref.watch(purchasesProvider);
    final sales = ref.watch(salesProvider).value ?? [];
    
    final double inventoryValue = inventoryProducts.fold(0.0, (sum, p) => sum + p.totalCostValue);
    final double suppliersOwing = purchases.fold(0.0, (sum, p) {
      final receivedValue = p.totalReceivedValue;
      final paid = p.amountPaid;
      return sum + (receivedValue - paid).clamp(0.0, double.maxFinite);
    });
    final double accountsReceivable = sales
        .where((s) => s.orderStatus != OrderStatus.cancelled)
        .fold(0.0, (sum, s) => sum + s.outstanding);
    
    final currentNetEquity = (baseAssets + inventoryValue + accountsReceivable) - (baseLiabilities + suppliersOwing);

    final data = <Map<String, dynamic>>[];
    final now = DateTime.now();
    double runningEquity = currentNetEquity;

    data.add({
      'month': DateFormat('MMM').format(now),
      'amount': runningEquity,
    });

    for (int i = 1; i <= 5; i++) {
      final monthEnd = DateTime(now.year, now.month - i + 1, 1);
      final monthStart = DateTime(now.year, now.month - i, 1);
      
      // Calculate net flow for that month
      double monthlyFlow = 0;
      for (final tx in transactions) {
        if (tx.excludeFromPL) continue;
        if (!tx.dateTime.isBefore(monthStart) && tx.dateTime.isBefore(monthEnd)) {
          monthlyFlow += tx.isIncome ? tx.amount.abs() : -tx.amount.abs();
        }
      }
      
      // If we go backwards, equity at start of month = equity at end - monthly flow
      runningEquity = runningEquity - monthlyFlow;
      
      data.insert(0, {
        'month': DateFormat('MMM').format(monthStart),
        'amount': runningEquity,
      });
    }

    double maxAmount = 1.0;
    for(final d in data) {
      if ((d['amount'] as double).abs() > maxAmount) maxAmount = (d['amount'] as double).abs();
    }

    return ReportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NET WORTH TREND',
            style: AppTypography.badge.copyWith(
              fontSize: 11,
              letterSpacing: 1.2,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 24),
          Container(
            height: 220,
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: data.map((d) {
                final amount = d['amount'] as double;
                final heightFactor = (amount.abs() / maxAmount).clamp(0.0, 1.0);
                final isCurrent = d == data.last;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Tooltip-ish label for current
                    if (isCurrent)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryNavy,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${(amount/1000).toStringAsFixed(0)}k',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      )
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .moveY(begin: 0, end: -4, duration: 1.seconds, curve: Curves.easeInOut),

                    // Bar
                    TweenAnimationBuilder<double>(
                      duration: 600.ms,
                      curve: Curves.easeOutBack,
                      tween: Tween(begin: 0, end: heightFactor),
                      builder: (context, val, _) {
                        return Container(
                          width: 32,
                          height: 140 * val, // Max bar height
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: isCurrent
                                  ? [AppColors.primaryNavy, AppColors.chartIndigo]
                                  : [const Color(0xFFE2E8F0), const Color(0xFFCBD5E1)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    // Label
                    Text(
                      d['month'] as String,
                      style: TextStyle(
                        color: isCurrent ? AppColors.textPrimary : AppColors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetEquitySection(NumberFormat fmt, double netEquity, double totalAssets, double totalLiabilities) {
    final currency = ref.watch(appSettingsProvider).currency;
    // Avoid division by zero
    final total = totalAssets + totalLiabilities;
    final assetPct = total > 0 ? totalAssets / total : 0.5;
    final liabilityPct = total > 0 ? totalLiabilities / total : 0.5;

    return Column(
      children: [
        Text(
          'NET EQUITY POSITION',
          style: AppTypography.badge.copyWith(
            fontSize: 11,
            letterSpacing: 1.2,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              currency,
              style: AppTypography.metricSmall.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              fmt.format(netEquity),
              style: AppTypography.metric,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.chartGreenLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.badgeBgPositive),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF6B7280)),
              SizedBox(width: 4),
              Text(
                'Add last month\'s data to see trend',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Distribution Card
        ReportCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Distribution',
                    style: AppTypography.sectionTitle.copyWith(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: 16,
                  child: Row(
                    children: [
                      Expanded(
                        flex: (assetPct * 100).toInt(),
                        child: Container(color: AppColors.chartBlue),
                      ),
                      Container(width: 2, color: Colors.white),
                      Expanded(
                        flex: (liabilityPct * 100).toInt(),
                        child: Container(color: AppColors.chartRed),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Legend
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildLegendItem(
                    label: 'Assets',
                    amount: '$currency ${(totalAssets / 1000).toStringAsFixed(0)}k',
                    color: AppColors.chartBlue,
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: AppColors.borderLight,
                  ),
                  _buildLegendItem(
                    label: 'Liabilities',
                    amount: '$currency ${(totalLiabilities / 1000).toStringAsFixed(0)}k',
                    color: AppColors.chartRed,
                    alignRight: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLegendItem({
    required String label,
    required String amount,
    required Color color,
    bool alignRight = false,
  }) {
    return Column(
      crossAxisAlignment:
          alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!alignRight) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
                letterSpacing: 0.5,
              ),
            ),
            if (alignRight) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: EdgeInsets.only(
              left: alignRight ? 0 : 16, right: alignRight ? 16 : 0),
          child: Text(
            amount,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  // Collapsible Section with Clickable Items
  Widget _buildCollapsibleSection({
    required String title,
    required String subtitle,
    required double amount,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required List<_SheetItem> items,
    required NumberFormat fmt,
    required bool isAssets,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppColors.cardShadow,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.sectionTitle.copyWith(fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTypography.captionSmall.copyWith(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              Text(
                '${(amount / 1000).toStringAsFixed(0)}k',
                style: AppTypography.metricSmall.copyWith(fontSize: 16),
              ),
            ],
          ),
          children: items.map((item) {
            final color = isAssets ? AppColors.chartBlue : AppColors.chartRed;
            return GestureDetector(
              onTap: () {
                if (item.onTap != null) {
                  HapticFeedback.lightImpact();
                  item.onTap!();
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundLight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(item.icon, size: 16, color: AppColors.textTertiary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.label,
                            style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                          ),
                        ),
                        if (item.isEditable)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Icon(Icons.edit_rounded, size: 12, color: AppColors.textTertiary.withValues(alpha: 0.5)),
                          ),
                        Text(
                          fmt.format(item.amount),
                          style: AppTypography.labelSmall.copyWith(color: AppColors.textPrimary),
                        ),
                        if (item.showChevron)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textTertiary),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: item.pct,
                        backgroundColor: AppColors.backgroundLight,
                        valueColor: AlwaysStoppedAnimation(color.withValues(alpha: 0.7)),
                        minHeight: 5,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _showEditDialog(String title, double currentValue, Function(double) onSave) async {
    final controller = TextEditingController(text: currentValue.toStringAsFixed(0));
    final currency = ref.read(appSettingsProvider).currency;
    final formKey = GlobalKey<FormState>();

    return showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Edit $title', style: AppTypography.h3),
              const SizedBox(height: 4),
              Text(
                'Current value: $currency ${NumberFormat('#,##0').format(currentValue)}',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Amount ($currency)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.attach_money_rounded),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () => controller.clear(),
                    tooltip: 'Clear',
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter an amount';
                  if (double.tryParse(v.trim()) == null) return 'Enter a valid number';
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (!formKey.currentState!.validate()) return;
                        final val = double.tryParse(controller.text.trim()) ?? currentValue;
                        onSave(val);
                        Navigator.of(ctx).pop();
                      },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }



  Widget _buildAIInsightCard(double totalAssets, double totalLiabilities, double netEquity) {
    return ReportCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.chartIndigo, AppColors.chartPurple],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 14),
              ),
              const SizedBox(width: 8),
              Text(
                'MASARI AI',
                style: AppTypography.badge.copyWith(
                  fontSize: 11,
                  letterSpacing: 1.0,
                  color: AppColors.chartIndigo,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Text(
                  'Coming Soon',
                  style: AppTypography.badge.copyWith(
                    fontSize: 10,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _generateAIInsight(totalAssets, totalLiabilities, netEquity),
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('AI analysis — coming soon!')),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'View Full Analysis',
                  style: AppTypography.badge.copyWith(
                    fontSize: 12,
                    color: AppColors.chartIndigo,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded,
                    size: 14, color: AppColors.chartIndigo),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _generateAIInsight(double totalAssets, double totalLiabilities, double netEquity) {
    if (totalAssets == 0 && totalLiabilities == 0) {
      return 'Start by adding your bank accounts, cash on hand, and liabilities to get a snapshot of your financial position.';
    }
    final debtRatio = totalAssets > 0 ? totalLiabilities / totalAssets : 0.0;
    if (debtRatio > 0.8) {
      return 'Your debt-to-asset ratio is ${(debtRatio * 100).toStringAsFixed(0)}%, which is high. Consider prioritizing debt repayment to improve your financial health.';
    }
    if (debtRatio > 0.5) {
      return 'Your debt-to-asset ratio is ${(debtRatio * 100).toStringAsFixed(0)}%. This is moderate — consider reducing liabilities to build a stronger equity position.';
    }
    final bsAi = ref.read(balanceSheetEntriesProvider);
    if (bsAi.cashOnHand > bsAi.loans && bsAi.loans > 0) {
      return 'Your cash on hand exceeds your loan balance. Consider paying down the loan to reduce interest expenses.';
    }
    if (netEquity > 0) {
      return 'Your net equity is positive at ${NumberFormat("#,##0").format(netEquity)}. Keep monitoring your balance sheet to maintain a healthy position.';
    }
    return 'Your liabilities exceed your assets. Focus on increasing revenue or reducing debt to improve your equity position.';
  }

  Widget _buildDownloadButton() {
    return Semantics(
      button: true,
      label: 'Download Balance Sheet report',
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
      onPressed: () async {
        HapticFeedback.mediumImpact();
        final origin = ShareService.originFrom(context);
        try {
          final reportSvc = ref.read(reportServiceProvider);
          final shareSvc = ref.read(shareServiceProvider);
          final settings = ref.read(appSettingsProvider);
          final bsManual = ref.read(balanceSheetEntriesProvider);
          final allTxns = ref.read(transactionsProvider).value ?? [];
          final products = await ref.read(inventoryProvider.future);
          final purchases = ref.read(purchasesProvider);
          final sales = await ref.read(salesProvider.future);

          // Compute bank balance from CF (opening cash + all transaction flows)
          final computedBank = allTxns.fold(
            settings.openingCashBalance,
            (sum, t) => sum + (t.isIncome ? t.amount.abs() : -t.amount.abs()),
          );
          final bs = bsManual.copyWith(bankAccounts: computedBank);

          final inventoryValue = products.fold<double>(0, (s, p) => s + p.totalCostValue);
          final accountsReceivable = sales
              .where((s) => s.orderStatus != OrderStatus.cancelled)
              .fold<double>(0, (sum, s) => sum + s.outstanding);
          final suppliersOwing = purchases.fold<double>(0.0, (sum, p) {
            final received = p.totalReceivedValue;
            return sum + (received - p.amountPaid).clamp(0.0, double.maxFinite);
          });
          final supplierPrepayments = purchases.fold<double>(0.0, (sum, p) {
            final received = p.totalReceivedValue;
            return sum + (p.amountPaid - received).clamp(0.0, double.maxFinite);
          });
          final bytes = await reportSvc.generateBalanceSheetPdf(
            bs: bs,
            inventoryValue: inventoryValue,
            accountsReceivable: accountsReceivable,
            supplierPrepayments: supplierPrepayments,
            suppliersOwing: suppliersOwing,
            currency: settings.currency,
          );
          await shareSvc.sharePdf(bytes, 'Balance_Sheet.pdf', subject: 'Balance Sheet', origin: origin);
        } catch (e) {
          debugPrint('Balance Sheet share error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong. Please try again.'), backgroundColor: Colors.red));
          }
        }
      },
      icon: const Icon(Icons.ios_share_rounded, size: 18),
      label: const Text('Share Report', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryNavy,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        elevation: 2,
        shadowColor: AppColors.primaryNavy.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
    ),
      ),
    );
  }
}

class _SheetItem {
  final String label;
  final double amount;
  final IconData icon;
  final double pct;
  final VoidCallback? onTap;
  final bool isEditable;
  final bool showChevron;

  _SheetItem({
    required this.label,
    required this.amount,
    required this.icon,
    required this.pct,
    this.onTap,
    this.isEditable = false,
    this.showChevron = false,
  });
}
