import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../shared/utils/safe_pop.dart';

/// Severity of an audit finding.
enum _Severity { error, warning, info, ok }

/// A single audit finding.
class _Finding {
  final _Severity severity;
  final String category;
  final String title;
  final String detail;

  const _Finding({
    required this.severity,
    required this.category,
    required this.title,
    required this.detail,
  });
}

/// Comprehensive data integrity audit for all financial data.
class DataAuditScreen extends ConsumerStatefulWidget {
  const DataAuditScreen({super.key});

  @override
  ConsumerState<DataAuditScreen> createState() => _DataAuditScreenState();
}

class _DataAuditScreenState extends ConsumerState<DataAuditScreen> {
  bool _loading = true;
  String _status = 'Starting audit...';
  final List<_Finding> _findings = [];
  int _checksRun = 0;
  String _filterCategory = 'all';

  // Cached snapshots — loaded once, used by all checks.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _salesDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _txDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _shipDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _cashoutDocs = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _invDocs = [];
  Map<String, dynamic> _bsData = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(_runFullAudit);
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String get _uid {
    return ref.read(authProvider).user?.id ?? '';
  }

  /// Safe num parse — handles both num and String values from Firestore.
  static double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  // ── Main audit runner ────────────────────────────────────
  Future<void> _runFullAudit() async {
    if (_uid.isEmpty) {
      _addFinding(_Severity.error, 'Auth', 'No user ID', 'Cannot run audit without a logged-in user.');
      setState(() => _loading = false);
      return;
    }

    // Load ALL data — each query is independent so one failure won't kill the rest.
    _setStatus('Loading data...');

    Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> safeQuery(String collection) async {
      try {
        final snap = await _db.collection(collection).where('user_id', isEqualTo: _uid).get();
        return snap.docs;
      } catch (e) {
        _addFinding(_Severity.warning, 'Access', 'Cannot read $collection', '$e');
        return [];
      }
    }

    final futures = await Future.wait([
      safeQuery('sales'),
      safeQuery('transactions'),
      safeQuery('bosta_shipments'),
      safeQuery('bosta_cashouts'),
      safeQuery('products'),
    ]);

    _salesDocs = futures[0];
    _txDocs = futures[1];
    _shipDocs = futures[2];
    _cashoutDocs = futures[3];
    _invDocs = futures[4];

    try {
      final bsDoc = await _db.collection('balance_sheet').doc(_uid).get();
      _bsData = bsDoc.data() ?? {};
    } catch (e) {
      _addFinding(_Severity.warning, 'Access', 'Cannot read balance_sheet', '$e');
      _bsData = {};
    }

    _auditSales();
    _auditTransactions();
    _auditSaleTransactionLinks();
    _auditBostaShipments();
    _auditBostaCashouts();
    _auditInventory();
    _auditCashBalance();
    _auditBalanceSheet();

    if (_findings.where((f) => f.severity == _Severity.error || f.severity == _Severity.warning).isEmpty) {
      _addFinding(_Severity.ok, 'Overall', 'All checks passed', 'No critical issues found across $_checksRun checks.');
    }

    if (mounted) setState(() { _loading = false; _status = 'Audit complete'; });
  }

  void _addFinding(_Severity sev, String cat, String title, String detail) {
    _findings.add(_Finding(severity: sev, category: cat, title: title, detail: detail));
    if (mounted) setState(() {});
  }

  void _setStatus(String s) {
    if (mounted) setState(() => _status = s);
  }

