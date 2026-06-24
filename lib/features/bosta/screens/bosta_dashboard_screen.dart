import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/bosta_connection_provider.dart';
import '../../../core/services/bosta_api_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../shared/models/bosta_connection_model.dart';
import '../../../shared/models/transaction_model.dart';
import '../../../shared/utils/report_constants.dart';
import '../../../shared/utils/safe_pop.dart';
import '../../reports/widgets/financial_period_sheet.dart';

void _log(String msg) => dev.log(msg, name: 'BostaDash');

const _bostaRed = Color(0xFFE2342D);

/// Full Bosta Dashboard — Overview · Cashouts · Transactions.
///
/// Shows dashboard login status, cashout history, and all sale-linked
/// transactions for auditing accounting accuracy.
class BostaDashboardScreen extends ConsumerStatefulWidget {
  const BostaDashboardScreen({super.key});

  @override
  ConsumerState<BostaDashboardScreen> createState() =>
      _BostaDashboardScreenState();
}

class _BostaDashboardScreenState extends ConsumerState<BostaDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // ── Dashboard login ──
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isConnecting = false;
  bool _obscurePass = true;
  bool _shownAuthWarning = false;

  // ── Cashouts ──
  List<Map<String, dynamic>>? _cashouts;
  bool _cashoutsLoading = true;
  bool _isSyncing = false;

  // ── Transactions ──
  List<Transaction>? _transactions;
  bool _txnsLoading = true;
  String _txnFilter = 'all'; // all, revenue, cogs, shipping, bosta

  // ── Date filter (shared across all tabs) ──
  FinancialPeriodResult? _period;
  DateTimeRange? _customRange;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    Future.microtask(() {
      _loadCashouts();
      _loadTransactions();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════
  //  DATA LOADING
  // ═══════════════════════════════════════════════════════

  Future<void> _loadCashouts() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('bosta_cashouts')
          .where('user_id', isEqualTo: userId)
          .orderBy('transaction_date', descending: true)
          .get();
      if (mounted) {
        setState(() {
          _cashouts = snap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList();
          _cashoutsLoading = false;
        });
      }
    } catch (e) {
      _log('loadCashouts error: $e');
      if (mounted) setState(() => _cashoutsLoading = false);
    }
  }

  Future<void> _loadTransactions() async {
    final userId = ref.read(authProvider).user?.id;
    if (userId == null) return;
    try {
      // Top-level 'transactions' collection, filtered by user_id.
      final snap = await FirebaseFirestore.instance
          .collection('transactions')
          .where('user_id', isEqualTo: userId)
          .orderBy('date_time', descending: true)
          .get();
      if (mounted) {
        setState(() {
          _transactions =
              snap.docs.map((d) {
                final data = d.data();
                data['id'] = d.id;
                return Transaction.fromJson(data);
              }).toList();
          _txnsLoading = false;
        });
      }
    } catch (e) {
      _log('loadTransactions error: $e');
      if (mounted) setState(() => _txnsLoading = false);
    }
  }

  Future<void> _connectDashboard() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (email.isEmpty || pass.isEmpty) return;
    setState(() => _isConnecting = true);
    try {
      final api = BostaApiService();
      final result = await api.connectDashboard(email: email, password: pass);
      if (mounted) {
        if (result.isSuccess) {
          ref.invalidate(bostaConnectionProvider);
          _shownAuthWarning = false;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Dashboard connected — syncing cashouts…'),
                backgroundColor: Colors.green),
          );
          _emailCtrl.clear();
          _passCtrl.clear();
          // Auto-sync cashouts to catch up on missed period
          _syncCashouts();
          _loadCashouts();
          _loadTransactions();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(result.error ?? 'Login failed'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _isConnecting = false);
  }

  Future<void> _syncCashouts({String? startDate}) async {
    HapticFeedback.mediumImpact();
    setState(() => _isSyncing = true);
    try {
      final api = BostaApiService();
      final result = await api.syncCashouts(startDate: startDate);
      if (mounted) {
        final data = result.isSuccess ? result.data : null;
        final fetched = data?['cashoutsFetched'] ?? 0;
        final msg = result.isSuccess
            ? 'Synced $fetched cashouts'
            : (result.error ?? 'Sync failed');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: result.isSuccess ? Colors.green : Colors.red,
          ),
        );
        if (result.isSuccess) _loadCashouts();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _syncCashoutsWithDatePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 365)),
        end: DateTime.now(),
      ),
      helpText: 'Select cashout date range',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.primaryNavy,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final start = picked.start.toIso8601String().substring(0, 10);
    await _syncCashouts(startDate: start);
  }

  // ═══════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(bostaConnectionProvider).value;

    // One-time snackbar when dashboard auth failure is detected
    if (conn?.isDashboardAuthFailed == true && !_shownAuthWarning) {
      _shownAuthWarning = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Bosta dashboard login expired — please re-login',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      });
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            _buildPeriodFilterBar(),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildOverviewTab(conn),
                  _buildCashoutsTab(),
                  _buildTransactionsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderLight.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            onPressed: () => context.safePop(),
            color: AppColors.primaryNavy,
          ),
          const SizedBox(width: 4),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _bostaRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.local_shipping_rounded,
                size: 15, color: _bostaRed),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bosta Dashboard',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: _bostaRed),
              ),
            )
          else
            PopupMenuButton<String>(
              icon: const Icon(Icons.sync_rounded, size: 20,
                  color: AppColors.textSecondary),
              tooltip: 'Sync Cashouts',
              onSelected: (v) {
                if (v == 'quick') _syncCashouts();
                if (v == 'range') _syncCashoutsWithDatePicker();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'quick',
                  child: ListTile(
                    leading: Icon(Icons.sync_rounded),
                    title: Text('Quick Sync'),
                    subtitle: Text('Last 7 days'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'range',
                  child: ListTile(
                    leading: Icon(Icons.date_range_rounded),
                    title: Text('Full Sync'),
                    subtitle: Text('Choose date range'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabCtrl,
        labelColor: _bostaRed,
        unselectedLabelColor: AppColors.textTertiary,
        indicatorColor: _bostaRed,
        indicatorWeight: 2.5,
        dividerColor: Colors.transparent,
        labelStyle: AppTypography.labelSmall.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        unselectedLabelStyle: AppTypography.labelSmall.copyWith(
          fontWeight: FontWeight.w500,
          fontSize: 12.5,
        ),
        tabs: const [
          Tab(
            icon: Icon(Icons.dashboard_rounded, size: 18),
            text: 'Overview',
            height: 52,
          ),
          Tab(
            icon: Icon(Icons.account_balance_wallet_rounded, size: 18),
            text: 'Cashouts',
            height: 52,
          ),
          Tab(
            icon: Icon(Icons.receipt_long_rounded, size: 18),
            text: 'Transactions',
            height: 52,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  PERIOD FILTER
  // ═══════════════════════════════════════════════════════

  /// Active date range from either period sheet or custom picker.
  DateTimeRange? get _activeDateRange {
    if (_period != null) return _period!.range;
    return _customRange;
  }

  /// Label for the active filter.
  String get _activeFilterLabel {
    if (_period != null) return _period!.label;
    if (_customRange != null) {
      final fmt = DateFormat('dd MMM');
      return '${fmt.format(_customRange!.start)} – ${fmt.format(_customRange!.end)}';
    }
    return 'All Time';
  }

  bool get _hasActiveFilter => _period != null || _customRange != null;

  void _clearFilter() {
    setState(() {
      _period = null;
      _customRange = null;
    });
  }

  Future<void> _showPeriodSheet() async {
    HapticFeedback.selectionClick();
    final result = await showFinancialPeriodSheet(context, current: _period);
    if (result != null && mounted) {
      setState(() {
        _period = result;
        _customRange = null;
      });
    }
  }

  Future<void> _showCustomRange() async {
    HapticFeedback.selectionClick();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
      initialDateRange: _customRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFFE2342D),
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _customRange = DateTimeRange(
          start: picked.start,
          end: DateTime(picked.end.year, picked.end.month, picked.end.day,
              23, 59, 59),
        );
        _period = null;
      });
    }
  }

  Widget _buildPeriodFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderLight.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          // Month button
          _periodButton(
            label: 'Month',
            icon: Icons.calendar_month_rounded,
            isActive: _period?.type == FinancialPeriodType.monthEnd,
            onTap: _showPeriodSheet,
          ),
          const SizedBox(width: 8),
          // Year button
          _periodButton(
            label: 'Year',
            icon: Icons.calendar_today_rounded,
            isActive: _period?.type == FinancialPeriodType.yearEnd,
            onTap: _showPeriodSheet,
          ),
          const SizedBox(width: 8),
          // Custom button
          _periodButton(
            label: 'Custom',
            icon: Icons.date_range_rounded,
            isActive: _customRange != null,
            onTap: _showCustomRange,
          ),
          const Spacer(),
          // Active label / clear
          if (_hasActiveFilter)
            GestureDetector(
              onTap: _clearFilter,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _bostaRed.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _bostaRed.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _activeFilterLabel,
                      style: AppTypography.captionSmall.copyWith(
                        color: _bostaRed,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.close_rounded,
                        size: 12, color: _bostaRed),
                  ],
                ),
              ),
            )
          else
            Text(
              'All Time',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }

  Widget _periodButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? _bostaRed : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? _bostaRed : AppColors.borderLight,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13,
                color: isActive ? Colors.white : AppColors.textTertiary),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTypography.captionSmall.copyWith(
                color: isActive ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Filter a date against the active range.
  bool _dateInRange(DateTime? date) {
    if (date == null) return false;
    final range = _activeDateRange;
    if (range == null) return true;
    return !date.isBefore(range.start) && !date.isAfter(range.end);
  }

  /// Parse cashout transaction_date string to DateTime.
  DateTime? _parseCashoutDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    return DateTime.tryParse(dateStr);
  }

  // ═══════════════════════════════════════════════════════
  //  TAB 1: OVERVIEW
  // ═══════════════════════════════════════════════════════

  Widget _buildOverviewTab(BostaConnection? conn) {
    final fmt = NumberFormat('#,##0.00', 'en');
    final fmtInt = NumberFormat('#,##0', 'en');

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(bostaConnectionProvider);
        await _loadCashouts();
        await _loadTransactions();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          // ── Auth Failure Warning Banner ──
          if (conn?.isDashboardAuthFailed == true)
            _buildDashboardAuthBanner()
                .animate().fadeIn(duration: 200.ms),

          // ── Connection Status Card ──
          _buildStatusCard(conn)
              .animate().fadeIn(duration: 250.ms),
          const SizedBox(height: 16),

          // ── Dashboard Login (if not active) ──
          if (conn?.dashboardStatus != 'active') ...[
            _buildLoginCard()
                .animate().fadeIn(duration: 250.ms, delay: 60.ms),
            const SizedBox(height: 16),
          ],

          // ── Shipment Stats ──
          if (conn?.stats != null) ...[
            _buildShipmentStatsCard(conn!.stats!, fmtInt)
                .animate().fadeIn(duration: 250.ms, delay: 120.ms),
            const SizedBox(height: 16),
          ],

          // ── KPI Cards ──
          if (_cashouts != null || _transactions != null) ...[
            _buildKpiSection(conn, fmt, fmtInt)
                .animate().fadeIn(duration: 250.ms, delay: 180.ms),
          ],
        ],
      ),
    );
  }

  Widget _buildDashboardAuthBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                size: 22, color: Color(0xFFEF4444)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dashboard login expired',
                    style: AppTypography.labelSmall.copyWith(
                      color: const Color(0xFFEF4444),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your Bosta password may have changed. Re-login below to restore cashout sync.',
                    style: AppTypography.bodySmall.copyWith(
                      color: const Color(0xFFB91C1C),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_downward_rounded,
                size: 18, color: Color(0xFFEF4444)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BostaConnection? conn) {
    final isActive = conn?.isActive ?? false;
    final dashActive = conn?.dashboardStatus == 'active';
    final dashFailed = conn?.isDashboardAuthFailed ?? false;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row with pulsing dot
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isActive
                        ? [const Color(0xFF10B981), const Color(0xFF059669)]
                        : [const Color(0xFFEF4444), const Color(0xFFDC2626)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isActive
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isActive ? 'Connected' : 'Disconnected',
                          style: AppTypography.labelMedium.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Pulsing dot
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Two status chips
                    Row(
                      children: [
                        _statusChip(
                          'API',
                          isActive,
                          isActive ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                        ),
                        const SizedBox(width: 6),
                        _statusChip(
                          'Dashboard',
                          dashActive,
                          dashActive
                              ? const Color(0xFF10B981)
                              : dashFailed
                                  ? const Color(0xFFEF4444)
                                  : AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (conn != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _infoRow('Connected Since',
                      conn.connectedAt.toString().substring(0, 10)),
                  if (conn.lastSyncAt != null)
                    _infoRow('Last Sync',
                        DateFormat('dd MMM yyyy, HH:mm').format(conn.lastSyncAt!)),
                  if (conn.cfLastCashoutDate != null)
                    _infoRow('Last Cashout',
                        DateFormat('dd MMM yyyy').format(conn.cfLastCashoutDate!)),
                  if (conn.cfLastCashoutSyncAt != null)
                    _infoRow('Cashout Sync',
                        DateFormat('dd MMM yyyy, HH:mm').format(conn.cfLastCashoutSyncAt!)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(String label, bool active, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 12,
              )),
          const Spacer(),
          Text(value,
              style: AppTypography.labelSmall.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              )),
        ],
      ),
    );
  }

  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _bostaRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.login_rounded,
                    size: 18, color: _bostaRed),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dashboard Login',
                        style: AppTypography.labelMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                    Text(
                      'Connect to sync cashout data',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            style: AppTypography.bodySmall.copyWith(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Email',
              labelStyle: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary, fontSize: 12),
              prefixIcon: const Icon(Icons.email_outlined, size: 18),
              filled: true,
              fillColor: AppColors.backgroundLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passCtrl,
            obscureText: _obscurePass,
            style: AppTypography.bodySmall.copyWith(fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Password',
              labelStyle: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary, fontSize: 12),
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscurePass
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 18),
                onPressed: () =>
                    setState(() => _obscurePass = !_obscurePass),
              ),
              filled: true,
              fillColor: AppColors.backgroundLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isConnecting ? null : _connectDashboard,
              style: ElevatedButton.styleFrom(
                backgroundColor: _bostaRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isConnecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('Connect Dashboard',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      )),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiSection(
      BostaConnection? conn, NumberFormat fmt, NumberFormat fmtInt) {
    // Cashout totals (filtered)
    double totalCashouts = 0;
    int cashoutCount = 0;
    if (_cashouts != null) {
      for (final c in _cashouts!) {
        if (!_dateInRange(_parseCashoutDate(c['transaction_date'] as String?))) {
          continue;
        }
        totalCashouts += (c['amount'] as num?)?.toDouble() ?? 0;
        cashoutCount++;
      }
    }

    // Transaction totals by category (filtered)
    double totalRevenue = 0, totalCogs = 0, totalShipping = 0;
    double totalBostaFees = 0;
    int revCount = 0, cogsCount = 0, shipCount = 0, bostaCount = 0;
    if (_transactions != null) {
      for (final t in _transactions!) {
        if (!_dateInRange(t.dateTime)) continue;
        if (t.categoryId == 'cat_sales_revenue') {
          totalRevenue += t.amount;
          revCount++;
        } else if (t.categoryId == 'cat_cogs') {
          totalCogs += t.amount;
          cogsCount++;
        } else if (t.categoryId == 'cat_shipping') {
          totalShipping += t.amount;
          shipCount++;
        } else if (t.categoryId == 'cat_shipping_expense') {
          totalBostaFees += t.amount;
          bostaCount++;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('CASH FLOW'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _kpiCard(
                    'Total Cashouts',
                    fmt.format(totalCashouts),
                    '$cashoutCount deposits',
                    const Color(0xFF10B981),
                    Icons.arrow_downward_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: _kpiCard(
                    'Pending AR',
                    fmt.format(conn?.cfPendingAr ?? 0),
                    '${conn?.cfPendingArCount ?? 0} shipments',
                    const Color(0xFFF59E0B),
                    Icons.hourglass_top_rounded)),
          ],
        ),
        const SizedBox(height: 20),
        _sectionLabel('ACCRUAL ENTRIES'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _kpiCard('Revenue', fmt.format(totalRevenue),
                    '$revCount txns', const Color(0xFF3B82F6),
                    Icons.point_of_sale_rounded)),
            const SizedBox(width: 10),
            Expanded(
                child: _kpiCard('COGS', fmt.format(totalCogs),
                    '$cogsCount txns', const Color(0xFFEF4444),
                    Icons.inventory_2_outlined)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _kpiCard('Shipping Rev', fmt.format(totalShipping),
                    '$shipCount txns', const Color(0xFF8B5CF6),
                    Icons.local_shipping_outlined)),
            const SizedBox(width: 10),
            Expanded(
                child: _kpiCard('Bosta Fees', fmt.format(totalBostaFees),
                    '$bostaCount txns', _bostaRed,
                    Icons.receipt_long_outlined)),
          ],
        ),
        const SizedBox(height: 16),
        // Accuracy check
        _buildAccuracyCheck(fmt, totalCashouts, totalRevenue, totalCogs,
            totalShipping, totalBostaFees, conn),
      ],
    );
  }

  Widget _buildAccuracyCheck(
    NumberFormat fmt,
    double totalCashouts,
    double totalRevenue,
    double totalCogs,
    double totalShipping,
    double totalBostaFees,
    BostaConnection? conn,
  ) {
    final netAccrual = totalRevenue + totalShipping + totalCogs;
    final diff = totalCashouts - netAccrual;
    final isBalanced = diff.abs() < 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isBalanced
            ? const Color(0xFF10B981).withValues(alpha: 0.05)
            : const Color(0xFFF59E0B).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isBalanced
              ? const Color(0xFF10B981).withValues(alpha: 0.2)
              : const Color(0xFFF59E0B).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (isBalanced
                          ? const Color(0xFF10B981)
                          : const Color(0xFFF59E0B))
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isBalanced
                      ? Icons.verified_rounded
                      : Icons.warning_amber_rounded,
                  size: 18,
                  color: isBalanced
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cashout vs Accrual Check',
                      style: AppTypography.labelSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      isBalanced ? 'Everything balanced' : 'Variance detected',
                      style: AppTypography.captionSmall.copyWith(
                        color: isBalanced
                            ? const Color(0xFF10B981)
                            : const Color(0xFFF59E0B),
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                _auditRow('Net Accrual (Rev+Ship+COGS)', fmt.format(netAccrual)),
                _auditRow('Total Cashouts', fmt.format(totalCashouts)),
                const SizedBox(height: 4),
                Container(
                  height: 1,
                  color: AppColors.borderLight.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 4),
                _auditRow('Difference', fmt.format(diff),
                    highlight: !isBalanced),
                _auditRow('Pending AR', fmt.format(conn?.cfPendingAr ?? 0)),
                _auditRow('Expected Diff',
                    fmt.format((conn?.cfPendingAr ?? 0) + totalBostaFees)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _auditRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11.5,
                  ))),
          Text(value,
              style: AppTypography.labelSmall.copyWith(
                fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12,
                color: highlight ? const Color(0xFFF59E0B) : AppColors.textPrimary,
              )),
        ],
      ),
    );
  }

  Widget _kpiCard(String title, String value, String sub, Color color,
      IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(height: 10),
          Text(title,
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
                fontSize: 10,
              )),
          const SizedBox(height: 4),
          Text(value,
              style: AppTypography.labelMedium.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(sub,
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10,
              )),
        ],
      ),
    );
  }

  Widget _buildShipmentStatsCard(BostaStats stats, NumberFormat fmtInt) {
    final total = stats.totalShipments;
    final matchPct = total > 0 ? stats.matchedCount / total : 0.0;
    final settlePct = total > 0 ? stats.settledCount / total : 0.0;
    final feeFmt = NumberFormat('#,##0.00', 'en');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.analytics_rounded,
                    size: 18, color: AppColors.primaryNavy),
              ),
              const SizedBox(width: 12),
              Text('Shipment Stats',
                  style: AppTypography.labelMedium.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
              const Spacer(),
              Text(
                '${fmtInt.format(total)} total',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Matched progress
          _progressRow(
            label: 'Matched',
            count: '${fmtInt.format(stats.matchedCount)} / ${fmtInt.format(total)}',
            pct: matchPct,
            color: const Color(0xFF10B981),
          ),
          const SizedBox(height: 12),

          // Settled progress
          _progressRow(
            label: 'Settled',
            count: '${fmtInt.format(stats.settledCount)} / ${fmtInt.format(total)}',
            pct: settlePct,
            color: const Color(0xFF3B82F6),
          ),
          const SizedBox(height: 14),

          // Bottom row: fees + unlinked/awaiting
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Fees',
                          style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                          )),
                      const SizedBox(height: 2),
                      Text(
                        'EGP ${feeFmt.format(stats.totalFees)}',
                        style: AppTypography.labelSmall.copyWith(
                          color: _bostaRed,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: AppColors.borderLight,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF59E0B),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text('${fmtInt.format(stats.unlinkedCount)} unlinked',
                                style: AppTypography.captionSmall.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                )),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: AppColors.textTertiary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text('${fmtInt.format(stats.awaitingCount)} awaiting',
                                style: AppTypography.captionSmall.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                )),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressRow({
    required String label,
    required String count,
    required double pct,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                )),
            Row(
              children: [
                Text(count,
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                    )),
                const SizedBox(width: 6),
                Text('${(pct * 100).toStringAsFixed(0)}%',
                    style: AppTypography.labelSmall.copyWith(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    )),
              ],
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 5,
            backgroundColor: AppColors.borderLight,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: AppTypography.captionSmall.copyWith(
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        fontSize: 11,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  TAB 2: CASHOUTS
  // ═══════════════════════════════════════════════════════

  Widget _buildCashoutsTab() {
    if (_cashoutsLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final allCashouts = _cashouts;
    if (allCashouts == null || allCashouts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_wallet_outlined,
                size: 56, color: AppColors.textTertiary.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            Text('No cashouts yet',
                style: AppTypography.h3.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 6),
            Text('Sync cashouts to see deposit history',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                )),
          ],
        ),
      );
    }

    // Apply date filter
    final cashouts = _hasActiveFilter
        ? allCashouts
            .where((c) => _dateInRange(
                _parseCashoutDate(c['transaction_date'] as String?)))
            .toList()
        : allCashouts;

    final fmt = NumberFormat('#,##0.00', 'en');
    double runningTotal = 0;
    final reversed = cashouts.reversed.toList();
    final runningTotals = <double>[];
    for (final c in reversed) {
      runningTotal += (c['amount'] as num?)?.toDouble() ?? 0;
      runningTotals.add(runningTotal);
    }
    final totals = runningTotals.reversed.toList();
    final avgCashout = cashouts.isNotEmpty ? runningTotal / cashouts.length : 0.0;

    return RefreshIndicator(
      onRefresh: _loadCashouts,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        itemCount: cashouts.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            // Summary header card
            return Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Received',
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            )),
                        const SizedBox(height: 2),
                        Text(
                          'EGP ${fmt.format(runningTotal)}',
                          style: AppTypography.labelLarge.copyWith(
                            color: const Color(0xFF059669),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text('${cashouts.length} deposits',
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                            )),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Avg / Cashout',
                              style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w600,
                                fontSize: 10,
                              )),
                          const SizedBox(height: 2),
                          Text(
                            'EGP ${fmt.format(avgCashout)}',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.sync_rounded, size: 18,
                        color: Color(0xFF059669)),
                    onPressed: _syncCashouts,
                    tooltip: 'Sync cashouts',
                  ),
                ],
              ),
            ).animate().fadeIn(duration: 200.ms);
          }

          final c = cashouts[index - 1];
          final amt = (c['amount'] as num?)?.toDouble() ?? 0;
          final date = c['transaction_date'] as String? ?? '';
          final txId = c['transaction_id'] as String? ?? c['id'] as String? ?? '';
          final cumulative = totals[index - 1];
          final isLast = index == cashouts.length;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline line
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.3),
                            width: 2),
                      ),
                    ),
                    if (!isLast)
                      Container(
                        width: 1.5,
                        height: 64,
                        color: AppColors.borderLight.withValues(alpha: 0.5),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Card
              Expanded(
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.borderLight.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(date,
                                style: AppTypography.labelSmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                )),
                            const SizedBox(height: 2),
                            Text(
                              txId.length > 24 ? '${txId.substring(0, 24)}…' : txId,
                              style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('+${fmt.format(amt)}',
                              style: AppTypography.labelSmall.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF10B981),
                              )),
                          const SizedBox(height: 2),
                          Text('Σ ${fmt.format(cumulative)}',
                              style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 10,
                              )),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ).animate().fadeIn(
                duration: 200.ms,
                delay: ((index - 1).clamp(0, 20) * 15).ms,
              );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  TAB 3: TRANSACTIONS
  // ═══════════════════════════════════════════════════════

  Widget _buildTransactionsTab() {
    if (_txnsLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final allTxns = _transactions;
    if (allTxns == null || allTxns.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 56, color: AppColors.textTertiary.withValues(alpha: 0.4)),
            const SizedBox(height: 14),
            Text('No transactions',
                style: AppTypography.h3.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 6),
            Text('Transactions will appear as sales are synced',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                )),
          ],
        ),
      );
    }

    // Date filter first, then category filter
    final dateTxns = _hasActiveFilter
        ? allTxns.where((t) => _dateInRange(t.dateTime)).toList()
        : allTxns;

    // Category filter
    final filtered = dateTxns.where((t) {
      switch (_txnFilter) {
        case 'revenue':
          return t.categoryId == 'cat_sales_revenue';
        case 'cogs':
          return t.categoryId == 'cat_cogs';
        case 'shipping':
          return t.categoryId == 'cat_shipping';
        case 'bosta':
          return t.categoryId == 'cat_shipping_expense';
        case 'sale_linked':
          return t.saleId != null && saleTxnCats.contains(t.categoryId);
        default:
          return t.categoryId == 'cat_sales_revenue' ||
              t.categoryId == 'cat_cogs' ||
              t.categoryId == 'cat_shipping' ||
              t.categoryId == 'cat_shipping_expense';
      }
    }).toList();

    final fmt = NumberFormat('#,##0.00', 'en');
    final sum = filtered.fold<double>(0, (s, t) => s + t.amount);

    return Column(
      children: [
        // Filter chips
        Container(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', 'all'),
                _filterChip('Revenue', 'revenue'),
                _filterChip('COGS', 'cogs'),
                _filterChip('Shipping', 'shipping'),
                _filterChip('Bosta Fees', 'bosta'),
                _filterChip('Sale Linked', 'sale_linked'),
              ],
            ),
          ),
        ),
        // Summary bar
        Container(
          margin: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              Text(
                '${filtered.length} transactions',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                'Net: ',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 12,
                ),
              ),
              Text(
                'EGP ${fmt.format(sum)}',
                style: AppTypography.labelSmall.copyWith(
                  fontWeight: FontWeight.w700,
                  color: sum >= 0
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadTransactions,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                return _buildTransactionTile(filtered[index], fmt)
                    .animate()
                    .fadeIn(
                      duration: 200.ms,
                      delay: (index.clamp(0, 20) * 15).ms,
                    );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _txnFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _txnFilter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? _bostaRed : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? _bostaRed : AppColors.borderLight,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: isSelected ? Colors.white : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionTile(Transaction t, NumberFormat fmt) {
    final isPositive = t.amount >= 0;
    final catLabel = _categoryLabel(t.categoryId);
    final dateStr = DateFormat('dd MMM yyyy').format(t.dateTime);
    final isReversal = t.id.contains('_reversal');
    final isRefund = t.id.contains('_refund_');

    Color catColor;
    IconData catIcon;
    switch (t.categoryId) {
      case 'cat_sales_revenue':
        catColor = const Color(0xFF3B82F6);
        catIcon = Icons.point_of_sale_rounded;
      case 'cat_cogs':
        catColor = const Color(0xFFEF4444);
        catIcon = Icons.inventory_2_outlined;
      case 'cat_shipping':
        catColor = const Color(0xFF8B5CF6);
        catIcon = Icons.local_shipping_outlined;
      case 'cat_shipping_expense':
        catColor = _bostaRed;
        catIcon = Icons.receipt_long_outlined;
      default:
        catColor = AppColors.textTertiary;
        catIcon = Icons.receipt_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isReversal || isRefund
              ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
              : AppColors.borderLight.withValues(alpha: 0.4),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Left accent border
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: catColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(catIcon, color: catColor, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(catLabel,
                                  style: AppTypography.labelSmall.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  )),
                              if (isReversal) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('REV',
                                      style: AppTypography.captionSmall.copyWith(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFFD97706),
                                      )),
                                ),
                              ],
                              if (isRefund) ...[
                                const SizedBox(width: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('REFUND',
                                      style: AppTypography.captionSmall.copyWith(
                                        fontSize: 8,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFFEF4444),
                                      )),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$dateStr${t.saleId != null ? " · ${t.saleId!.length > 8 ? t.saleId!.substring(0, 8) : t.saleId}" : ""}',
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${isPositive ? "+" : ""}${fmt.format(t.amount)}',
                      style: AppTypography.labelSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: isPositive
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _categoryLabel(String catId) {
    switch (catId) {
      case 'cat_sales_revenue':
        return 'Revenue';
      case 'cat_cogs':
        return 'COGS';
      case 'cat_shipping':
        return 'Shipping Revenue';
      case 'cat_shipping_expense':
        return 'Bosta Fee';
      default:
        return catId;
    }
  }
}
