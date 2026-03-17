import 'package:flutter/material.dart';
import '../../../shared/models/category_data.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/sale_model.dart';
import 'widgets/transaction_filter_sheet.dart';
import 'widgets/sale_filter_sheet.dart';
import 'widgets/transaction_search_delegate.dart';
import '../../shared/widgets/async_value_widget.dart';
import 'package:go_router/go_router.dart';
import '../../shared/utils/safe_pop.dart';
import '../../core/services/shopify_sync_service.dart';
import '../../core/navigation/app_router.dart';
import '../shopify/providers/shopify_connection_provider.dart';

class TransactionsListScreen extends ConsumerStatefulWidget {
  final bool showBackButton;
  final TransactionFilter? initialFilter;
  final String? pageTitle;

  const TransactionsListScreen({
    super.key,
    this.showBackButton = false,
    this.initialFilter,
    this.pageTitle,
  });

  @override
  ConsumerState<TransactionsListScreen> createState() => _TransactionsListScreenState();
}

class _TransactionsListScreenState extends ConsumerState<TransactionsListScreen> {
  int _selectedPeriodIndex = 2; // "This Month" default
  TransactionFilter _filter = TransactionFilter.empty;
  SaleFilter _salesFilter = SaleFilter.empty;
  DateTimeRange? _customRange;
  int _tabIndex = 0; // 0 = All, 1 = Sales
  bool _isRefreshing = false;

  // ── Expanded sale groups (tracks which saleIds are expanded) ──
  final Set<String> _expandedSaleIds = {};

  // ── Bulk selection (Sales tab only) ────────────────────
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _shopifyBannerDismissed = false;

  final _periods = const ['All', 'This Week', 'This Month', 'Last Month', 'Custom'];

  final _scrollController = ScrollController();