  // ── 1. Sales Audit ───────────────────────────────────────
  void _auditSales() {
    _setStatus('Auditing sales...');
    _checksRun++;

    int total = _salesDocs.length;
    int noItems = 0;
    int negativeAmount = 0;
    int duplicateOrderNums = 0;
    int cancelledWithPayment = 0;
    int futureDated = 0;
    int missingCustomer = 0;
    double totalRevenue = 0;
    double totalCogs = 0;

    final orderNumSet = <int>{};
    final orderNumDups = <int>{};
    final now = DateTime.now();

    for (final doc in _salesDocs) {
      final d = doc.data();
      final orderNum = _toInt(d['shopify_order_number']);
      final orderStatus = _toInt(d['order_status']);
      final amountPaid = _toDouble(d['amount_paid']);
      final items = d['items'] as List<dynamic>? ?? [];
      final customerName = d['customer_name'] as String? ?? '';
      final dateVal = d['date'];

      if (items.isEmpty && orderStatus != 4) noItems++;
      if (amountPaid < 0) negativeAmount++;

      if (orderNum > 0) {
        if (!orderNumSet.add(orderNum)) orderNumDups.add(orderNum);
      }

      if (orderStatus == 4 && amountPaid > 0) cancelledWithPayment++;

      DateTime? saleDate;
      if (dateVal is Timestamp) {
        saleDate = dateVal.toDate();
      } else if (dateVal is String) {
        saleDate = DateTime.tryParse(dateVal);
      }
      if (saleDate != null && saleDate.isAfter(now.add(const Duration(days: 1)))) futureDated++;

      if (customerName.isEmpty && orderStatus != 4) missingCustomer++;

      if (orderStatus != 4) {
        double subtotal = 0;
        double discount = _toDouble(d['discount_amount']);
        double cogs = 0;
        for (final item in items) {
          if (item is Map) {
            final qty = _toInt(item['quantity']);
            final price = _toDouble(item['unit_price']);
            final cost = _toDouble(item['cost_price']);
            subtotal += qty * price;
            cogs += qty * cost;
          }
        }
        totalRevenue += subtotal - discount;
        totalCogs += cogs;
      }
    }

    duplicateOrderNums = orderNumDups.length;

    if (noItems > 0) _addFinding(_Severity.warning, 'Sales', '$noItems sales with no items', 'Active sales with an empty items array may cause zero-revenue entries.');
    if (negativeAmount > 0) _addFinding(_Severity.error, 'Sales', '$negativeAmount sales with negative amount_paid', 'Negative amount_paid is invalid and corrupts AR calculations.');
    if (duplicateOrderNums > 0) _addFinding(_Severity.error, 'Sales', '$duplicateOrderNums duplicate order numbers', 'Orders: ${orderNumDups.take(10).join(", ")}. Duplicates cause double-counting in revenue.');
    if (cancelledWithPayment > 0) _addFinding(_Severity.warning, 'Sales', '$cancelledWithPayment cancelled orders still show payment', 'Cancelled orders with amount_paid > 0 may need refund processing.');
    if (futureDated > 0) _addFinding(_Severity.warning, 'Sales', '$futureDated future-dated sales', 'Sales dated after today affect period calculations.');
    if (missingCustomer > 0) _addFinding(_Severity.info, 'Sales', '$missingCustomer active sales missing customer name', 'May indicate incomplete Shopify sync.');

    final fmt = NumberFormat('#,##0.00', 'en');
    _addFinding(_Severity.info, 'Sales', 'Sales summary: $total orders', 'Revenue: EGP ${fmt.format(totalRevenue)} | COGS: EGP ${fmt.format(totalCogs)} | GP: EGP ${fmt.format(totalRevenue - totalCogs)}');
  }

