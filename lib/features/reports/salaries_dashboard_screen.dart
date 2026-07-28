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
import '../../shared/models/salary_model.dart';
import '../../shared/utils/safe_pop.dart';
import 'package:go_router/go_router.dart';

/// Comprehensive Salaries dashboard showing total payroll, unpaid salaries,
/// employee list, payment history, and payroll schedule.
class SalariesDashboardScreen extends ConsumerStatefulWidget {
  const SalariesDashboardScreen({super.key});

  @override
  ConsumerState<SalariesDashboardScreen> createState() =>
      _SalariesDashboardScreenState();
}

class _SalariesDashboardScreenState
    extends ConsumerState<SalariesDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _fmt = NumberFormat('#,##0.00', 'en');
  final _dateFmt = DateFormat('MMM d, yyyy');
  final _monthFmt = DateFormat('MMM yyyy');

  /// Captured once so every "this month" figure on screen agrees, even if the
  /// dashboard is left open across midnight.
  final _now = DateTime.now();

  /// Payroll month being viewed. Defaults to the current month; the arrows on
  /// the Employees tab step back through history so past dues stay visible.
  late DateTime _selectedMonth = DateTime(_now.year, _now.month);

  /// True when [_selectedMonth] is the live month (blocks stepping forward).
  bool get _isCurrentMonth =>
      _selectedMonth.year == _now.year && _selectedMonth.month == _now.month;

  void _stepMonth(int delta) => setState(() {
        _selectedMonth =
            DateTime(_selectedMonth.year, _selectedMonth.month + delta);
      });

  // ── Filters ──
  String _statusFilter = 'all'; // all / active / terminated / onLeave
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

  List<Salary> _filtered(List<Salary> all) {
    return all.where((s) {
      if (_statusFilter != 'all' && s.status.name != _statusFilter) {
        return false;
      }
      if (_typeFilter != 'all' && s.type.name != _typeFilter) return false;
      return true;
    }).toList();
  }

  double _totalMonthlyPayroll(List<Salary> salaries) =>
      salaries
          .where((s) => s.status == SalaryStatus.active)
          .fold(0.0, (acc, s) => acc + s.monthlySalary);

  double _totalUnpaid(List<Salary> salaries) =>
      salaries
          .where((s) => s.status == SalaryStatus.active)
          .fold(0.0, (acc, s) => acc + s.unpaidAmount);

  double _totalPaid(List<Salary> salaries) =>
      salaries.fold(0.0, (acc, s) => acc + s.totalPaid);

  /// Payroll actually disbursed in [month] (all employees).
  double _paidInMonth(List<Salary> salaries, DateTime month) =>
      salaries.fold(0.0, (acc, s) => acc + s.paidInMonth(month));

  /// Payroll still owed for [month] (active employees only).
  double _remainingInMonth(List<Salary> salaries, DateTime month) => salaries
      .where((s) => s.status == SalaryStatus.active)
      .fold(0.0, (acc, s) => acc + s.remainingForMonth(month));

  /// Everyone still owed money for [month], most owed first.
  List<Salary> _owedInMonth(List<Salary> salaries, DateTime month) {
    final owed = salaries
        .where((s) =>
            s.status == SalaryStatus.active && s.remainingForMonth(month) > 0.01)
        .toList()
      ..sort((a, b) =>
          b.remainingForMonth(month).compareTo(a.remainingForMonth(month)));
    return owed;
  }

  @override
  Widget build(BuildContext context) {
    final salaries = ref.watch(salariesProvider);
    final settings = ref.watch(appSettingsProvider);
    final currency = settings.currency;
    final active =
        salaries.where((s) => s.status == SalaryStatus.active).toList();

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
                onPressed: () => context.push(AppRoutes.addSalary),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1B6B4F), Color(0xFF2E8B57)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 56, 24, 60),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Salaries',
                            style: AppTypography.metricSmall
                                .copyWith(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(
                          '$currency ${_fmt.format(_totalUnpaid(salaries))}',
                          style: AppTypography.metric
                              .copyWith(color: Colors.white, fontSize: 28),
                        ),
                        const SizedBox(height: 2),
                        Text('Unpaid Salaries',
                            style: AppTypography.caption
                                .copyWith(color: Colors.white60)),
                        const Spacer(),
                        // Month-scoped figures first — "what's left to pay this
                        // month" is the actionable number; all-time totals live
                        // in the tabs below.
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _heroStat('Monthly Payroll',
                                  '$currency ${_fmt.format(_totalMonthlyPayroll(salaries))}'),
                              const SizedBox(width: 20),
                              _heroStat(
                                  'Paid ${DateFormat('MMM').format(_selectedMonth)}',
                                  '$currency ${_fmt.format(_paidInMonth(salaries, _selectedMonth))}'),
                              const SizedBox(width: 20),
                              _heroStat(
                                  'Left ${DateFormat('MMM').format(_selectedMonth)}',
                                  '$currency ${_fmt.format(_remainingInMonth(salaries, _selectedMonth))}'),
                              const SizedBox(width: 20),
                              _heroStat('Employees', '${active.length}'),
                            ],
                          ),
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
                Tab(text: 'Employees'),
                Tab(text: 'Payments'),
                Tab(text: 'Payroll'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOverviewTab(salaries, active, currency),
            _buildEmployeesTab(salaries, currency),
            _buildPaymentsTab(salaries, currency),
            _buildPayrollTab(active, currency),
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
      List<Salary> all, List<Salary> active, String currency) {
    final terminated =
        all.where((s) => s.status == SalaryStatus.terminated).toList();
    final onLeave =
        all.where((s) => s.status == SalaryStatus.onLeave).toList();
    final monthlyPayroll = _totalMonthlyPayroll(all);
    final annualPayroll = monthlyPayroll * 12;

    // Type breakdown
    final byType = <SalaryType, List<Salary>>{};
    for (final s in active) {
      byType.putIfAbsent(s.type, () => []).add(s);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // KPI Cards
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                'Total Employees',
                '${all.length}',
                Icons.people_rounded,
                AppColors.chartBlue,
                subtitle:
                    '${active.length} active · ${terminated.length} left',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _kpiCard(
                'Monthly Payroll',
                '$currency ${_fmt.format(monthlyPayroll)}',
                Icons.calendar_month_rounded,
                AppColors.chartGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _kpiCard(
                'Annual Payroll',
                '$currency ${_fmt.format(annualPayroll)}',
                Icons.trending_up_rounded,
                AppColors.chartPurple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Unpaid salaries progress
        if (active.isNotEmpty) ...[
          _sectionTitle('Payment Status'),
          const SizedBox(height: 8),
          _overallPaymentCard(active, currency),
          const SizedBox(height: 20),
        ],

        // By type breakdown
        if (byType.isNotEmpty) ...[
          _sectionTitle('By Type'),
          const SizedBox(height: 8),
          ...byType.entries.map((e) {
            final typeSalaries = e.value;
            final monthlyCost =
                typeSalaries.fold(0.0, (acc, s) => acc + s.monthlySalary);
            return _typeRow(
              '${e.key.icon} ${e.key.label}',
              '${typeSalaries.length} employee${typeSalaries.length == 1 ? '' : 's'}',
              '$currency ${_fmt.format(monthlyCost)}/mo',
            );
          }),
        ],

        const SizedBox(height: 20),

        // Workforce health
        _sectionTitle('Workforce Status'),
        const SizedBox(height: 8),
        _healthRow(Icons.check_circle_rounded, AppColors.chartGreen,
            'Active', '${active.length} employees', 'Currently on payroll'),
        if (onLeave.isNotEmpty)
          _healthRow(Icons.pause_circle_rounded, AppColors.chartOrange,
              'On Leave', '${onLeave.length} employees', 'Temporarily paused'),
        if (terminated.isNotEmpty)
          _healthRow(Icons.cancel_rounded, AppColors.chartRed,
              'Terminated', '${terminated.length} employees', 'No longer employed'),
      ].animate(interval: 50.ms).fadeIn(duration: 300.ms).slideY(begin: 0.02),
    );
  }

  Widget _overallPaymentCard(List<Salary> active, String currency) {
    final totalAccrued =
        active.fold(0.0, (acc, s) => acc + s.totalAccrued);
    final totalPd = _totalPaid(active);
    final pct = totalAccrued > 0 ? totalPd / totalAccrued : 0.0;

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
              Text('Overall Payment Progress',
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
              Text('Unpaid: $currency ${_fmt.format(_totalUnpaid(active))}',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.chartRed)),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 2: EMPLOYEES LIST
  // ═══════════════════════════════════════════════════════

  Widget _buildEmployeesTab(List<Salary> all, String currency) {
    final filtered = _filtered(all);

    return Column(
      children: [
        _monthNavigator(all, currency),
        _buildFilters(all),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              Text(
                  '${filtered.length} employee${filtered.length == 1 ? '' : 's'}',
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
              ? _emptyState('No employees match filters')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: filtered.length,
                  itemBuilder: (context, i) =>
                      _employeeTile(filtered[i], currency),
                ),
        ),
      ],
    );
  }

  /// Month stepper + "who is still owed" summary for the selected month.
  Widget _monthNavigator(List<Salary> all, String currency) {
    final owed = _owedInMonth(all, _selectedMonth);
    final due = _remainingInMonth(all, _selectedMonth);
    final paid = _paidInMonth(all, _selectedMonth);
    final settled = owed.isEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
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
              IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                tooltip: 'Previous month',
                onPressed: () => _stepMonth(-1),
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(_monthFmt.format(_selectedMonth),
                        style: AppTypography.labelMedium),
                    Text(
                        _isCurrentMonth
                            ? 'This month'
                            : 'Paid $currency ${_fmt.format(paid)}',
                        style: AppTypography.caption
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                tooltip: 'Next month',
                // Future payroll isn't payable yet — don't step past today.
                onPressed: _isCurrentMonth ? null : () => _stepMonth(1),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const Divider(height: 12),
          if (settled)
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 16, color: AppColors.chartGreen),
                const SizedBox(width: 6),
                Text('Everyone paid for this month',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.chartGreen)),
              ],
            )
          else ...[
            Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 16, color: AppColors.chartOrange),
                const SizedBox(width: 6),
                Text(
                    '${owed.length} unpaid · $currency ${_fmt.format(due)} due',
                    style: AppTypography.labelSmall
                        .copyWith(color: AppColors.chartOrange)),
              ],
            ),
            const SizedBox(height: 8),
            // Who exactly is owed, biggest first.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: owed
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.chartOrange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                            '${s.employeeName} · $currency ${_fmt.format(s.remainingForMonth(_selectedMonth))}',
                            style: AppTypography.caption
                                .copyWith(color: AppColors.chartOrange)),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilters(List<Salary> all) {
    final types = all.map((s) => s.type).toSet().toList()
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
                _filterChip('Terminated', _statusFilter == 'terminated',
                    () => setState(() => _statusFilter = 'terminated')),
                _filterChip('On Leave', _statusFilter == 'onLeave',
                    () => setState(() => _statusFilter = 'onLeave')),
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

  Widget _employeeTile(Salary salary, String currency) {
    return GestureDetector(
      onTap: () => _showSalaryDetail(salary, currency),
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
                    color: _typeColor(salary.type).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(salary.type.icon,
                        style: const TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(salary.employeeName,
                          style: AppTypography.labelMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${salary.type.label}${salary.role != null ? ' · ${salary.role}' : ''}',
                              style: AppTypography.caption
                                  .copyWith(color: AppColors.textTertiary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (salary.status != SalaryStatus.active) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: salary.status == SalaryStatus.onLeave
                                    ? AppColors.chartOrange.withValues(alpha: 0.12)
                                    : AppColors.chartRed.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(salary.status.label,
                                  style: AppTypography.caption.copyWith(
                                    color: salary.status == SalaryStatus.onLeave
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
                    Text('$currency ${_fmt.format(salary.monthlySalary)}',
                        style: AppTypography.labelMedium),
                    Text('/month',
                        style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary, fontSize: 10)),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textTertiary),
              ],
            ),
            // "This month" is the question people actually ask about payroll —
            // the figures above are the contract rate and all-time totals.
            _thisMonthStrip(salary, currency),
          ],
        ),
      ),
    );
  }

  /// Compact per-month payroll status: taken that month vs still owed.
  Widget _thisMonthStrip(Salary salary, String currency) {
    final month = _selectedMonth;
    final status = salary.statusForMonth(month);
    if (status == MonthPayStatus.notEmployed) return const SizedBox.shrink();

    final paid = salary.paidInMonth(month);
    final remaining = salary.remainingForMonth(month);
    final color = _monthStatusColor(status);

    return Column(
      children: [
        const SizedBox(height: 10),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(DateFormat('MMMM').format(month),
                style: AppTypography.caption
                    .copyWith(color: AppColors.textTertiary)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(status.label,
                  style: AppTypography.caption
                      .copyWith(color: color, fontSize: 10)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _monthFigure(
                  'Taken', '$currency ${_fmt.format(paid)}', AppColors.chartGreen),
            ),
            Expanded(
              child: _monthFigure('Remaining',
                  '$currency ${_fmt.format(remaining)}',
                  remaining > 0 ? AppColors.chartOrange : AppColors.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: salary.progressForMonth(month),
            minHeight: 4,
            backgroundColor: Colors.grey.shade100,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Widget _monthFigure(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTypography.caption
                  .copyWith(color: AppColors.textTertiary, fontSize: 10)),
          const SizedBox(height: 1),
          Text(value,
              style: AppTypography.labelSmall.copyWith(color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      );

  /// Detail-sheet card answering "what's still owed for the selected month?"
  Widget _thisMonthDetailCard(Salary salary, String currency) {
    final month = _selectedMonth;
    final status = salary.statusForMonth(month);
    if (status == MonthPayStatus.notEmployed) return const SizedBox.shrink();

    final due = salary.dueForMonth(month);
    final paid = salary.paidInMonth(month);
    final remaining = salary.remainingForMonth(month);
    final color = _monthStatusColor(status);
    final paymentsThisMonth = salary.payments
        .where((p) => p.date.year == month.year && p.date.month == month.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 16, color: color),
              const SizedBox(width: 6),
              Text('${_monthFmt.format(month)} payroll',
                  style: AppTypography.labelMedium),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(status.label,
                    style: AppTypography.caption
                        .copyWith(color: color, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _depDetail('Salary', '$currency ${_fmt.format(due)}'),
              _depDetail('Taken', '$currency ${_fmt.format(paid)}'),
              _depDetail('Remaining', '$currency ${_fmt.format(remaining)}'),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: salary.progressForMonth(month),
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          if (paymentsThisMonth.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Tap a payment to correct or remove it.
            ...paymentsThisMonth.map((p) => InkWell(
                  onTap: () =>
                      _showRecordPaymentSheet(salary, currency, existing: p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 12, color: AppColors.chartGreen),
                        const SizedBox(width: 6),
                        Text(_dateFmt.format(p.date),
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textTertiary)),
                        const Spacer(),
                        Text('$currency ${_fmt.format(p.amount)}',
                            style: AppTypography.caption),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit_outlined,
                            size: 13, color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Color _monthStatusColor(MonthPayStatus s) {
    switch (s) {
      case MonthPayStatus.paid:
        return AppColors.chartGreen;
      case MonthPayStatus.partial:
        return AppColors.chartBlue;
      case MonthPayStatus.unpaid:
        return AppColors.chartRed;
      case MonthPayStatus.notEmployed:
        return AppColors.textTertiary;
    }
  }

  // ═══════════════════════════════════════════════════════
  // TAB 3: PAYMENTS
  // ═══════════════════════════════════════════════════════

  Widget _buildPaymentsTab(List<Salary> all, String currency) {
    final allPayments = <_PaymentEntry>[];
    for (final salary in all) {
      for (final pmt in salary.payments) {
        allPayments.add(_PaymentEntry(salary: salary, payment: pmt));
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
      return _emptyState('No salary payments recorded yet');
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
                        '$currency ${_fmt.format(allPayments.fold(0.0, (acc, e) => acc + e.payment.amount))}',
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
    return GestureDetector(
      // Tap to edit or delete this payment (and its linked transaction).
      onTap: () => _showRecordPaymentSheet(entry.salary, currency,
          existing: entry.payment),
      child: Container(
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
                Text(entry.salary.employeeName,
                    style: AppTypography.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                    '${_dateFmt.format(entry.payment.date)}${entry.payment.period != null ? ' · ${entry.payment.period}' : ''}',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
          Text('$currency ${_fmt.format(entry.payment.amount)}',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.chartGreen)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded,
              size: 16, color: AppColors.textTertiary),
        ],
      ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 4: PAYROLL SCHEDULE
  // ═══════════════════════════════════════════════════════

  Widget _buildPayrollTab(List<Salary> active, String currency) {
    final monthlyPayroll = _totalMonthlyPayroll(active);

    // Build next-12-months payroll schedule
    final schedule = <_MonthSchedule>[];
    final now = DateTime.now();
    for (int i = 0; i < 12; i++) {
      final month = DateTime(now.year, now.month + i, 1);
      double cost = 0;
      int count = 0;
      for (final s in active) {
        if (s.status != SalaryStatus.active) continue;
        // Employee must have started by this month
        final started = !s.startDate.isAfter(
            DateTime(month.year, month.month + 1, 0)); // last day of month
        final notEnded = s.endDate == null ||
            !s.endDate!.isBefore(DateTime(month.year, month.month, 1));
        if (started && notEnded) {
          cost += s.monthlySalary;
          count++;
        }
      }
      schedule
          .add(_MonthSchedule(month: month, amount: cost, employeeCount: count));
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
              Text('Payroll Schedule',
                  style: AppTypography.labelMedium.copyWith(fontSize: 15)),
              const SizedBox(height: 12),
              _scheduleSummaryRow('Monthly Payroll', monthlyPayroll, currency,
                  AppColors.chartGreen),
              _scheduleSummaryRow('Annual Payroll', monthlyPayroll * 12,
                  currency, AppColors.chartPurple),
              _scheduleSummaryRow('Unpaid Salaries', _totalUnpaid(active),
                  currency, AppColors.chartRed),
            ],
          ),
        ),
        const SizedBox(height: 20),

        _sectionTitle('Next 12 Months'),
        const SizedBox(height: 8),
        ...schedule.map((m) => _scheduleRow(m, currency)),

        const SizedBox(height: 20),

        // Per-employee summary
        _sectionTitle('Per-Employee Breakdown'),
        const SizedBox(height: 8),
        if (active.isEmpty)
          _emptyState('No active employees')
        else
          ...active.map((s) => _employeeBreakdownRow(s, currency)),
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
          const Icon(Icons.calendar_today_rounded,
              size: 16, color: AppColors.chartGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_monthFmt.format(m.month),
                    style: AppTypography.bodyMedium),
                Text(
                    '${m.employeeCount} employee${m.employeeCount == 1 ? '' : 's'}',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary, fontSize: 10)),
              ],
            ),
          ),
          Text('$currency ${_fmt.format(m.amount)}',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.chartGreen)),
        ],
      ),
    );
  }

  Widget _employeeBreakdownRow(Salary s, String currency) {
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
              Text(s.type.icon, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.employeeName,
                    style: AppTypography.labelMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (s.totalAccrued > 0)
                Text('${(s.progressPct * 100).toStringAsFixed(0)}%',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniStat('Monthly', '$currency ${_fmt.format(s.monthlySalary)}'),
              _miniStat('Total Paid', '$currency ${_fmt.format(s.totalPaid)}'),
              _miniStat('Unpaid', '$currency ${_fmt.format(s.unpaidAmount)}'),
              _miniStat('Since', _monthFmt.format(s.startDate)),
            ],
          ),
          if (s.unpaidAmount > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: s.progressPct.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: Colors.grey.shade100,
                valueColor: AlwaysStoppedAnimation(
                  s.isFullyPaid
                      ? AppColors.chartGreen
                      : s.unpaidAmount > s.monthlySalary * 2
                          ? AppColors.chartRed
                          : AppColors.chartBlue,
                ),
              ),
            ),
          ],
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

  void _showSalaryDetail(Salary initial, String currency) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        // Re-read the employee from the provider so edits/deletes made from
        // inside this sheet update it live instead of leaving stale figures.
        builder: (_, controller) => Consumer(builder: (_, ref, _) {
          final salary = ref.watch(salariesProvider).firstWhere(
              (s) => s.id == initial.id,
              orElse: () => initial);
          return Container(
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
                      color: _typeColor(salary.type).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(salary.type.icon,
                          style: const TextStyle(fontSize: 22)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(salary.employeeName,
                            style: AppTypography.metricSmall
                                .copyWith(fontSize: 17)),
                        Text(salary.role ?? salary.type.label,
                            style: AppTypography.caption
                                .copyWith(color: AppColors.textTertiary)),
                      ],
                    ),
                  ),
                  _statusBadge(salary.status),
                ],
              ),
              const SizedBox(height: 20),

              // Payment status
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
                        Text('Payment Progress',
                            style: AppTypography.labelMedium),
                        if (salary.totalAccrued > 0)
                          Text(
                              '${(salary.progressPct * 100).toStringAsFixed(1)}%',
                              style: AppTypography.labelMedium
                                  .copyWith(color: AppColors.chartGreen)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: salary.progressPct.clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(
                          salary.isFullyPaid
                              ? AppColors.chartGreen
                              : AppColors.chartBlue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _depDetail('Paid (all time)',
                            '$currency ${_fmt.format(salary.totalPaid)}'),
                        _depDetail('Unpaid (all time)',
                            '$currency ${_fmt.format(salary.unpaidAmount)}'),
                        _depDetail('Accrued',
                            '$currency ${_fmt.format(salary.totalAccrued)}'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _thisMonthDetailCard(salary, currency),

              _detailRow('Employee Type', salary.type.label),
              if (salary.role != null) _detailRow('Role', salary.role!),
              _detailRow('Monthly Salary',
                  '$currency ${_fmt.format(salary.monthlySalary)}'),
              _detailRow('Annual Salary',
                  '$currency ${_fmt.format(salary.annualSalary)}'),
              _detailRow('Payment Frequency', salary.frequency.label),
              _detailRow('Start Date', _dateFmt.format(salary.startDate)),
              _detailRow('Months Employed', '${salary.monthsEmployed} months'),
              if (salary.endDate != null)
                _detailRow('End Date', _dateFmt.format(salary.endDate!)),
              if (salary.notes != null && salary.notes!.isNotEmpty)
                _detailRow('Notes', salary.notes!),

              const SizedBox(height: 16),

              // Record salary payable + payment buttons
              if (salary.status == SalaryStatus.active) ...[
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showRecordAccrualSheet(salary, currency);
                  },
                  icon: const Icon(Icons.receipt_long_rounded, size: 18),
                  label: const Text('Record Salary Payable'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.chartOrange,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showRecordPaymentSheet(salary, currency);
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
                        context.push(AppRoutes.editSalary,
                            extra: {'salary': salary});
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
                      onPressed: () => _confirmDelete(ctx, salary),
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

              // Accrual history within this employee
              if (salary.accruals.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Salary Payable History',
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 8),
                ...salary.accruals
                    .toList()
                    .reversed
                    .map((a) => _singleAccrualRow(a, currency)),
              ],

              // Payment history within this employee
              if (salary.payments.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Payment History',
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 8),
                ...salary.payments
                    .toList()
                    .reversed
                    .map((p) => _singlePaymentRow(salary, p, currency)),
              ],
            ],
          ),
          );
        }),
      ),
    );
  }

  Widget _singlePaymentRow(
      Salary salary, SalaryPayment p, String currency) {
    return GestureDetector(
      // Tap to edit or delete this payment.
      onTap: () => _showRecordPaymentSheet(salary, currency, existing: p),
      child: Container(
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_dateFmt.format(p.date),
                    style: AppTypography.bodyMedium),
                if (p.period != null)
                  Text(p.period!,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textTertiary, fontSize: 10)),
              ],
            ),
          ),
          Text('$currency ${_fmt.format(p.amount)}',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.chartGreen)),
          const SizedBox(width: 6),
          const Icon(Icons.edit_outlined,
              size: 14, color: AppColors.textTertiary),
        ],
      ),
      ),
    );
  }

  Widget _singleAccrualRow(SalaryAccrual a, String currency) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 16, color: AppColors.chartOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_dateFmt.format(a.date),
                    style: AppTypography.bodyMedium),
                if (a.period != null)
                  Text(a.period!,
                      style: AppTypography.caption
                          .copyWith(color: AppColors.textTertiary, fontSize: 10)),
              ],
            ),
          ),
          Text('$currency ${_fmt.format(a.amount)}',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.chartOrange)),
        ],
      ),
    );
  }

  void _showRecordAccrualSheet(Salary salary, String currency) {
    final amtCtrl =
        TextEditingController(text: salary.monthlySalary.toStringAsFixed(2));
    final noteCtrl = TextEditingController();
    DateTime accrualDate = DateTime.now();
    String period = _monthFmt.format(DateTime.now());
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
                Text('Record Salary Payable',
                    style: AppTypography.metricSmall
                        .copyWith(fontSize: 17)),
                Text(
                    '${salary.employeeName} · Current Payable: $currency ${_fmt.format(salary.unpaidAmount)}',
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
                      initialDate: accrualDate,
                      firstDate: salary.startDate,
                      lastDate:
                          DateTime.now().add(const Duration(days: 90)),
                    );
                    if (d != null) {
                      setSheetState(() => accrualDate = d);
                    }
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
                          child: Text(dateFmt.format(accrualDate),
                              style: AppTypography.bodyMedium),
                        ),
                        const Icon(Icons.calendar_today_rounded,
                            size: 18, color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Text('Period (e.g. Apr 2026)',
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: TextEditingController(text: period),
                  onChanged: (v) => period = v,
                  decoration: InputDecoration(
                    hintText: 'Apr 2026',
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

                Text('Note (optional)',
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    hintText: 'Accrual note',
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
                      final accrual = SalaryAccrual(
                        id: const Uuid().v4(),
                        amount: amt,
                        date: accrualDate,
                        note: noteCtrl.text.trim().isEmpty
                            ? null
                            : noteCtrl.text.trim(),
                        period:
                            period.trim().isEmpty ? null : period.trim(),
                      );
                      await ref
                          .read(salariesProvider.notifier)
                          .recordAccrual(salary.id, accrual);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.chartOrange,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Record Salary Payable'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Records a new salary payment, or edits [existing] when one is passed.
  void _showRecordPaymentSheet(Salary salary, String currency,
      {SalaryPayment? existing}) {
    final isEdit = existing != null;
    // Pre-fill what's actually still owed for the month in view, falling back
    // to the full rate when it's already settled.
    final outstanding = salary.remainingForMonth(_selectedMonth);
    final amtCtrl = TextEditingController(text: (existing?.amount ??
            (outstanding > 0.01 ? outstanding : salary.monthlySalary))
        .toStringAsFixed(2));
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    // When catching up on an earlier month, default the payment to that month
    // (its last day) instead of today, so it lands in the period being viewed.
    final defaultDate = _isCurrentMonth
        ? DateTime.now()
        : DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    DateTime payDate = existing?.date ?? defaultDate;
    String period = existing?.period ?? _monthFmt.format(_selectedMonth);
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                          isEdit
                              ? 'Edit Salary Payment'
                              : 'Record Salary Payment',
                          style: AppTypography.metricSmall
                              .copyWith(fontSize: 17)),
                    ),
                    if (isEdit)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: AppColors.chartRed),
                        tooltip: 'Delete payment',
                        onPressed: () =>
                            _confirmDeletePayment(ctx, salary, existing),
                      ),
                  ],
                ),
                Text(
                    '${salary.employeeName} · Unpaid: $currency ${_fmt.format(salary.unpaidAmount)}',
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

                Text('Payment Date',
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    // Clamp so the picker can never be handed an initialDate
                    // outside [firstDate, lastDate] (which throws).
                    final first = salary.startDate;
                    final last = DateTime.now();
                    final initial = payDate.isBefore(first)
                        ? first
                        : (payDate.isAfter(last) ? last : payDate);
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: initial,
                      firstDate: first.isAfter(last) ? last : first,
                      lastDate: last,
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

                Text('Period (e.g. Apr 2026)',
                    style: AppTypography.labelMedium
                        .copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: TextEditingController(text: period),
                  onChanged: (v) => period = v,
                  decoration: InputDecoration(
                    hintText: 'Apr 2026',
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
                      final pmt = SalaryPayment(
                        // Keep the id when editing so the existing payment (and
                        // its ledger transaction) is rewritten, not duplicated.
                        id: existing?.id ?? const Uuid().v4(),
                        amount: amt,
                        date: payDate,
                        note: noteCtrl.text.trim().isEmpty
                            ? null
                            : noteCtrl.text.trim(),
                        period: period.trim().isEmpty ? null : period.trim(),
                        transactionId: existing?.transactionId,
                      );
                      final notifier = ref.read(salariesProvider.notifier);
                      if (isEdit) {
                        await notifier.updatePayment(salary.id, pmt);
                      } else {
                        await notifier.recordPayment(salary.id, pmt);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.chartGreen,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(isEdit ? 'Save Changes' : 'Record Payment'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Deletes a single salary payment (and its linked cash transaction).
  void _confirmDeletePayment(
      BuildContext sheetCtx, Salary salary, SalaryPayment payment) {
    final currency = ref.read(appSettingsProvider).currency;
    showDialog(
      context: sheetCtx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Delete Payment'),
        content: Text(
            'Delete the $currency ${_fmt.format(payment.amount)} payment '
            'on ${_dateFmt.format(payment.date)}?\n\n'
            'This also removes its transaction from your books and adds the '
            'amount back to what ${salary.employeeName} is owed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dCtx); // close confirm
              final ok = await ref
                  .read(salariesProvider.notifier)
                  .deletePayment(salary.id, payment.id);
              if (sheetCtx.mounted) Navigator.pop(sheetCtx); // close edit sheet
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Payment deleted'
                        : 'Could not delete payment'),
                    backgroundColor:
                        ok ? AppColors.chartGreen : AppColors.chartRed,
                  ),
                );
              }
            },
            child: const Text('Delete',
                style: TextStyle(color: AppColors.chartRed)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext sheetCtx, Salary salary) {
    showDialog(
      context: sheetCtx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Delete Employee'),
        content: Text(
            'Are you sure you want to delete "${salary.employeeName}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dCtx);
              Navigator.pop(sheetCtx);
              await ref
                  .read(salariesProvider.notifier)
                  .remove(salary.id);
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

  Widget _statusBadge(SalaryStatus status) {
    final Color color;
    switch (status) {
      case SalaryStatus.active:
        color = AppColors.chartGreen;
      case SalaryStatus.terminated:
        color = AppColors.chartRed;
      case SalaryStatus.onLeave:
        color = AppColors.chartOrange;
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
            Icon(Icons.people_outline_rounded,
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

  Color _typeColor(SalaryType type) {
    switch (type) {
      case SalaryType.fullTime:
        return AppColors.chartBlue;
      case SalaryType.partTime:
        return AppColors.chartOrange;
      case SalaryType.contractor:
        return AppColors.chartPurple;
      case SalaryType.freelancer:
        return AppColors.chartGreen;
      case SalaryType.intern:
        return AppColors.primaryNavy;
      case SalaryType.other:
        return Colors.grey;
    }
  }
}

class _PaymentEntry {
  final Salary salary;
  final SalaryPayment payment;
  const _PaymentEntry({required this.salary, required this.payment});
}

class _MonthSchedule {
  final DateTime month;
  final double amount;
  final int employeeCount;
  const _MonthSchedule(
      {required this.month, required this.amount, required this.employeeCount});
}
