import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/services/shopify_sync_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/models/sale_model.dart';
import '../../shared/widgets/async_value_widget.dart';
import '../shopify/providers/shopify_connection_provider.dart';
import '../shopify/widgets/shopify_reconnect_banner.dart';
import '../../shared/utils/safe_pop.dart';

/// Sales list screen (Growth tier).
class SalesListScreen extends ConsumerStatefulWidget {
  const SalesListScreen({super.key});

  @override
  ConsumerState<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends ConsumerState<SalesListScreen> {
  AppLocalizations get l10n => AppLocalizations.of(context)!;
  final _scrollCtrl = ScrollController();
  String _search = '';
  int _statusFilter = -1; // -1 = all
  String _sourceFilter = 'all'; // 'all', 'manual', 'shopify'
  bool _isRefreshing = false;

  // ── Bulk selection ──────────────────────────────────────
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  Future<void> _refreshSales() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      final futures = <Future>[
        ref.read(salesProvider.notifier).refresh(),
      ];
      final hasAccess = ref.read(hasShopifyAccessProvider);
      if (hasAccess) {
        final conn = ref.read(shopifyConnectionProvider).value;
        if (conn != null && conn.isActive) {
          futures.add(
            ref.read(shopifyConnectionProvider.notifier).refresh(),
          );
        }
      }
      await Future.wait(futures);
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

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

  void _toggleSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<Sale> filtered) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedIds.addAll(filtered.map((s) => s.id));
    });
  }

  Future<void> _bulkMarkPaid(List<Sale> allSales) async {
    final toUpdate = allSales
        .where((s) =>
            _selectedIds.contains(s.id) &&
            s.paymentStatus != PaymentStatus.paid)
        .toList();
    if (toUpdate.isEmpty) {
      _exitSelectionMode();
      return;
    }
    _exitSelectionMode();
    final notifier = ref.read(salesProvider.notifier);
    final allTxns = ref.read(transactionsProvider).value ?? [];
    final txnNotifier = ref.read(transactionsProvider.notifier);
    for (final sale in toUpdate) {
      await notifier.updateSale(sale.copyWith(
        paymentStatus: PaymentStatus.paid,
        amountPaid: sale.total,
      ));

      // Now paid: include linked revenue txns in P&L / cash-basis reports
      for (final tx in allTxns) {
        if (tx.saleId == sale.id && tx.excludeFromPL) {
          txnNotifier.updateTransaction(tx.copyWith(
            excludeFromPL: false,
            updatedAt: DateTime.now(),
          ));
        }
      }
    }
    if (mounted) {
      final shopifyCount = toUpdate.where((s) =>
          s.externalOrderId != null || s.shopifyOrderNumber != null).length;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          shopifyCount > 0
              ? l10n.salesMarkedPaidShopify(toUpdate.length, shopifyCount)
              : l10n.salesMarkedPaid(toUpdate.length),
        ),
        backgroundColor: shopifyCount > 0 ? Colors.orange.shade700 : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _bulkCancel(List<Sale> allSales) async {
    final toUpdate = allSales
        .where((s) =>
            _selectedIds.contains(s.id) &&
            s.orderStatus != OrderStatus.cancelled)
        .toList();
    if (toUpdate.isEmpty) {
      _exitSelectionMode();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.cancelOrders),
        content: Text(
          l10n.cancelOrdersBulkMsg(toUpdate.length),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.goBack),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: Text(l10n.cancelOrders),
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
          await inventoryNotifier.adjustStock(
            item.productId!,
            item.variantId ?? '${item.productId}_v0',
            item.quantity.toInt(),
            'Order cancelled',
            valuationMethod: valMethod,
          );
        }
      }

      // 2) Create reversal entries for linked transactions (visible in P&L)
      for (final tx in transactions) {
        if (tx.saleId == sale.id && tx.amount != 0) {
          transNotifier.updateTransaction(tx.copyWith(
            title: '[Cancelled] ${tx.title}',
            updatedAt: now,
          ));

          final reversalId = '${tx.id}_reversal_${now.millisecondsSinceEpoch}';
          transNotifier.addTransaction(tx.copyWith(
            id: reversalId,
            title: '[Reversal] ${tx.title}',
            amount: -tx.amount,
            dateTime: now,
            note: 'Auto-reversal for cancelled order ${sale.id}',
            excludeFromPL: false,
            createdAt: now,
            updatedAt: now,
          ));
        }
      }

      // 3) Mark order as cancelled
      await notifier.updateSale(sale.copyWith(
        orderStatus: OrderStatus.cancelled,
        updatedAt: now,
      ));

      // 4) Cancel on Shopify if linked (fire-and-forget)
      if (sale.externalSource == 'shopify' && sale.externalOrderId != null) {
        shopifyApi.cancelOrder(orderId: sale.externalOrderId!).then((result) {
          if (!mounted) return;
          if (!result.isSuccess && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(l10n.shopifyCancelFailedMsg(result.error ?? '')),
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
        content: Text(l10n.ordersCancelledDetail(toUpdate.length)),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(salesProvider.notifier).loadMore();
    }
  }

  List<Sale> _filter(List<Sale> sales) {
    var list = sales;
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((s) =>
              (s.customerName ?? '').toLowerCase().contains(q) ||
              s.displayOrderTitle.toLowerCase().contains(q) ||
              (s.customerPhone ?? '').toLowerCase().contains(q) ||
              (s.customerEmail ?? '').toLowerCase().contains(q) ||
              s.items.any(
                  (i) => i.productName.toLowerCase().contains(q)))
          .toList();
    }
    if (_statusFilter >= 0) {
      list = list
          .where((s) => s.paymentStatus.index == _statusFilter)
          .toList();
    }
    if (_sourceFilter == 'shopify') {
      list = list.where((s) => s.externalSource == 'shopify').toList();
    } else if (_sourceFilter == 'manual') {
      list = list.where((s) => s.externalSource == null || s.externalSource!.isEmpty).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencyProvider);
    final salesAsync = ref.watch(salesProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, salesAsync.value ?? []),
            if (!_selectionMode) ...[
              const ShopifyReconnectBanner(),
              _buildSyncStatus(),
              _buildFilters(),
            ],
            Expanded(
              child: AsyncValueWidget<List<Sale>>(
                value: salesAsync,
                onRetry: () =>
                    ref.read(salesProvider.notifier).refresh(),
                data: (sales) {
                  final filtered = _filter(sales);
                  if (filtered.isEmpty) return _buildEmpty();
                  return Stack(
                    children: [
                      RefreshIndicator(
                        onRefresh: _refreshSales,
                        child: ListView.separated(
                          controller: _scrollCtrl,
                          physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics()),
                          padding: EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            _selectionMode ? 100 : 120,
                          ),
                          itemCount: filtered.length +
                              (ref.read(salesProvider.notifier).hasMore
                                  ? 1
                                  : 0),
                          separatorBuilder: (context, idx) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            if (i >= filtered.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              );
                            }
                            final sale = filtered[i];
                            return _SaleCard(
                              sale: sale,
                              currency: currency,
                              selectionMode: _selectionMode,
                              isSelected: _selectedIds.contains(sale.id),
                              onToggle: () => _toggleSelection(sale.id),
                              onLongPress: _selectionMode
                                  ? null
                                  : () => _enterSelectionMode(),
                            )
                                .animate()
                                .fadeIn(
                                    duration: 200.ms,
                                    delay: (i * 40).ms)
                                .slideY(begin: 0.04, duration: 200.ms);
                          },
                        ),
                      ),
                      // Bulk action bar
                      if (_selectionMode)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: _BulkActionBar(
                            selectedCount: _selectedIds.length,
                            onMarkPaid: () => _bulkMarkPaid(filtered),
                            onCancel: () => _bulkCancel(filtered),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<Sale> allSales) {
    if (_selectionMode) {
      final filtered = _filter(allSales);
      final allSelected = filtered.isNotEmpty &&
          filtered.every((s) => _selectedIds.contains(s.id));

      return Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.primaryNavy,
          border: Border(
            bottom: BorderSide(
                color: AppColors.borderLight.withValues(alpha: 0.3)),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: _exitSelectionMode,
              icon: const Icon(Icons.close_rounded),
              color: Colors.white,
            ),
            Expanded(
              child: Text(
                _selectedIds.isEmpty
                    ? l10n.selectOrders
                    : l10n.selectedCount(_selectedIds.length),
                style: AppTypography.h1.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  fontSize: 18,
                ),
              ),
            ),
            TextButton(
              onPressed: allSelected
                  ? () => setState(() => _selectedIds.clear())
                  : () => _selectAll(filtered),
              child: Text(
                allSelected ? l10n.deselectAll : l10n.selectAll,
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryNavy,
          ),
          Expanded(
            child: Text(
              l10n.salesHeader,
              style: AppTypography.h1.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          // Action buttons row
          Row(
            children: [
              // Select button
              _headerButton(Icons.checklist_rounded, _enterSelectionMode),
              // Refresh button
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
                      _refreshSales();
                    }),
              const SizedBox(width: 2),
              // Add sale button
              GestureDetector(
                onTap: () => context.pushNamed('RecordSaleScreen'),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.add_rounded,
                      size: 22, color: AppColors.accentOrange),
                ),
              ),
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

  Widget _buildSyncStatus() {
    final hasAccess = ref.watch(hasShopifyAccessProvider);
    if (!hasAccess) return const SizedBox.shrink();

    final asyncConn = ref.watch(shopifyConnectionProvider);
    return asyncConn.when(
      loading: () => const SizedBox.shrink(),
      error: (_, e) => const SizedBox.shrink(),
      data: (conn) {
        if (conn == null || !conn.isActive) return const SizedBox.shrink();
        final lastSync = conn.lastOrderSyncAt;
        final label = lastSync != null
            ? l10n.lastSyncTimeAgo(_timeAgo(lastSync))
            : l10n.syncingOrdersFromShopify;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF7C3AED).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.sync_rounded, color: Color(0xFF7C3AED), size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.captionSmall.copyWith(
                    color: const Color(0xFF7C3AED),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  ref.read(salesProvider.notifier).refresh();
                  ref.read(shopifyConnectionProvider.notifier).refresh();
                },
                child: const Icon(Icons.refresh_rounded, color: Color(0xFF7C3AED), size: 18),
              ),
            ],
          ),
        );
      },
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return l10n.timeAgoJustNow;
    if (diff.inMinutes < 60) return l10n.timeAgoMinutes(diff.inMinutes);
    if (diff.inHours < 24) return l10n.timeAgoHours(diff.inHours);
    if (diff.inDays < 7) return l10n.timeAgoDays(diff.inDays);
    return DateFormat('MMM dd').format(dt);
  }

  Widget _buildFilters() {
    final hasAccess = ref.watch(hasShopifyAccessProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        children: [
          // Search
          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: l10n.searchSales,
              hintStyle: AppTypography.bodySmall
                  .copyWith(color: AppColors.textTertiary),
              prefixIcon: Icon(Icons.search_rounded,
                  size: 20, color: AppColors.textSecondary),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color:
                        AppColors.borderLight.withValues(alpha: 0.6)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Payment status chips
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _filterChip(-1, l10n.all),
                const SizedBox(width: 6),
                _filterChip(2, l10n.paid),
                const SizedBox(width: 6),
                _filterChip(1, l10n.partial),
                const SizedBox(width: 6),
                _filterChip(0, l10n.unpaid),
                const SizedBox(width: 6),
                _filterChip(3, l10n.refunded),
              ],
            ),
          ),
          // Source filter chips (only when Shopify access)
          if (hasAccess) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _sourceChip('all', l10n.allSources),
                  const SizedBox(width: 6),
                  _sourceChip('manual', l10n.manualSource),
                  const SizedBox(width: 6),
                  _sourceChip('shopify', 'Shopify'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sourceChip(String value, String label) {
    final selected = _sourceFilter == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _sourceFilter = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF7C3AED) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? const Color(0xFF7C3AED)
                : AppColors.borderLight.withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.captionSmall.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _filterChip(int value, String label) {
    final selected = _statusFilter == value;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _statusFilter = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryNavy : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppColors.primaryNavy
                : AppColors.borderLight.withValues(alpha: 0.6),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.captionSmall.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded,
                size: 48,
                color: AppColors.textTertiary.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(l10n.noSalesFound,
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text(l10n.tapPlusToRecordFirstSale,
                style: AppTypography.captionSmall
                    .copyWith(color: AppColors.textTertiary)),
          ],
        ),
      ),
    );
  }
}