  // ── 2. Transactions Audit ────────────────────────────────
  void _auditTransactions() {
    _setStatus('Auditing transactions...');
    _checksRun++;

    int total = _txDocs.length;
    int uncategorized = 0;
    int futureDated = 0;
    int zeroAmount = 0;
    double totalIncome = 0;
    double totalExpense = 0;
    final now = DateTime.now();
    final idSet = <String>{};
    final idDups = <String>[];

    for (final doc in _txDocs) {
      final d = doc.data();
      final catId = d['category_id'] as String? ?? '';
      final amount = _toDouble(d['amount']);
      final isIncome = d['is_income'] as bool? ?? false;
      final dateVal = d['date'];

      if (!idSet.add(doc.id)) idDups.add(doc.id);

      if (catId.isEmpty) uncategorized++;
      if (amount == 0) zeroAmount++;

      DateTime? txDate;
      if (dateVal is Timestamp) {
        txDate = dateVal.toDate();
      } else if (dateVal is String) {
        txDate = DateTime.tryParse(dateVal);
      }
      if (txDate != null && txDate.isAfter(now.add(const Duration(days: 1)))) futureDated++;

      if (isIncome) {
        totalIncome += amount.abs();
      } else {
        totalExpense += amount.abs();
      }
    }

    if (uncategorized > 0) _addFinding(_Severity.warning, 'Transactions', '$uncategorized uncategorized transactions', 'Missing category_id affects P&L and CF classification.');
    if (futureDated > 0) _addFinding(_Severity.warning, 'Transactions', '$futureDated future-dated transactions', 'Transactions dated after today may inflate current period.');
    if (zeroAmount > 0) _addFinding(_Severity.info, 'Transactions', '$zeroAmount zero-amount transactions', 'These have no financial impact but clutter the ledger.');
    if (idDups.isNotEmpty) _addFinding(_Severity.error, 'Transactions', '${idDups.length} duplicate transaction IDs', 'IDs: ${idDups.take(5).join(", ")}');

    final fmt = NumberFormat('#,##0.00', 'en');
    _addFinding(_Severity.info, 'Transactions', 'Transaction summary: $total records', 'Income: EGP ${fmt.format(totalIncome)} | Expenses: EGP ${fmt.format(totalExpense)} | Net: EGP ${fmt.format(totalIncome - totalExpense)}');
  }

  // ── 3. Sale ↔ Transaction Link Audit ─────────────────────
  void _auditSaleTransactionLinks() {
    _setStatus('Auditing sale-transaction links...');
    _checksRun++;

    final activeSaleIds = <String>{};
    final cancelledSaleIds = <String>{};
    for (final doc in _salesDocs) {
      final status = _toInt(doc.data()['order_status']);
      if (status == 4) {
        cancelledSaleIds.add(doc.id);
      } else {
        activeSaleIds.add(doc.id);
      }
    }

    int orphanedTxns = 0;
    int missingRevenueTxn = 0;
    int missingCogsTxn = 0;
    final saleIdsWithRevenue = <String>{};
    final saleIdsWithCogs = <String>{};

    for (final doc in _txDocs) {
      final d = doc.data();
      final saleId = d['sale_id'] as String?;
      final catId = d['category_id'] as String? ?? '';

      if (saleId != null && saleId.isNotEmpty) {
        if (!activeSaleIds.contains(saleId) && !cancelledSaleIds.contains(saleId)) {
          orphanedTxns++;
        }
        if (catId == 'cat_sales_revenue') saleIdsWithRevenue.add(saleId);
        if (catId == 'cat_cogs') saleIdsWithCogs.add(saleId);
      }
    }

    for (final saleId in activeSaleIds) {
      if (!saleIdsWithRevenue.contains(saleId)) missingRevenueTxn++;
      if (!saleIdsWithCogs.contains(saleId)) missingCogsTxn++;
    }

    if (orphanedTxns > 0) _addFinding(_Severity.error, 'Links', '$orphanedTxns orphaned transactions', 'Transactions linked to non-existent sales — stale data after deletion.');
    if (missingRevenueTxn > 0) _addFinding(_Severity.warning, 'Links', '$missingRevenueTxn active sales missing revenue transaction', 'These sales exist but have no cat_sales_revenue transaction — revenue undercounted.');
    if (missingCogsTxn > 0) _addFinding(_Severity.info, 'Links', '$missingCogsTxn active sales missing COGS transaction', 'May be expected if products had no cost price set.');
  }

