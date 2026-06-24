import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/navigation/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/bosta_connection_provider.dart';
import '../../shared/models/sale_model.dart';
import '../../shared/models/bosta_shipment_model.dart';
import '../../shared/utils/money_utils.dart';
import '../../shared/utils/safe_pop.dart';

/// CF user ID for AR dashboard.
const _cfUserId = 'EGYQnP7ughdUtTbn04UwUET534i1';

// ── AR Entry: a COD sale that contributes to accounts receivable ──
class _ArEntry {
  final String saleId;
  final String label;
  final String? customerName;
  final double saleTotal;
  final DateTime date;
  final String? shopifyOrderNumber;
  final String? trackingNumber;
  final String shipmentStatus; // 'In Transit', 'Delivered', 'RTO', etc.
  final String cashoutStatus; // 'pending', 'paid'
  final int shipmentState; // bosta state code
  final int daysAsAr; // days since sale date
  final bool isStale; // true if AR for > 14 days without update
  final Map<String, dynamic> rawSaleData;
  final Map<String, dynamic>? rawShipmentData;

  const _ArEntry({
    required this.saleId,
    required this.label,
    this.customerName,
    required this.saleTotal,
    required this.date,
    this.shopifyOrderNumber,
    this.trackingNumber,
    required this.shipmentStatus,
    required this.cashoutStatus,
    required this.shipmentState,
    required this.daysAsAr,
    required this.isStale,
    required this.rawSaleData,
    this.rawShipmentData,
  });
}

/// Monthly AR snapshot for history tab.
class _MonthAr {
  final DateTime month;
  double totalAr = 0;
  int orderCount = 0;
  int deliveredCount = 0;
  int inTransitCount = 0;
  int rtoCount = 0;

  _MonthAr({required this.month});
}

/// Accounts Receivable dashboard for the CF user.
/// Shows COD orders awaiting cashout, grouped by shipment status.
class ArDashboardScreen extends ConsumerStatefulWidget {
  const ArDashboardScreen({super.key});

  @override
  ConsumerState<ArDashboardScreen> createState() => _ArDashboardScreenState();
}

