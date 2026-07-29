import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import '../../core/navigation/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/bosta_connection_provider.dart';
import '../../core/services/bosta_api_service.dart';
import '../../core/services/share_service.dart';
import '../../core/providers/export_providers.dart';
import '../../core/providers/repository_providers.dart';
import '../../shared/models/bosta_connection_model.dart';
import '../../shared/models/production_order_model.dart';
import '../../shared/models/sale_model.dart';
import '../../shared/models/fixed_asset_model.dart';
import '../../shared/models/loan_model.dart';
import '../../shared/models/salary_model.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/purchase_model.dart';
import '../../shared/utils/money_utils.dart';
import '../../shared/utils/report_constants.dart';
import '../../shared/utils/equity_recon.dart';
import '../../shared/utils/cf_engine.dart';
import '../../shared/utils/books_cutover.dart';
import '../../shared/utils/supplier_position.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/report_card.dart';
import 'widgets/chart_toggle.dart';
import 'widgets/financial_period_sheet.dart';

/// User ID for which CF-driven balance sheet is enabled.
const _cfUserId = 'EGYQnP7ughdUtTbn04UwUET534i1';

class _BSData {
  final double bankBalance;
  final double inventoryValue;
  final double suppliersOwing;
  final double supplierAdvancePayments;
  final double accountsReceivable;
  final double gatewayReceivables;
  final double fixedAssetsNetValue;
  final double loansOutstanding;
  final double unpaidSalaries;
  final double accruedExpenses;
  final double retainedEarnings;
  final double currentPeriodNetIncome;
  final double depreciationExpense;
  final double ownerContributions;
  final double ownerWithdrawals;
  final double salaryPaymentsTotal;
  final double totalAssets;
  final double totalLiabilities;
  final double netEquity;
  final bool hasManualCapital;
  final double effectiveCapital;
  final double openingRetainedEarnings;
  final double unexplainedDifference;

  const _BSData({
    required this.bankBalance,
    required this.inventoryValue,
    required this.suppliersOwing,
    required this.supplierAdvancePayments,
    required this.accountsReceivable,
    this.gatewayReceivables = 0,
    required this.fixedAssetsNetValue,
    required this.loansOutstanding,
    required this.unpaidSalaries,
    this.accruedExpenses = 0,
    required this.retainedEarnings,
    required this.currentPeriodNetIncome,
    this.depreciationExpense = 0,
    this.ownerContributions = 0,
    this.ownerWithdrawals = 0,
    this.salaryPaymentsTotal = 0,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.netEquity,
    required this.hasManualCapital,
    required this.effectiveCapital,
    this.openingRetainedEarnings = 0,
    required this.unexplainedDifference,
  });
}

class BalanceSheetScreen extends ConsumerStatefulWidget {
  const BalanceSheetScreen({super.key});

  @override
  ConsumerState<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends ConsumerState<BalanceSheetScreen>
    with AutomaticKeepAliveClientMixin {
  bool _showTrend = false;
  bool _sharing = false;
  FinancialPeriodResult _period = FinancialPeriodResult(
    type: FinancialPeriodType.monthEnd,
    range: DateTimeRange(
      start: DateTime(DateTime.now().year, DateTime.now().month, 1),
      end: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59),
    ),
    label: DateFormat('MMMM yyyy').format(DateTime.now()),
  );

  // Cached balance sheet computation
  _BSData? _cachedData;
  Object? _lastDataKey;

  // Local data fetched via direct repo queries (no loadAll on shared provider)
  List<Transaction> _transactions = [];
  List<Sale> _sales = [];
  // True only until the very first fetch completes. After that, we keep the
  // previous period's data on-screen while a new period is fetching, so
  // re-opening the screen or switching periods feels instant.
  bool _isFirstLoad = true;
  bool _isRefreshing = false;

  // ── CF User state ────────────────────────────────────────
  bool _isCfUser = false;
  bool _cfSyncing = false;
  final bool _sanityCheckDismissed = false;
  int _rtoCount = 0;
  /// Live-computed pending AR for current period (null = not yet loaded).
  double? _liveAr;
  /// Historical cashout total when asOf < today, null means use pre-computed.
  double? _historicalCashoutTotal;
  /// Historical pending AR when asOf < today.
  double? _historicalPendingAr;

  @override
  bool get wantKeepAlive => true;