  // ── 4. Bosta Shipments Audit ─────────────────────────────
  void _auditBostaShipments() {
    _setStatus('Auditing Bosta shipments...');
    _checksRun++;

    if (_shipDocs.isEmpty) return;

    // Build sale tracking lookup from cached sales.
    final saleTrackingMap = <String, String>{};
    for (final doc in _salesDocs) {
      final t = doc.data()['tracking_number'];
      if (t != null) saleTrackingMap[doc.id] = t.toString();
    }

    int total = _shipDocs.length;
    int unmatched = 0;
    int rtoCorrect = 0;
    int rtoReshipped = 0;
    int delivered = 0;
    int inTransit = 0;

    for (final doc in _shipDocs) {
      final d = doc.data();
      final matched = d['matched'] as bool? ?? false;
      final state = _toInt(d['state']);
      final saleId = d['sale_id'] as String?;
      final bostaTracking = d['tracking_number']?.toString() ?? '';

      if (!matched) { unmatched++; continue; }

      if (state == 45) { delivered++; continue; }
      if (state != 60 && state != 46) { inTransit++; continue; }

      // RTO/Returned — verify against sale tracking (no extra Firestore read).
      if (saleId != null && bostaTracking.isNotEmpty) {
        final saleTracking = saleTrackingMap[saleId] ?? '';
        if (saleTracking.isNotEmpty && saleTracking != bostaTracking) {
          rtoReshipped++;
          continue;
        }
      }
      rtoCorrect++;
    }

    if (unmatched > 0) _addFinding(_Severity.warning, 'Bosta', '$unmatched unmatched Bosta shipments', 'Shipments not linked to any sale — may affect AR calculations.');
    if (rtoReshipped > 0) _addFinding(_Severity.info, 'Bosta', '$rtoReshipped RTO shipments were re-shipped', 'These orders were delivered on retry — correctly excluded from RTO count.');
    _addFinding(_Severity.info, 'Bosta', 'Shipment breakdown', 'Total: $total | Delivered: $delivered | RTO: $rtoCorrect | Re-shipped: $rtoReshipped | In-transit: $inTransit | Unmatched: $unmatched');
  }

  // ── 5. Bosta Cashouts Audit ──────────────────────────────
  void _auditBostaCashouts() {
    _setStatus('Auditing Bosta cashouts...');
    _checksRun++;

    if (_cashoutDocs.isEmpty) return;

    double totalCashouts = 0;
    int futureDated = 0;
    int noAmount = 0;
    final now = DateTime.now();
    final idSet = <String>{};
    int dups = 0;

    for (final doc in _cashoutDocs) {
      final d = doc.data();
      final amount = _toDouble(d['amount']);
      final dateStr = d['transaction_date'] as String? ?? '';

      if (!idSet.add(doc.id)) dups++;
      if (amount == 0) noAmount++;
      totalCashouts += amount;

      final dt = DateTime.tryParse(dateStr);
      if (dt != null && dt.isAfter(now.add(const Duration(days: 1)))) futureDated++;
    }

    if (dups > 0) _addFinding(_Severity.error, 'Cashouts', '$dups duplicate cashout IDs', 'Duplicate cashouts inflate cash balance.');
    if (noAmount > 0) _addFinding(_Severity.warning, 'Cashouts', '$noAmount cashouts with zero amount', 'These have no cash impact but may indicate sync issues.');
    if (futureDated > 0) _addFinding(_Severity.warning, 'Cashouts', '$futureDated future-dated cashouts', 'Cash received in the future inflates current period balance.');

    final fmt = NumberFormat('#,##0.00', 'en');
    _addFinding(_Severity.info, 'Cashouts', 'Cashout summary: ${_cashoutDocs.length} records', 'Total: EGP ${fmt.format(totalCashouts)}');
  }

