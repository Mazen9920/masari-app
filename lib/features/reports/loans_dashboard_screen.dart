import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/navigation/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/loan_model.dart';
import '../../shared/utils/safe_pop.dart';
import 'package:go_router/go_router.dart';

/// Comprehensive Loans dashboard showing total debt, outstanding balances,
/// payment progress, all loans, and payment history.
class LoansDashboardScreen extends ConsumerStatefulWidget {
  const LoansDashboardScreen({super.key});

  @override
  ConsumerState<LoansDashboardScreen> createState() =>
      _LoansDashboardScreenState();
}

class _LoansDashboardScreenState extends ConsumerState<LoansDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _fmt = NumberFormat('#,##0.00', 'en');
  final _dateFmt = DateFormat('MMM d, yyyy');
  final _monthFmt = DateFormat('MMM yyyy');

  // ── Filters ──
  String _statusFilter = 'all'; // all / active / paidOff / defaulted
  String _typeFilter = 'all'; // all / type name

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

  List<Loan> _filtered(List<Loan> all) {
    return all.where((l) {
      if (_statusFilter != 'all' && l.status.name != _statusFilter) {
        return false;
      }
      if (_typeFilter != 'all' && l.type.name != _typeFilter) return false;
      return true;
    }).toList();
  }

  double _totalPrincipal(List<Loan> loans) =>
      loans.fold(0.0, (s, l) => s + l.principalAmount);

  double _totalOutstanding(List<Loan> loans) =>
      loans.fold(0.0, (s, l) => s + l.outstandingBalance);

  double _totalPaid(List<Loan> loans) =>
      loans.fold(0.0, (s, l) => s + l.totalPaid);

  double _totalMonthlyPayment(List<Loan> loans) =>
      loans.where((l) => l.status == LoanStatus.active).fold(
          0.0, (s, l) => s + l.monthlyPayment);

  @override
  Widget build(BuildContext context) {
    final loans = ref.watch(loansProvider);
    final settings = ref.watch(appSettingsProvider);
    final currency = settings.currency;
    final activeLoans =
        loans.where((l) => l.status == LoanStatus.active).toList();

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
                onPressed: () => context.push(AppRoutes.addLoan),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6B1B4F), Color(0xFFB83280)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 56, 24, 60),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Loans',
                            style: AppTypography.metricSmall
                                .copyWith(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          '$currency ${_fmt.format(_totalOutstanding(activeLoans))}',
                          style: AppTypography.metric
                              .copyWith(color: Colors.white, fontSize: 28),
                        ),
                        const SizedBox(height: 2),
                        Text('Outstanding Balance',
                            style: AppTypography.caption
                                .copyWith(color: Colors.white60)),
                        const Spacer(),
                        Row(
                          children: [
                            _heroStat('Total Borrowed',
                                '$currency ${_fmt.format(_totalPrincipal(activeLoans))}'),
                            const SizedBox(width: 24),
                            _heroStat('Total Paid',
                                '$currency ${_fmt.format(_totalPaid(activeLoans))}'),
                            const SizedBox(width: 24),
                            _heroStat('Loans', '${activeLoans.length}'),
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
                Tab(text: 'Loans'),
                Tab(text: 'Payments'),
                Tab(text: 'Schedule'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(loans, activeLoans, currency),
            _buildLoansTab(loans, currency),
            _buildPaymentsTab(loans, currency),
            _buildScheduleTab(activeLoans, currency),
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
            style: AppTypography.caption
                .copyWith(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value,
            style: AppTypography.labelMedium
                .copyWith(color: Colors.white, fontSize: 13)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 1: OVERVIEW
  // ═══════════════════════════════════════════════════════

  Widget _buildOverviewTab(
      List<Loan> all, List<Loan> active, String currency) {
    final paidOff =
        all.where((l) => l.status == LoanStatus.paidOff).toList();
    final monthlyPmt = _totalMonthlyPayment(active);
    final totalInterest =
        active.fold(0.0, (s, l) => s + l.totalInterest);

    // Type breakdown
    final byType = <LoanType, List<Loan>>{};
    for (final l in active) {
      byType.putIfAbsent(l.type, () => []).add(l);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // KPI Cards
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                'Total Loans',
                '${all.length}',
                Icons.account_balance_rounded,
                AppColors.chartPurple,
                subtitle:
                    '${active.length} active · ${paidOff.length} paid off',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                'Monthly Payment',
                '$currency ${_fmt.format(monthlyPmt)}',
                Icons.calendar_month_rounded,
                AppColors.chartOrange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _kpiCard(
                'Total Interest',
                '$currency ${_fmt.format(totalInterest)}',
                Icons.percent_rounded,
                AppColors.chartRed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Overall progress
        if (active.isNotEmpty) ...[
          _sectionTitle('Repayment Progress'),
          const SizedBox(height: 8),
          _overallProgressCard(active, currency),
          const SizedBox(height: 20),
        ],

        // By type breakdown
        if (byType.isNotEmpty) ...[
          _sectionTitle('By Type'),
          const SizedBox(height: 8),
          ...byType.entries.map((e) {
            final typeLoans = e.value;
            final outstanding = _totalOutstanding(typeLoans);
            return _typeRow(
              '${e.key.icon} ${e.key.label}',
              '${typeLoans.length} loan${typeLoans.length == 1 ? '' : 's'}',
              '$currency ${_fmt.format(outstanding)}',
            );
          }),
        ],

        const SizedBox(height: 20),

        // Health indicators
        _sectionTitle('Loan Health'),
        const SizedBox(height: 8),
        ..._buildLoanHealth(active),
      ].animate(interval: 50.ms).fadeIn(duration: 300.ms).slideY(begin: 0.02),
    );
  }

  Widget _overallProgressCard(List<Loan> active, String currency) {
    final totalDue =
        active.fold(0.0, (s, l) => s + l.totalAmountDue);
    final totalPd = _totalPaid(active);
    final pct = totalDue > 0 ? totalPd / totalDue : 0.0;

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
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Overall Progress',
                  style: AppTypography.labelMedium),
              Text('${(pct * 100).toStringAsFixed(1)}%',
                  style: AppTypography.labelMedium
                      .copyWith(color: AppColors.chartGreen)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.grey.shade100,
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.chartGreen),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Paid: $currency ${_fmt.format(totalPd)}',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.chartGreen)),
              Text('Remaining: $currency ${_fmt.format(totalDue - totalPd)}',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLoanHealth(List<Loan> active) {
    final nearEnd =
        active.where((l) => l.remainingMonths <= 3 && !l.isFullyPaid).length;
    final onTrack = active
        .where((l) => l.remainingMonths > 3 && !l.isFullyPaid)
        .length;
    final overdue = active
        .where((l) => l.status == LoanStatus.defaulted)
        .length;

    return [
      _healthRow(Icons.check_circle_rounded, AppColors.chartGreen,
          'On Track', '$onTrack loans', 'More than 3 months remaining'),
      _healthRow(Icons.warning_rounded, AppColors.chartOrange,
          'Near Maturity', '$nearEnd loans', '3 months or less remaining'),
      if (overdue > 0)
        _healthRow(Icons.error_rounded, AppColors.chartRed,
            'Defaulted', '$overdue loans', 'Requires attention'),
    ];
  }

  Widget _healthRow(
      IconData icon, Color color, String label, String count, String sub) {
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
  // TAB 2: LOANS LIST
  // ═══════════════════════════════════════════════════════

  Widget _buildLoansTab(List<Loan> all, String currency) {
    final filtered = _filtered(all);

    return Column(
      children: [
        _buildLoanFilters(all),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                  '${filtered.length} loan${filtered.length == 1 ? '' : 's'}',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textTertiary)),
              const Spacer(),
              if (_statusFilter != 'all' || _typeFilter != 'all')
                GestureDetector(
                  onTap: () => setState(() {
                    _statusFilter = 'all';
                    _typeFilter = 'all';
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
              ? _emptyState('No loans match filters')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) =>
                      _loanTile(filtered[i], currency),
                ),
        ),
      ],
    );
  }

  Widget _buildLoanFilters(List<Loan> all) {
    final types = all.map((l) => l.type).toSet().toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', _statusFilter == 'all',
                    () => setState(() => _statusFilter = 'all')),
                _filterChip('Active', _statusFilter == 'active',
                    () => setState(() => _statusFilter = 'active')),
                _filterChip('Paid Off', _statusFilter == 'paidOff',
                    () => setState(() => _statusFilter = 'paidOff')),
                _filterChip('Defaulted', _statusFilter == 'defaulted',
                    () => setState(() => _statusFilter = 'defaulted')),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (types.length > 1)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('All Types', _typeFilter == 'all',
                      () => setState(() => _typeFilter = 'all')),
                  ...types.map((t) => _filterChip(
                      '${t.icon} ${t.label}',
                      _typeFilter == t.name,
                      () => setState(() => _typeFilter = t.name))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _loanTile(Loan loan, String currency) {
    return GestureDetector(
      onTap: () => _showLoanDetail(loan, currency),
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
                    color: _typeColor(loan.type).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(loan.type.icon,
                        style: const TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loan.name,
                          style: AppTypography.labelMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${loan.type.label} · ${loan.lender ?? 'N/A'}',
                              style: AppTypography.caption
                                  .copyWith(color: AppColors.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (loan.status != LoanStatus.active) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: loan.status == LoanStatus.paidOff
                                    ? AppColors.chartGreen.withValues(alpha: 0.12)
                                    : AppColors.chartRed.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(loan.status.label,
                                  style: AppTypography.caption.copyWith(
                                    color: loan.status == LoanStatus.paidOff
                                        ? AppColors.chartGreen
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
                    Text('$currency ${_fmt.format(loan.outstandingBalance)}',
                        style: AppTypography.labelMedium),
                    Text('Outstanding',
                        style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary, fontSize: 10)),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textTertiary),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: loan.progressPct.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: Colors.grey.shade100,
                valueColor: AlwaysStoppedAnimation(
                  loan.isFullyPaid
                      ? AppColors.chartGreen
                      : loan.remainingMonths <= 3
                          ? AppColors.chartOrange
                          : AppColors.chartBlue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 3: PAYMENTS
  // ═══════════════════════════════════════════════════════

  Widget _buildPaymentsTab(List<Loan> all, String currency) {
    // Collect all payments across all loans
    final allPayments = <_PaymentEntry>[];
    for (final loan in all) {
      for (final pmt in loan.payments) {
        allPayments.add(_PaymentEntry(
          loan: loan,
          payment: pmt,
        ));
      }
    }
    allPayments.sort((a, b) => b.payment.date.compareTo(a.payment.date));

    // Group by month
    final grouped = <String, List<_PaymentEntry>>{};
    for (final entry in allPayments) {
      final key = _monthFmt.format(entry.payment.date);
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    if (allPayments.isEmpty) {
      return _emptyState('No payments recorded yet');
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
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text('${allPayments.length}',
                        style: AppTypography.metricSmall
                            .copyWith(fontSize: 20)),
                    Text('Payments',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              Container(
                  width: 1, height: 36, color: Colors.grey.shade200),
              Expanded(
                child: Column(
                  children: [
                    Text(
                        '$currency ${_fmt.format(allPayments.fold(0.0, (s, e) => s + e.payment.amount))}',
                        style: AppTypography.metricSmall
                            .copyWith(fontSize: 16)),
                    Text('Total Paid',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(entry.key,
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.textTertiary, fontSize: 13)),
          ),
          ...entry.value.map((e) => _paymentTile(e, currency)),
          const SizedBox(height: 8),
        ],
      ].animate(interval: 40.ms).fadeIn(duration: 300.ms),
    );
  }

  Widget _paymentTile(_PaymentEntry entry, String currency) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
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
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.chartGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.payment_rounded,
                color: AppColors.chartGreen, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.loan.name,
                    style: AppTypography.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(_dateFmt.format(entry.payment.date),
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
          Text('$currency ${_fmt.format(entry.payment.amount)}',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.chartGreen)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 4: SCHEDULE
  // ═══════════════════════════════════════════════════════

  Widget _buildScheduleTab(List<Loan> active, String currency) {
    final monthlyPmt = _totalMonthlyPayment(active);

    // Build next-12-months schedule
    final schedule = <_MonthSchedule>[];
    final now = DateTime.now();
    for (int i = 0; i < 12; i++) {
      final month = DateTime(now.year, now.month + i, 1);
      double pmt = 0;
      int count = 0;
      for (final l in active) {
        if (l.isFullyPaid) continue;
        final monthsFrom = (month.year - l.startDate.year) * 12 +
            (month.month - l.startDate.month);
        if (monthsFrom >= 0 && monthsFrom < l.termMonths) {
          pmt += l.monthlyPayment;
          count++;
        }
      }
      schedule.add(_MonthSchedule(month: month, amount: pmt, loanCount: count));
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
              Text('Payment Schedule',
                  style: AppTypography.labelMedium.copyWith(fontSize: 15)),
              const SizedBox(height: 12),
              _scheduleSummaryRow(
                  'Monthly Payment', monthlyPmt, currency, AppColors.chartBlue),
              _scheduleSummaryRow('Annual Payment', monthlyPmt * 12, currency,
                  AppColors.chartPurple),
              _scheduleSummaryRow('Total Outstanding',
                  _totalOutstanding(active), currency, AppColors.chartRed),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _sectionTitle('Next 12 Months'),
        const SizedBox(height: 8),
        ...schedule.map((m) => _scheduleRow(m, currency)),

        const SizedBox(height: 20),

        // Per-loan summary
        _sectionTitle('Per-Loan Breakdown'),
        const SizedBox(height: 8),
        if (active.isEmpty)
          _emptyState('No active loans')
        else
          ...active.map((l) => _loanBreakdownRow(l, currency)),
      ].animate(interval: 40.ms).fadeIn(duration: 300.ms),
    );
  }

  Widget _scheduleSummaryRow(
      String label, double amount, String currency, Color color) {
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

  Widget _scheduleRow(_MonthSchedule m, String currency) {
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
              size: 16, color: AppColors.chartPurple),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_monthFmt.format(m.month),
                    style: AppTypography.bodyMedium),
                Text('${m.loanCount} loan${m.loanCount == 1 ? '' : 's'}',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary, fontSize: 10)),
              ],
            ),
          ),
          Text('$currency ${_fmt.format(m.amount)}',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.chartPurple)),
        ],
      ),
    );
  }

  Widget _loanBreakdownRow(Loan l, String currency) {
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
              Text(l.type.icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l.name,
                    style: AppTypography.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Text('${(l.progressPct * 100).toStringAsFixed(0)}%',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniStat(
                  'Principal', '$currency ${_fmt.format(l.principalAmount)}'),
              _miniStat('Interest', '${l.interestRate}%'),
              _miniStat('Outstanding',
                  '$currency ${_fmt.format(l.outstandingBalance)}'),
              _miniStat('Monthly', '$currency ${_fmt.format(l.monthlyPayment)}'),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: l.progressPct.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: Colors.grey.shade100,
              valueColor: AlwaysStoppedAnimation(
                l.isFullyPaid
                    ? AppColors.chartGreen
                    : l.remainingMonths <= 3
                        ? AppColors.chartOrange
                        : AppColors.chartBlue,
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
  // DETAIL BOTTOM SHEET
  // ═══════════════════════════════════════════════════════

  void _showLoanDetail(Loan loan, String currency) {
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
                      color: _typeColor(loan.type).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(loan.type.icon,
                          style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(loan.name,
                            style: AppTypography.metricSmall
                                .copyWith(fontSize: 17)),
                        Text(loan.lender ?? loan.type.label,
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                  _statusBadge(loan.status),
                ],
              ),
              const SizedBox(height: 20),

              // Progress
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
                        Text('Repayment Progress',
                            style: AppTypography.labelMedium),
                        Text(
                            '${(loan.progressPct * 100).toStringAsFixed(1)}%',
                            style: AppTypography.labelMedium
                                .copyWith(color: AppColors.chartGreen)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: loan.progressPct.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(
                          loan.isFullyPaid
                              ? AppColors.chartGreen
                              : AppColors.chartBlue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _depDetail(
                            'Paid', '$currency ${_fmt.format(loan.totalPaid)}'),
                        _depDetail('Outstanding',
                            '$currency ${_fmt.format(loan.outstandingBalance)}'),
                        _depDetail(
                            'Total Due',
                            '$currency ${_fmt.format(loan.totalAmountDue)}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _detailRow('Loan Type', loan.type.label),
              if (loan.lender != null) _detailRow('Lender', loan.lender!),
              _detailRow('Principal',
                  '$currency ${_fmt.format(loan.principalAmount)}'),
              _detailRow('Interest Rate', '${loan.interestRate}% per year'),
              _detailRow('Total Interest',
                  '$currency ${_fmt.format(loan.totalInterest)}'),
              _detailRow('Term', '${loan.termMonths} months'),
              _detailRow('Start Date', _dateFmt.format(loan.startDate)),
              _detailRow('Remaining', '${loan.remainingMonths} months'),
              _detailRow('Monthly Payment',
                  '$currency ${_fmt.format(loan.monthlyPayment)}'),
              if (loan.notes != null && loan.notes!.isNotEmpty)
                _detailRow('Notes', loan.notes!),

              const SizedBox(height: 16),

              // Record loan + payment buttons
              if (loan.status == LoanStatus.active) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showRecordDisbursementSheet(loan, currency);
                  },
                  icon: const Icon(Icons.account_balance_rounded, size: 18),
                  label: const Text('Record Loan'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.chartBlue,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showRecordPaymentSheet(loan, currency);
                  },
                  icon: const Icon(Icons.payment_rounded, size: 18),
                  label: const Text('Record Payment'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.chartGreen,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                        context.push(AppRoutes.editLoan,
                            extra: {'loan': loan});
                      },
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Edit'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryNavy,
                        side: BorderSide(
                            color: AppColors.primaryNavy.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmDelete(ctx, loan),
                      icon: const Icon(Icons.delete_rounded, size: 18),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.chartRed,
                        side: BorderSide(
                            color: AppColors.chartRed.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),

              // Disbursement history within this loan
              if (loan.disbursements.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Loan Disbursement History',
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 8),
                ...loan.disbursements
                    .toList()
                    .reversed
                    .map((d) => _singleDisbursementRow(d, currency)),
              ],

              // Payment history within this loan
              if (loan.payments.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Payment History',
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 8),
                ...loan.payments
                    .toList()
                    .reversed
                    .map((p) => _singlePaymentRow(p, currency)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _singlePaymentRow(LoanPayment p, String currency) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              size: 16, color: AppColors.chartGreen),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_dateFmt.format(p.date),
                style: AppTypography.bodyMedium),
          ),
          Text('$currency ${_fmt.format(p.amount)}',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.chartGreen)),
        ],
      ),
    );
  }

  Widget _singleDisbursementRow(LoanDisbursement d, String currency) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_rounded,
              size: 16, color: AppColors.chartBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_dateFmt.format(d.date),
                style: AppTypography.bodyMedium),
          ),
          Text('$currency ${_fmt.format(d.amount)}',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.chartBlue)),
        ],
      ),
    );
  }

  void _showRecordDisbursementSheet(Loan loan, String currency) {
    final amtCtrl = TextEditingController(
        text: loan.principalAmount > 0
            ? loan.principalAmount.toStringAsFixed(2)
            : '');
    final noteCtrl = TextEditingController();
    DateTime disbDate = DateTime.now();
    final dateFmt = DateFormat('MMM d, yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                Text('Record Loan',
                    style: AppTypography.metricSmall
                        .copyWith(fontSize: 17)),
                Text(
                    '${loan.name} · Total Disbursed: $currency ${_fmt.format(loan.totalDisbursed)}',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary)),
                const SizedBox(height: 16),

                Text('Amount',
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: amtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
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
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: disbDate,
                      firstDate: loan.startDate,
                      lastDate:
                          DateTime.now().add(const Duration(days: 90)),
                    );
                    if (d != null) setSheetState(() => disbDate = d);
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
                          child: Text(dateFmt.format(disbDate),
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
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    hintText: 'Disbursement note',
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
                      final disb = LoanDisbursement(
                        id: const Uuid().v4(),
                        amount: amt,
                        date: disbDate,
                        note: noteCtrl.text.trim().isEmpty
                            ? null
                            : noteCtrl.text.trim(),
                      );
                      await ref
                          .read(loansProvider.notifier)
                          .recordDisbursement(loan.id, disb);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.chartBlue,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Record Loan'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showRecordPaymentSheet(Loan loan, String currency) {
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime payDate = DateTime.now();
    final dateFmt = DateFormat('MMM d, yyyy');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                Text('Record Payment',
                    style: AppTypography.metricSmall
                        .copyWith(fontSize: 17)),
                Text(
                    'Outstanding: $currency ${_fmt.format(loan.outstandingBalance)}',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary)),
                const SizedBox(height: 16),

                Text('Amount',
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: amtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
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
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: payDate,
                      firstDate: loan.startDate,
                      lastDate: DateTime.now(),
                    );
                    if (d != null) setSheetState(() => payDate = d);
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
                          child: Text(dateFmt.format(payDate),
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
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    hintText: 'Payment note',
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
                      final pmt = LoanPayment(
                        id: const Uuid().v4(),
                        amount: amt,
                        date: payDate,
                        note: noteCtrl.text.trim().isEmpty
                            ? null
                            : noteCtrl.text.trim(),
                      );
                      await ref
                          .read(loansProvider.notifier)
                          .recordPayment(loan.id, pmt);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.chartGreen,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Record Payment'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext sheetCtx, Loan loan) {
    showDialog(
      context: sheetCtx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Delete Loan'),
        content: Text('Are you sure you want to delete "${loan.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dCtx);
              Navigator.pop(sheetCtx);
              await ref.read(loansProvider.notifier).remove(loan.id);
            },
            child:
                Text('Delete', style: TextStyle(color: AppColors.chartRed)),
          ),
        ],
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
          Expanded(child: Text(value, style: AppTypography.bodyMedium)),
        ],
      ),
    );
  }

  Widget _statusBadge(LoanStatus status) {
    final Color color;
    switch (status) {
      case LoanStatus.active:
        color = AppColors.chartBlue;
      case LoanStatus.paidOff:
        color = AppColors.chartGreen;
      case LoanStatus.defaulted:
        color = AppColors.chartRed;
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
                      style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary, fontSize: 10)),
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

  Widget _typeRow(String label, String count, String value) {
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
              color:
                  selected ? AppColors.primaryNavy : Colors.grey.shade300,
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
            Icon(Icons.account_balance_outlined,
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

  Color _typeColor(LoanType type) {
    switch (type) {
      case LoanType.bankLoan:
        return AppColors.chartBlue;
      case LoanType.personalLoan:
        return AppColors.chartGreen;
      case LoanType.businessLoan:
        return AppColors.chartPurple;
      case LoanType.creditLine:
        return AppColors.chartOrange;
      case LoanType.microfinance:
        return AppColors.primaryNavy;
      case LoanType.other:
        return Colors.grey;
    }
  }
}

class _PaymentEntry {
  final Loan loan;
  final LoanPayment payment;
  const _PaymentEntry({required this.loan, required this.payment});
}

class _MonthSchedule {
  final DateTime month;
  final double amount;
  final int loanCount;
  const _MonthSchedule(
      {required this.month, required this.amount, required this.loanCount});
}