// ── Bulk Action Bar ────────────────────────────────────────

class _BulkActionBar extends StatelessWidget {
  final int selectedCount;
  final VoidCallback onMarkPaid;
  final VoidCallback onCancel;

  const _BulkActionBar({
    required this.selectedCount,
    required this.onMarkPaid,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
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
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: selectedCount > 0
                      ? AppColors.success
                      : AppColors.success.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        size: 18, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      l10n.markAsPaid,
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
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: selectedCount > 0
                      ? AppColors.danger
                      : AppColors.danger.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cancel_rounded,
                        size: 18, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      l10n.cancel,
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
    )
        .animate()
        .slideY(begin: 1, duration: 220.ms, curve: Curves.easeOut)
        .fadeIn(duration: 180.ms);
  }
}

// ── Sale Card ──────────────────────────────────────────────

class _SaleCard extends ConsumerWidget {
  final Sale sale;
  final String currency;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onToggle;
  final VoidCallback? onLongPress;

  const _SaleCard({
    required this.sale,
    required this.currency,
    this.selectionMode = false,
    this.isSelected = false,
    required this.onToggle,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = NumberFormat('#,##0.00', 'en');
    final dateFmt = DateFormat('MMM dd, yyyy');

    Color statusColor;
    String statusLabel;
    switch (sale.paymentStatus) {
      case PaymentStatus.paid:
        statusColor = AppColors.success;
        statusLabel = l10n.paid;
        break;
      case PaymentStatus.refunded:
        statusColor = AppColors.danger;
        statusLabel = l10n.refunded;
        break;
      case PaymentStatus.partial:
        statusColor = AppColors.warning;
        statusLabel = l10n.partial;
        break;
      case PaymentStatus.unpaid:
        statusColor = AppColors.danger;
        statusLabel = l10n.unpaid;
        break;
    }

    final isCancelled = sale.orderStatus == OrderStatus.cancelled;

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

    return GestureDetector(
      onTap: () {
        if (selectionMode) {
          onToggle();
        } else {
          HapticFeedback.lightImpact();
          context.pushNamed('SaleDetailScreen', extra: {'sale': sale});
        }
      },
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Checkbox / Icon
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: selectionMode
                  ? SizedBox(
                      key: const ValueKey('checkbox'),
                      width: 48,
                      height: 48,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primaryNavy
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primaryNavy
                                  : AppColors.borderLight,
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check_rounded,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                      ),
                    )
                  : Container(
                      key: const ValueKey('icon'),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isCancelled
                            ? AppColors.danger.withValues(alpha: 0.08)
                            : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isCancelled
                            ? Icons.cancel_rounded
                            : Icons.shopping_bag_rounded,
                        size: 22,
                        color: isCancelled
                            ? AppColors.danger
                            : const Color(0xFF10B981),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.localizedDisplayOrderTitle(l10n),
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.saleItemsCount(sale.items.length, dateFmt.format(sale.date)),
                    style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textSecondary),
                  ),
                  if (sale.externalSource == 'shopify') ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Shopify',
                        style: AppTypography.captionSmall.copyWith(
                          color: const Color(0xFF7C3AED),
                          fontWeight: FontWeight.w700,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                  if (!isCancelled &&
                      sale.totalCogs == 0 &&
                      sale.items.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 10, color: AppColors.warning),
                          const SizedBox(width: 3),
                          Text(
                            l10n.noCogs,
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w700,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Amount + status badges
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currency ${fmt.format(sale.total)}',
                  style: AppTypography.labelMedium.copyWith(
                    color: isCancelled
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    decoration: isCancelled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Delivery status badge
                    if (!isCancelled && sale.deliveryStatus == 'Delivered') ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          l10n.delivered,
                          style: AppTypography.captionSmall.copyWith(
                            color: const Color(0xFF3B82F6),
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    // Order / payment status badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isCancelled
                            ? AppColors.danger.withValues(alpha: 0.1)
                            : statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isCancelled ? l10n.cancelled : statusLabel,
                        style: AppTypography.captionSmall.copyWith(
                          color: isCancelled ? AppColors.danger : statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