  // ── 6. Inventory Audit ───────────────────────────────────
  void _auditInventory() {
    _setStatus('Auditing inventory...');
    _checksRun++;

    if (_invDocs.isEmpty) return;

    int negativeStock = 0;
    int zeroCostWithStock = 0;
    double totalValue = 0;
    int totalSkus = 0;

    for (final doc in _invDocs) {
      final d = doc.data();
      final variants = d['variants'] as List<dynamic>? ?? [];

      for (final v in variants) {
        if (v is! Map) continue;
        totalSkus++;
        final stock = _toInt(v['current_stock']);
        final cost = _toDouble(v['cost_price']);

        if (stock < 0) negativeStock++;
        if (stock > 0 && cost == 0) zeroCostWithStock++;
        if (stock > 0) totalValue += stock * cost;
      }
    }

    if (negativeStock > 0) _addFinding(_Severity.error, 'Inventory', '$negativeStock SKUs with negative stock', 'Negative stock corrupts inventory valuation and COGS.');
    if (zeroCostWithStock > 0) _addFinding(_Severity.warning, 'Inventory', '$zeroCostWithStock SKUs with stock but zero cost', 'In-stock items with no cost undercount COGS and inflate gross profit.');

    final fmt = NumberFormat('#,##0.00', 'en');
    _addFinding(_Severity.info, 'Inventory', '$totalSkus total SKUs', 'Total inventory value: EGP ${fmt.format(totalValue)}');
  }

  // ── 7. Cash Balance Cross-Check ──────────────────────────
  void _auditCashBalance() {
    _setStatus('Cross-checking cash balance...');
    _checksRun++;

    final openingCash = _toDouble(_bsData['bank_balance']);

    double totalCashouts = 0;
    for (final doc in _cashoutDocs) {
      totalCashouts += _toDouble(doc.data()['amount']);
    }

    double txCashFlow = 0;
    const saleTxnCats = {'cat_sales_revenue', 'cat_cogs', 'cat_shipping'};
    const plExcluded = {'cat_investments', 'cat_loan_received', 'cat_loan_repayment', 'cat_equity_injection', 'cat_owner_withdrawal'};

    for (final doc in _txDocs) {
      final d = doc.data();
      final catId = d['category_id'] as String? ?? '';
      final saleId = d['sale_id'] as String?;
      final isIncome = d['is_income'] as bool? ?? false;
      final amount = _toDouble(d['amount']);
      final excludeFromPL = d['exclude_from_pl'] as bool? ?? false;
      final id = doc.id;

      if (saleId != null && saleTxnCats.contains(catId)) continue;
      if (id.startsWith('bosta_est_daily_') || id.startsWith('bosta_rec_daily_')) continue;

      bool include = false;
      if (catId == 'cat_supplier_payment') {
        include = true;
      } else if (plExcluded.contains(catId)) {
        include = true;
      } else if (!excludeFromPL) {
        include = true;
      }

      if (include) {
        txCashFlow += isIncome ? amount.abs() : -amount.abs();
      }
    }

    final computedCash = ((openingCash + totalCashouts + txCashFlow) * 100).roundToDouble() / 100;

    final fmt = NumberFormat('#,##0.00', 'en');
    _addFinding(_Severity.info, 'Cash', 'Cash balance breakdown',
        'Opening: EGP ${fmt.format(openingCash)} + Cashouts: EGP ${fmt.format(totalCashouts)} + Txn flow: EGP ${fmt.format(txCashFlow)} = EGP ${fmt.format(computedCash)}');
  }