class _ArDashboardScreenState extends ConsumerState<ArDashboardScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  String _error = '';
  late TabController _tabController;

  // ── Loaded data ──
  double _totalAr = 0;
  double _precomputedAr = 0; // from bosta_connections doc
  final List<_ArEntry> _arEntries = [];

  // Shipment status breakdown
  int _deliveredAwaitingCount = 0;
  double _deliveredAwaitingAmount = 0;
  int _inTransitCount = 0;
  double _inTransitAmount = 0;
  int _noShipmentCount = 0;
  double _noShipmentAmount = 0;
  int _staleCount = 0;
  double _staleAmount = 0;

  /// Days threshold for flagging an AR entry as stale.
  static const _staleDays = 14;

  // Monthly history
  final List<_MonthAr> _monthHistory = [];

  // ── Month filter ──
  DateTime? _selectedMonth;
  List<DateTime> _availableMonths = [];

  // ── Transaction filters ──
  /// 0=All, 1=Delivered Awaiting, 2=In Transit, 3=No Shipment, 4=Stale (>14d)
  int _statusFilter = 0;
  /// Shipments tab: 0=All, 1=Delivered, 2=In Transit
  int _shipmentFilter = 0;

  final _fmt = NumberFormat('#,##0.00', 'en');
  final _dateFmt = DateFormat('MMM d, yyyy');
  final _monthFmt = DateFormat('MMM yyyy');

  // ── Filtered accessors ──
  bool _matchesMonth(_ArEntry e) {
    if (_selectedMonth == null) return true;
    return e.date.year == _selectedMonth!.year &&
        e.date.month == _selectedMonth!.month;
  }

  List<_ArEntry> get _filteredEntries {
    var list = _selectedMonth == null
        ? _arEntries
        : _arEntries.where(_matchesMonth).toList();

    switch (_statusFilter) {
      case 1:
        list = list.where((e) => e.shipmentState == 45).toList();
      case 2:
        list = list
            .where((e) =>
                e.shipmentState != 45 &&
                e.shipmentState != 60 &&
                e.shipmentState != 46 &&
                e.shipmentState != 0)
            .toList();
      case 3:
        list = list.where((e) => e.shipmentState == 0).toList();
      case 4:
        list = list.where((e) => e.isStale).toList();
    }
    return list;
  }

  double get _filteredTotalAr {
    if (_selectedMonth == null && _statusFilter == 0) return _totalAr;
    return roundMoney(
        _filteredEntries.fold(0.0, (s, e) => s + e.saleTotal));
  }

  _MonthAr? get _selectedMonthData {
    if (_selectedMonth == null) return null;
    try {
      return _monthHistory.firstWhere((m) =>
          m.month.year == _selectedMonth!.year &&
          m.month.month == _selectedMonth!.month);
    } catch (_) {
      return null;
    }
  }

  _MonthAr? get _previousMonthData {
    final target = _selectedMonth ?? DateTime.now();
    final prev = DateTime(target.year, target.month - 1);
    try {
      return _monthHistory
          .firstWhere((m) => m.month.year == prev.year && m.month.month == prev.month);
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

  DateTime _parseDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime(2020);
    return DateTime(2020);
  }

  // ── Sale total from raw Firestore data (same logic as balance sheet) ──
  static double _computeSaleTotal(Map<String, dynamic> data) {
    final items = data['items'] as List<dynamic>? ?? [];
    double subtotal = 0;
    for (final item in items) {
      if (item is Map) {
        subtotal += ((item['quantity'] as num?)?.toDouble() ?? 0) *
            ((item['unit_price'] as num?)?.toDouble() ?? 0);
      }
    }
    final tax = (data['tax_amount'] as num?)?.toDouble() ?? 0;
    final discount = (data['discount_amount'] as num?)?.toDouble() ?? 0;
    final shipping = (data['shipping_cost'] as num?)?.toDouble() ?? 0;
    return roundMoney(subtotal + tax - discount + shipping);
  }

  // ── Data Loading ──────────────────────────────────────────
  Future<void> _loadData() async {
    try {
      const uid = _cfUserId;

      // Get pre-computed AR from connection doc
      final conn = ref.read(bostaConnectionProvider).value;
      _precomputedAr = conn?.cfPendingAr ?? 0;
      final arCutoff = conn?.cfArCutoffDate;

      // Load shipments + COD sales in parallel
      final results = await Future.wait([
        _db
            .collection('bosta_shipments')
            .where('user_id', isEqualTo: uid)
            .get(),
        _db
            .collection('sales')
            .where('user_id', isEqualTo: uid)
            .where('payment_method', isEqualTo: 'Cash on Delivery (COD)')
            .get(),
      ]);

      final shipmentSnap = results[0];
      final salesSnap = results[1];

      // Build shipment lookup: saleId → best shipment data
      // For each sale, track: hasPaid, allRto, shipment state/tracking
      // Primary: saleId → shipment info
      final saleShipmentMap = <String, _ShipmentInfo>{};
      // Secondary: trackingNumber → shipment info (for unmatched shipments)
      final trackingShipmentMap = <String, _ShipmentInfo>{};

      for (final doc in shipmentSnap.docs) {
        final d = doc.data();
        final state = (d['state'] as num?)?.toInt() ?? 0;
        final stateValue = d['state_value'] as String? ?? '';
        final cashoutSt = d['cashout_status'] as String? ?? 'pending';
        final isPaid = cashoutSt == 'paid';
        final isRtoOrReturned = state == 60 || state == 46;
        final tracking = d['tracking_number']?.toString();

        final info = _ShipmentInfo(
          hasPaid: isPaid,
          allRto: isRtoOrReturned,
          state: state,
          stateValue: stateValue,
          cashoutStatus: cashoutSt,
          trackingNumber: tracking,
          rawData: d,
        );

        // Primary lookup: by sale_id
        final saleId = d['sale_id'] as String?;
        if (saleId != null) {
          final prev = saleShipmentMap[saleId];
          if (prev == null) {
            saleShipmentMap[saleId] = info;
          } else {
            // Merge: prefer non-RTO shipment for display
            saleShipmentMap[saleId] = _ShipmentInfo(
              hasPaid: prev.hasPaid || isPaid,
              allRto: prev.allRto && isRtoOrReturned,
              state: isRtoOrReturned ? prev.state : state,
              stateValue: isRtoOrReturned ? prev.stateValue : stateValue,
              cashoutStatus:
                  isPaid ? 'paid' : (prev.cashoutStatus == 'paid' ? 'paid' : cashoutSt),
              trackingNumber: tracking ?? prev.trackingNumber,
              rawData: isRtoOrReturned ? prev.rawData : d,
            );
          }
        }

        // Secondary lookup: by tracking_number
        if (tracking != null && tracking.isNotEmpty) {
          final prev = trackingShipmentMap[tracking];
          if (prev == null) {
            trackingShipmentMap[tracking] = info;
          } else {
            trackingShipmentMap[tracking] = _ShipmentInfo(
              hasPaid: prev.hasPaid || isPaid,
              allRto: prev.allRto && isRtoOrReturned,
              state: isRtoOrReturned ? prev.state : state,
              stateValue: isRtoOrReturned ? prev.stateValue : stateValue,
              cashoutStatus:
                  isPaid ? 'paid' : (prev.cashoutStatus == 'paid' ? 'paid' : cashoutSt),
              trackingNumber: tracking,
              rawData: isRtoOrReturned ? prev.rawData : d,
            );
          }
        }
      }

      // Process COD sales to find AR entries
      _arEntries.clear();
      _totalAr = 0;
      _deliveredAwaitingCount = 0;
      _deliveredAwaitingAmount = 0;
      _inTransitCount = 0;
      _inTransitAmount = 0;
      _noShipmentCount = 0;
      _noShipmentAmount = 0;
      _staleCount = 0;
      _staleAmount = 0;

      for (final doc in salesSnap.docs) {
        final d = doc.data();

        // Skip cancelled
        final orderStatus = (d['order_status'] as num?)?.toInt() ?? 0;
        if (orderStatus == 4) continue;

        // AR cutoff
        if (arCutoff != null) {
          final saleDate = _parseDate(d['date']);
          if (saleDate.isBefore(arCutoff)) continue;
        }

        final saleTotal = _computeSaleTotal(d);
        if (saleTotal <= 0) continue;

        // Check shipment status (primary: by sale_id, fallback: by tracking)
        var shipInfo = saleShipmentMap[doc.id];
        if (shipInfo == null) {
          final saleTracking = d['tracking_number']?.toString() ?? '';
          if (saleTracking.isNotEmpty) {
            shipInfo = trackingShipmentMap[saleTracking];
          }
        }
        if (shipInfo != null) {
          if (shipInfo.hasPaid) continue; // Already cashed out
          if (shipInfo.allRto) continue; // All shipments RTO
        }

        // This sale contributes to AR
        _totalAr += saleTotal;

        final customerName = d['customer_name'] as String?;
        final shopifyOrderNum = d['shopify_order_number']?.toString();
        final saleDate = _parseDate(d['date']);

        // Determine display label
        String label;
        if (shopifyOrderNum != null && shopifyOrderNum.isNotEmpty) {
          label = 'Order #$shopifyOrderNum';
          if (customerName != null && customerName.isNotEmpty) {
            label += ' · $customerName';
          }
        } else if (customerName != null && customerName.isNotEmpty) {
          label = customerName;
        } else {
          label = 'Sale ${doc.id.substring(0, 8)}';
        }

        // Determine shipment status
        String shipmentStatus;
        int shipmentState;
        if (shipInfo == null) {
          shipmentStatus = 'No Shipment';
          shipmentState = 0;
        } else if (shipInfo.state == 45) {
          shipmentStatus = 'Delivered · Pending';
          shipmentState = 45;
        } else if (shipInfo.state == 60 || shipInfo.state == 46) {
          shipmentStatus = 'RTO / Returned';
          shipmentState = shipInfo.state;
        } else {
          shipmentStatus = shipInfo.stateValue.isNotEmpty
              ? shipInfo.stateValue
              : 'In Transit';
          shipmentState = shipInfo.state;
        }

        // Bucket counts
        final daysAsAr = DateTime.now().difference(saleDate).inDays;
        final isStale = daysAsAr >= _staleDays;

        if (shipmentState == 45) {
          _deliveredAwaitingCount++;
          _deliveredAwaitingAmount += saleTotal;
        } else if (shipmentState == 0) {
          _noShipmentCount++;
          _noShipmentAmount += saleTotal;
        } else {
          _inTransitCount++;
          _inTransitAmount += saleTotal;
        }

        if (isStale) {
          _staleCount++;
          _staleAmount += saleTotal;
        }

        _arEntries.add(_ArEntry(
          saleId: doc.id,
          label: label,
          customerName: customerName,
          saleTotal: saleTotal,
          date: saleDate,
          shopifyOrderNumber: shopifyOrderNum,
          trackingNumber: shipInfo?.trackingNumber,
          shipmentStatus: shipmentStatus,
          cashoutStatus: shipInfo?.cashoutStatus ?? 'pending',
          shipmentState: shipmentState,
          daysAsAr: daysAsAr,
          isStale: isStale,
          rawSaleData: d,
          rawShipmentData: shipInfo?.rawData,
        ));
      }

      _totalAr = roundMoney(_totalAr);
      _arEntries.sort((a, b) => b.date.compareTo(a.date));

      // Build monthly history
      _buildMonthHistory();

      // Build available months
      final monthSet = <String, DateTime>{};
      for (final e in _arEntries) {
        final key = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
        monthSet.putIfAbsent(key, () => DateTime(e.date.year, e.date.month));
      }
      _availableMonths = monthSet.values.toList()
        ..sort((a, b) => b.compareTo(a));

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  void _buildMonthHistory() {
    _monthHistory.clear();
    final monthMap = <String, _MonthAr>{};

    for (final e in _arEntries) {
      final key =
          '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
      final m = monthMap.putIfAbsent(
          key, () => _MonthAr(month: DateTime(e.date.year, e.date.month)));
      m.totalAr += e.saleTotal;
      m.orderCount++;
      if (e.shipmentState == 45) {
        m.deliveredCount++;
      } else if (e.shipmentState == 0) {
        // no shipment — skip
      } else if (e.shipmentState == 60 || e.shipmentState == 46) {
        m.rtoCount++;
      } else {
        m.inTransitCount++;
      }
    }

    for (final m in monthMap.values) {
      m.totalAr = roundMoney(m.totalAr);
    }

    final sorted = monthMap.values.toList()
      ..sort((a, b) => b.month.compareTo(a.month));
    _monthHistory.addAll(sorted);
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
                        icon:
                            const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => context.safePop(),
                      ),
                      flexibleSpace: FlexibleSpaceBar(
                        background: _buildHeroHeader(),
                      ),
                      title: innerBoxIsScrolled
                          ? Text('EGP ${_fmt.format(_filteredTotalAr)}',
                              style: AppTypography.labelMedium.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700))
                          : null,
                      bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(46),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(20)),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            labelColor: AppColors.primaryNavy,
                            unselectedLabelColor: AppColors.textSecondary,
                            labelStyle: AppTypography.labelMedium
                                .copyWith(fontWeight: FontWeight.w700),
                            unselectedLabelStyle: AppTypography.labelMedium,
                            indicatorColor: AppColors.primaryNavy,
                            indicatorWeight: 2.5,
                            indicatorSize: TabBarIndicatorSize.label,
                            dividerColor: Colors.transparent,
                            tabs: const [
                              Tab(text: 'Overview'),
                              Tab(text: 'Sales'),
                              Tab(text: 'Shipments'),
                              Tab(text: 'History'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  body: Column(
                    children: [
                      _buildMonthFilterBar(),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildOverviewTab(),
                            _buildSalesTab(),
                            _buildShipmentsTab(),
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
          for (final m in _availableMonths) _monthChip(m, _monthFmt.format(m)),
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
              child: const Icon(Icons.error_outline_rounded,
                  size: 40, color: AppColors.chartRed),
            ),
            const SizedBox(height: 16),
            Text('Something went wrong',
                style: AppTypography.labelLarge),
            const SizedBox(height: 8),
            Text(_error,
                style: AppTypography.caption, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = '';
                });
                _loadData();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Hero Header ───────────────────────────────────────────
  Widget _buildHeroHeader() {
    final diff = _totalAr - _precomputedAr;
    final hasDiff = diff.abs() > 1;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFA78BFA)],
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
              Text('Accounts Receivable',
                  style: AppTypography.caption
                      .copyWith(color: Colors.white60, letterSpacing: 0.5)),
              const SizedBox(height: 2),
              Text('EGP ${_fmt.format(_totalAr)}',
                  style: AppTypography.metric.copyWith(color: Colors.white)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.chartOrange.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 14, color: AppColors.chartOrange),
                        const SizedBox(width: 4),
                        Text(
                          '${_arEntries.length} orders pending',
                          style: AppTypography.caption.copyWith(
                            color: const Color(0xFFFCD34D),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasDiff) ...[
                    const SizedBox(width: 8),
                    Text(
                        'sync: ${_fmt.format(_precomputedAr)}',
                        style: AppTypography.caption
                            .copyWith(color: Colors.white38, fontSize: 10)),
                  ],
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
        _buildKpiRow(),
        const SizedBox(height: 20),
        if (_selectedMonth != null) ...[
          _buildMonthComparisonCard(),
          const SizedBox(height: 16),
        ],
        _buildStatusBreakdownCard(),
        const SizedBox(height: 16),
        _buildWaterfallCard(),
        const SizedBox(height: 16),
        _buildInfoCard(),
      ].animate(interval: 40.ms).fadeIn(duration: 350.ms).slideY(begin: 0.03, end: 0),
    );
  }

  Widget _buildKpiRow() {
    final entries = _filteredEntries;
    final totalAr = _filteredTotalAr;
    final avgPerOrder = entries.isNotEmpty ? totalAr / entries.length : 0.0;
    return Row(
      children: [
        Expanded(
            child: _kpiCard(
          'Total AR',
          'EGP ${_fmt.format(totalAr)}',
          '${entries.length} orders',
          AppColors.chartPurple,
          Icons.request_quote_rounded,
        )),
        const SizedBox(width: 12),
        Expanded(
            child: _kpiCard(
          'Avg per Order',
          'EGP ${_fmt.format(avgPerOrder)}',
          'COD pending',
          AppColors.chartBlue,
          Icons.analytics_rounded,
        )),
      ],
    );
  }

  Widget _kpiCard(
      String title, String value, String sub, Color color, IconData icon) {
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
              style: AppTypography.caption
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: AppTypography.metricSmall.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(sub,
              style: AppTypography.caption
                  .copyWith(color: AppColors.textTertiary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildStatusBreakdownCard() {
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
                child: const Icon(Icons.pie_chart_rounded,
                    size: 16, color: AppColors.chartPurple),
              ),
              const SizedBox(width: 10),
              Text('By Shipment Status',
                  style: AppTypography.labelMedium
                      .copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 18),
          _statusRow(
              'Delivered · Awaiting Cashout',
              _deliveredAwaitingAmount,
              _deliveredAwaitingCount,
              AppColors.chartGreen,
              Icons.check_circle_rounded),
          const SizedBox(height: 12),
          _statusRow('In Transit', _inTransitAmount, _inTransitCount,
              AppColors.chartBlue, Icons.local_shipping_rounded),
          const SizedBox(height: 12),
          _statusRow('No Shipment Yet', _noShipmentAmount, _noShipmentCount,
              AppColors.chartOrange, Icons.hourglass_empty_rounded),
          const SizedBox(height: 12),
          _statusRow('Stale (>$_staleDays days)', _staleAmount, _staleCount,
              const Color(0xFFEF4444), Icons.warning_amber_rounded),
        ],
      ),
    );
  }

  Widget _statusRow(
      String label, double amount, int count, Color color, IconData icon) {
    final pct = _totalAr > 0 ? amount / _totalAr : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 14, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: AppTypography.bodyMedium
                          .copyWith(fontWeight: FontWeight.w500)),
                  Text('$count orders',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary, fontSize: 11)),
                ],
              ),
            ),
            Text('EGP ${_fmt.format(amount)}',
                style: AppTypography.bodyMedium
                    .copyWith(fontWeight: FontWeight.w700, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 4,
            backgroundColor: const Color(0xFFF1F5F9),
            valueColor:
                AlwaysStoppedAnimation(color.withValues(alpha: 0.6)),
          ),
        ),
      ],
    );
  }

  Widget _buildWaterfallCard() {
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
                child: const Icon(Icons.waterfall_chart_rounded,
                    size: 16, color: AppColors.chartBlue),
              ),
              const SizedBox(width: 10),
              Text('AR Composition',
                  style: AppTypography.labelMedium
                      .copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 18),
          _waterfallItem('Delivered Awaiting', _deliveredAwaitingAmount,
              AppColors.chartGreen,
              count: _deliveredAwaitingCount, isFirst: true),
          _waterfallConnector(),
          _waterfallItem(
              'In Transit', _inTransitAmount, AppColors.chartBlue,
              count: _inTransitCount),
          _waterfallConnector(),
          _waterfallItem(
              'No Shipment', _noShipmentAmount, AppColors.chartOrange,
              count: _noShipmentCount),
          _waterfallConnector(),
          _waterfallItem(
              'Stale >$_staleDays d', _staleAmount, const Color(0xFFEF4444),
              count: _staleCount),
          const SizedBox(height: 4),
          Container(width: double.infinity, height: 1, color: AppColors.borderLight),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.chartPurple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.request_quote_rounded,
                    size: 16, color: AppColors.chartPurple),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Total AR',
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w700)),
              ),
              Text('EGP ${_fmt.format(_totalAr)}',
                  style: AppTypography.metricSmall
                      .copyWith(color: AppColors.chartPurple)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _waterfallItem(String label, double amount, Color color,
      {int? count, bool isFirst = false}) {
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
              isFirst ? Icons.flag_rounded : Icons.add_rounded,
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w500)),
                if (count != null)
                  Text('$count orders',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          Text(
            'EGP ${_fmt.format(amount)}',
            style: AppTypography.bodyMedium
                .copyWith(fontWeight: FontWeight.w700, color: color),
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

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.chartPurpleLight,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.chartPurple.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.chartPurple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.info_outline_rounded,
                size: 16, color: AppColors.chartPurple),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How AR is Calculated',
                    style: AppTypography.labelMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.chartPurple)),
                const SizedBox(height: 4),
                Text(
                  'AR = total of COD (Cash on Delivery) orders that have not '
                  'yet been cashed out by Bosta. Once a shipment is marked as '
                  '"paid" in a Bosta cashout cycle, it is removed from AR.',
                  style: AppTypography.caption
                      .copyWith(height: 1.4, color: AppColors.textSecondary),
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

    final curLabel = _monthFmt.format(current.month);
    final prevLabel = prev != null ? _monthFmt.format(prev.month) : 'N/A';

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
                child: const Icon(Icons.compare_arrows_rounded,
                    size: 16, color: AppColors.chartBlue),
              ),
              const SizedBox(width: 10),
              Text('Month Comparison',
                  style: AppTypography.labelMedium
                      .copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: _comparisonColumn(curLabel, current, true)),
              Container(width: 1, height: 80, color: AppColors.borderLight),
              Expanded(
                  child: _comparisonColumn(prevLabel, prev, false)),
            ],
          ),
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
                  _deltaRow('New AR', current.totalAr, prev.totalAr),
                  const SizedBox(height: 6),
                  _deltaRow('Orders', current.orderCount.toDouble(),
                      prev.orderCount.toDouble()),
                  const SizedBox(height: 6),
                  _deltaRow('Delivered', current.deliveredCount.toDouble(),
                      prev.deliveredCount.toDouble()),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _comparisonColumn(String label, _MonthAr? data, bool isCurrent) {
    return Padding(
      padding: EdgeInsets.only(
          left: isCurrent ? 0 : 14, right: isCurrent ? 14 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isCurrent)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                      color: AppColors.primaryNavy, shape: BoxShape.circle),
                ),
              Text(label,
                  style: AppTypography.caption.copyWith(
                    color: isCurrent
                        ? AppColors.primaryNavy
                        : AppColors.textTertiary,
                    fontWeight:
                        isCurrent ? FontWeight.w700 : FontWeight.w500,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          if (data != null) ...[
            Text(_fmt.format(data.totalAr),
                style: AppTypography.metricSmall
                    .copyWith(color: AppColors.chartPurple)),
            const SizedBox(height: 2),
            Text('total AR',
                style: AppTypography.caption
                    .copyWith(color: AppColors.textTertiary, fontSize: 10)),
            const SizedBox(height: 8),
            Text('${data.orderCount} orders · ${data.deliveredCount} delivered',
                style: AppTypography.caption
                    .copyWith(color: AppColors.textSecondary, fontSize: 10)),
          ] else
            Text('No data',
                style: AppTypography.caption
                    .copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }

  Widget _deltaRow(String label, double current, double previous) {
    final diff = current - previous;
    final pctChange =
        previous != 0 ? (diff / previous.abs()) * 100 : 0.0;
    final isUp = diff >= 0;

    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: AppTypography.caption
                  .copyWith(color: AppColors.textSecondary, fontSize: 11)),
        ),
        Text(
          '${isUp ? '+' : ''}${_fmt.format(diff)}',
          style: AppTypography.caption.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isUp ? AppColors.chartRed : AppColors.chartGreen,
          ),
        ),
        if (previous != 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: (isUp ? AppColors.chartRed : AppColors.chartGreen)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${isUp ? '+' : ''}${pctChange.toStringAsFixed(0)}%',
              style: AppTypography.caption.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: isUp ? AppColors.chartRed : AppColors.chartGreen,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  // TAB 2: Sales (AR orders)
  // ══════════════════════════════════════════════════════════
  Widget _buildSalesTab() {
    final entries = _filteredEntries;

    return Column(
      children: [
        // ── Filter bar ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _statusChip('All', _statusFilter == 0,
                          () => setState(() => _statusFilter = 0)),
                      const SizedBox(width: 6),
                      _statusChip('Delivered', _statusFilter == 1,
                          () => setState(() => _statusFilter = 1),
                          color: AppColors.chartGreen),
                      const SizedBox(width: 6),
                      _statusChip('In Transit', _statusFilter == 2,
                          () => setState(() => _statusFilter = 2),
                          color: AppColors.chartBlue),
                      const SizedBox(width: 6),
                      _statusChip('No Shipment', _statusFilter == 3,
                          () => setState(() => _statusFilter = 3),
                          color: AppColors.chartOrange),
                      const SizedBox(width: 6),
                      _statusChip('Stale >$_staleDays d', _statusFilter == 4,
                          () => setState(() => _statusFilter = 4),
                          color: const Color(0xFFEF4444)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              Text('${entries.length} orders · EGP ${_fmt.format(_filteredTotalAr)}',
                  style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_statusFilter != 0)
                GestureDetector(
                  onTap: () => setState(() => _statusFilter = 0),
                  child: Text('Clear',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.chartBlue,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        if (entries.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.filter_list_off_rounded,
                      size: 40, color: AppColors.textTertiary),
                  const SizedBox(height: 10),
                  Text('No orders match filters',
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: entries.length,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                return _buildSaleTile(entries[index]);
              },
            ),
          ),
      ],
    );
  }

  Widget _statusChip(String label, bool selected, VoidCallback onTap,
      {Color? color}) {
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
              ? Border.all(
                  color:
                      (color ?? AppColors.primaryNavy).withValues(alpha: 0.3))
              : null,
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: selected
                ? (color ?? AppColors.primaryNavy)
                : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSaleTile(_ArEntry entry) {
    Color statusColor;
    IconData statusIcon;
    if (entry.shipmentState == 45) {
      statusColor = AppColors.chartGreen;
      statusIcon = Icons.check_circle_rounded;
    } else if (entry.shipmentState == 0) {
      statusColor = AppColors.chartOrange;
      statusIcon = Icons.hourglass_empty_rounded;
    } else {
      statusColor = AppColors.chartBlue;
      statusIcon = Icons.local_shipping_rounded;
    }

    return GestureDetector(
      onTap: () => _showArDetail(entry),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(statusIcon, size: 17, color: statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w500),
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
                      const SizedBox(width: 6),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            entry.shipmentStatus,
                            style: AppTypography.caption.copyWith(
                                fontSize: 8,
                                color: statusColor,
                                fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (entry.isStale) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            '${entry.daysAsAr}d',
                            style: AppTypography.caption.copyWith(
                                fontSize: 8,
                                color: const Color(0xFFEF4444),
                                fontWeight: FontWeight.w700),
                          ),
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
                Text(
                  'EGP ${_fmt.format(entry.saleTotal)}',
                  style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.chartPurple),
                ),
                const SizedBox(height: 2),
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.textTertiary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Detail Bottom Sheet ──────────────────────────────────
  void _showArDetail(_ArEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.85,
          expand: false,
          builder: (_, scrollController) {
            Color statusColor;
            if (entry.shipmentState == 45) {
              statusColor = AppColors.chartGreen;
            } else if (entry.shipmentState == 0) {
              statusColor = AppColors.chartOrange;
            } else {
              statusColor = AppColors.chartBlue;
            }

            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
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
                          color:
                              AppColors.chartPurple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.request_quote_rounded,
                            size: 22, color: AppColors.chartPurple),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.label,
                                style: AppTypography.labelLarge
                                    .copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(_dateFmt.format(entry.date),
                                style: AppTypography.caption.copyWith(
                                    color: AppColors.textSecondary)),
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
                          'EGP ${_fmt.format(entry.saleTotal)}',
                          style: AppTypography.metric.copyWith(
                            color: AppColors.chartPurple,
                            fontSize: 28,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pending Collection',
                          style: AppTypography.caption
                              .copyWith(color: AppColors.textSecondary),
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
                      _detailBadge(
                          entry.shipmentStatus, statusColor),
                      _detailBadge('COD', AppColors.primaryNavy),
                      _detailBadge(
                          'Cashout: ${entry.cashoutStatus}',
                          entry.cashoutStatus == 'paid'
                              ? AppColors.chartGreen
                              : AppColors.chartOrange),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Detail rows
                  _detailRow('Sale ID', entry.saleId),
                  if (entry.shopifyOrderNumber != null)
                    _detailRow(
                        'Shopify Order', '#${entry.shopifyOrderNumber}'),
                  if (entry.customerName != null)
                    _detailRow('Customer', entry.customerName!),
                  _detailRow('Order Total',
                      'EGP ${_fmt.format(entry.saleTotal)}'),
                  _detailRow('Date',
                      DateFormat('EEEE, MMM d, yyyy').format(entry.date)),
                  if (entry.trackingNumber != null)
                    _detailRow('Tracking #', entry.trackingNumber!),
                  _detailRow('Shipment Status', entry.shipmentStatus),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _navigateToSale(entry);
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('View Sale Details'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryNavy,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  if (entry.rawShipmentData != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _navigateToShipment(entry);
                        },
                        icon: const Icon(Icons.local_shipping_rounded,
                            size: 16),
                        label: const Text('View Shipment Details'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primaryNavy,
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          side: BorderSide(
                              color: AppColors.primaryNavy
                                  .withValues(alpha: 0.3)),
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
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: AppTypography.bodySmall
                    .copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  void _navigateToSale(_ArEntry entry) {
    final sale = Sale.fromJson({...entry.rawSaleData, 'id': entry.saleId});
    context.push('/sales/detail', extra: {'sale': sale});
  }

  void _navigateToShipment(_ArEntry entry) {
    if (entry.rawShipmentData == null) return;
    final data = entry.rawShipmentData!;
    final shipment = BostaShipment(
      bostaDeliveryId: data['bosta_delivery_id']?.toString() ??
          data['_id']?.toString() ??
          '',
      userId: _cfUserId,
      trackingNumber: data['tracking_number']?.toString() ?? '',
      businessReference: data['business_reference']?.toString(),
      saleId: data['sale_id']?.toString(),
      state: (data['state'] as num?)?.toInt() ?? 0,
      stateValue: data['state_value']?.toString() ?? '',
      type: data['type']?.toString() ?? '',
      cod: (data['cod'] as num?)?.toDouble(),
      cashoutStatus: data['cashout_status']?.toString(),
      cashoutId: data['cashout_id']?.toString(),
      matched: data['matched'] as bool? ?? false,
    );
    context.push(AppRoutes.bostaShipmentDetail,
        extra: {'shipment': shipment});
  }

  // ══════════════════════════════════════════════════════════
  // TAB 3: Shipments
  // ══════════════════════════════════════════════════════════
  Widget _buildShipmentsTab() {
    final allShipments = _filteredEntries
        .where((e) => e.rawShipmentData != null)
        .toList();

    final delivered =
        allShipments.where((e) => e.shipmentState == 45).toList();
    final inTransit = allShipments
        .where((e) =>
            e.shipmentState != 45 &&
            e.shipmentState != 60 &&
            e.shipmentState != 46)
        .toList();

    // Apply filter
    List<_ArEntry> entries;
    switch (_shipmentFilter) {
      case 1:
        entries = delivered;
      case 2:
        entries = inTransit;
      default:
        entries = allShipments;
    }

    return Column(
      children: [
        // ── Filter bar ──
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 30,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _statusChip('All', _shipmentFilter == 0,
                          () => setState(() => _shipmentFilter = 0)),
                      const SizedBox(width: 6),
                      _statusChip('Delivered', _shipmentFilter == 1,
                          () => setState(() => _shipmentFilter = 1),
                          color: AppColors.chartGreen),
                      const SizedBox(width: 6),
                      _statusChip('In Transit', _shipmentFilter == 2,
                          () => setState(() => _shipmentFilter = 2),
                          color: AppColors.chartBlue),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              Text('${entries.length} shipments',
                  style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              if (_shipmentFilter != 0)
                GestureDetector(
                  onTap: () => setState(() => _shipmentFilter = 0),
                  child: Text('Clear',
                      style: AppTypography.caption.copyWith(
                          color: AppColors.chartBlue,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        if (entries.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_shipping_outlined,
                      size: 48, color: AppColors.textTertiary),
                  const SizedBox(height: 12),
                  Text('No shipments match filters',
                      style: AppTypography.bodyMedium
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
              children: [
                // Summary hero
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.chartBlue.withValues(alpha: 0.25),
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
                        child: const Icon(Icons.local_shipping_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Active Shipments',
                                style: AppTypography.caption
                                    .copyWith(color: Colors.white60)),
                            Text('${allShipments.length} shipments',
                                style: AppTypography.metric.copyWith(
                                    color: Colors.white, fontSize: 24)),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 12, color: Colors.white54),
                              const SizedBox(width: 4),
                              Text('${delivered.length}',
                                  style: AppTypography.caption
                                      .copyWith(color: Colors.white70)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.local_shipping_rounded,
                                  size: 12, color: Colors.white54),
                              const SizedBox(width: 4),
                              Text('${inTransit.length}',
                                  style: AppTypography.caption
                                      .copyWith(color: Colors.white70)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                for (final e in entries) ...[
                  _buildShipmentTile(e),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildShipmentTile(_ArEntry entry) {
    Color statusColor;
    if (entry.shipmentState == 45) {
      statusColor = AppColors.chartGreen;
    } else {
      statusColor = AppColors.chartBlue;
    }

    return GestureDetector(
      onTap: () => _showArDetail(entry),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.local_shipping_rounded,
                  size: 17, color: statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.trackingNumber ?? entry.label,
                    style: AppTypography.bodyMedium
                        .copyWith(fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    entry.shipmentStatus,
                    style: AppTypography.caption.copyWith(
                        color: AppColors.textTertiary, fontSize: 11),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('EGP ${_fmt.format(entry.saleTotal)}',
                    style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.chartPurple)),
                const SizedBox(height: 2),
                Icon(Icons.chevron_right_rounded,
                    size: 16, color: AppColors.textTertiary),
              ],
            ),
          ],
        ),
      ),
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
            Icon(Icons.timeline_rounded,
                size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text('No history data',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
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
                    color: AppColors.chartPurpleLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.timeline_rounded,
                      size: 16, color: AppColors.chartPurple),
                ),
                const SizedBox(width: 10),
                Text('Monthly AR by Order Date',
                    style: AppTypography.labelMedium
                        .copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          );
        }

        final m = _monthHistory[index - 1];
        return _buildMonthCard(m, isFirst: index == 1);
      },
    );
  }

  Widget _buildMonthCard(_MonthAr m, {bool isFirst = false}) {
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
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isFirst
                          ? AppColors.chartPurple
                          : AppColors.chartBlue,
                      shape: BoxShape.circle,
                      border: isFirst
                          ? Border.all(
                              color: AppColors.chartPurple
                                  .withValues(alpha: 0.3),
                              width: 3)
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
                            style: AppTypography.labelMedium
                                .copyWith(fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.chartPurpleLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'EGP ${_fmt.format(m.totalAr)}',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.chartPurple,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _miniMetric(
                            'Orders', m.orderCount.toDouble(), AppColors.textSecondary),
                        _miniMetric('Delivered', m.deliveredCount.toDouble(),
                            AppColors.chartGreen),
                        _miniMetric('In Transit', m.inTransitCount.toDouble(),
                            AppColors.chartBlue),
                        _miniMetric(
                            'AR Amount', m.totalAr, AppColors.chartPurple,
                            isBold: true),
                      ],
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

  Widget _miniMetric(String label, double value, Color color,
      {bool isBold = false}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTypography.caption.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 9.5,
                  letterSpacing: 0.2)),
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

/// Internal helper for tracking shipment info per sale.
class _ShipmentInfo {
  final bool hasPaid;
  final bool allRto;
  final int state;
  final String stateValue;
  final String cashoutStatus;
  final String? trackingNumber;
  final Map<String, dynamic> rawData;

  const _ShipmentInfo({
    required this.hasPaid,
    required this.allRto,
    required this.state,
    required this.stateValue,
    required this.cashoutStatus,
    this.trackingNumber,
    required this.rawData,
  });
}