  /// Compute sale total from raw Firestore data (mirrors Sale.total getter).
  /// total = Σ(item.quantity * item.unit_price) + tax - discount + shipping
  static double _computeSaleTotalFromFirestore(Map<String, dynamic> data) {
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

  Future<void> _openDatePicker() async {
    final result = await showFinancialPeriodSheet(context, current: _period);
    if (result == null) return;
    setState(() => _period = result);
    _loadData();
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      // Inventory & purchases still use their own providers (no bounds issue).
      ref.read(inventoryProvider.notifier).loadAll();
      // Detect CF user early so _loadData can use it.
      final userId = ref.read(authProvider).user?.id;
      if (userId == _cfUserId) {
        _isCfUser = true;
      }
      // Load all data (txns, sales, live AR, cashout sync) in parallel.
      // _loadData awaits live AR before revealing content.
      _loadData();
    });
  }

  Future<void> _loadData({bool forceServer = false}) async {
    // Only show the full-screen spinner on the very first load. On period
    // changes / refreshes we keep the previous data rendered and just mark
    // "refreshing" so the header can optionally show a small indicator.
    if (mounted) {
      setState(() {
        _isRefreshing = true;
      });
    }
    try {
      final txnRepo = ref.read(transactionRepositoryProvider);
      final saleRepo = ref.read(saleRepositoryProvider);
      final asOf = _period.range.end;

      // Kick off ALL independent network work in parallel — including the
      // CF-user-specific queries. Previously the CF queries waited for
      // txn/sale fetch to finish, doubling the perceived load time.
      final futures = <Future<dynamic>>[
        txnRepo.getTransactionsInRange(
            start: DateTime(2000), end: asOf, forceServer: forceServer),
        saleRepo.getSalesInRange(
            start: DateTime(2000), end: asOf, forceServer: forceServer),
      ];
      if (_isCfUser) {
        futures.add(_loadHistoricalCashouts());
        futures.add(_triggerCashoutSync());
      }
      final results = await Future.wait(futures);

      if (mounted) {
        _transactions = (results[0].data as List<Transaction>?) ?? [];
        _sales = (results[1].data as List<Sale>?) ?? [];
      }
    } catch (_) {
      // Fall through — show whatever we have.
    }

    if (mounted) {
      setState(() {
        _isFirstLoad = false;
        _isRefreshing = false;
      });
    }
  }

  /// Triggers an on-demand cashout sync (Phase 4.6).
  /// Fires and forgets — updates come via bostaConnectionProvider refresh.
  Future<void> _triggerCashoutSync() async {
    if (!_isCfUser || _cfSyncing) return;
    setState(() => _cfSyncing = true);
    try {
      final api = BostaApiService();
      await api.syncCashouts();
      // Refresh the connection provider to pick up updated summary.
      if (mounted) {
        ref.invalidate(bostaConnectionProvider);
      }
    } catch (_) {
      // Sync failure is non-fatal — use cached data.
    }
    if (mounted) setState(() => _cfSyncing = false);
  }

  /// For historical periods, query bosta_cashouts directly.
  Future<void> _loadHistoricalCashouts() async {
    final asOf = _period.range.end;
    final now = DateTime.now();
    final isCurrentPeriod = asOf.year == now.year &&
        asOf.month == now.month &&
        asOf.day == now.day;

    // Books-start cutover key, read directly from Firestore so it's available
    // regardless of provider load timing. When set, the all-time cloud
    // aggregate (cfTotalCashouts) is wrong because it counts pre-tracking
    // cashouts — we must compute the cashout total from the collection within
    // the window instead.
    String? booksStart;
    try {
      final bsDoc = await FirebaseFirestore.instance
          .collection('balance_sheet')
          .doc(_cfUserId)
          .get();
      final raw = bsDoc.data()?['books_start_date'] as String?;
      if (raw != null && raw.isNotEmpty) booksStart = raw.substring(0, 10);
    } catch (_) {}

    if (isCurrentPeriod) {
      // Compute live AR + count RTO shipments.
      try {
        // Run both Firestore queries in parallel for speed.
        final results = await Future.wait([
          FirebaseFirestore.instance
              .collection('bosta_shipments')
              .where('user_id', isEqualTo: _cfUserId)
              .get(),
          FirebaseFirestore.instance
              .collection('sales')
              .where('user_id', isEqualTo: _cfUserId)
              .where('payment_method', isEqualTo: 'Cash on Delivery (COD)')
              .get(),
        ]);
        final shipmentsSnap = results[0];
        final codSalesSnap = results[1];

        // Build shipment lookup: saleId → { hasPaid, allRto }
        // Also collect RTO shipments that need re-ship checking.
        // Secondary: trackingNumber → { hasPaid, allRto } for unmatched.
        final saleShipmentMap =
            <String, ({bool hasPaid, bool allRto, int state})>{};
        final trackingShipmentMap =
            <String, ({bool hasPaid, bool allRto, int state})>{};
        final rtoCheckEntries = <({String saleId, String bostaTracking})>[];

        for (final doc in shipmentsSnap.docs) {
          final data = doc.data();
          final saleId = data['sale_id'] as String?;
          final state = (data['state'] as num?)?.toInt() ?? 0;
          final isRtoOrReturned = state == 60 || state == 46;
          final isPaid = data['cashout_status'] == 'paid';
          final tracking = data['tracking_number']?.toString() ?? '';

          // Collect RTOs for batch re-ship check
          if (isRtoOrReturned && data['matched'] == true && saleId != null) {
            if (tracking.isNotEmpty) {
              rtoCheckEntries.add((saleId: saleId, bostaTracking: tracking));
            }
          }

          // Primary lookup: by sale_id
          if (saleId != null) {
            final prev = saleShipmentMap[saleId];
            saleShipmentMap[saleId] = (
              hasPaid: (prev?.hasPaid ?? false) || isPaid,
              allRto: (prev?.allRto ?? true) && isRtoOrReturned,
              // Prefer the non-RTO shipment's state for display/bucketing.
              state: isRtoOrReturned ? (prev?.state ?? state) : state,
            );
          }

          // Secondary lookup: by tracking_number
          if (tracking.isNotEmpty) {
            final prev = trackingShipmentMap[tracking];
            trackingShipmentMap[tracking] = (
              hasPaid: (prev?.hasPaid ?? false) || isPaid,
              allRto: (prev?.allRto ?? true) && isRtoOrReturned,
              state: isRtoOrReturned ? (prev?.state ?? state) : state,
            );
          }
        }

        // Batch re-ship check: use the COD sales we already fetched to
        // compare tracking numbers (avoids N individual reads).
        final codSaleMap = <String, String>{};
        for (final doc in codSalesSnap.docs) {
          final tracking = doc.data()['tracking_number']?.toString() ?? '';
          if (tracking.isNotEmpty) codSaleMap[doc.id] = tracking;
        }
        int rtoCount = 0;
        for (final entry in rtoCheckEntries) {
          final saleTracking = codSaleMap[entry.saleId] ?? '';
          final isReshipped =
              saleTracking.isNotEmpty && saleTracking != entry.bostaTracking;
          if (!isReshipped) rtoCount++;
        }

        // Compute live AR from COD sales. New model: delivered-not-cashed-out
        // orders are valued via the Bosta wallet balance (net, authoritative);
        // in-transit / not-shipped by their gross COD. Falls back to gross-COD
        // for everything when no wallet balance is available yet.
        final conn = ref.read(bostaConnectionProvider).value;
        final arCutoff = conn?.cfArCutoffDate;
        final walletBalance = conn?.cfWalletBalance;
        final hasWallet = walletBalance != null;
        double pendingAr = 0;

        for (final saleDoc in codSalesSnap.docs) {
          final saleData = saleDoc.data();
          final orderStatus = (saleData['order_status'] as num?)?.toInt() ?? 0;
          if (orderStatus == 4) continue;

          if (arCutoff != null) {
            final saleDateTs = saleData['date'];
            DateTime? saleDate;
            if (saleDateTs is Timestamp) {
              saleDate = saleDateTs.toDate();
            } else if (saleDateTs is String) {
              saleDate = DateTime.tryParse(saleDateTs);
            }
            if (saleDate != null && saleDate.isBefore(arCutoff)) continue;
          }

          final saleTotal = _computeSaleTotalFromFirestore(saleData);
          if (saleTotal <= 0) continue;

          // Primary: by sale_id. Fallback: by tracking_number.
          var shipInfo = saleShipmentMap[saleDoc.id];
          if (shipInfo == null) {
            final saleTracking = saleData['tracking_number']?.toString() ?? '';
            if (saleTracking.isNotEmpty) {
              shipInfo = trackingShipmentMap[saleTracking];
            }
          }
          if (shipInfo != null) {
            if (shipInfo.hasPaid) continue;
            if (shipInfo.allRto) continue;
            // Delivered, not cashed out → covered by the wallet balance below.
            if (hasWallet && shipInfo.state == 45) continue;
          }

          pendingAr += saleTotal;
        }

        // For cutover users, compute the cashout total from the collection
        // within [booksStart, asOf] so the current-period view doesn't fall
        // back to the uncutover'd cloud aggregate. Null = no cutover (keep the
        // existing cfTotalCashouts fast-path).
        double? cutoverCashoutTotal;
        if (booksStart != null) {
          final coSnap = await FirebaseFirestore.instance
              .collection('bosta_cashouts')
              .where('user_id', isEqualTo: _cfUserId)
              .get();
          final asOfStr = asOf.toIso8601String().substring(0, 10);
          double t = 0;
          for (final doc in coSnap.docs) {
            final dateStr = doc.data()['transaction_date'] as String? ?? '';
            if (cashoutOnOrBeforeAsOf(dateStr, asOfStr) &&
                cashoutOnOrAfterStart(dateStr, booksStart)) {
              t += (doc.data()['amount'] as num?)?.toDouble() ?? 0;
            }
          }
          cutoverCashoutTotal = roundMoney(t);
        }

        if (mounted) {
          setState(() {
            _historicalCashoutTotal = cutoverCashoutTotal;
            _historicalPendingAr = null;
            _liveAr = hasWallet
                ? roundMoney(pendingAr + walletBalance)
                : roundMoney(pendingAr);
            _rtoCount = rtoCount;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _historicalCashoutTotal = null;
            _historicalPendingAr = null;
            _liveAr = null;
          });
        }
      }
      return;
    }

    // Historical: query all bosta data in parallel to avoid sequential reads.
    final asOfStr = asOf.toIso8601String().substring(0, 10);
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection('bosta_cashouts')
            .where('user_id', isEqualTo: _cfUserId)
            .get(),
        FirebaseFirestore.instance
            .collection('bosta_shipments')
            .where('user_id', isEqualTo: _cfUserId)
            .get(),
        FirebaseFirestore.instance
            .collection('sales')
            .where('user_id', isEqualTo: _cfUserId)
            .where('payment_method', isEqualTo: 'Cash on Delivery (COD)')
            .get(),
      ]);
      final cashoutsSnap = results[0];
      final shipmentsSnap = results[1];
      final codSalesSnap = results[2];

      // Build cashout map: id → transactionDate, and compute total within the
      // books window [booksStartDate, asOf]. Pre-cutover cashouts are excluded
      // (their net sits in the opening cash balance).
      final cashoutStartKey = booksStart;
      final cashoutDateMap = <String, String>{};
      double total = 0;
      for (final doc in cashoutsSnap.docs) {
        final data = doc.data();
        final dateStr = data['transaction_date'] as String? ?? '';
        cashoutDateMap[doc.id] = dateStr;
        if (cashoutOnOrBeforeAsOf(dateStr, asOfStr) &&
            cashoutOnOrAfterStart(dateStr, cashoutStartKey)) {
          total += (data['amount'] as num?)?.toDouble() ?? 0;
        }
      }

      // Build sale tracking map from COD sales for re-ship detection.
      final codSaleMap = <String, String>{};
      for (final doc in codSalesSnap.docs) {
        final tracking = doc.data()['tracking_number']?.toString() ?? '';
        if (tracking.isNotEmpty) codSaleMap[doc.id] = tracking;
      }

      // Process shipments (no individual reads needed).
      int rtoCount = 0;
      final saleShipmentMap = <String, ({bool hasPaid, bool allRto})>{};
      final rtoCheckEntries = <({String saleId, String bostaTracking})>[];

      for (final doc in shipmentsSnap.docs) {
        final data = doc.data();
        final saleId = data['sale_id'] as String?;
        if (saleId == null) continue;

        final state = (data['state'] as num?)?.toInt() ?? 0;
        final isRtoOrReturned = state == 60 || state == 46;

        if (isRtoOrReturned && data['matched'] == true) {
          final bostaTracking = data['tracking_number']?.toString() ?? '';
          if (bostaTracking.isNotEmpty) {
            rtoCheckEntries
                .add((saleId: saleId, bostaTracking: bostaTracking));
          }
        }

        final isPaid = data['cashout_status'] == 'paid';
        bool cashoutAfterAsOf = false;
        if (isPaid) {
          final cashoutId = data['cashout_id'] as String?;
          if (cashoutId != null) {
            final cashoutDate = cashoutDateMap[cashoutId] ?? '';
            if (cashoutDate.isNotEmpty && cashoutDate.compareTo(asOfStr) > 0) {
              cashoutAfterAsOf = true;
            }
          }
        }

        final prev = saleShipmentMap[saleId];
        final effectivelyPaid =
            ((prev?.hasPaid ?? false) || isPaid) && !cashoutAfterAsOf;
        final allRto = (prev?.allRto ?? true) && isRtoOrReturned;
        saleShipmentMap[saleId] =
            (hasPaid: effectivelyPaid, allRto: allRto);
      }

      // Batch RTO re-ship check using COD sales map.
      for (final entry in rtoCheckEntries) {
        final saleTracking = codSaleMap[entry.saleId] ?? '';
        final isReshipped =
            saleTracking.isNotEmpty && saleTracking != entry.bostaTracking;
        if (!isReshipped) rtoCount++;
      }

      // Compute pending AR from COD sales.
      final conn = ref.read(bostaConnectionProvider).value;
      final arCutoff = conn?.cfArCutoffDate;
      double pendingAr = 0;

      for (final saleDoc in codSalesSnap.docs) {
        final saleData = saleDoc.data();
        final orderStatus = (saleData['order_status'] as num?)?.toInt() ?? 0;
        if (orderStatus == 4) continue;

        if (arCutoff != null) {
          final saleDateTs = saleData['date'];
          DateTime? saleDate;
          if (saleDateTs is Timestamp) {
            saleDate = saleDateTs.toDate();
          } else if (saleDateTs is String) {
            saleDate = DateTime.tryParse(saleDateTs);
          }
          if (saleDate != null && saleDate.isBefore(arCutoff)) continue;
        }

        final saleDateTs = saleData['date'];
        DateTime? saleDate;
        if (saleDateTs is Timestamp) {
          saleDate = saleDateTs.toDate();
        } else if (saleDateTs is String) {
          saleDate = DateTime.tryParse(saleDateTs);
        }
        if (saleDate != null && saleDate.isAfter(asOf)) continue;

        final saleTotal = _computeSaleTotalFromFirestore(saleData);
        if (saleTotal <= 0) continue;

        final shipInfo = saleShipmentMap[saleDoc.id];
        if (shipInfo != null) {
          if (shipInfo.hasPaid) continue;
          if (shipInfo.allRto) continue;
        }

        pendingAr += saleTotal;
      }

      if (mounted) {
        setState(() {
          _historicalCashoutTotal = roundMoney(total);
          _historicalPendingAr = roundMoney(pendingAr);
          _rtoCount = rtoCount;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _historicalCashoutTotal = null;
          _historicalPendingAr = null;
        });
      }
    }
  }

  _BSData _computeData({
    required List<dynamic> inventoryProducts,
    required List<dynamic> purchases,
    required List<Sale> sales,
    required List<dynamic> allTransactions,
    required dynamic bs,
    required double openingCash,
    BostaConnection? bostaConnection,
  }) {
    final key = Object.hashAll([
      identityHashCode(inventoryProducts),
      identityHashCode(purchases),
      identityHashCode(sales),
      identityHashCode(allTransactions),
      bs.hashCode,
      openingCash,
      _period.range.start,
      _period.range.end,
      _isCfUser,
      _historicalCashoutTotal,
      _historicalPendingAr,
      _liveAr,
      bostaConnection?.cfTotalCashouts,
      bostaConnection?.cfPendingAr,
      _isCfUser ? identityHashCode(ref.read(loansProvider)) : 0,
      _isCfUser ? identityHashCode(ref.read(salariesProvider)) : 0,
      identityHashCode(ref.read(gatewayReceivablesProvider)),
      identityHashCode(ref.read(accruedExpensesProvider)),
      identityHashCode(ref.read(productionOrdersProvider).value),
    ]);

    if (_cachedData != null && _lastDataKey == key) return _cachedData!;

    final asOf = _period.range.end;
    final periodStart = _period.range.start;

    // ── Cash & Bank = CF closing balance (single source of truth) ──
    // Uses the shared CF engine so Balance Sheet and Cash Flow Statement
    // always agree on the closing cash figure.
    double bankBalance;
    double accountsReceivable;

    if (_isCfUser) {
      final double totalCashouts = _historicalCashoutTotal ??
          bostaConnection?.cfTotalCashouts ??
          0;

      bankBalance = computeClosingCash(
        openingCash: openingCash,
        transactions: allTransactions.cast<Transaction>(),
        asOf: asOf,
        isCfUser: true,
        totalCashouts: totalCashouts,
      );

      // ── CF-driven AR (Phase 4.3) ─────────────────────────
      // Prefer live-computed AR (same query as AR dashboard),
      // then historical, then pre-computed cloud function value.
      final double bostaPendingAr = _liveAr ??
          _historicalPendingAr ??
          bostaConnection?.cfPendingAr ??
          0;
      accountsReceivable = roundMoney(bostaPendingAr);
    } else {
      final double cashFromSales = sales
          .where((s) => s.orderStatus != OrderStatus.cancelled)
          .where((s) => s.createdAt != null && !s.createdAt!.isAfter(asOf))
          .fold<double>(0.0, (acc, s) => acc + s.amountPaid);

      bankBalance = computeClosingCash(
        openingCash: openingCash,
        transactions: allTransactions.cast<Transaction>(),
        asOf: asOf,
        isCfUser: false,
        cashFromSales: cashFromSales,
      );

      accountsReceivable = roundMoney(sales
          .where((s) => s.orderStatus != OrderStatus.cancelled)
          .where((s) => s.createdAt != null && !s.createdAt!.isAfter(asOf))
          .fold<double>(0.0, (acc, s) => acc + s.outstanding));
    }

    // Finished + raw inventory at cost, PLUS work-in-progress (materials
    // already consumed by in-progress production runs but not yet booked as
    // finished goods). Including WIP keeps total assets whole between a run's
    // START (raw stock drops) and COMPLETE (finished stock rises).
    final List<ProductionOrder> productionOrders =
        ref.read(productionOrdersProvider).value ?? const [];
    final inProgressAsOf = productionOrders
        .where((o) => o.isInProgress && !o.startedAt.isAfter(asOf));
    // WIP = materials actually consumed by in-progress runs (raw inventory has
    // already dropped, so this keeps assets whole). Finishing labor/made-to-order
    // are recognized only at completion, so they are NOT in WIP and NOT a
    // liability here.
    final double workInProgressValue = roundMoney(
        inProgressAsOf.fold<double>(0.0, (acc, o) => acc + o.wipValue));

    final double inventoryValue = roundMoney(
        inventoryProducts.fold<double>(0.0, (acc, p) => acc + p.totalCostValue) +
            workInProgressValue);

    final periodPurchases = purchases.where((p) => !p.date.isAfter(asOf)).toList();

    // Payments not applied to a specific purchase still left the bank, so they
    // reduce what is owed. Counting only per-purchase amountPaid overstated
    // supplier liabilities by the value of every unapplied credit.
    final unappliedBySupplier = <String, double>{};
    for (final pay in ref.read(paymentsProvider).value ?? const []) {
      if (pay.appliedToPurchaseIds.isNotEmpty) continue;
      if (pay.date.isAfter(asOf)) continue;
      unappliedBySupplier[pay.supplierId] =
          (unappliedBySupplier[pay.supplierId] ?? 0) + pay.amount;
    }

    // Group by supplier so credits offset that supplier's payable, matching
    // supplierAccrualProvider / computeSupplierPosition exactly.
    final purchasesBySupplier = <String, List<Purchase>>{};
    for (final p in periodPurchases) {
      (purchasesBySupplier[p.supplierId] ??= []).add(p);
    }
    for (final sid in unappliedBySupplier.keys) {
      purchasesBySupplier.putIfAbsent(sid, () => []);
    }

    double owing = 0, advances = 0;
    for (final entry in purchasesBySupplier.entries) {
      final pos = computeSupplierPosition(entry.value,
          unappliedCredits: unappliedBySupplier[entry.key] ?? 0);
      owing += pos.payable;
      advances += pos.prepaid;
    }
    final double suppliersOwing = roundMoney(owing);
    final double supplierAdvancePayments = roundMoney(advances);

    final plEligible = allTransactions
        .where((t) => !t.dateTime.isAfter(asOf))
        .where((t) => !t.excludeFromPL && !plExcludedCats.contains(t.categoryId));

    // Raw P&L (before depreciation, which never posts as a transaction).
    final double rawRetained = roundMoney(plEligible
        .where((t) => t.dateTime.isBefore(periodStart))
        .fold<double>(0.0, (acc, t) => acc + (t.isIncome ? t.amount.abs() : -t.amount.abs())));
    final double rawCurrent = roundMoney(plEligible
        .where((t) => !t.dateTime.isBefore(periodStart))
        .fold<double>(0.0, (acc, t) => acc + (t.isIncome ? t.amount.abs() : -t.amount.abs())));

    // Fixed assets — net book values for active assets + depreciation expense.
    final fixedAssets = ref.read(fixedAssetsProvider);
    final activeAssets =
        fixedAssets.where((a) => a.status == FixedAssetStatus.active);
    final double fixedAssetsNetValue =
        roundMoney(activeAssets.fold(0.0, (acc, a) => acc + a.netBookValue));
    // Depreciation never posts as a txn, yet netBookValue (asset side) already
    // nets it. Book the matching expense here so net income is correct and the
    // depreciation doesn't leak into the equity plug. Split prior vs current.
    double priorDep = 0, currentDep = 0;
    for (final a in activeAssets) {
      final toStart = a.accumulatedDepreciationAsOf(periodStart);
      final toAsOf = a.accumulatedDepreciationAsOf(asOf);
      priorDep += toStart;
      currentDep += (toAsOf - toStart);
    }
    final double depreciationExpense = roundMoney(currentDep);

    final double retainedEarnings = roundMoney(rawRetained - roundMoney(priorDep));
    final double currentPeriodNetIncome =
        roundMoney(rawCurrent - depreciationExpense);

    // Loans — for CF user, compute from loan records; otherwise use manual entry
    final loanRecords = ref.read(loansProvider);
    final double loansOutstanding = _isCfUser
        ? roundMoney(loanRecords
            .where((l) => l.status == LoanStatus.active)
            .fold(0.0, (s, l) => s + l.outstandingBalance))
        : bs.loans;

    // Salaries — for CF user, compute from salary records; otherwise use manual entry
    final salaryRecords = ref.read(salariesProvider);
    final double unpaidSalaries = _isCfUser
        ? roundMoney(salaryRecords
            .where((s) => s.status == SalaryStatus.active)
            .fold(0.0, (acc, s) => acc + s.unpaidAmount))
        : bs.unpaidSalaries;

    // Payment-gateway receivables (asset) — sum of active gateways' pending
    // (uncleared) balances. Maintained manually + reduced by settlements.
    final gatewayRecords = ref.read(gatewayReceivablesProvider);
    final double gatewayReceivables = roundMoney(gatewayRecords
        .where((g) => g.isActive)
        .fold<double>(0.0, (acc, g) => acc + g.pendingBalance));

    // Accrued expenses (liability) — sum of active accruals' outstanding amounts.
    final accruedRecords = ref.read(accruedExpensesProvider);
    final double accruedExpenses = roundMoney(accruedRecords
        .where((a) => a.isActive)
        .fold<double>(0.0, (acc, a) => acc + a.amount));

    // Owner equity movements (excluded from P&L but real equity changes).
    final double ownerContributions = roundMoney(allTransactions
        .where((t) =>
            !t.dateTime.isAfter(asOf) && t.categoryId == 'cat_equity_injection')
        .fold<double>(0.0, (acc, t) => acc + (t.amount as num).abs()));
    final double ownerWithdrawals = roundMoney(allTransactions
        .where((t) =>
            !t.dateTime.isAfter(asOf) && t.categoryId == 'cat_owner_withdrawal')
        .fold<double>(0.0, (acc, t) => acc + (t.amount as num).abs()));

    // Cash salary settlements (excluded from P&L) — used by the orphan-payment
    // guard: these should be settling a tracked salary liability.
    final double salaryPaymentsTotal = roundMoney(allTransactions
        .where((t) =>
            !t.dateTime.isAfter(asOf) && t.categoryId == 'cat_salary_payment')
        .fold<double>(0.0, (acc, t) => acc + (t.amount as num).abs()));

    final double totalAssets = roundMoney(bankBalance + bs.cashOnHand + bs.unpaidInvoices + inventoryValue + accountsReceivable + gatewayReceivables + supplierAdvancePayments + fixedAssetsNetValue);
    final double totalLiabilities = roundMoney(
        suppliersOwing + loansOutstanding + unpaidSalaries + accruedExpenses);
    final double netEquity = roundMoney(totalAssets - totalLiabilities);

    final bool hasManualCapital = bs.hasSetCapital;
    // Real integrity check (see [reconcileEquity]): independent expected equity
    // vs assets−liabilities. Surfaces genuine unexplained differences for
    // manual-capital users; 0 by construction for auto users.
    final recon = reconcileEquity(
      netEquity: netEquity,
      openingCapital: bs.openingCapital,
      hasManualCapital: hasManualCapital,
      retainedEarnings: retainedEarnings,
      currentNetIncome: currentPeriodNetIncome,
      ownerContributions: ownerContributions,
      ownerWithdrawals: ownerWithdrawals,
      openingRetainedEarnings: bs.openingRetainedEarnings,
    );
    final double effectiveCapital = recon.effectiveCapital;
    final double unexplainedDifference = recon.unexplainedDifference;

    _lastDataKey = key;
    _cachedData = _BSData(
      bankBalance: bankBalance,
      inventoryValue: inventoryValue,
      suppliersOwing: suppliersOwing,
      supplierAdvancePayments: supplierAdvancePayments,
      accountsReceivable: accountsReceivable,
      gatewayReceivables: gatewayReceivables,
      fixedAssetsNetValue: fixedAssetsNetValue,
      loansOutstanding: loansOutstanding,
      unpaidSalaries: unpaidSalaries,
      accruedExpenses: accruedExpenses,
      retainedEarnings: retainedEarnings,
      currentPeriodNetIncome: currentPeriodNetIncome,
      depreciationExpense: depreciationExpense,
      ownerContributions: ownerContributions,
      ownerWithdrawals: ownerWithdrawals,
      salaryPaymentsTotal: salaryPaymentsTotal,
      totalAssets: totalAssets,
      totalLiabilities: totalLiabilities,
      netEquity: netEquity,
      hasManualCapital: hasManualCapital,
      effectiveCapital: effectiveCapital,
      openingRetainedEarnings: bs.openingRetainedEarnings,
      unexplainedDifference: unexplainedDifference,
    );
    return _cachedData!;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final fmt = NumberFormat('#,##0', 'en');

    // Persisted manual entries from Firestore
    final bs = ref.watch(balanceSheetEntriesProvider);

    // Watch providers to trigger rebuilds when data changes
    final inventoryProducts = ref.watch(filteredInventoryProvider).value ?? [];
    final purchases = ref.watch(purchasesProvider).value ?? [];
    final sales = _sales;
    final allTransactions = _transactions;
    // Prefer the Firestore-persisted opening cash (auditable, device-independent);
    // fall back to the legacy device-local setting if not set yet.
    final openingCash = bs.openingCashBalance != 0
        ? bs.openingCashBalance
        : ref.watch(appSettingsProvider).openingCashBalance;
    ref.watch(fixedAssetsProvider); // trigger rebuild when assets change
    if (_isCfUser) ref.watch(loansProvider); // trigger rebuild when loans change
    if (_isCfUser) ref.watch(salariesProvider); // trigger rebuild when salaries change
    ref.watch(gatewayReceivablesProvider); // rebuild when gateways change
    ref.watch(accruedExpensesProvider); // rebuild when accruals change

    // CF user: watch bosta connection for pre-computed summary + dashboard status.
    final bostaConn = _isCfUser ? ref.watch(bostaConnectionProvider).value : null;

    // Compute (cached — skips math when inputs haven't changed)
    final d = _computeData(
      inventoryProducts: inventoryProducts,
      purchases: purchases,
      sales: sales,
      allTransactions: allTransactions,
      bs: bs,
      openingCash: openingCash,
      bostaConnection: bostaConn,
    );

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: _isFirstLoad
          ? const Center(child: CircularProgressIndicator())
          : Column(
            children: [
              // Thin refresh indicator when silently refreshing in background
              // (period change, CF sync, etc.) so users know data is updating.
              SizedBox(
                height: 2,
                child: _isRefreshing
                    ? const LinearProgressIndicator(minHeight: 2)
                    : null,
              ),
              Expanded(
                child: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                ref.read(inventoryProvider.notifier).refreshAll(),
                _loadData(forceServer: true),
              ]);
              ref.invalidate(purchasesProvider);
            },
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 100 + MediaQuery.of(context).padding.bottom),
              physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics()),
              child: Column(
              children: [
                // Header / Trend Toggle + Period Selector
                _buildHeaderControls(),
                const SizedBox(height: 12),
                _buildPeriodSelector(),
                const SizedBox(height: 16),

                // ── CF User: Auth failure banner (Phase 4.4) ───
                if (_isCfUser && bostaConn?.isDashboardAuthFailed == true)
                  _buildAuthFailureBanner(),

                // ── CF User: Staleness indicator (Phase 4.5) ───
                if (_isCfUser) _buildStalenessIndicator(bostaConn),

                // ── CF User: Sanity check banner (Phase 6.1) ───
                if (_isCfUser && !_isFirstLoad && !_sanityCheckDismissed && d.bankBalance != 0)
                  _buildSanityCheckBanner(fmt, d.bankBalance),

                // ── CF User: RTO warning (Phase 6.3) ───────────
                if (_isCfUser && _rtoCount > 0)
                  _buildRtoWarning(),

                // ── CF User: Sync in progress ──────────────────
                if (_isCfUser && _cfSyncing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Syncing cashouts…',
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textTertiary, fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Net Equity / Trend Section
                 AnimatedCrossFade(
                  firstChild: _buildNetEquitySection(fmt, d.netEquity, d.totalAssets, d.totalLiabilities),
                  secondChild: _buildTrendChart(fmt),
                  crossFadeState: _showTrend ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  duration: 300.ms,
                ),
                const SizedBox(height: 24),

                // Assets (What You Own)
                _buildCollapsibleSection(
                  title: AppLocalizations.of(context)!.whatYouOwn,
                  subtitle: AppLocalizations.of(context)!.totalAssets,
                  amount: d.totalAssets,
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: AppColors.chartBlue,
                  iconBg: AppColors.chartBlueLight,
                  items: [
                    _SheetItem(
                      label: AppLocalizations.of(context)!.bankAccounts,
                      amount: d.bankBalance,
                      icon: Icons.account_balance_rounded,
                      pct: (d.totalAssets > 0) ? d.bankBalance / d.totalAssets : 0,
                      onTap: _isCfUser ? () => context.push(AppRoutes.cashBankDashboard) : null,
                      showChevron: _isCfUser,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.cashOnHand,
                      amount: bs.cashOnHand,
                      icon: Icons.payments_rounded,
                      pct: (d.totalAssets > 0) ? bs.cashOnHand / d.totalAssets : 0,
                      onTap: () => _showEditDialog(AppLocalizations.of(context)!.cashOnHand, bs.cashOnHand, (v) {
                        ref.read(balanceSheetEntriesProvider.notifier).update(bs.copyWith(cashOnHand: v));
                      }),
                      isEditable: true,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.inventory,
                      amount: d.inventoryValue,
                      icon: Icons.inventory_2_rounded,
                      pct: (d.totalAssets > 0) ? d.inventoryValue / d.totalAssets : 0,
                      onTap: () => context.push('/manage/inventory'),
                      showChevron: true,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.otherReceivables,
                      amount: bs.unpaidInvoices,
                      icon: Icons.receipt_long_rounded,
                      pct: (d.totalAssets > 0) ? bs.unpaidInvoices / d.totalAssets : 0,
                      onTap: () => _showEditDialog(AppLocalizations.of(context)!.otherReceivables, bs.unpaidInvoices, (v) {
                        ref.read(balanceSheetEntriesProvider.notifier).update(bs.copyWith(unpaidInvoices: v));
                      }),
                      isEditable: true,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.salesReceivables,
                      amount: d.accountsReceivable,
                      icon: Icons.request_quote_rounded,
                      pct: (d.totalAssets > 0) ? d.accountsReceivable / d.totalAssets : 0,
                      onTap: _isCfUser ? () => context.push(AppRoutes.arDashboard) : () => context.push('/sales'),
                      showChevron: true,
                    ),
                    _SheetItem(
                      label: 'Payment Gateway Receivables',
                      amount: d.gatewayReceivables,
                      icon: Icons.credit_card_rounded,
                      pct: (d.totalAssets > 0)
                          ? d.gatewayReceivables / d.totalAssets
                          : 0,
                      onTap: () =>
                          context.push(AppRoutes.gatewayReceivablesDashboard),
                      showChevron: true,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.supplierPrepayments,
                      amount: d.supplierAdvancePayments,
                      icon: Icons.schedule_send_rounded,
                      pct: (d.totalAssets > 0) ? d.supplierAdvancePayments / d.totalAssets : 0,
                      onTap: () => context.push('/manage/suppliers'),
                      showChevron: true,
                    ),
                    _SheetItem(
                      label: 'Fixed Assets (Net)',
                      amount: d.fixedAssetsNetValue,
                      icon: Icons.business_center_rounded,
                      pct: (d.totalAssets > 0) ? d.fixedAssetsNetValue / d.totalAssets : 0,
                      onTap: () => context.push(AppRoutes.fixedAssetsDashboard),
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
                  amount: d.totalLiabilities,
                  icon: Icons.money_off_rounded,
                  iconColor: AppColors.chartRed,
                  iconBg: AppColors.chartRedLight,
                  items: [
                    _SheetItem(
                      label: AppLocalizations.of(context)!.supplierPayable,
                      amount: d.suppliersOwing,
                      icon: Icons.local_shipping_rounded,
                      pct: (d.totalLiabilities > 0) ? d.suppliersOwing / d.totalLiabilities : 0,
                       onTap: () => context.push('/manage/suppliers'),
                      showChevron: true,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.loans,
                      amount: d.loansOutstanding,
                      icon: Icons.credit_card_rounded,
                      pct: (d.totalLiabilities > 0) ? d.loansOutstanding / d.totalLiabilities : 0,
                       onTap: _isCfUser
                           ? () => context.push(AppRoutes.loansDashboard)
                           : () => _showEditDialog(AppLocalizations.of(context)!.loans, bs.loans, (v) {
                               ref.read(balanceSheetEntriesProvider.notifier).update(bs.copyWith(loans: v));
                             }),
                       showChevron: _isCfUser,
                       isEditable: !_isCfUser,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.unpaidSalaries,
                      amount: d.unpaidSalaries,
                      icon: Icons.people_rounded,
                      pct: (d.totalLiabilities > 0) ? d.unpaidSalaries / d.totalLiabilities : 0,
                      onTap: _isCfUser
                          ? () => context.push(AppRoutes.salariesDashboard)
                          : () => _showEditDialog(AppLocalizations.of(context)!.unpaidSalaries, bs.unpaidSalaries, (v) {
                              ref.read(balanceSheetEntriesProvider.notifier).update(bs.copyWith(unpaidSalaries: v));
                            }),
                      showChevron: _isCfUser,
                      isEditable: !_isCfUser,
                    ),
                    _SheetItem(
                      label: 'Accrued Expenses',
                      amount: d.accruedExpenses,
                      icon: Icons.receipt_long_rounded,
                      pct: (d.totalLiabilities > 0)
                          ? d.accruedExpenses / d.totalLiabilities
                          : 0,
                      onTap: () =>
                          context.push(AppRoutes.accruedExpensesDashboard),
                      showChevron: true,
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
                  amount: d.netEquity,
                  icon: Icons.diamond_rounded,
                  iconColor: AppColors.chartGreen,
                  iconBg: AppColors.chartGreenLight,
                  items: [
                    _SheetItem(
                      label: d.hasManualCapital
                          ? AppLocalizations.of(context)!.ownersCapital
                          : '${AppLocalizations.of(context)!.ownersCapital} (${AppLocalizations.of(context)!.autoCalculated})',
                      amount: d.effectiveCapital,
                      icon: Icons.account_balance_rounded,
                      pct: d.netEquity != 0 ? (d.effectiveCapital / d.netEquity).clamp(-1.0, 1.0) : 0,
                      onTap: () => _showEditDialog(AppLocalizations.of(context)!.ownersCapital, bs.openingCapital, (v) {
                        ref.read(balanceSheetEntriesProvider.notifier).update(bs.copyWith(openingCapital: v, hasSetCapital: true));
                      }, allowNegative: true),
                      isEditable: true,
                    ),
                    // Pre-books retained earnings / accumulated deficit — shown
                    // distinctly so contributed capital stays positive and any
                    // opening deficit (e.g. debt carried before tracking) has a
                    // clear home instead of landing in "unexplained difference".
                    if (d.hasManualCapital || d.openingRetainedEarnings.abs() >= 0.01)
                      _SheetItem(
                        label: AppLocalizations.of(context)!.openingRetainedEarnings,
                        amount: d.openingRetainedEarnings,
                        icon: Icons.history_rounded,
                        pct: d.netEquity != 0 ? (d.openingRetainedEarnings / d.netEquity).clamp(-1.0, 1.0) : 0,
                        onTap: () => _showEditDialog(AppLocalizations.of(context)!.openingRetainedEarnings, bs.openingRetainedEarnings, (v) {
                          ref.read(balanceSheetEntriesProvider.notifier).update(bs.copyWith(openingRetainedEarnings: v));
                        }, allowNegative: true),
                        isEditable: true,
                      ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.retainedEarnings,
                      amount: d.retainedEarnings,
                      icon: Icons.savings_rounded,
                      pct: d.netEquity != 0 ? (d.retainedEarnings / d.netEquity).clamp(-1.0, 1.0) : 0,
                    ),
                    _SheetItem(
                      label: AppLocalizations.of(context)!.currentPeriodNetIncome,
                      amount: d.currentPeriodNetIncome,
                      icon: Icons.trending_up_rounded,
                      pct: d.netEquity != 0 ? (d.currentPeriodNetIncome / d.netEquity).clamp(-1.0, 1.0) : 0,
                    ),
                    if (d.ownerContributions.abs() >= 0.01)
                      _SheetItem(
                        label: AppLocalizations.of(context)!.ownerContributions,
                        amount: d.ownerContributions,
                        icon: Icons.add_card_rounded,
                        pct: d.netEquity != 0 ? (d.ownerContributions / d.netEquity).clamp(-1.0, 1.0) : 0,
                      ),
                    if (d.ownerWithdrawals.abs() >= 0.01)
                      _SheetItem(
                        label: AppLocalizations.of(context)!.ownerWithdrawals,
                        amount: -d.ownerWithdrawals,
                        icon: Icons.money_off_csred_rounded,
                        pct: d.netEquity != 0 ? (-d.ownerWithdrawals / d.netEquity).clamp(-1.0, 1.0) : 0,
                      ),
                    if (d.unexplainedDifference.abs() >= 1.0)
                      _SheetItem(
                        label: AppLocalizations.of(context)!.unexplainedDifference,
                        amount: d.unexplainedDifference,
                        icon: Icons.error_outline_rounded,
                        pct: d.netEquity != 0 ? (d.unexplainedDifference / d.netEquity).clamp(-1.0, 1.0) : 0,
                      ),
                  ],
                  fmt: fmt,
                  isAssets: true,
                ).animate().fadeIn(duration: 400.ms, delay: 250.ms),

                // Accounting equation check — green when the books reconcile,
                // orange when there's a real unexplained difference between
                // assets−liabilities and independently-expected equity.
                Builder(builder: (_) {
                  final isBalanced = d.unexplainedDifference.abs() < 1.0;
                  final badgeColor = isBalanced ? AppColors.badgeTextPositive : AppColors.accentOrange;
                  final bgColors = isBalanced
                      ? const [AppColors.chartGreenLight, Color(0xFFD1FAE5)]
                      : [AppColors.accentOrange.withValues(alpha: 0.1), AppColors.accentOrange.withValues(alpha: 0.15)];
                  final borderColor = isBalanced ? AppColors.badgeBgPositive : AppColors.accentOrange.withValues(alpha: 0.3);
                  final icon = isBalanced ? Icons.check_circle_rounded : Icons.warning_amber_rounded;
                  final text = isBalanced
                      ? AppLocalizations.of(context)!.accountingEquationBalanced
                      : AppLocalizations.of(context)!.accountingEquationUnbalanced;

                  return Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: bgColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
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
                            child: Icon(icon, size: 18, color: badgeColor),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            text,
                            style: AppTypography.badge.copyWith(
                              fontSize: 12,
                              color: badgeColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                // Data-hygiene warnings (double-count / orphan settlements)
                _buildDataWarnings(d, bs),

                // AI Insight
                _buildAIInsightCard(d.totalAssets, d.totalLiabilities, d.netEquity)
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
              ),
            ],
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
        if (_isCfUser)
          IconButton(
            icon: const Icon(Icons.verified_user_outlined, size: 20),
            tooltip: 'Data Audit',
            color: AppColors.textTertiary,
            onPressed: () => context.pushNamed('DataAuditScreen'),
          ),
        ChartToggle(
          showChart: _showTrend,
          onToggle: () => setState(() => _showTrend = !_showTrend),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return Center(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          _openDatePicker();
        },
        child: Container(
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
              const Icon(Icons.calendar_today_rounded,
                  size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                _period.label,
                style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.expand_more_rounded,
                  size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  // ── CF User: Auth failure banner (Phase 4.4) ─────────────
  Widget _buildAuthFailureBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => context.push('/manage/bosta'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.chartRedLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.chartRed.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, size: 20, color: AppColors.chartRed),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Bosta connection lost — tap to reconnect',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.chartRed, fontSize: 13, fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.chartRed),
            ],
          ),
        ),
      ),
    );
  }

  // ── CF User: Staleness indicator (Phase 4.5) ────────────
  Widget _buildStalenessIndicator(BostaConnection? conn) {
    if (conn == null) return const SizedBox.shrink();
    final lastSync = conn.cfLastCashoutSyncAt;
    if (lastSync == null) return const SizedBox.shrink();

    final age = DateTime.now().difference(lastSync);
    if (age.inHours < 24) return const SizedBox.shrink();

    final agoText = age.inDays > 0
        ? '${age.inDays}d ago'
        : '${age.inHours}h ago';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accentOrange.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time_rounded, size: 14, color: AppColors.accentOrange.withValues(alpha: 0.8)),
            const SizedBox(width: 6),
            Text(
              'Last synced: $agoText',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.accentOrange, fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── CF User: Sanity check banner (Phase 6.1) ─────────────
  Widget _buildSanityCheckBanner(NumberFormat fmt, double bankBalance) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => context.push(AppRoutes.cashBankDashboard),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.chartBlueLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.chartBlue.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.fact_check_rounded, size: 18, color: AppColors.chartBlue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Calculated Cash & Bank = EGP ${fmt.format(bankBalance)}',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.chartBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.chartBlue),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Tap to see full breakdown · Does this match your real bank balance?',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.chartBlue.withValues(alpha: 0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── CF User: RTO warning (Phase 6.3) ─────────────────────
  Widget _buildRtoWarning() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => context.pushNamed('RtoOrdersScreen'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.accentOrange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.accentOrange.withValues(alpha: 0.9)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$_rtoCount RTO/returned shipment${_rtoCount == 1 ? '' : 's'} excluded from AR — tap to review',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.accentOrange, fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.accentOrange.withValues(alpha: 0.7)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrendChart(NumberFormat fmt) {
    // Calculate historical Net Equity Trend based on transactions
    final transactions = _transactions;
    final bs = ref.watch(balanceSheetEntriesProvider);

    // Compute bank balance using CF engine (single source of truth).
    final openingCash = bs.openingCashBalance != 0
        ? bs.openingCashBalance
        : ref.watch(appSettingsProvider).openingCashBalance;
    final sales = _sales;
    final double bankBalance;

    if (_isCfUser) {
      final conn = ref.watch(bostaConnectionProvider).value;
      final totalCashouts = _historicalCashoutTotal ?? conn?.cfTotalCashouts ?? 0;
      bankBalance = computeClosingCash(
        openingCash: openingCash,
        transactions: transactions,
        asOf: DateTime.now(),
        isCfUser: true,
        totalCashouts: totalCashouts,
      );
    } else {
      final double cashFromSales = sales
          .where((s) => s.orderStatus != OrderStatus.cancelled)
          .where((s) => s.createdAt != null)
          .fold<double>(0.0, (acc, s) => acc + s.amountPaid);
      bankBalance = computeClosingCash(
        openingCash: openingCash,
        transactions: transactions,
        asOf: DateTime.now(),
        isCfUser: false,
        cashFromSales: cashFromSales,
      );
    }

    // Get inventory, AR, supplier balances
    final inventoryProducts = ref.watch(filteredInventoryProvider).value ?? [];
    final purchases = ref.watch(purchasesProvider).value ?? [];

    final double inventoryValue = inventoryProducts.fold(0.0, (acc, p) => acc + p.totalCostValue);
    final double suppliersOwing = purchases.fold(0.0, (acc, p) {
      final receivedValue = p.totalReceivedValue;
      final paid = p.amountPaid;
      return acc + (receivedValue - paid).clamp(0.0, double.maxFinite);
    });
    final double supplierAdvancePayments = purchases.fold(0.0, (acc, p) {
      final receivedValue = p.totalReceivedValue;
      final paid = p.amountPaid;
      return acc + (paid - receivedValue).clamp(0.0, double.maxFinite);
    });
    final double accountsReceivable = _isCfUser
        ? (_historicalPendingAr ?? _liveAr ?? ref.watch(bostaConnectionProvider).value?.cfPendingAr ?? 0)
        : sales
            .where((s) => s.orderStatus != OrderStatus.cancelled)
            .fold(0.0, (acc, s) => acc + s.outstanding);

    final faAssets = ref.read(fixedAssetsProvider);
    final fixedAssetsNBV = faAssets
        .where((a) => a.status == FixedAssetStatus.active)
        .fold(0.0, (s, a) => s + a.netBookValue);

    final totalAssets = bankBalance + bs.cashOnHand + bs.unpaidInvoices +
        inventoryValue + accountsReceivable + supplierAdvancePayments +
        fixedAssetsNBV;
    final cfLoansOutstanding = _isCfUser
        ? ref.read(loansProvider)
            .where((l) => l.status == LoanStatus.active)
            .fold(0.0, (s, l) => s + l.outstandingBalance)
        : bs.loans;
    final cfUnpaidSalaries = _isCfUser
        ? ref.read(salariesProvider)
            .where((s) => s.status == SalaryStatus.active)
            .fold(0.0, (acc, s) => acc + s.unpaidAmount)
        : bs.unpaidSalaries;
    final totalLiabilities = cfLoansOutstanding + cfUnpaidSalaries + suppliersOwing;
    final currentNetEquity = totalAssets - totalLiabilities;

    // Build 6-month backward trend by deducting monthly P&L flows
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

      // Calculate net flow for that month (P&L items only)
      double monthlyFlow = 0;
      for (final tx in transactions) {
        if (tx.excludeFromPL) continue;
        if (plExcludedCats.contains(tx.categoryId)) continue;
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
            AppLocalizations.of(context)!.netWorthTrend,
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

  /// Non-blocking data-hygiene warnings: manual receivables that may overlap
  /// computed AR, and salary cash payments that exceed any tracked liability
  /// (orphan settlements that bypass P&L). `bs` is the BalanceSheetEntries doc.
  Widget _buildDataWarnings(_BSData d, dynamic bs) {
    final l10n = AppLocalizations.of(context)!;
    final warnings = <String>[];
    if ((bs.unpaidInvoices as double) > 0 && d.accountsReceivable > 0) {
      warnings.add(l10n.bsWarnReceivablesOverlap);
    }
    if (roundMoney(d.salaryPaymentsTotal - d.unpaidSalaries) > 1.0) {
      warnings.add(l10n.bsWarnOrphanSalary);
    }
    if (warnings.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.accentOrange.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.accentOrange.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: AppColors.accentOrange),
                const SizedBox(width: 8),
                Text(l10n.bsDataChecks,
                    style: AppTypography.labelMedium.copyWith(
                        color: AppColors.accentOrange,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            ...warnings.map((w) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ',
                          style: TextStyle(color: AppColors.accentOrange)),
                      Expanded(
                        child: Text(w,
                            style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textSecondary, height: 1.35)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
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
          AppLocalizations.of(context)!.netEquityPosition,
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF6B7280)),
              SizedBox(width: 4),
              Text(
                AppLocalizations.of(context)!.addLastMonthTrend,
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
                    AppLocalizations.of(context)!.distribution,
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
                    label: AppLocalizations.of(context)!.assets,
                    amount: '$currency ${(totalAssets / 1000).toStringAsFixed(0)}k',
                    color: AppColors.chartBlue,
                  ),
                  Container(
                    width: 1,
                    height: 32,
                    color: AppColors.borderLight,
                  ),
                  _buildLegendItem(
                    label: AppLocalizations.of(context)!.liabilities,
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

  Future<void> _showEditDialog(String title, double currentValue, Function(double) onSave, {bool allowNegative = false}) async {
    final controller = TextEditingController(text: currentValue.toStringAsFixed(0));
    final currency = ref.read(appSettingsProvider).currency;
    final formKey = GlobalKey<FormState>();
    final l10n = AppLocalizations.of(context)!;
    final fmt = NumberFormat('#,##0', 'en');

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
              Text(l10n.editField(title), style: AppTypography.h3),
              const SizedBox(height: 4),
              Text(
                l10n.currentValueLabel(currency, fmt.format(currentValue)),
                style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.amountWithCurrency(currency),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixText: '$currency ',
                  prefixStyle: AppTypography.labelLarge.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () => controller.clear(),
                    tooltip: l10n.clear,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return l10n.enterAnAmount;
                  final parsed = double.tryParse(v.trim());
                  if (parsed == null) return l10n.enterAValidNumber;
                  if (!allowNegative && parsed < 0) return l10n.amountCannotBeNegative;
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
                      child: Text(l10n.cancel),
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
                      child: Text(l10n.save),
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
    final l10n = AppLocalizations.of(context)!;
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
                'REVVO AI',
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
                  l10n.comingSoon,
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
                SnackBar(content: Text(AppLocalizations.of(context)!.aiAnalysisComingSoon)),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.viewFullAnalysis,
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
    final l10n = AppLocalizations.of(context)!;
    final fmt = NumberFormat('#,##0', 'en');
    if (totalAssets == 0 && totalLiabilities == 0) {
      return l10n.bsInsightEmpty;
    }
    final debtRatio = totalAssets > 0 ? totalLiabilities / totalAssets : 0.0;
    if (debtRatio > 0.8) {
      return l10n.bsInsightHighDebt((debtRatio * 100).toStringAsFixed(0));
    }
    if (debtRatio > 0.5) {
      return l10n.bsInsightModerateDebt((debtRatio * 100).toStringAsFixed(0));
    }
    final bsAi = ref.read(balanceSheetEntriesProvider);
    if (bsAi.cashOnHand > bsAi.loans && bsAi.loans > 0) {
      return l10n.bsInsightCashExceedsLoan;
    }
    if (netEquity > 0) {
      return l10n.bsInsightPositiveEquity(fmt.format(netEquity));
    }
    return l10n.bsInsightNegativeEquity;
  }

  Widget _buildDownloadButton() {
    return Semantics(
      button: true,
      label: 'Download Balance Sheet report',
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
      onPressed: _sharing ? null : () async {
        HapticFeedback.mediumImpact();
        setState(() => _sharing = true);
        final origin = ShareService.originFrom(context);
        final l10n = AppLocalizations.of(context)!;
        try {
          final reportSvc = ref.read(reportServiceProvider);
          final shareSvc = ref.read(shareServiceProvider);
          final settings = ref.read(appSettingsProvider);
          final bsManual = ref.read(balanceSheetEntriesProvider);
          final allTxns = _transactions;
          final products = ref.read(filteredInventoryProvider).value ?? [];
          final purchases = ref.read(purchasesProvider).value ?? [];
          final sales = _sales;

          // Compute bank balance using CF engine (single source of truth)
          final asOfDate = _period.range.end;
          final double computedBank;
          if (_isCfUser) {
            final conn = ref.read(bostaConnectionProvider).value;
            final totalCashouts = _historicalCashoutTotal ?? conn?.cfTotalCashouts ?? 0;
            computedBank = computeClosingCash(
              openingCash: bsManual.openingCashBalance != 0
                  ? bsManual.openingCashBalance
                  : settings.openingCashBalance,
              transactions: allTxns,
              asOf: asOfDate,
              isCfUser: true,
              totalCashouts: totalCashouts,
            );
          } else {
            final pdfCashFromSales = sales
                .where((s) => s.orderStatus != OrderStatus.cancelled)
                .where((s) => s.createdAt != null && !s.createdAt!.isAfter(asOfDate))
                .fold<double>(0.0, (acc, s) => acc + s.amountPaid);
            computedBank = computeClosingCash(
              openingCash: bsManual.openingCashBalance != 0
                  ? bsManual.openingCashBalance
                  : settings.openingCashBalance,
              transactions: allTxns,
              asOf: asOfDate,
              isCfUser: false,
              cashFromSales: pdfCashFromSales,
            );
          }

          final pdfInProgress = (ref.read(productionOrdersProvider).value ?? const [])
              .where((o) => o.isInProgress && !o.startedAt.isAfter(asOfDate));
          final pdfWip = roundMoney(
              pdfInProgress.fold<double>(0.0, (acc, o) => acc + o.wipValue));
          final inventoryValue =
              products.fold<double>(0, (acc, p) => acc + p.totalCostValue) + pdfWip;
          final accountsReceivable = _isCfUser
              ? (_historicalPendingAr ?? ref.read(bostaConnectionProvider).value?.cfPendingAr ?? 0)
              : sales
                  .where((s) => s.orderStatus != OrderStatus.cancelled)
                  .where((s) => s.createdAt != null && !s.createdAt!.isAfter(asOfDate))
                  .fold<double>(0, (acc, s) => acc + s.outstanding);
          final pdfPurchases = purchases.where((p) => !p.date.isAfter(asOfDate)).toList();
          final suppliersOwing = pdfPurchases.fold<double>(0.0, (acc, p) {
            final received = p.totalReceivedValue;
            return acc + (received - p.amountPaid).clamp(0.0, double.maxFinite);
          });
          final supplierPrepayments = pdfPurchases.fold<double>(0.0, (acc, p) {
            final received = p.totalReceivedValue;
            return acc + (p.amountPaid - received).clamp(0.0, double.maxFinite);
          });
          // Compute equity components for PDF (same logic as the screen).
          final pdfFixedAssets = ref.read(fixedAssetsProvider)
              .where((a) => a.status == FixedAssetStatus.active);
          final pdfFixedAssetsNBV =
              pdfFixedAssets.fold(0.0, (s, a) => s + a.netBookValue);
          double pdfPriorDep = 0, pdfCurrentDep = 0;
          for (final a in pdfFixedAssets) {
            final toStart = a.accumulatedDepreciationAsOf(_period.range.start);
            final toAsOf = a.accumulatedDepreciationAsOf(asOfDate);
            pdfPriorDep += toStart;
            pdfCurrentDep += (toAsOf - toStart);
          }
          final pdfRetained = roundMoney(allTxns
              .where((t) => t.dateTime.isBefore(_period.range.start))
              .where((t) => !t.excludeFromPL && !plExcludedCats.contains(t.categoryId))
              .fold(0.0, (s, t) => s + (t.isIncome ? t.amount.abs() : -t.amount.abs())) - pdfPriorDep);
          final pdfCurrentNet = roundMoney(allTxns
              .where((t) => !t.dateTime.isBefore(_period.range.start) && !t.dateTime.isAfter(asOfDate))
              .where((t) => !t.excludeFromPL && !plExcludedCats.contains(t.categoryId))
              .fold(0.0, (s, t) => s + (t.isIncome ? t.amount.abs() : -t.amount.abs())) - pdfCurrentDep);
          final pdfOwnerContrib = roundMoney(allTxns
              .where((t) => !t.dateTime.isAfter(asOfDate) && t.categoryId == 'cat_equity_injection')
              .fold(0.0, (s, t) => s + (t.amount as num).abs()));
          final pdfOwnerWithdraw = roundMoney(allTxns
              .where((t) => !t.dateTime.isAfter(asOfDate) && t.categoryId == 'cat_owner_withdrawal')
              .fold(0.0, (s, t) => s + (t.amount as num).abs()));

          final pdfTotalAssets = roundMoney(computedBank + bsManual.cashOnHand + bsManual.unpaidInvoices +
              inventoryValue + accountsReceivable + supplierPrepayments + pdfFixedAssetsNBV);
          final pdfLoansAmt = _isCfUser
              ? ref.read(loansProvider)
                  .where((l) => l.status == LoanStatus.active)
                  .fold(0.0, (s, l) => s + l.outstandingBalance)
              : bsManual.loans;
          final pdfSalariesAmt = _isCfUser
              ? ref.read(salariesProvider)
                  .where((s) => s.status == SalaryStatus.active)
                  .fold(0.0, (acc, s) => acc + s.unpaidAmount)
              : bsManual.unpaidSalaries;
          final pdfTotalLiabilities =
              roundMoney(suppliersOwing + pdfLoansAmt + pdfSalariesAmt);
          final pdfNetEquity = roundMoney(pdfTotalAssets - pdfTotalLiabilities);
          final pdfHasManual = bsManual.openingCapital != 0;
          final pdfRecon = reconcileEquity(
            netEquity: pdfNetEquity,
            openingCapital: bsManual.openingCapital,
            hasManualCapital: pdfHasManual,
            retainedEarnings: pdfRetained,
            currentNetIncome: pdfCurrentNet,
            ownerContributions: pdfOwnerContrib,
            ownerWithdrawals: pdfOwnerWithdraw,
            openingRetainedEarnings: bsManual.openingRetainedEarnings,
          );
          final pdfEffectiveCapital = pdfRecon.effectiveCapital;
          final pdfAdjustment = pdfRecon.unexplainedDifference;

          final bytes = await reportSvc.generateBalanceSheetPdf(
            l10n: l10n,
            bs: bsManual,
            bankBalance: computedBank,
            inventoryValue: inventoryValue,
            accountsReceivable: accountsReceivable,
            supplierPrepayments: supplierPrepayments,
            suppliersOwing: suppliersOwing,
            currency: settings.currency,
            retainedEarnings: pdfRetained,
            currentPeriodNetIncome: pdfCurrentNet,
            effectiveOpeningCapital: pdfEffectiveCapital,
            reconAdjustment: pdfAdjustment,
            ownerContributions: pdfOwnerContrib,
            ownerWithdrawals: pdfOwnerWithdraw,
            openingRetainedEarnings: bsManual.openingRetainedEarnings,
            asOfDate: asOfDate,
          );
          await shareSvc.sharePdf(bytes, 'Balance_Sheet.pdf', subject: 'Balance Sheet', origin: origin);
        } catch (e) {
          if (kDebugMode) debugPrint('Balance Sheet share error: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.somethingWentWrong), backgroundColor: Colors.red));
          }
        } finally {
          if (mounted) setState(() => _sharing = false);
        }
      },
      icon: _sharing
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.ios_share_rounded, size: 18),
      label: Text(_sharing ? AppLocalizations.of(context)!.preparingReport : AppLocalizations.of(context)!.shareReport, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