  // ── 8. Balance Sheet Equation Audit ──────────────────────
  void _auditBalanceSheet() {
    _setStatus('Checking Balance Sheet equation...');
    _checksRun++;

    final bankBalance = _toDouble(_bsData['bank_balance']);
    final cashOnHand = _toDouble(_bsData['cash_on_hand']);
    final unpaidInvoices = _toDouble(_bsData['unpaid_invoices']);
    final loans = _toDouble(_bsData['loans']);
    final unpaidSalaries = _toDouble(_bsData['unpaid_salaries']);
    final openingCapital = _toDouble(_bsData['opening_capital']);
    final supplierAdvances = _toDouble(_bsData['supplier_advances']);

    double inventoryValue = 0;
    for (final doc in _invDocs) {
      final variants = doc.data()['variants'] as List<dynamic>? ?? [];
      for (final v in variants) {
        if (v is! Map) continue;
        final stock = _toInt(v['current_stock']);
        final cost = _toDouble(v['cost_price']);
        if (stock > 0) inventoryValue += stock * cost;
      }
    }

    final totalAssets = bankBalance + cashOnHand + unpaidInvoices + inventoryValue + supplierAdvances;
    final totalLiabilities = loans + unpaidSalaries;
    final equity = totalAssets - totalLiabilities;

    final fmt = NumberFormat('#,##0.00', 'en');
    _addFinding(_Severity.info, 'Balance Sheet', 'Assets = EGP ${fmt.format(totalAssets)}',
        'Bank: ${fmt.format(bankBalance)} | Cash: ${fmt.format(cashOnHand)} | AR: ${fmt.format(unpaidInvoices)} | Inventory: ${fmt.format(inventoryValue)} | Advances: ${fmt.format(supplierAdvances)}');
    _addFinding(_Severity.info, 'Balance Sheet', 'Liabilities = EGP ${fmt.format(totalLiabilities)}',
        'Loans: ${fmt.format(loans)} | Salaries: ${fmt.format(unpaidSalaries)}');
    _addFinding(_Severity.info, 'Balance Sheet', 'Equity = EGP ${fmt.format(equity)}',
        'Opening capital: ${fmt.format(openingCapital)} | Computed equity: ${fmt.format(equity)}');
  }

  // ── UI ───────────────────────────────────────────────────

  List<String> get _categories {
    final cats = _findings.map((f) => f.category).toSet().toList();
    cats.sort();
    return ['all', ...cats];
  }

  List<_Finding> get _filtered {
    if (_filterCategory == 'all') return _findings;
    return _findings.where((f) => f.category == _filterCategory).toList();
  }

  @override
  Widget build(BuildContext context) {
    final errors = _findings.where((f) => f.severity == _Severity.error).length;
    final warnings = _findings.where((f) => f.severity == _Severity.warning).length;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(errors, warnings),
            if (_loading) _buildProgress(),
            if (!_loading) _buildCategoryFilter(),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(child: Text('Running checks...', style: AppTypography.bodyMedium))
                  : _buildFindingsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(int errors, int warnings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => context.safePop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Data Integrity Audit',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                if (!_loading)
                  Text(
                    '$_checksRun checks · $errors errors · $warnings warnings',
                    style: AppTypography.caption,
                  ),
              ],
            ),
          ),
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 22),
              tooltip: 'Re-run audit',
              onPressed: () {
                setState(() {
                  _findings.clear();
                  _checksRun = 0;
                  _loading = true;
                  _filterCategory = 'all';
                });
                Future.microtask(_runFullAudit);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(_status, style: AppTypography.caption),
        ],
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = _categories[i];
          final selected = _filterCategory == cat;
          return GestureDetector(
            onTap: () => setState(() => _filterCategory = cat),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppColors.primaryNavy : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? AppColors.primaryNavy : AppColors.borderLight),
              ),
              child: Text(
                cat == 'all' ? 'All' : cat,
                style: AppTypography.labelSmall.copyWith(
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFindingsList() {
    final findings = _filtered;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      itemCount: findings.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildFindingCard(findings[i]),
    );
  }

  Widget _buildFindingCard(_Finding f) {
    final Color color;
    final IconData icon;
    switch (f.severity) {
      case _Severity.error:
        color = AppColors.chartRed;
        icon = Icons.error_rounded;
      case _Severity.warning:
        color = AppColors.accentOrange;
        icon = Icons.warning_amber_rounded;
      case _Severity.info:
        color = AppColors.primaryNavy;
        icon = Icons.info_outline_rounded;
      case _Severity.ok:
        color = const Color(0xFF10B981);
        icon = Icons.check_circle_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(f.category, style: AppTypography.captionSmall.copyWith(color: AppColors.textTertiary, fontSize: 10)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f.title,
                        style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  f.detail,
                  style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
