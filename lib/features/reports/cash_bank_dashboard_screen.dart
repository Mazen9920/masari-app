import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/transaction_model.dart' show Transaction;
import '../../shared/utils/books_cutover.dart';
import '../../shared/utils/cf_engine.dart' show cashImpact;
import '../../shared/utils/safe_pop.dart';
import '../transactions/transaction_detail_screen.dart';

/// User ID for which CF-driven cash dashboard is enabled.
const _cfUserId = 'EGYQnP7ughdUtTbn04UwUET534i1';

/// A single line-item in the cash waterfall.
class _CashEntry {
  final String id;
  final String label;
  final String? sublabel;
  final double amount;
  final bool isIncome;
  final DateTime date;
  final String category;
  final String? saleId;
  final bool isExcluded;
  final bool isCashout;
  final Map<String, dynamic>? rawData; // original Firestore doc data

  const _CashEntry({
    required this.id,
    required this.label,
    this.sublabel,
    required this.amount,
    required this.isIncome,
    required this.date,
    required this.category,
    this.saleId,
    this.isExcluded = false,
    this.isCashout = false,
    this.rawData,
  });
}

/// Comprehensive Cash & Bank dashboard showing how the balance is calculated,
/// all contributing transactions, cashouts, and a full waterfall breakdown.
class CashBankDashboardScreen extends ConsumerStatefulWidget {
  const CashBankDashboardScreen({super.key});

  @override
  ConsumerState<CashBankDashboardScreen> createState() =>
      _CashBankDashboardScreenState();
}