  void _enterSelectionMode() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectionMode = true;
      _selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSaleSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<Sale> sales) {
    HapticFeedback.lightImpact();
    setState(() => _selectedIds.addAll(sales.map((s) => s.id)));
  }

  Future<void> _bulkMarkPaid(List<Sale> sales) async {
    final toUpdate = sales
        .where((s) => _selectedIds.contains(s.id) && s.paymentStatus != PaymentStatus.paid)
        .toList();
    _exitSelectionMode();
    if (toUpdate.isEmpty) return;
    
    final notifier = ref.read(salesProvider.notifier);
    final shopifyApi = ref.read(shopifyApiServiceProvider);
    
    for (final sale in toUpdate) {
      final updated = sale.copyWith(
        paymentStatus: PaymentStatus.paid,
        amountPaid: sale.total,
        updatedAt: DateTime.now(),
      );
      await notifier.updateSale(updated);
      
      // Sync to Shopify if linked
      if (sale.externalSource == 'shopify' && sale.externalOrderId != null) {
        shopifyApi.markOrderPaid(orderId: sale.externalOrderId!).then((result) {
          if (!mounted) return;
          if (!result.isSuccess && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Shopify payment sync failed for order: ${result.error}'),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
          }
        });
      }
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${toUpdate.length} sale${toUpdate.length != 1 ? 's' : ''} marked as paid'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _bulkCancel(List<Sale> sales) async {
    final toUpdate = sales
        .where((s) => _selectedIds.contains(s.id) && s.orderStatus != OrderStatus.cancelled)
        .toList();
    if (toUpdate.isEmpty) { _exitSelectionMode(); return; }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Orders'),
        content: Text('Cancel ${toUpdate.length} selected order${toUpdate.length != 1 ? 's' : ''}?\n\nThis will restore stock and create reversal accounting entries. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Go Back')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Cancel Orders'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    _exitSelectionMode();
    
    final now = DateTime.now();
    final notifier = ref.read(salesProvider.notifier);
    final transNotifier = ref.read(transactionsProvider.notifier);
    final inventoryNotifier = ref.read(inventoryProvider.notifier);
    final shopifyApi = ref.read(shopifyApiServiceProvider);
    
    final transactions = ref.read(transactionsProvider).value ?? [];

    final valMethod = ref.read(appSettingsProvider).valuationMethod;
    for (final sale in toUpdate) {
      // 1) Restore stock for each sale item
      for (final item in sale.items) {
        if (item.productId != null && item.quantity > 0) {
          inventoryNotifier.adjustStock(
            item.productId!,
            item.variantId ?? '${item.productId}_v0',
            item.quantity.toInt(),
            'Order cancelled',
            valuationMethod: valMethod,
          );
        }
      }

      // 2) Create reversal entries for linked transactions
      for (final tx in transactions) {
        if (tx.saleId == sale.id && tx.amount != 0) {
          // Mark original as cancelled (audit trail — keep original amount)
          transNotifier.updateTransaction(tx.copyWith(
            title: '[Cancelled] ${tx.title}',
            excludeFromPL: true,
            updatedAt: now,
          ));

          // Create reversal entry with negated amount
          final reversalId = '${tx.id}_reversal_${now.millisecondsSinceEpoch}';
          transNotifier.addTransaction(tx.copyWith(
            id: reversalId,
            title: '[Reversal] ${tx.title}',
            amount: -tx.amount,
            dateTime: now,
            note: 'Auto-reversal for cancelled order ${sale.id}',
            excludeFromPL: true,
            createdAt: now,
            updatedAt: now,
          ));
        }
      }

      // 3) Update sale to cancelled
      final cancelledSale = sale.copyWith(
        orderStatus: OrderStatus.cancelled,
        updatedAt: now,
      );
      await notifier.updateSale(cancelledSale);

      // 4) Cancel on Shopify if linked
      if (sale.externalSource == 'shopify' && sale.externalOrderId != null) {
        shopifyApi.cancelOrder(orderId: sale.externalOrderId!).then((result) {
          if (!mounted) return;
          if (!result.isSuccess && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Shopify cancel failed for order: ${result.error}'),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
          }
        });
      }
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${toUpdate.length} order${toUpdate.length != 1 ? 's' : ''} cancelled (stock & accounting reverted)'),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _refreshTransactions() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final futures = <Future>[
        ref.read(transactionsProvider.notifier).refreshAll(),
      ];
      if (_tabIndex == 1) {
        futures.add(ref.read(salesProvider.notifier).refreshAll());
      }
      await Future.wait(futures);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialFilter != null) {
      _filter = widget.initialFilter!;
    }
    _scrollController.addListener(_onScroll);
    // Load all pages so sale-related transactions (revenue/COGS) are
    // always visible regardless of which pagination page they fall on.
    Future.microtask(() {
      ref.read(transactionsProvider.notifier).loadAll();
      ref.read(salesProvider.notifier).loadAll();
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(transactionsProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<Transaction> get _allTransactions => ref.watch(transactionsProvider).value ?? [];

  /// Returns (from, to) bounds for the selected period pill.
  (DateTime?, DateTime?) get _periodBounds {
    final now = DateTime.now();
    switch (_selectedPeriodIndex) {
      case 0: // All
        return (null, null);
      case 1: // This Week — Mon … now
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return (DateTime(monday.year, monday.month, monday.day), now);
      case 2: // This Month
        return (DateTime(now.year, now.month, 1), now);
      case 3: // Last Month
        return (
          DateTime(now.year, now.month - 1, 1),
          DateTime(now.year, now.month, 0, 23, 59, 59),
        );
      case 4: // Custom
        if (_customRange != null) {
          return (
            _customRange!.start,
            DateTime(_customRange!.end.year, _customRange!.end.month, _customRange!.end.day, 23, 59, 59),
          );
        }
        return (null, null);
      default:
        return (null, null);
    }
  }

  /// Sales category IDs for the Sales tab
  static const _salesCategoryIds = {'cat_sales_revenue', 'cat_cogs'};

  List<Transaction> get _filteredTransactions {
    var list = List<Transaction>.from(_allTransactions);

    // Filter by sales tab
    if (_tabIndex == 1) {
      list = list.where((t) => _salesCategoryIds.contains(t.categoryId)).toList();
    }

    // Filter by period
    final (from, to) = _periodBounds;
    if (from != null) list = list.where((t) => !t.dateTime.isBefore(from)).toList();
    if (to != null)   list = list.where((t) => !t.dateTime.isAfter(to)).toList();

    // Filter by type
    if (_filter.type == TransactionType.income) {
      list = list.where((t) => t.isIncome).toList();
    } else if (_filter.type == TransactionType.expense) {
      list = list.where((t) => !t.isIncome).toList();
    }

    // Filter by amount range
    list = list.where((t) {
      final absAmount = t.amount.abs();
      return absAmount >= _filter.amountRange.start &&
          absAmount <= _filter.amountRange.end;
    }).toList();

    // Filter by categories (by ID)
    if (_filter.selectedCategories.isNotEmpty) {
      list = list
          .where((t) => _filter.selectedCategories.contains(t.categoryId))
          .toList();
    }

    // Filter by suppliers
    if (_filter.onlySuppliers) {
      list = list.where((t) => t.supplierId != null).toList();
    }

    // Sort by date descending
    list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return list;
  }

  /// Map from revenue transaction ID → list of child transactions (COGS, shipping)
  /// for the same sale, used to render expandable groups.
  Map<String, List<Transaction>> get _saleChildTransactions {
    final all = _filteredTransactions;
    // Build saleId → list of child txns (COGS + shipping)
    final childrenBySaleId = <String, List<Transaction>>{};
    for (final tx in all) {
      if (tx.saleId != null &&
          (tx.categoryId == 'cat_cogs' || tx.categoryId == 'cat_shipping')) {
        childrenBySaleId.putIfAbsent(tx.saleId!, () => []).add(tx);
      }
    }
    // Map revenue tx ID → children
    final result = <String, List<Transaction>>{};
    for (final tx in all) {
      if (tx.saleId != null && tx.categoryId == 'cat_sales_revenue') {
        final children = childrenBySaleId[tx.saleId];
        if (children != null && children.isNotEmpty) {
          result[tx.id] = children;
        }
      }
    }
    return result;
  }

  Map<String, List<Transaction>> get _groupedTransactions {
    final map = <String, List<Transaction>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    // Hide sale-linked transactions from the list — they appear in the Sales tab.
    // Also hide COGS and shipping (they appear as expandable children).
    final displayList = _filteredTransactions
        .where((t) => t.saleId == null)
        .toList();

    for (final tx in displayList) {
      final txDate = DateTime(tx.dateTime.year, tx.dateTime.month, tx.dateTime.day);
      String label;
      if (txDate == today) {
        label = 'Today — ${_formatMonthDay(tx.dateTime)}';
      } else if (txDate == yesterday) {
        label = 'Yesterday — ${_formatMonthDay(tx.dateTime)}';
      } else {
        label = _formatMonthDay(tx.dateTime);
      }
      map.putIfAbsent(label, () => []).add(tx);
    }
    return map;
  }

  String _formatMonthDay(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  double get _totalIncome =>
      _filteredTransactions.where((t) => t.isIncome && !t.excludeFromPL).fold(0.0, (sum, t) => sum + t.amount);

  double get _totalExpenses =>
      _filteredTransactions.where((t) => !t.isIncome && !t.excludeFromPL).fold(0.0, (sum, t) => sum + t.amount.abs());

  double get _salesTotalRevenue =>
      _filteredTransactions.where((t) => t.categoryId == 'cat_sales_revenue' && !t.excludeFromPL).fold(0.0, (sum, t) => sum + t.amount.abs());

  double get _salesTotalCogs =>
      _filteredTransactions.where((t) => t.categoryId == 'cat_cogs' && !t.excludeFromPL).fold(0.0, (sum, t) => sum + t.amount.abs());

  // ─── Sales tab: render Sale objects directly ─────────
  List<Sale> get _filteredSales {
    var list = List<Sale>.from(ref.watch(salesProvider).value ?? []);
    // Filter by period
    final (from, to) = _periodBounds;
    if (from != null) list = list.where((s) => !s.date.isBefore(from)).toList();
    if (to != null)   list = list.where((s) => !s.date.isAfter(to)).toList();

    // Payment status filter
    if (_salesFilter.paymentStatus != null) {
      list = list.where((s) => s.paymentStatus == _salesFilter.paymentStatus).toList();
    }
    // Fulfillment status filter
    if (_salesFilter.fulfillmentStatus != null) {
      list = list.where((s) => s.fulfillmentStatus == _salesFilter.fulfillmentStatus).toList();
    }
    // Amount range filter
    list = list.where((s) {
      final amt = s.total;
      return amt >= _salesFilter.amountRange.start &&
          amt <= _salesFilter.amountRange.end;
    }).toList();

    // Sort by date descending
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  Map<String, List<Sale>> get _groupedSales {
    final map = <String, List<Sale>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    for (final s in _filteredSales) {
      final d = DateTime(s.date.year, s.date.month, s.date.day);
      String label;
      if (d == today) {
        label = 'Today — ${_formatMonthDay(s.date)}';
      } else if (d == yesterday) {
        label = 'Yesterday — ${_formatMonthDay(s.date)}';
      } else {
        label = _formatMonthDay(s.date);
      }
      map.putIfAbsent(label, () => []).add(s);
    }
    return map;
  }

  void _openFilter() async {
    HapticFeedback.lightImpact();
    if (_tabIndex == 1) {
      final result = await showModalBottomSheet<SaleFilter>(
        useRootNavigator: true,
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => SaleFilterSheet(initialFilter: _salesFilter),
      );
      if (result != null) {
        setState(() => _salesFilter = result);
      }
    } else {
      final result = await showModalBottomSheet<TransactionFilter>(
        useRootNavigator: true,
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => TransactionFilterSheet(initialFilter: _filter),
      );
      if (result != null) {
        setState(() => _filter = result);
      }
    }
  }

  void _openSearch() {
    HapticFeedback.lightImpact();
    showSearch(
      context: context,
      delegate: TransactionSearchDelegate(
          transactions: _allTransactions,
          currency: ref.read(appSettingsProvider).currency),
    );
  }

  // ── Swipe action handlers ──────────────────────────────

  void _editTransaction(Transaction tx) {
    HapticFeedback.lightImpact();
    context.pushNamed('EditTransactionScreen', extra: {'transaction': tx});
  }

  void _duplicateTransaction(Transaction tx) {
    HapticFeedback.lightImpact();
    final dup = tx.copyWith(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dateTime: DateTime.now(),
      createdAt: DateTime.now(),
      saleId: null,
    );
    ref.read(transactionsProvider.notifier).addTransaction(dup);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Transaction duplicated'),
          backgroundColor: AppColors.primaryNavy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  void _deleteTransaction(Transaction tx) {
    HapticFeedback.mediumImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Transaction', style: AppTypography.h3),
        content: const Text('Are you sure you want to delete this transaction?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final deleted = tx;
              ref.read(transactionsProvider.notifier).removeTransaction(tx.id);
              Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Transaction deleted'),
                    backgroundColor: AppColors.primaryNavy,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    action: SnackBarAction(
                      label: 'Undo',
                      textColor: AppColors.accentOrange,
                      onPressed: () {
                        ref
                            .read(transactionsProvider.notifier)
                            .addTransaction(deleted);
                      },
                    ),
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _onTransactionTap(Transaction tx) {
    HapticFeedback.lightImpact();

    // If this transaction is linked to a sale/order, open the order detail
    if (_navigateToSaleIfLinked(tx)) return;

    context.pushNamed('TransactionDetailScreen', extra: {'transaction': tx});
  }

  /// Returns true if we navigated to a sale detail screen.
  bool _navigateToSaleIfLinked(Transaction tx) {
    final sales = ref.read(salesProvider).value ?? [];

    // 1) Direct saleId link
    if (tx.saleId != null) {
      for (final s in sales) {
        if (s.id == tx.saleId) {
          context.pushNamed('SaleDetailScreen', extra: {'sale': s});
          return true;
        }
      }
    }

    // 2) Sale-category transactions
    if (tx.categoryId == 'cat_sales_revenue' ||
        tx.categoryId == 'cat_cogs' ||
        tx.categoryId == 'cat_shipping') {
      // 2a) Extract saleId from tx ID pattern
      String? extractedId;
      if (tx.id.startsWith('sale_rev_')) {
        extractedId = tx.id.substring('sale_rev_'.length);
      } else if (tx.id.startsWith('sale_cogs_')) {
        extractedId = tx.id.substring('sale_cogs_'.length);
      } else if (tx.id.startsWith('sale_ship_')) {
        extractedId = tx.id.substring('sale_ship_'.length);
      }
      if (extractedId != null) {
        for (final s in sales) {
          if (s.id == extractedId) {
            context.pushNamed('SaleDetailScreen', extra: {'sale': s});
            return true;
          }
        }
      }

      // 2b) Fallback: match by amount + date
      if (tx.categoryId == 'cat_sales_revenue') {
        for (final s in sales) {
          if (s.total == tx.amount &&
              s.date.year == tx.dateTime.year &&
              s.date.month == tx.dateTime.month &&
              s.date.day == tx.dateTime.day) {
            context.pushNamed('SaleDetailScreen', extra: {'sale': s});
            return true;
          }
        }
      }
      if (tx.categoryId == 'cat_cogs') {
        for (final s in sales) {
          if (-s.totalCogs == tx.amount &&
              s.date.year == tx.dateTime.year &&
              s.date.month == tx.dateTime.month &&
              s.date.day == tx.dateTime.day) {
            context.pushNamed('SaleDetailScreen', extra: {'sale': s});
            return true;
          }
        }
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: AsyncValueWidget<List<Transaction>>(
          value: transactionsAsync,
          onRetry: () => ref.read(transactionsProvider.notifier).refresh(),
          data: (_) {
            return Column(
              children: [
                _buildHeader(),
                _buildTabToggle(),
                _buildPeriodPills(),
                _tabIndex == 0 ? _buildSummaryBar() : _buildSalesSummaryBar(),
                Expanded(child: _tabIndex == 0
                    ? _buildTransactionsList()
                    : _buildSalesList()),
              ],
            );
          },
          loading: () => Column(
            children: [
              _buildHeader(), // Keep header visible while loading
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  TAB TOGGLE (All / Sales)
  // ═══════════════════════════════════════════════════
  Widget _buildTabToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _buildTabItem('All Transactions', 0),
            const SizedBox(width: 4),
            _buildTabItem('Sales', 1),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(String label, int index) {
    final isActive = _tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _tabIndex = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (index == 1) ...[
                Icon(
                  Icons.shopping_bag_rounded,
                  size: 14,
                  color: isActive ? AppColors.accentOrange : AppColors.textTertiary,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? AppColors.textPrimary : AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  SALES SUMMARY BAR
  // ═══════════════════════════════════════════════════
  Widget _buildSalesSummaryBar() {
    final currency = ref.watch(appSettingsProvider).currency;
    final revenue = _salesTotalRevenue;
    final cogs = _salesTotalCogs;
    final grossProfit = revenue - cogs;
    final fmtNum = NumberFormat('#,##0.00', 'en');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Revenue
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Revenue',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currency ${fmtNum.format(revenue)}',
                    style: AppTypography.h3.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 36, color: AppColors.borderLight),
            // COGS
            Expanded(
              child: Column(
                children: [
                  Text(
                    'COGS',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currency ${fmtNum.format(cogs)}',
                    style: AppTypography.h3.copyWith(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Container(width: 1, height: 36, color: AppColors.borderLight),
            // Gross Profit
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Gross Profit',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currency ${fmtNum.format(grossProfit)}',
                    style: AppTypography.h3.copyWith(
                      color: grossProfit >= 0 ? const Color(0xFF16A34A) : AppColors.danger,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  // ═══════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════
  Widget _buildHeader() {
    // ── Selection mode header (Sales tab only) ────────────
    if (_selectionMode && _tabIndex == 1) {
      final allSales = _filteredSales;
      final allSelected = allSales.isNotEmpty &&
          allSales.every((s) => _selectedIds.contains(s.id));
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryNavy, const Color(0xFF1E293B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryNavy.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: _exitSelectionMode,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedIds.isEmpty ? 'Select orders' : '${_selectedIds.length} Selected',
                      style: AppTypography.h3.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (_selectedIds.isNotEmpty)
                      Text(
                        'Ready for bulk actions',
                        style: AppTypography.captionSmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: allSelected
                    ? () => setState(() => _selectedIds.clear())
                    : () => _selectAll(allSales),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: allSelected ? Colors.white.withValues(alpha: 0.15) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    allSelected ? 'Deselect All' : 'Select All',
                    style: AppTypography.labelSmall.copyWith(
                      color: allSelected ? Colors.white : AppColors.primaryNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Normal header ─────────────────────────────────────
    final hasBack = widget.showBackButton;
    return Padding(
      padding: EdgeInsets.fromLTRB(hasBack ? 8 : 20, 8, 12, 4),
      child: Row(
        children: [
          if (hasBack)
            IconButton(
              onPressed: () => context.safePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.primaryNavy,
            ),
          // Title
          Expanded(
            child: Text(
              widget.pageTitle ?? 'Transactions',
              style: AppTypography.h1.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          
          // Action buttons
          Row(
            children: [
              // Checklist icon — only visible on the Sales tab
              if (_tabIndex == 1)
                _headerButton(Icons.checklist_rounded, _enterSelectionMode),
              _isRefreshing
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primaryNavy,
                        ),
                      ),
                    )
                  : _headerButton(Icons.refresh_rounded, () {
                      HapticFeedback.lightImpact();
                      _refreshTransactions();
                    }),
              const SizedBox(width: 2),
              _headerButton(Icons.search_rounded, _openSearch),
              const SizedBox(width: 2),
              Builder(builder: (ctx) {
                final isActive = _tabIndex == 1
                    ? !_salesFilter.isDefault
                    : !_filter.isDefault;
                final count = _tabIndex == 1
                    ? _salesFilter.activeCount
                    : _filter.activeCount;
                return Stack(
                  children: [
                    _headerButton(Icons.filter_list_rounded, _openFilter),
                    if (isActive)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppColors.accentOrange,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.backgroundLight, width: 2),
                          ),
                          child: Center(
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(50),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: AppColors.textSecondary, size: 24),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  PERIOD PILLS
  // ═══════════════════════════════════════════════════
  Widget _buildPeriodPills() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        itemCount: _periods.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final isSelected = _selectedPeriodIndex == index;
          return GestureDetector(
            onTap: () async {
              HapticFeedback.lightImpact();
              if (index == 4) {
                // Custom — show date range picker
                final range = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: _customRange,
                  builder: (ctx, child) => Theme(
                    data: Theme.of(ctx).copyWith(
                      colorScheme: const ColorScheme.light(
                        primary: AppColors.accentOrange,
                        onPrimary: Colors.white,
                        surface: Colors.white,
                        onSurface: AppColors.textPrimary,
                      ),
                    ),
                    child: child!,
                  ),
                );
                if (range != null) {
                  setState(() {
                    _customRange = range;
                    _selectedPeriodIndex = 4;
                  });
                }
              } else {
                setState(() => _selectedPeriodIndex = index);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accentOrange : Colors.white,
                borderRadius: BorderRadius.circular(50),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.accentOrange.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Center(
                child: Text(
                  _periods[index],
                  style: AppTypography.labelMedium.copyWith(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  SUMMARY BAR
  // ═══════════════════════════════════════════════════
  Widget _buildSummaryBar() {
    final currency = ref.watch(appSettingsProvider).currency;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Income
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Income',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '+$currency ${NumberFormat('#,##0.00', 'en').format(_totalIncome)}',
                    style: AppTypography.h3.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 36,
              color: AppColors.borderLight,
            ),
            // Expenses
            Expanded(
              child: Column(
                children: [
                  Text(
                    'Expenses',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '-$currency ${NumberFormat('#,##0.00', 'en').format(_totalExpenses)}',
                    style: AppTypography.h3.copyWith(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.1, end: 0);
  }

  // ═══════════════════════════════════════════════════
  //  TRANSACTIONS LIST (Grouped by date)
  // ═══════════════════════════════════════════════════
  Widget _buildTransactionsList() {
    final groups = _groupedTransactions;

    if (groups.isEmpty) {
      return _buildEmptyState();
    }

    final items = <Widget>[];
    int animIndex = 0;

    for (final entry in groups.entries) {
      // Sticky date header
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            entry.key.toUpperCase(),
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              fontSize: 11,
            ),
          ),
        ),
      );

      // Transaction tiles
      final saleChildren = _saleChildTransactions;
      for (final tx in entry.value) {
        final i = animIndex++;
        final isSaleRevenue = tx.categoryId == 'cat_sales_revenue';
        final children = isSaleRevenue ? saleChildren[tx.id] : null;
        final hasChildren = children != null && children.isNotEmpty;

        if (isSaleRevenue && hasChildren) {
          // Expandable sale group
          final isExpanded = _expandedSaleIds.contains(tx.saleId ?? tx.id);
          items.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _SaleGroupTile(
                revenueTransaction: tx,
                childTransactions: children,
                isExpanded: isExpanded,
                onToggleExpand: () {
                  setState(() {
                    final key = tx.saleId ?? tx.id;
                    if (_expandedSaleIds.contains(key)) {
                      _expandedSaleIds.remove(key);
                    } else {
                      _expandedSaleIds.add(key);
                    }
                  });
                },
                onTap: () => _onTransactionTap(tx),
              ),
            )
                .animate()
                .fadeIn(
                  duration: 350.ms,
                  delay: Duration(milliseconds: 50 * i),
                )
                .slideX(
                  begin: 0.05,
                  end: 0,
                  duration: 350.ms,
                  delay: Duration(milliseconds: 50 * i),
                  curve: Curves.easeOutCubic,
                ),
          );
        } else if (isSaleRevenue) {
          // Sale revenue with no children — plain tile
          items.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _TransactionTile(
                transaction: tx,
                onTap: () => _onTransactionTap(tx),
              ),
            )
                .animate()
                .fadeIn(
                  duration: 350.ms,
                  delay: Duration(milliseconds: 50 * i),
                )
                .slideX(
                  begin: 0.05,
                  end: 0,
                  duration: 350.ms,
                  delay: Duration(milliseconds: 50 * i),
                  curve: Curves.easeOutCubic,
                ),
          );
        } else {
          items.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _SwipeActionTile(
                transaction: tx,
                onTap: () => _onTransactionTap(tx),
                onEdit: () => _editTransaction(tx),
                onDuplicate: () => _duplicateTransaction(tx),
                onDelete: () => _deleteTransaction(tx),
              ),
            )
                .animate()
                .fadeIn(
                  duration: 350.ms,
                  delay: Duration(milliseconds: 50 * i),
                )
                .slideX(
                  begin: 0.05,
                  end: 0,
                  duration: 350.ms,
                  delay: Duration(milliseconds: 50 * i),
                  curve: Curves.easeOutCubic,
                ),
          );
        }
      }
    }

    // Check if we're currently loading more
    final isPageLoading = ref.watch(transactionsProvider.notifier).hasMore;
    
    if (isPageLoading) {
      items.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshTransactions,
      child: ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 100, top: 8),
        children: items,
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  SALES LIST (Grouped by date — renders Sale objects)
  // ═══════════════════════════════════════════════════
  Widget _buildSalesList() {
    final salesAsync = ref.watch(salesProvider);

    // Show loading spinner while sales are loading
    if (salesAsync.isLoading && (salesAsync.value == null || salesAsync.value!.isEmpty)) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show error if sales failed to load
    if (salesAsync.hasError && (salesAsync.value == null || salesAsync.value!.isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.danger),
            const SizedBox(height: 12),
            Text('Failed to load sales', style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(salesProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final groups = _groupedSales;
    final allFilteredSales = _filteredSales;

    // ── Shopify banner (shows even when sales list is empty) ──
    Widget? shopifyBanner;
    if (!_shopifyBannerDismissed) {
      final tier = ref.watch(tierProvider);
      final isGrowth = tier.isGrowthOrAbove;
      final shopifyActive = ref.watch(shopifyConnectionProvider).value?.isActive ?? false;

      if (isGrowth && !shopifyActive) {
        shopifyBanner = _ShopifyBanner(
          title: 'Connect your Shopify store',
          subtitle: 'Sync orders, inventory & products automatically.',
          actionLabel: 'Connect Shopify',
          onAction: () => context.push(AppRoutes.shopifySetupWizard),
          onDismiss: () => setState(() => _shopifyBannerDismissed = true),
        );
      } else if (!isGrowth) {
        shopifyBanner = _ShopifyBanner(
          title: 'Shopify Integration',
          subtitle: 'Sync your Shopify store with Masari. Available on Growth Mode.',
          actionLabel: 'Upgrade to Growth',
          isUpgrade: true,
          onAction: () => context.push('/profile/subscription'),
          onDismiss: () => setState(() => _shopifyBannerDismissed = true),
        );
      }
    }

    if (groups.isEmpty) {
      return Column(
        children: [
          ?shopifyBanner,
          Expanded(child: _buildEmptyState()),
        ],
      );
    }

    final currency = ref.watch(appSettingsProvider).currency;
    final fmt = NumberFormat('#,##0.00', 'en');
    final items = <Widget>[];
    int animIndex = 0;

    // Build a map of saleId → child transactions for expandable breakdown
    final allTxns = ref.watch(transactionsProvider).value ?? [];
    final saleTxnMap = <String, List<Transaction>>{};
    for (final tx in allTxns) {
      if (tx.saleId != null) {
        saleTxnMap.putIfAbsent(tx.saleId!, () => []).add(tx);
      }
    }

    if (shopifyBanner != null) {
      items.add(shopifyBanner);
    }

    for (final entry in groups.entries) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            entry.key.toUpperCase(),
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              fontSize: 11,
            ),
          ),
        ),
      );

      for (final sale in entry.value) {
        final i = animIndex++;
        final saleTxns = saleTxnMap[sale.id] ?? [];
        final isExpanded = _expandedSaleIds.contains(sale.id);
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              children: [
                _SaleTileWithExpand(
                  sale: sale,
                  currency: currency,
                  fmt: fmt,
                  selectionMode: _selectionMode,
                  isSelected: _selectedIds.contains(sale.id),
                  onToggle: () => _toggleSaleSelection(sale.id),
                  hasChildren: saleTxns.isNotEmpty,
                  isExpanded: isExpanded,
                  onToggleExpand: saleTxns.isNotEmpty
                      ? () {
                          setState(() {
                            if (_expandedSaleIds.contains(sale.id)) {
                              _expandedSaleIds.remove(sale.id);
                            } else {
                              _expandedSaleIds.add(sale.id);
                            }
                          });
                        }
                      : null,
                  onTap: _selectionMode
                      ? () => _toggleSaleSelection(sale.id)
                      : () {
                          HapticFeedback.lightImpact();
                          context.pushNamed('SaleDetailScreen', extra: {'sale': sale});
                        },
                  onLongPress: _selectionMode ? null : _enterSelectionMode,
                ),
                if (isExpanded)
                  ...saleTxns.map((tx) => _SaleChildRow(
                        transaction: tx,
                        currency: currency,
                      )),
              ],
            ),
          )
              .animate()
              .fadeIn(
                duration: 350.ms,
                delay: Duration(milliseconds: 50 * i),
              )
              .slideX(
                begin: 0.05,
                end: 0,
                duration: 350.ms,
                delay: Duration(milliseconds: 50 * i),
                curve: Curves.easeOutCubic,
              ),
        );
      }
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _refreshTransactions,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics()),
            padding: EdgeInsets.only(bottom: _selectionMode ? 100 : 100, top: 8),
            children: items,
          ),
        ),
        // Bulk action bar — slides up when in selection mode
        if (_selectionMode)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _SalesBulkActionBar(
              selectedCount: _selectedIds.length,
              onMarkPaid: () => _bulkMarkPaid(allFilteredSales),
              onCancel: () => _bulkCancel(allFilteredSales),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentOrange.withValues(alpha: 0.08),
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 36,
              color: AppColors.accentOrange.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Transactions Found',
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters or period',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }
}

// ═══════════════════════════════════════════════════════════
//  TRANSACTION TILE WIDGET
// ═══════════════════════════════════════════════════════════
class _TransactionTile extends ConsumerWidget {
  final Transaction transaction;
  final VoidCallback onTap;

  const _TransactionTile({
    required this.transaction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider).value ?? [];
    final currency = ref.watch(appSettingsProvider).currency;
    final category = categories.firstWhere(
      (c) => c.id == transaction.categoryId,
      orElse: () => CategoryData.findById(transaction.categoryId),
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Category icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: category.displayBgColor,
                ),
                child: Icon(
                  category.iconData,
                  color: category.displayColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),

              // Title + category badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.title,
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: transaction.isIncome
                            ? AppColors.accentOrange.withValues(alpha: 0.08)
                            : AppColors.backgroundLight,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(
                        category.name,
                        style: AppTypography.captionSmall.copyWith(
                          color: transaction.isIncome
                              ? AppColors.accentOrange
                              : AppColors.textTertiary,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Amount + time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    transaction.formattedAmountWith(currency),
                    style: AppTypography.labelLarge.copyWith(
                      color: transaction.isIncome
                          ? AppColors.success
                          : AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    transaction.formattedTime,
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
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
}

// ═══════════════════════════════════════════════════════════
//  SWIPE-ACTION TRANSACTION TILE
// ═══════════════════════════════════════════════════════════

/// Wraps a [_TransactionTile] with iOS-style swipe-to-reveal actions.
/// Swipe left to reveal Edit, Duplicate, and Delete buttons.
class _SwipeActionTile extends StatefulWidget {
  final Transaction transaction;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const _SwipeActionTile({
    required this.transaction,
    required this.onTap,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  State<_SwipeActionTile> createState() => _SwipeActionTileState();
}

class _SwipeActionTileState extends State<_SwipeActionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _slideAnimation;

  /// Total width of the revealed action buttons.
  static const double _actionsWidth = 180;

  double _dragStart = 0;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slideAnimation = Tween<double>(begin: 0, end: -_actionsWidth).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragStart = _slideAnimation.value;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0;
    final newValue = (_dragStart + delta).clamp(-_actionsWidth, 0.0);
    _controller.value = newValue / -_actionsWidth;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -300) {
      // Fast swipe left → open
      _controller.forward();
      _isOpen = true;
    } else if (velocity > 300) {
      // Fast swipe right → close
      _controller.reverse();
      _isOpen = false;
    } else {
      // Settle based on position
      if (_controller.value > 0.4) {
        _controller.forward();
        _isOpen = true;
      } else {
        _controller.reverse();
        _isOpen = false;
      }
    }
  }

  void _close() {
    _controller.reverse();
    _isOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 76,
        child: Stack(
          children: [
            // ── Action buttons (behind) ──
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _actionButton(
                    icon: Icons.edit_rounded,
                    label: 'Edit',
                    color: AppColors.primaryNavy,
                    onTap: () {
                      _close();
                      widget.onEdit();
                    },
                  ),
                  _actionButton(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    color: const Color(0xFF6366F1),
                    onTap: () {
                      _close();
                      widget.onDuplicate();
                    },
                  ),
                  _actionButton(
                    icon: Icons.delete_rounded,
                    label: 'Delete',
                    color: AppColors.danger,
                    onTap: () {
                      _close();
                      widget.onDelete();
                    },
                  ),
                ],
              ),
            ),

            // ── Foreground tile (slides left) ──
            AnimatedBuilder(
              animation: _slideAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_slideAnimation.value, 0),
                  child: child,
                );
              },
              child: GestureDetector(
                onHorizontalDragStart: _onHorizontalDragStart,
                onHorizontalDragUpdate: _onHorizontalDragUpdate,
                onHorizontalDragEnd: _onHorizontalDragEnd,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _TransactionTile(
                    transaction: widget.transaction,
                    onTap: () {
                      if (_isOpen) {
                        _close();
                      } else {
                        widget.onTap();
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _actionsWidth / 3,
        color: color,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTypography.captionSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  SALE TILE WIDGET (for Sales tab — renders Sale objects directly)
// ═══════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════
//  BULK ACTION BAR
// ═══════════════════════════════════════════════════════════
class _SalesBulkActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onMarkPaid;
  final VoidCallback onCancel;

  const _SalesBulkActionBar({
    required this.selectedCount,
    required this.onMarkPaid,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPad == 0 ? 20 : bottomPad + 8),
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryNavy.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
          // Mark as Paid
          Expanded(
            child: GestureDetector(
              onTap: selectedCount > 0 ? onMarkPaid : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selectedCount > 0
                      ? AppColors.success
                      : AppColors.success.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      'Mark as Paid',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Cancel Orders
          Expanded(
            child: GestureDetector(
              onTap: selectedCount > 0 ? onCancel : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selectedCount > 0
                      ? AppColors.danger
                      : AppColors.danger.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cancel_rounded, size: 18, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      'Cancel',
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ))
        .animate()
        .slideY(begin: 1.0, duration: 220.ms, curve: Curves.easeOut)
        .fadeIn(duration: 180.ms);
  }
}

// ═══════════════════════════════════════════════════
//  SHOPIFY ANNOUNCEMENT BANNER
// ═══════════════════════════════════════════════════
class _ShopifyBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final bool isUpgrade;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  const _ShopifyBanner({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    required this.onDismiss,
    this.isUpgrade = false,
  });

  @override
  Widget build(BuildContext context) {
    const shopifyGreen = Color(0xFF96BF48);
    final accentColor = isUpgrade ? AppColors.accentOrange : shopifyGreen;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              accentColor.withValues(alpha: 0.08),
              accentColor.withValues(alpha: 0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accentColor.withValues(alpha: 0.25)),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 40, 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.store_rounded,
                      color: accentColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            if (isUpgrade) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.accentOrange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'GROWTH',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.accentOrange,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: onAction,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  actionLabel,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward_rounded, size: 14, color: Colors.white),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: onDismiss,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded, size: 14, color: AppColors.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  EXPANDABLE SALE GROUP TILE (All Transactions tab)
// ═══════════════════════════════════════════════════════════

/// Shows a revenue transaction with an expand chevron.
/// When expanded, reveals COGS and shipping child rows.
class _SaleGroupTile extends ConsumerWidget {
  final Transaction revenueTransaction;
  final List<Transaction> childTransactions;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onTap;

  const _SaleGroupTile({
    required this.revenueTransaction,
    required this.childTransactions,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(appSettingsProvider).currency;
    final categories = ref.watch(categoriesProvider).value ?? [];
    final category = categories.firstWhere(
      (c) => c.id == revenueTransaction.categoryId,
      orElse: () => CategoryData.findById(revenueTransaction.categoryId),
    );

    return Column(
      children: [
        // Main revenue row
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Category icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: category.displayBgColor,
                    ),
                    child: Icon(
                      category.iconData,
                      color: category.displayColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Title + category badge
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          revenueTransaction.title,
                          style: AppTypography.labelLarge.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accentOrange.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text(
                            category.name,
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.accentOrange,
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Amount + time
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        revenueTransaction.formattedAmountWith(currency),
                        style: AppTypography.labelLarge.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        revenueTransaction.formattedTime,
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  // Expand chevron
                  GestureDetector(
                    onTap: onToggleExpand,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Expanded children
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: childTransactions
                .map((tx) => _SaleChildRow(transaction: tx, currency: currency))
                .toList(),
          ),
          crossFadeState:
              isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  SALE CHILD ROW (COGS / Shipping sub-item)
// ═══════════════════════════════════════════════════════════

class _SaleChildRow extends StatelessWidget {
  final Transaction transaction;
  final String currency;

  const _SaleChildRow({
    required this.transaction,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final category = CategoryData.findById(transaction.categoryId);
    final isExpense = transaction.amount < 0;

    return Padding(
      padding: const EdgeInsets.only(left: 40, right: 8, top: 2, bottom: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.backgroundLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.borderLight.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: category.displayBgColor,
              ),
              child: Icon(category.iconData, size: 16, color: category.displayColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                category.name,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              transaction.formattedAmountWith(currency),
              style: AppTypography.labelMedium.copyWith(
                color: isExpense ? AppColors.danger : AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Fulfillment status helpers
// ═══════════════════════════════════════════════════════════

Color _fulfillmentColor(FulfillmentStatus s) {
  switch (s) {
    case FulfillmentStatus.fulfilled:
      return AppColors.success;
    case FulfillmentStatus.partial:
      return AppColors.warning;
    case FulfillmentStatus.unfulfilled:
      return AppColors.textTertiary;
  }
}

String _fulfillmentLabel(FulfillmentStatus s) {
  switch (s) {
    case FulfillmentStatus.fulfilled:
      return 'Fulfilled';
    case FulfillmentStatus.partial:
      return 'Partial Ship';
    case FulfillmentStatus.unfulfilled:
      return 'Unfulfilled';
  }
}

// ═══════════════════════════════════════════════════════════
//  SALE TILE WITH EXPAND (Sales tab)
// ═══════════════════════════════════════════════════════════

class _SaleTileWithExpand extends StatelessWidget {
  final Sale sale;
  final String currency;
  final NumberFormat fmt;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onToggle;
  final bool hasChildren;
  final bool isExpanded;
  final VoidCallback? onToggleExpand;

  const _SaleTileWithExpand({
    required this.sale,
    required this.currency,
    required this.fmt,
    required this.onTap,
    this.onLongPress,
    this.selectionMode = false,
    this.isSelected = false,
    required this.onToggle,
    required this.hasChildren,
    required this.isExpanded,
    this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final isCancelled = sale.orderStatus == OrderStatus.cancelled;

    Color statusColor;
    String statusLabel;
    switch (sale.paymentStatus) {
      case PaymentStatus.paid:
        statusColor = AppColors.success;
        statusLabel = 'Paid';
        break;
      case PaymentStatus.refunded:
        statusColor = AppColors.danger;
        statusLabel = 'Refunded';
        break;
      case PaymentStatus.partial:
        statusColor = AppColors.warning;
        statusLabel = 'Partial';
        break;
      case PaymentStatus.unpaid:
        statusColor = AppColors.danger;
        statusLabel = 'Unpaid';
        break;
    }

    Color borderColor;
    Color cardColor;
    if (isSelected) {
      borderColor = AppColors.primaryNavy;
      cardColor = AppColors.primaryNavy.withValues(alpha: 0.04);
    } else if (isCancelled) {
      borderColor = AppColors.danger.withValues(alpha: 0.2);
      cardColor = const Color(0xFFFEFCFC);
    } else {
      borderColor = AppColors.borderLight.withValues(alpha: 0.4);
      cardColor = Colors.white;
    }

    // Build subtitle parts: customer • items • time
    final subtitleParts = <String>[];
    if ((sale.shopifyOrderNumber != null || sale.orderNumber != null) &&
        sale.customerName != null) {
      subtitleParts.add(sale.customerName!);
    }
    final itemCount = sale.items.length;
    subtitleParts.add('$itemCount ${itemCount == 1 ? 'item' : 'items'}');
    subtitleParts.add(DateFormat('h:mm a').format(sale.date));

    // Title text
    final titleText = sale.displayOrderTitle;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selection checkbox
            if (selectionMode) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primaryNavy : Colors.white,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primaryNavy
                          : AppColors.borderLight,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded,
                          size: 15, color: Colors.white)
                      : null,
                ),
              ),
            ],
            // Main content — vertical Shopify-style layout
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Title + Amount + Chevron
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          titleText,
                          style: AppTypography.labelLarge.copyWith(
                            color: isCancelled
                                ? AppColors.textTertiary
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$currency ${fmt.format(sale.total)}',
                        style: AppTypography.labelLarge.copyWith(
                          color: isCancelled
                              ? AppColors.textTertiary
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          decoration:
                              isCancelled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      // Chevron next to amount
                      if (hasChildren && !selectionMode) ...[
                        const SizedBox(width: 2),
                        GestureDetector(
                          onTap: onToggleExpand,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: AnimatedRotation(
                              turns: isExpanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: AppColors.textTertiary.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  // Row 2: Subtitle — customer • items • time
                  Text(
                    subtitleParts.join(' \u2022 '),
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // Row 3: Status badges
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (sale.isCompleted)
                              _StatusBadge(
                                label: 'Completed',
                                variant: _BadgeVariant.success,
                              )
                            else ...[
                              if (isCancelled)
                                _StatusBadge(
                                  label: 'Cancelled',
                                  variant: _BadgeVariant.critical,
                                )
                              else ...[
                                // Fulfillment badge
                                _StatusBadge(
                                  label: _fulfillmentLabel(sale.fulfillmentStatus),
                                  variant: sale.fulfillmentStatus == FulfillmentStatus.fulfilled
                                      ? _BadgeVariant.neutral
                                      : sale.fulfillmentStatus == FulfillmentStatus.partial
                                          ? _BadgeVariant.attention
                                          : _BadgeVariant.info,
                                ),
                                // Payment badge
                                _StatusBadge(
                                  label: sale.paymentStatus == PaymentStatus.unpaid
                                      ? 'Payment pending'
                                      : sale.paymentStatus == PaymentStatus.refunded
                                          ? 'Refunded'
                                          : statusLabel,
                                  variant: sale.paymentStatus == PaymentStatus.paid
                                      ? _BadgeVariant.success
                                      : sale.paymentStatus == PaymentStatus.unpaid
                                          ? _BadgeVariant.warning
                                          : sale.paymentStatus == PaymentStatus.refunded
                                              ? _BadgeVariant.critical
                                              : _BadgeVariant.attention,
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Badge visual variants matching Shopify's Polaris badge system.
enum _BadgeVariant { neutral, info, success, attention, warning, critical }

/// Shopify Polaris-style status badge.
class _StatusBadge extends StatelessWidget {
  final String label;
  final _BadgeVariant variant;

  const _StatusBadge({
    required this.label,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    switch (variant) {
      case _BadgeVariant.neutral:
        // Shopify "Fulfilled" — dark text on light grey
        bgColor = const Color(0xFFE4E5E7);
        textColor = const Color(0xFF303030);
        break;
      case _BadgeVariant.info:
        // "Unfulfilled" — muted outline-style
        bgColor = const Color(0xFFEAF0F6);
        textColor = const Color(0xFF5C6AC4);
        break;
      case _BadgeVariant.success:
        // "Paid" / "Completed" — green tint
        bgColor = const Color(0xFFD4EDDA);
        textColor = const Color(0xFF1B7A3D);
        break;
      case _BadgeVariant.attention:
        // "Partial" — amber/gold
        bgColor = const Color(0xFFFFF3CD);
        textColor = const Color(0xFF856404);
        break;
      case _BadgeVariant.warning:
        // "Payment pending" — warm peach/orange
        bgColor = const Color(0xFFFFE8D4);
        textColor = const Color(0xFFB44C00);
        break;
      case _BadgeVariant.critical:
        // "Cancelled" / "Refunded" — red
        bgColor = const Color(0xFFFED3D1);
        textColor = const Color(0xFFCC2200);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          height: 1.2,
        ),
      ),
    );
  }
}