class _CashBankDashboardScreenState
    extends ConsumerState<CashBankDashboardScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String _error = '';
  late TabController _tabController;

  // ── Loaded data ──
  double _openingCash = 0;
  double _totalCashouts = 0;
  double _txnCashFlow = 0;
  double _closingCash = 0;

  final List<_CashEntry> _includedTxns = [];
  final List<_CashEntry> _excludedTxns = [];
  final List<_CashEntry> _cashouts = [];

  // Category breakdown
  final Map<String, double> _categoryTotals = {};

  // Monthly history
  final List<_MonthCash> _monthHistory = [];

  // ── Month filter ──
  /// null = All Time, otherwise a specific month
  DateTime? _selectedMonth;
  List<DateTime> _availableMonths = [];

  // ── Transaction filters ──
  /// 0=All, 1=Included, 2=Excluded
  int _txnStatusFilter = 0;
  /// 0=All, 1=Income, 2=Expense
  int _txnDirectionFilter = 0;
  /// null=All, otherwise a specific category
  String? _txnCategoryFilter;

  final _fmt = NumberFormat('#,##0.00', 'en');
  final _dateFmt = DateFormat('MMM d, yyyy');
  final _monthFmt = DateFormat('MMM yyyy');

  // ── Filtered accessors ──
  bool _matchesMonth(_CashEntry e) {
    if (_selectedMonth == null) return true;
    return e.date.year == _selectedMonth!.year &&
        e.date.month == _selectedMonth!.month;
  }

  List<_CashEntry> get _filteredIncluded =>
      _selectedMonth == null ? _includedTxns : _includedTxns.where(_matchesMonth).toList();

  List<_CashEntry> get _filteredExcluded =>
      _selectedMonth == null ? _excludedTxns : _excludedTxns.where(_matchesMonth).toList();

  List<_CashEntry> get _filteredCashouts =>
      _selectedMonth == null ? _cashouts : _cashouts.where(_matchesMonth).toList();

  double get _filteredTxnCashFlow {
    if (_selectedMonth == null) return _txnCashFlow;
    double sum = 0;
    for (final e in _filteredIncluded) {
      sum += e.isIncome ? e.amount.abs() : -e.amount.abs();
    }
    return (sum * 100).roundToDouble() / 100;
  }

  double get _filteredTotalCashouts {
    if (_selectedMonth == null) return _totalCashouts;
    double sum = 0;
    for (final c in _filteredCashouts) {
      sum += c.amount;
    }
    return sum;
  }

  Map<String, double> get _filteredCategoryTotals {
    if (_selectedMonth == null) return _categoryTotals;
    final map = <String, double>{};
    for (final e in _filteredIncluded) {
      final impact = e.isIncome ? e.amount.abs() : -e.amount.abs();
      final catLabel = _categoryLabel(e.category);
      map[catLabel] = (map[catLabel] ?? 0) + impact;
    }
    return map;
  }

  /// Get the _MonthCash for the selected month (if any)
  _MonthCash? get _selectedMonthData {
    if (_selectedMonth == null) return null;
    try {
      return _monthHistory.firstWhere(
          (m) => m.month.year == _selectedMonth!.year && m.month.month == _selectedMonth!.month);
    } catch (_) {
      return null;
    }
  }

  /// Get previous month's _MonthCash relative to selected
  _MonthCash? get _previousMonthData {
    final target = _selectedMonth ?? DateTime.now();
    final prev = DateTime(target.year, target.month - 1);
    try {
      return _monthHistory.firstWhere(
          (m) => m.month.year == prev.year && m.month.month == prev.month);
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    Future.microtask(_loadData);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  // ── Data Loading ──────────────────────────────────────────
  Future<void> _loadData() async {
    try {
      const uid = _cfUserId;

      // Opening cash + books-start cutover, read directly from the Firestore
      // balance_sheet doc (auditable, device-independent, no provider load
      // race). Fall back to the legacy device-local opening cash.
      String? cashoutStartKey;
      double openingFromDoc = 0;
      try {
        final bsDoc = await _db.collection('balance_sheet').doc(uid).get();
        final data = bsDoc.data();
        openingFromDoc = (data?['opening_cash_balance'] as num?)?.toDouble() ?? 0;
        final raw = data?['books_start_date'] as String?;
        if (raw != null && raw.isNotEmpty) {
          cashoutStartKey = raw.substring(0, 10);
        }
      } catch (_) {}
      _openingCash = openingFromDoc != 0
          ? openingFromDoc
          : ref.read(appSettingsProvider).openingCashBalance;

      // Load Firestore data in parallel — each wrapped safely
      Future<QuerySnapshot<Map<String, dynamic>>> safeQuery(String col) async {
        try {
          return await _db.collection(col).where('user_id', isEqualTo: uid).get();
        } catch (_) {
          rethrow;
        }
      }

      final results = await Future.wait([
        safeQuery('transactions'),
        safeQuery('bosta_cashouts'),
      ]);

      final txSnap = results[0];
      final cashoutSnap = results[1];

      // ── Process cashouts ──
      _totalCashouts = 0;
      _cashouts.clear();
      for (final doc in cashoutSnap.docs) {
        final d = doc.data();
        final date = _parseDate(d['transaction_date'] ?? d['date'] ?? d['created_at']);
        // Exclude pre-cutover cashouts — their net is in the opening balance.
        if (!cashoutOnOrAfterStart(
            date.toIso8601String().substring(0, 10), cashoutStartKey)) {
          continue;
        }
        final amount = _toDouble(d['amount']);
        _totalCashouts += amount;


        _cashouts.add(_CashEntry(
          id: doc.id,
          label: 'Bosta Cashout',
          sublabel: d['tracking_number'] as String? ?? doc.id,
          amount: amount,
          isIncome: true,
          date: date,
          category: 'Bosta Cashout',
          isCashout: true,
          rawData: d,
        ));
      }
      _cashouts.sort((a, b) => b.date.compareTo(a.date));

      // ── Process transactions ──
      _includedTxns.clear();
      _excludedTxns.clear();
      _categoryTotals.clear();
      _txnCashFlow = 0;

      // Only needed now for the display-only exclusion reason below.
      const saleTxnCats = {'cat_sales_revenue', 'cat_cogs', 'cat_shipping'};

      for (final doc in txSnap.docs) {
        final d = doc.data();
        final catId = d['category_id'] as String? ?? '';
        final saleId = d['sale_id'] as String?;
        final amount = _toDouble(d['amount']);
        // Match Transaction.isIncome (amount > 0) and the CF engine — the stored
        // is_income flag is missing on many entries (e.g. direct cash sales),
        // which previously flipped income into a negative cash impact.
        final isIncome = amount > 0;
        final date = _parseDate(d['date_time'] ?? d['date'] ?? d['created_at']);
        final rawName = d['title'] as String? ?? d['name'] as String? ?? '';
        final note = d['note'] as String? ?? '';
        final catLabel = _categoryLabel(catId);

        // Extract clean order number from title (e.g. "#19684 — Shopify — Ahmed")
        String? displayOrderNum;
        if (saleId != null && saleId.isNotEmpty) {
          final hashMatch = RegExp(r'#(\d+)').firstMatch(rawName);
          if (hashMatch != null) {
            displayOrderNum = hashMatch.group(1);
          } else {
            // Try from note
            final noteMatch = RegExp(r'#(\d+)').firstMatch(note);
            if (noteMatch != null) {
              displayOrderNum = noteMatch.group(1);
            }
          }
        }

        // Build a clear, descriptive label
        String label;
        if (displayOrderNum != null) {
          label = '$catLabel · Order #$displayOrderNum';
        } else if (rawName.isNotEmpty && rawName != catId) {
          label = rawName;
        } else if (note.isNotEmpty) {
          label = note;
        } else {
          label = catLabel;
        }

        final entry = _CashEntry(
          id: doc.id,
          label: label,
          sublabel: displayOrderNum != null ? 'Order #$displayOrderNum' : (note.isNotEmpty && note != label ? note : null),
          amount: amount,
          isIncome: isIncome,
          date: date,
          category: catId,
          saleId: saleId,
          rawData: d,
        );

        // Single source of truth: the shared CF engine decides inclusion AND
        // sign (cashImpact). This dashboard can no longer drift from the
        // Balance Sheet / Cash Flow. The reason below is display-only.
        final impact =
            cashImpact(Transaction.fromJson({...d, 'id': doc.id}), isCfUser: true);
        final bool excluded = impact == null;
        String? exclusionReason;
        if (excluded) {
          if (catId == 'cat_cogs') {
            exclusionReason = 'COGS (accrual, not cash)';
          } else if (saleId != null && saleTxnCats.contains(catId)) {
            exclusionReason = 'Sale-linked accrual (cash via Bosta)';
          } else if (doc.id.startsWith('bosta_est_daily_') ||
              doc.id.startsWith('bosta_rec_daily_')) {
            exclusionReason = 'Bosta daily estimate/reconciliation';
          } else {
            exclusionReason = 'Excluded from P&L (non-cash)';
          }
        }

        if (excluded) {
          _excludedTxns.add(_CashEntry(
            id: entry.id,
            label: entry.label,
            sublabel: exclusionReason,
            amount: entry.amount,
            isIncome: entry.isIncome,
            date: entry.date,
            category: entry.category,
            saleId: entry.saleId,
            isExcluded: true,
            rawData: d,
          ));
        } else {
          _includedTxns.add(entry);
          _txnCashFlow += impact;

          final catLabel = _categoryLabel(catId);
          _categoryTotals[catLabel] =
              (_categoryTotals[catLabel] ?? 0) + impact;
        }
      }

      _includedTxns.sort((a, b) => b.date.compareTo(a.date));
      _excludedTxns.sort((a, b) => b.date.compareTo(a.date));

      // Round
      _txnCashFlow = (_txnCashFlow * 100).roundToDouble() / 100;
      _closingCash =
          ((_openingCash + _totalCashouts + _txnCashFlow) * 100).roundToDouble() / 100;

      // ── Build monthly history ──
      _buildMonthHistory(txSnap.docs, cashoutSnap.docs,
          cashoutStartKey: cashoutStartKey);

      // ── Build available months for filter ──
      final monthSet = <String, DateTime>{};
      for (final e in [..._includedTxns, ..._excludedTxns, ..._cashouts]) {
        final key = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
        monthSet.putIfAbsent(key, () => DateTime(e.date.year, e.date.month));
      }
      _availableMonths = monthSet.values.toList()
        ..sort((a, b) => b.compareTo(a));

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  DateTime _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime(2020);
    return DateTime(2020);
  }

  void _buildMonthHistory(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> txDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> cashoutDocs, {
    String? cashoutStartKey,
  }) {
    _monthHistory.clear();
    final monthMap = <String, _MonthCash>{};

    // Cashouts — cutover-filtered, same window as the closing balance.
    for (final doc in cashoutDocs) {
      final d = doc.data();
      if (!cashoutOnOrAfterStart(
          (d['transaction_date'] as String?) ?? '', cashoutStartKey)) {
        continue;
      }
      final amount = _toDouble(d['amount']);
      final date = _parseDate(d['transaction_date'] ?? d['date'] ?? d['created_at']);
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      final m = monthMap.putIfAbsent(key, () => _MonthCash(month: DateTime(date.year, date.month)));
      m.cashouts += amount;
    }

    // Txn flow — shared CF engine (cashImpact), so per-month totals can't drift
    // from the headline balance.
    for (final doc in txDocs) {
      final d = doc.data();
      final date = _parseDate(d['date_time'] ?? d['date'] ?? d['created_at']);
      final key = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      final m = monthMap.putIfAbsent(key, () => _MonthCash(month: DateTime(date.year, date.month)));
      final impact =
          cashImpact(Transaction.fromJson({...d, 'id': doc.id}), isCfUser: true);
      if (impact != null) {
        m.txnFlow += impact;
        m.txnCount++;
      }
    }

    final sorted = monthMap.values.toList()
      ..sort((a, b) => a.month.compareTo(b.month));

    double running = _openingCash;
    for (final m in sorted) {
      m.openingBalance = running;
      m.closingBalance = ((running + m.cashouts + m.txnFlow) * 100).roundToDouble() / 100;
      running = m.closingBalance;
    }

    _monthHistory.addAll(sorted.reversed);
  }

  String _categoryLabel(String catId) {
    switch (catId) {
      case 'cat_supplier_payment': return 'Supplier Payment';
      case 'cat_sales_revenue': return 'Sales Revenue';
      case 'cat_cogs': return 'Cost of Goods';
      case 'cat_shipping': return 'Shipping Fees';
      case 'cat_shipping_expense': return 'Shipping Expense';
      case 'cat_loan_received': return 'Loan Received';
      case 'cat_loan_repayment': return 'Loan Repayment';
      case 'cat_equity_injection': return 'Capital Injection';
      case 'cat_owner_withdrawal': return 'Owner Withdrawal';
      case 'cat_investments': return 'Investments';
      case 'cat_other': return 'Other';
      case 'cat_rent': return 'Rent';
      case 'cat_salary': return 'Salary';
      case 'cat_marketing': return 'Marketing';
      case 'cat_utilities': return 'Utilities';
      case 'cat_subscriptions': return 'Subscriptions';
      default: return catId.replaceAll('cat_', '').replaceAll('_', ' ');
    }
  }

  // ── BUILD ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
              ? _buildErrorState()
              : NestedScrollView(
                  headerSliverBuilder: (context, innerBoxIsScrolled) => [
                    SliverAppBar(
                      expandedHeight: 220,
                      floating: false,
                      pinned: true,
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => context.safePop(),
                      ),
                      flexibleSpace: FlexibleSpaceBar(
                        background: _buildHeroHeader(),
                      ),
                      title: innerBoxIsScrolled
                          ? Text('EGP ${_fmt.format(_closingCash)}',
                              style: AppTypography.labelMedium.copyWith(
                                  color: Colors.white, fontWeight: FontWeight.w700))
                          : null,
                      bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(46),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            labelColor: AppColors.primaryNavy,
                            unselectedLabelColor: AppColors.textSecondary,
                            labelStyle: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w700),
                            unselectedLabelStyle: AppTypography.labelMedium,
                            indicatorColor: AppColors.primaryNavy,
                            indicatorWeight: 2.5,
                            indicatorSize: TabBarIndicatorSize.label,
                            dividerColor: Colors.transparent,
                            tabs: const [
                              Tab(text: 'Overview'),
                              Tab(text: 'Transactions'),
                              Tab(text: 'Cashouts'),
                              Tab(text: 'History'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  body: Column(
                    children: [
                      // ── Month filter bar ──
                      _buildMonthFilterBar(),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildOverviewTab(),
                            _buildTransactionsTab(),
                            _buildCashoutsTab(),
                            _buildHistoryTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  // ── Month Filter Bar ──────────────────────────────────────
  Widget _buildMonthFilterBar() {
    return Container(
      height: 42,
      color: Colors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          _monthChip(null, 'All Time'),
          for (final m in _availableMonths)
            _monthChip(m, _monthFmt.format(m)),
        ],
      ),
    );
  }

  Widget _monthChip(DateTime? month, String label) {
    final isSelected = _selectedMonth == month ||
        (_selectedMonth != null &&
            month != null &&
            _selectedMonth!.year == month.year &&
            _selectedMonth!.month == month.month);
    final isAll = month == null && _selectedMonth == null;
    final selected = isSelected || isAll;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _selectedMonth = month),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryNavy : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.chartRedLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, size: 40, color: AppColors.chartRed),
            ),
            const SizedBox(height: 16),
            Text('Something went wrong', style: AppTypography.labelLarge),
            const SizedBox(height: 8),
            Text(_error, style: AppTypography.caption, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () { setState(() { _loading = true; _error = ''; }); _loadData(); },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Hero Header (in SliverAppBar) ────────────────────────
  Widget _buildHeroHeader() {
    final diff = _closingCash - _openingCash;
    final isUp = diff >= 0;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryNavy, AppColors.secondaryBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 70),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Cash & Bank Balance',
                  style: AppTypography.caption.copyWith(
                      color: Colors.white60, letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text('EGP ${_fmt.format(_closingCash)}',
                  style: AppTypography.metric.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isUp ? AppColors.chartGreen : AppColors.chartRed).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                          size: 14,
                          color: isUp ? AppColors.chartGreen : AppColors.chartRed,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${isUp ? '+' : ''}EGP ${_fmt.format(diff)}',
                          style: AppTypography.caption.copyWith(
                            color: isUp ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('from opening',
                      style: AppTypography.caption.copyWith(color: Colors.white38)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  // TAB 1: Overview
  // ══════════════════════════════════════════════════════════
  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        // ── Quick KPI Row ──
        _buildKpiRow(),
        const SizedBox(height: 20),

        // ── Month-over-month comparison (only when a month is selected) ──
        if (_selectedMonth != null) ...[
          _buildMonthComparisonCard(),
          const SizedBox(height: 16),
        ],

        // ── Waterfall ──
        _buildWaterfallCard(),
        const SizedBox(height: 16),

        // ── Category Breakdown ──
        _buildCategoryBreakdownCard(),
        const SizedBox(height: 16),

        // ── Excluded Txns ──
        _buildExcludedSummaryCard(),
      ].animate(interval: 40.ms).fadeIn(duration: 350.ms).slideY(begin: 0.03, end: 0),
    );
  }

  Widget _buildKpiRow() {
    final cashouts = _filteredCashouts;
    final included = _filteredIncluded;
    final totalCashouts = _filteredTotalCashouts;
    final txnFlow = _filteredTxnCashFlow;
    return Row(
      children: [
        Expanded(child: _kpiCard(
          'Bosta Cashouts',
          'EGP ${_fmt.format(totalCashouts)}',
          '${cashouts.length} deposits',
          AppColors.chartGreen,
          Icons.account_balance_wallet_rounded,
        )),
        const SizedBox(width: 12),
        Expanded(child: _kpiCard(
          'Txn Cash Flow',
          'EGP ${_fmt.format(txnFlow)}',
          '${included.length} eligible',
          txnFlow >= 0 ? AppColors.chartBlue : AppColors.chartRed,
          Icons.swap_horiz_rounded,
        )),
      ],
    );
  }

  Widget _kpiCard(String title, String value, String sub, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(title,
              style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: AppTypography.metricSmall.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(sub,
              style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildWaterfallCard() {
    final cashouts = _filteredCashouts;
    final included = _filteredIncluded;
    final totalCashouts = _filteredTotalCashouts;
    final txnFlow = _filteredTxnCashFlow;

    // For a specific month, show that month's opening→closing
    final monthData = _selectedMonthData;
    final opening = monthData?.openingBalance ?? _openingCash;
    final closing = monthData?.closingBalance ??
        ((_openingCash + totalCashouts + txnFlow) * 100).roundToDouble() / 100;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.chartBlueLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.waterfall_chart_rounded, size: 16, color: AppColors.chartBlue),
              ),
              const SizedBox(width: 10),
              Text('Cash Waterfall', style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 18),

          // Waterfall items
          _waterfallItem('Opening Balance', opening, AppColors.textPrimary, isFirst: true),
          _waterfallConnector(),
          _waterfallItem('Bosta Cashouts', totalCashouts, AppColors.chartGreen,
              count: cashouts.length, icon: Icons.add_rounded),
          _waterfallConnector(),
          _waterfallItem('Transaction Flow', txnFlow,
              txnFlow >= 0 ? AppColors.chartGreen : AppColors.chartRed,
              count: included.length,
              icon: txnFlow >= 0 ? Icons.add_rounded : Icons.remove_rounded),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            height: 1,
            color: AppColors.borderLight,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.account_balance_rounded, size: 16, color: AppColors.primaryNavy),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Closing Balance',
                    style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
              ),
              Text('EGP ${_fmt.format(closing)}',
                  style: AppTypography.metricSmall.copyWith(color: AppColors.primaryNavy)),
            ],
          ),

          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.chartBlueLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 14,
                    color: AppColors.chartBlue.withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sale-linked accruals (revenue, COGS, shipping) are excluded — '
                    'actual cash flows through Bosta cashouts.',
                    style: AppTypography.caption.copyWith(
                        color: AppColors.primaryNavy.withValues(alpha: 0.7), height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _waterfallItem(String label, double amount, Color color,
      {int? count, IconData? icon, bool isFirst = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              isFirst ? Icons.flag_rounded : (icon ?? Icons.circle),
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w500)),
                if (count != null)
                  Text('$count items', style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          Text(
            '${!isFirst && amount >= 0 ? '+' : ''}EGP ${_fmt.format(amount)}',
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _waterfallConnector() {
    return Padding(
      padding: const EdgeInsets.only(left: 13),
      child: Container(
        width: 2,
        height: 16,
        decoration: BoxDecoration(
          color: AppColors.borderLight,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdownCard() {
    final catTotals = _filteredCategoryTotals;
    if (catTotals.isEmpty) return const SizedBox.shrink();

    final sorted = catTotals.entries.toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final maxAbs = sorted.first.value.abs();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.chartPurpleLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.donut_small_rounded, size: 16, color: AppColors.chartPurple),
              ),
              const SizedBox(width: 10),
              Text('By Category', style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < sorted.length; i++) ...[
            _categoryRow(sorted[i].key, sorted[i].value, maxAbs),
            if (i < sorted.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _categoryRow(String name, double amount, double maxAbs) {
    final isPositive = amount >= 0;
    final pct = maxAbs > 0 ? (amount.abs() / maxAbs) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(name, style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w500)),
            ),
            Text(
              '${isPositive ? '+' : ''}EGP ${_fmt.format(amount)}',
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w700,
                color: isPositive ? AppColors.chartGreen : AppColors.chartRed,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 4,
            backgroundColor: const Color(0xFFF1F5F9),
            valueColor: AlwaysStoppedAnimation(
              isPositive ? AppColors.chartGreen.withValues(alpha: 0.6) : AppColors.chartRed.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildExcludedSummaryCard() {
    final excluded = _filteredExcluded;
    if (excluded.isEmpty) return const SizedBox.shrink();

    double excludedTotal = 0;
    for (final e in excluded) {
      excludedTotal += e.isIncome ? e.amount.abs() : -e.amount.abs();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.chartOrangeLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.chartOrange.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.chartOrange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.visibility_off_rounded, size: 16, color: AppColors.chartOrange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${excluded.length} Excluded Transactions',
                    style: AppTypography.labelMedium.copyWith(
                        fontWeight: FontWeight.w700, color: AppColors.chartOrange)),
                const SizedBox(height: 4),
                Text(
                  'Net EGP ${_fmt.format(excludedTotal)} in accruals, estimates, '
                  'and non-cash entries are not counted. See "Transactions" tab for details.',
                  style: AppTypography.caption.copyWith(height: 1.4, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Month-over-Month Comparison ──────────────────────────
  Widget _buildMonthComparisonCard() {
    final current = _selectedMonthData;
    final prev = _previousMonthData;

    if (current == null) return const SizedBox.shrink();

    final curNet = current.cashouts + current.txnFlow;
    final prevNet = prev != null ? prev.cashouts + prev.txnFlow : 0.0;
    final prevLabel = prev != null ? _monthFmt.format(prev.month) : 'N/A';
    final curLabel = _monthFmt.format(current.month);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.chartBlueLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.compare_arrows_rounded, size: 16, color: AppColors.chartBlue),
              ),
              const SizedBox(width: 10),
              Text('Month Comparison',
                  style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 16),

          // Two-column comparison
          Row(
            children: [
              Expanded(child: _comparisonColumn(curLabel, current, curNet, true)),
              Container(width: 1, height: 80, color: AppColors.borderLight),
              Expanded(child: _comparisonColumn(prevLabel, prev, prevNet, false)),
            ],
          ),

          // Delta row
          if (prev != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _deltaRow('Net Cash Flow', curNet, prevNet),
                  const SizedBox(height: 6),
                  _deltaRow('Cashouts', current.cashouts, prev.cashouts),
                  const SizedBox(height: 6),
                  _deltaRow('Txn Flow', current.txnFlow, prev.txnFlow),
                  const SizedBox(height: 6),
                  _deltaRow('Closing Balance', current.closingBalance, prev.closingBalance),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _comparisonColumn(String label, _MonthCash? data, double netFlow, bool isCurrent) {
    return Padding(
      padding: EdgeInsets.only(left: isCurrent ? 0 : 14, right: isCurrent ? 14 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isCurrent)
                Container(
                  width: 6, height: 6, margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryNavy, shape: BoxShape.circle),
                ),
              Text(label,
                  style: AppTypography.caption.copyWith(
                    color: isCurrent ? AppColors.primaryNavy : AppColors.textTertiary,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          if (data != null) ...[
            Text(_fmt.format(netFlow),
                style: AppTypography.metricSmall.copyWith(
                  color: netFlow >= 0 ? AppColors.chartGreen : AppColors.chartRed)),
            const SizedBox(height: 2),
            Text('net flow', style: AppTypography.caption.copyWith(
                color: AppColors.textTertiary, fontSize: 10)),
            const SizedBox(height: 8),
            Text('${data.txnCount} txns · ${_fmt.format(data.cashouts)} cashouts',
                style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary, fontSize: 10)),
          ] else
            Text('No data', style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }

  Widget _deltaRow(String label, double current, double previous) {
    final diff = current - previous;
    final pctChange = previous != 0 ? (diff / previous.abs()) * 100 : 0.0;
    final isUp = diff >= 0;

    return Row(
      children: [
        Expanded(
          child: Text(label, style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary, fontSize: 11)),
        ),
        Text(
          '${isUp ? '+' : ''}${_fmt.format(diff)}',
          style: AppTypography.caption.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isUp ? AppColors.chartGreen : AppColors.chartRed,
          ),
        ),
        if (previous != 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: (isUp ? AppColors.chartGreen : AppColors.chartRed).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${isUp ? '+' : ''}${pctChange.toStringAsFixed(0)}%',
              style: AppTypography.caption.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: isUp ? AppColors.chartGreen : AppColors.chartRed,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  // TAB 2: Transactions
  // ══════════════════════════════════════════════════════════
  Widget _buildTransactionsTab() {
    final included = _filteredIncluded;
    final excluded = _filteredExcluded;
    final cashouts = _filteredCashouts;

    // Build unified list: MapEntry<bool excluded, _CashEntry>
    // Status filter: 0=All, 1=Included, 2=Excluded, 3=Cashouts
    List<MapEntry<bool, _CashEntry>> all;
    switch (_txnStatusFilter) {
      case 1:
        all = included.map((e) => MapEntry(false, e)).toList();
      case 2:
        all = excluded.map((e) => MapEntry(true, e)).toList();
      case 3:
        all = cashouts.map((e) => MapEntry(false, e)).toList();
      default:
        all = [
          ...included.map((e) => MapEntry(false, e)),
          ...excluded.map((e) => MapEntry(true, e)),
          ...cashouts.map((e) => MapEntry(false, e)),
        ];
    }

    // Apply direction filter
    if (_txnDirectionFilter == 1) {
      all = all.where((e) => e.value.isIncome).toList();
    } else if (_txnDirectionFilter == 2) {
      all = all.where((e) => !e.value.isIncome).toList();
    }

    // Apply category filter
    if (_txnCategoryFilter != null) {
      all = all.where((e) => e.value.category == _txnCategoryFilter).toList();
    }

    all.sort((a, b) => b.value.date.compareTo(a.value.date));

    // Collect available categories for filter (include cashouts)
    final allCats = <String>{};
    for (final e in [...included, ...excluded, ...cashouts]) {
      allCats.add(e.category);
    }
    final sortedCats = allCats.toList()..sort();

    return Column(
      children: [
        // ── Filter bar ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status row (scrollable to fit Cashouts chip)
              SizedBox(
                height: 30,
                child: Row(
                  children: [
                    Expanded(
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _txnFilterChip('All', _txnStatusFilter == 0,
                              () => setState(() => _txnStatusFilter = 0)),
                          const SizedBox(width: 6),
                          _txnFilterChip('Included', _txnStatusFilter == 1,
                              () => setState(() => _txnStatusFilter = 1),
                              color: AppColors.chartGreen),
                          const SizedBox(width: 6),
                          _txnFilterChip('Excluded', _txnStatusFilter == 2,
                              () => setState(() => _txnStatusFilter = 2),
                              color: AppColors.chartOrange),
                          const SizedBox(width: 6),
                          _txnFilterChip('Cashouts', _txnStatusFilter == 3,
                              () => setState(() => _txnStatusFilter = 3),
                              color: AppColors.chartBlue),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Direction toggle
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _directionBtn(Icons.swap_vert_rounded, 0),
                          _directionBtn(Icons.south_west_rounded, 1),
                          _directionBtn(Icons.north_east_rounded, 2),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Category filter row
              if (sortedCats.length > 1) ...[
                const SizedBox(height: 6),
                SizedBox(
                  height: 28,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _catFilterChip('All Categories', _txnCategoryFilter == null,
                          () => setState(() => _txnCategoryFilter = null)),
                      for (final cat in sortedCats) ...[
                        const SizedBox(width: 6),
                        _catFilterChip(_categoryLabel(cat), _txnCategoryFilter == cat,
                            () => setState(() => _txnCategoryFilter = cat)),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Summary counts ──
        Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              Text('${all.length} results',
                  style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_txnStatusFilter != 0 || _txnDirectionFilter != 0 || _txnCategoryFilter != null)
                GestureDetector(
                  onTap: () => setState(() {
                    _txnStatusFilter = 0;
                    _txnDirectionFilter = 0;
                    _txnCategoryFilter = null;
                  }),
                  child: Text('Clear filters',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.chartBlue, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),

        // ── List ──
        if (all.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_list_off_rounded, size: 40, color: AppColors.textTertiary),
                  const SizedBox(height: 10),
                  Text('No transactions match filters',
                      style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: all.length,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final isExcluded = all[index].key;
                final entry = all[index].value;
                return _buildTxnTile(entry, isExcluded);
              },
            ),
          ),
      ],
    );
  }

  Widget _txnFilterChip(String label, bool selected, VoidCallback onTap, {Color? color}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? (color ?? AppColors.primaryNavy).withValues(alpha: 0.1)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: (color ?? AppColors.primaryNavy).withValues(alpha: 0.3))
              : null,
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: selected ? (color ?? AppColors.primaryNavy) : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _directionBtn(IconData icon, int value) {
    final selected = _txnDirectionFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _txnDirectionFilter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryNavy : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16,
            color: selected ? Colors.white : AppColors.textTertiary),
      ),
    );
  }

  Widget _catFilterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryNavy : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            fontSize: 11,
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildTxnTile(_CashEntry entry, bool isExcluded) {
    final cashImpact = entry.isIncome ? entry.amount.abs() : -entry.amount.abs();
    return GestureDetector(
      onTap: () => _showEntryDetail(entry, isExcluded),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isExcluded ? const Color(0xFFFCFCFC) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isExcluded ? null : [
            BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1)),
          ],
          border: isExcluded
              ? Border.all(color: AppColors.borderLight, width: 0.5)
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: entry.isCashout
                    ? AppColors.chartBlueLight
                    : isExcluded
                        ? const Color(0xFFF1F5F9)
                        : (entry.isIncome ? AppColors.chartGreenLight : AppColors.chartRedLight),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                entry.isCashout
                    ? Icons.account_balance_wallet_rounded
                    : isExcluded
                        ? Icons.do_not_disturb_alt_rounded
                        : (entry.isIncome ? Icons.south_west_rounded : Icons.north_east_rounded),
                size: 17,
                color: entry.isCashout
                    ? AppColors.chartBlue
                    : isExcluded
                        ? AppColors.textTertiary
                        : (entry.isIncome ? AppColors.chartGreen : AppColors.chartRed),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isExcluded ? AppColors.textSecondary : AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        _dateFmt.format(entry.date),
                        style: AppTypography.caption.copyWith(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                      if (entry.isCashout) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.chartBlueLight,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text('CASHOUT',
                              style: AppTypography.caption.copyWith(
                                  fontSize: 8, color: AppColors.chartBlue, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  if (isExcluded && entry.sublabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.chartOrangeLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          entry.sublabel!,
                          style: AppTypography.caption.copyWith(
                              fontSize: 10, color: AppColors.chartOrange, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'EGP ${_fmt.format(cashImpact)}',
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isExcluded
                        ? AppColors.textTertiary
                        : (cashImpact >= 0 ? AppColors.chartGreen : AppColors.chartRed),
                  ),
                ),
                const SizedBox(height: 2),
                Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textTertiary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Detail Bottom Sheet ──────────────────────────────────
  void _showEntryDetail(_CashEntry entry, bool isExcluded) {
    final cashImpact = entry.isIncome ? entry.amount.abs() : -entry.amount.abs();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: entry.isCashout
                              ? AppColors.chartBlueLight
                              : (entry.isIncome ? AppColors.chartGreenLight : AppColors.chartRedLight),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          entry.isCashout
                              ? Icons.account_balance_wallet_rounded
                              : (entry.isIncome ? Icons.south_west_rounded : Icons.north_east_rounded),
                          size: 22,
                          color: entry.isCashout
                              ? AppColors.chartBlue
                              : (entry.isIncome ? AppColors.chartGreen : AppColors.chartRed),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.label,
                                style: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(_dateFmt.format(entry.date),
                                style: AppTypography.caption.copyWith(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Amount hero
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'EGP ${_fmt.format(cashImpact)}',
                          style: AppTypography.metric.copyWith(
                            color: cashImpact >= 0 ? AppColors.chartGreen : AppColors.chartRed,
                            fontSize: 28,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          cashImpact >= 0 ? 'Cash In' : 'Cash Out',
                          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Status badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (entry.isCashout)
                        _detailBadge('Bosta Cashout', AppColors.chartBlue),
                      if (isExcluded)
                        _detailBadge('Excluded from Cash Balance', AppColors.chartOrange),
                      if (!isExcluded && !entry.isCashout)
                        _detailBadge('Included in Cash Balance', AppColors.chartGreen),
                      _detailBadge(_categoryLabel(entry.category), AppColors.primaryNavy),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Detail rows
                  _detailRow('ID', entry.id),
                  _detailRow('Category', _categoryLabel(entry.category)),
                  _detailRow('Amount (raw)', 'EGP ${_fmt.format(entry.amount)}'),
                  _detailRow('Direction', entry.isIncome ? 'Income' : 'Expense'),
                  _detailRow('Date', DateFormat('EEEE, MMM d, yyyy · HH:mm').format(entry.date)),
                  if (entry.saleId != null)
                    _detailRow('Sale ID', '#${entry.saleId}'),
                  if (entry.sublabel != null && !isExcluded)
                    _detailRow('Note', entry.sublabel!),
                  if (isExcluded && entry.sublabel != null)
                    _detailRow('Exclusion Reason', entry.sublabel!),
                  if (entry.isCashout && entry.rawData != null) ...[
                    if (entry.rawData!['tracking_number'] != null)
                      _detailRow('Tracking #', entry.rawData!['tracking_number'].toString()),
                  ],

                  // Navigate to full detail screen (for regular transactions)
                  if (!entry.isCashout) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _navigateToDetail(entry);
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 16),
                        label: const Text('View Full Details'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryNavy,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: AppTypography.caption.copyWith(
              color: color, fontWeight: FontWeight.w600, fontSize: 11)),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  void _navigateToDetail(_CashEntry entry) {
    final tx = Transaction(
      id: entry.id,
      userId: _cfUserId,
      title: entry.label,
      amount: entry.isIncome ? entry.amount.abs() : -entry.amount.abs(),
      dateTime: entry.date,
      categoryId: entry.category,
      note: entry.sublabel,
      saleId: entry.saleId,
      excludeFromPL: entry.rawData?['exclude_from_pl'] as bool? ?? false,
      isEstimate: entry.rawData?['is_estimate'] as bool? ?? false,
      isReconciliation: entry.rawData?['is_reconciliation'] as bool? ?? false,
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TransactionDetailScreen(transaction: tx)),
    );
  }

  // ══════════════════════════════════════════════════════════
  // TAB 3: Cashouts
  // ══════════════════════════════════════════════════════════
  Widget _buildCashoutsTab() {
    final cashouts = _filteredCashouts;
    final totalCashouts = _filteredTotalCashouts;

    if (cashouts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text('No Bosta cashouts found', style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Hero summary
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF10B981)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.chartGreen.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Received',
                          style: AppTypography.caption.copyWith(color: Colors.white60)),
                      Text('EGP ${_fmt.format(totalCashouts)}',
                          style: AppTypography.metric.copyWith(color: Colors.white, fontSize: 24)),
                    ],
                  ),
                ),
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${cashouts.length}',
                          style: AppTypography.labelMedium.copyWith(
                              color: Colors.white, fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(height: 2),
                    Text('deposits', style: AppTypography.caption.copyWith(
                        color: Colors.white54, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (cashouts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Row(
              children: [
                Text('Avg per cashout: ',
                    style: AppTypography.caption.copyWith(color: AppColors.textTertiary)),
                Text('EGP ${_fmt.format(totalCashouts / cashouts.length)}',
                    style: AppTypography.caption.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            itemCount: cashouts.length,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final c = cashouts[index];
              return GestureDetector(
                onTap: () => _showEntryDetail(c, false),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4, offset: const Offset(0, 1)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.chartGreenLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text('${index + 1}',
                              style: AppTypography.labelSmall.copyWith(
                                  color: AppColors.chartGreen, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.sublabel ?? c.id,
                                style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w500),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(_dateFmt.format(c.date),
                                style: AppTypography.caption.copyWith(
                                    color: AppColors.textTertiary, fontSize: 11)),
                          ],
                        ),
                      ),
                      Text('+${_fmt.format(c.amount)}',
                          style: AppTypography.bodyMedium.copyWith(
                              fontWeight: FontWeight.w700, color: AppColors.chartGreen)),
                      const SizedBox(width: 4),
                      Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textTertiary),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  // TAB 4: History
  // ══════════════════════════════════════════════════════════
  Widget _buildHistoryTab() {
    if (_monthHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline_rounded, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text('No history data', style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _monthHistory.length + 1,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.chartBlueLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.timeline_rounded, size: 16, color: AppColors.chartBlue),
                ),
                const SizedBox(width: 10),
                Text('Monthly Running Balance',
                    style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          );
        }

        final m = _monthHistory[index - 1];
        return _buildMonthCard(m, isFirst: index == 1);
      },
    );
  }

  Widget _buildMonthCard(_MonthCash m, {bool isFirst = false}) {
    final netChange = m.cashouts + m.txnFlow;
    final isPositive = netChange >= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Timeline rail
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: isFirst ? AppColors.primaryNavy : AppColors.chartBlue,
                      shape: BoxShape.circle,
                      border: isFirst
                          ? Border.all(color: AppColors.chartBlue.withValues(alpha: 0.3), width: 3)
                          : null,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: AppColors.borderLight,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Card
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(_monthFmt.format(m.month),
                            style: AppTypography.labelMedium.copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPositive ? AppColors.chartGreenLight : AppColors.chartRedLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${isPositive ? '+' : ''}${_fmt.format(netChange)}',
                            style: AppTypography.caption.copyWith(
                              color: isPositive ? AppColors.chartGreen : AppColors.chartRed,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Mini grid
                    Row(
                      children: [
                        _miniMetric('Opening', m.openingBalance, AppColors.textSecondary),
                        _miniMetric('Cashouts', m.cashouts, AppColors.chartGreen),
                        _miniMetric('Txn Flow', m.txnFlow,
                            m.txnFlow >= 0 ? AppColors.chartBlue : AppColors.chartRed),
                        _miniMetric('Closing', m.closingBalance, AppColors.primaryNavy, isBold: true),
                      ],
                    ),
                    if (m.txnCount > 0) ...[
                      const SizedBox(height: 6),
                      Text('${m.txnCount} transaction${m.txnCount > 1 ? 's' : ''}',
                          style: AppTypography.caption.copyWith(
                              color: AppColors.textTertiary, fontSize: 10)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniMetric(String label, double value, Color color, {bool isBold = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.caption.copyWith(
              color: AppColors.textTertiary, fontSize: 9.5, letterSpacing: 0.2)),
          const SizedBox(height: 1),
          Text(
            _fmt.format(value),
            style: AppTypography.caption.copyWith(
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              fontSize: 11,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Monthly cash data for the History tab.
class _MonthCash {
  final DateTime month;
  double cashouts = 0;
  double txnFlow = 0;
  int txnCount = 0;
  double openingBalance = 0;
  double closingBalance = 0;

  _MonthCash({required this.month});
}
