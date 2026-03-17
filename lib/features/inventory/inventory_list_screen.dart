import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:csv/csv.dart' as csv_lib;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/share_service.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/providers/export_providers.dart';
import '../../shared/models/product_model.dart';
import 'inventory_filter_sheet.dart';
import '../../shared/widgets/async_value_widget.dart';
import '../shopify/providers/shopify_connection_provider.dart';
import '../shopify/providers/shopify_sync_provider.dart';
import '../../core/navigation/app_router.dart';
import '../../shared/utils/safe_pop.dart';

class InventoryListScreen extends ConsumerStatefulWidget {
  const InventoryListScreen({super.key});

  @override
  ConsumerState<InventoryListScreen> createState() =>
      _InventoryListScreenState();
}

class _InventoryListScreenState extends ConsumerState<InventoryListScreen>
    with WidgetsBindingObserver {
  int _selectedFilter = 0; // 0=All, 1=LowStock, 2=OutOfStock
  bool _isMaterialsView = false; // Toggle state
  bool _isSearchVisible = false;
  bool _isAutoSyncing = false; // For "always on" Shopify sync spinner
  String _searchQuery = '';
  InventoryFilterResult _filterResult = const InventoryFilterResult();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();
  Timer? _searchDebounce;

  /// Cached notifier reference — safe to use in dispose().
  ShopifySyncNotifier? _syncNotifier;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    // Start always-on timer after the first frame (providers are ready)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncNotifier = ref.read(shopifySyncProvider.notifier);
      _startAlwaysSyncIfNeeded();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _startAlwaysSyncIfNeeded();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _syncNotifier?.stopAlwaysSyncTimer();
    }
  }

  void _startAlwaysSyncIfNeeded() {
    // Always start the sync timer when Shopify is connected.
    // Product detail sync runs unconditionally; inventory sync
    // is gated by mode inside the timer handler.
    final hasAccess = ref.read(hasShopifyAccessProvider);
    final conn = ref.read(shopifyConnectionProvider).value;
    if (hasAccess && conn != null && conn.isActive) {
      _syncNotifier?.startAlwaysSyncTimer();
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      ref.read(inventoryProvider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncNotifier?.stopAlwaysSyncTimer();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<Product> get _filteredProducts {
    final products = ref.read(inventoryProvider).value ?? [];
    final hideOos = ref.watch(appSettingsProvider).hideOutOfStock;
    final hideDrafts = ref.watch(appSettingsProvider).hideShopifyDrafts;
    var list = products.where((p) {
      // 1. Filter by Type (Product vs Material)
      if (p.isMaterial != _isMaterialsView) return false;

      // 1b. Hide out-of-stock if setting is on
      if (hideOos && p.status == StockStatus.outOfStock) return false;

      // 1c. Hide Shopify drafted products if setting is on
      if (hideDrafts && p.shopifyStatus == 'draft') return false;

      // 2. Filter by Search
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!p.name.toLowerCase().contains(q) &&
            !p.sku.toLowerCase().contains(q) &&
            !p.category.toLowerCase().contains(q)) {
          return false;
        }
      }

      // 3. Filter by Stock Status (chip tabs)
      switch (_selectedFilter) {
        case 1:
          if (p.status != StockStatus.lowStock) { return false; }
        case 2:
          if (p.status != StockStatus.outOfStock) { return false; }
        default:
          break;
      }

      // 4. Advanced filter sheet — status
      if (_filterResult.statusFilters.isNotEmpty) {
        final statusLabel = switch (p.status) {
          StockStatus.inStock    => 'In Stock',
          StockStatus.lowStock   => 'Low Stock',
          StockStatus.outOfStock => 'Out of Stock',
        };
        if (!_filterResult.statusFilters.contains(statusLabel)) return false;
      }

      // 5. Advanced filter sheet — category
      if (_filterResult.categories.isNotEmpty &&
          !_filterResult.categories.contains(p.category)) { return false; }

      // 6. Advanced filter sheet — supplier
      if (_filterResult.suppliers.isNotEmpty &&
          !_filterResult.suppliers.contains(p.supplier)) { return false; }

      // 7. Advanced filter sheet — price range (sellingPrice)
      if (_filterResult.minPrice != null && p.sellingPrice < _filterResult.minPrice!) return false;
      if (_filterResult.maxPrice != null && p.sellingPrice > _filterResult.maxPrice!) return false;

      return true;
    }).toList();

    // 8. Sort from the filter sheet
    switch (_filterResult.sortIndex) {
      case 0: // Stock: Low → High
        list.sort((a, b) => a.currentStock.compareTo(b.currentStock));
      case 1: // Stock: High → Low
        list.sort((a, b) => b.currentStock.compareTo(a.currentStock));
      case 2: // Name: A-Z
        list.sort((a, b) => a.name.compareTo(b.name));
      case 3: // Value: High → Low
        list.sort((a, b) => b.totalValue.compareTo(a.totalValue));
    }

    return list;
  }

  bool get _hasActiveFilters =>
      _filterResult.sortIndex != 0 ||
      _filterResult.statusFilters.isNotEmpty ||
      _filterResult.categories.isNotEmpty ||
      _filterResult.suppliers.isNotEmpty ||
      _filterResult.minPrice != null ||
      _filterResult.maxPrice != null;

  int _countByStatus(StockStatus status) {
    final products = ref.read(inventoryProvider).value ?? [];
    return products
        .where((p) => p.status == status && p.isMaterial == _isMaterialsView)
        .length;
  }

  double _calculateCostValue() {
    final products = ref.read(inventoryProvider).value ?? [];
    return products
        .where((p) => p.isMaterial == _isMaterialsView)
        .fold(0.0, (sum, p) => sum + p.totalCostValue);
  }

  double _calculateSellingValue() {
    final products = ref.read(inventoryProvider).value ?? [];
    return products
        .where((p) => p.isMaterial == _isMaterialsView)
        .fold(0.0, (sum, p) => sum + p.totalValue);
  }

  /// Whether "always on" Shopify sync mode is active.
  bool get _isAlwaysOnSync {
    final hasAccess = ref.read(hasShopifyAccessProvider);
    if (!hasAccess) return false;
    final conn = ref.read(shopifyConnectionProvider).value;
    return conn != null && conn.isActive && conn.inventorySyncMode == 'always';
  }

  /// Refresh inventory + auto-sync with Shopify if in "always on" mode.
  Future<void> _refreshWithAutoSync() async {
    if (!mounted) return;

    // Capture refs before any async gap
    final inventoryNotifier = ref.read(inventoryProvider.notifier);
    final isAlwaysOn = _isAlwaysOnSync;

    if (isAlwaysOn) {
      setState(() => _isAutoSyncing = true);
      // Push/pull Shopify data first, then refresh the full product list once
      await (_syncNotifier?.performAutoSync() ?? Future.value());
      if (!mounted) return;
    }
    await inventoryNotifier.refresh();
    if (mounted && isAlwaysOn) setState(() => _isAutoSyncing = false);
  }

  /// Trigger Shopify auto-sync from the refresh button tap.
  Future<void> _onShopifyRefreshTap() async {
    if (_isAutoSyncing) return;
    HapticFeedback.mediumImpact();
    await _refreshWithAutoSync();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(inventoryProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            if (ref.watch(isGrowthProvider)) _buildTypeToggle(),
            _buildShopifySyncBar(),
            if (_isSearchVisible) _buildSearchBar(),
            Expanded(
              child: AsyncValueWidget<List<Product>>(
                value: productsAsync,
                onRetry: () => ref.read(inventoryProvider.notifier).refresh(),
                data: (products) {
                  final filtered = _filteredProducts;
                  final inStock = _countByStatus(StockStatus.inStock);
                  final lowStock = _countByStatus(StockStatus.lowStock);
                  final outOfStock = _countByStatus(StockStatus.outOfStock);
                  final costValue = _calculateCostValue();
                  final sellingValue = _calculateSellingValue();
                  final isPageLoading = ref.watch(inventoryProvider.notifier).hasMore;

                  return RefreshIndicator(
                    onRefresh: _refreshWithAutoSync,
                    color: _isAlwaysOnSync
                        ? AppColors.shopifyPurple
                        : AppColors.primaryNavy,
                    child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _StockStatusCard(
                          inStock: inStock,
                          lowStock: lowStock,
                          outOfStock: outOfStock,
                        ),
                        const SizedBox(height: 12),
                        _StockValueCard(costValue: costValue, sellingValue: sellingValue),
                        _buildMissingCostBanner(products),
                        const SizedBox(height: 16),
                        _buildQuickActions(),
                        const SizedBox(height: 16),
                        _buildFilterChips(products.length, lowStock, outOfStock),
                        const SizedBox(height: 16),
                        _buildProductList(filtered),
                        if (isPageLoading)
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
                      ],
                    ),
                  ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryNavy,
          ),
          Text(
            'Inventory',
            style: AppTypography.h2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const Spacer(),
          _headerButton(Icons.search_rounded, () {
            HapticFeedback.lightImpact();
            setState(() {
              _isSearchVisible = !_isSearchVisible;
              if (_isSearchVisible) {
                Future.delayed(200.ms, () => _searchFocus.requestFocus());
              } else {
                _searchQuery = '';
                _searchController.clear();
              }
            });
          }),
          Stack(
            children: [
              _headerButton(Icons.filter_list_rounded, () async {
                HapticFeedback.lightImpact();
                final cats = ref.read(categoriesProvider).value
                    ?.map((c) => c.name).toList() ?? [];
                final sups = ref.read(suppliersProvider).value
                    ?.map((s) => s.name).toList() ?? [];
                final currency = ref.read(currencyProvider);
                final result = await showInventoryFilterSheet(
                  context,
                  initial: _filterResult,
                  categoryOptions: cats,
                  supplierOptions: sups,
                  currency: currency,
                );
                if (result != null) setState(() => _filterResult = result);
              }),
              if (_hasActiveFilters)
                Positioned(
                  right: 6, top: 6,
                  child: Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.backgroundLight, width: 2),
                    ),
                    child: const Center(
                      child: Icon(Icons.check, size: 10, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          // Shopify sync refresh button — only in "always on" mode
          if (_isAlwaysOnSync)
            _isAutoSyncing
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.shopifyPurple,
                      ),
                    ),
                  )
                : _headerButton(Icons.sync_rounded, _onShopifyRefreshTap),
          _headerButton(Icons.more_horiz_rounded, () {
            HapticFeedback.lightImpact();
            _showOverflowMenu();
          }),
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
          child: Icon(icon, size: 24, color: AppColors.textSecondary),
        ),
      ),
    );
  }

  /// Shows a Shopify inventory sync bar only when the user has an active
  /// Shopify connection AND sync mode is set to "on_demand".
  Widget _buildShopifySyncBar() {
    final hasAccess = ref.watch(hasShopifyAccessProvider);
    if (!hasAccess) return const SizedBox.shrink();

    final asyncConn = ref.watch(shopifyConnectionProvider);
    return asyncConn.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (conn) {
        if (conn == null || !conn.isActive) return const SizedBox.shrink();
        // Only show persistent sync bar in on-demand mode
        if (conn.inventorySyncMode != 'on_demand') return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => context.push(AppRoutes.shopifyInventorySync),
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.shopifyPurple.withValues(alpha: 0.08),
                  AppColors.shopifyPurple.withValues(alpha: 0.03),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.shopifyPurple.withValues(alpha: 0.15)),
            ),
            child: Row(
              children: [
                Icon(Icons.sync_rounded, color: AppColors.shopifyPurple, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sync inventory with Shopify',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.shopifyPurple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.shopifyPurple, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        onChanged: (v) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 300), () {
            if (mounted) setState(() => _searchQuery = v);
          });
        },
        decoration: InputDecoration(
          hintText: 'Search products, SKU...',
          hintStyle: AppTypography.bodySmall
              .copyWith(color: AppColors.textTertiary),
          prefixIcon:
              const Icon(Icons.search_rounded, size: 20, color: AppColors.textTertiary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.borderLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: AppColors.borderLight.withValues(alpha: 0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppColors.primaryNavy, width: 1.5),
          ),
        ),
        style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms)
        .slideY(begin: -0.2, end: 0, duration: 200.ms);
  }

  // ═══════════════════════════════════════════════════
  //  MISSING COST BANNER
  // ═══════════════════════════════════════════════════
  Widget _buildMissingCostBanner(List<Product> products) {
    final missingCount = products.where((p) =>
        p.variants.any((v) => v.costPrice <= 0)).length;
    if (missingCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: GestureDetector(
        onTap: () => context.pushNamed('MissingCostScreen'),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.warning.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    size: 20, color: AppColors.warning),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$missingCount product${missingCount == 1 ? '' : 's'} missing cost',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Tap to record cost prices',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  QUICK ACTIONS
  // ═══════════════════════════════════════════════════
  Widget _buildQuickActions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _QuickActionButton(
            icon: Icons.add_rounded,
            label: _isMaterialsView ? 'Add Material' : 'Add Product',
            isPrimary: true,
            color: _isMaterialsView ? const Color(0xFF795548) : null,
            onTap: () {
              HapticFeedback.mediumImpact();
              if (_isMaterialsView) {
                context.pushNamed("AddMaterialScreen");
              } else {
                context.pushNamed("AddProductScreen");
              }
            },
          ),
          const SizedBox(width: 10),
          _QuickActionButton(
            icon: Icons.inventory_2_rounded,
            label: 'Add Stock',
            onTap: () {
              HapticFeedback.lightImpact();
              _showStockActionSheet(context, ref, 'Add Stock', 'Restock', _isMaterialsView);
            },
          ),
          const SizedBox(width: 10),
          _QuickActionButton(
            icon: Icons.tune_rounded,
            label: 'Adjust Stock',
            onTap: () {
              HapticFeedback.lightImpact();
              _showStockActionSheet(context, ref, 'Adjust Stock', 'Correction', _isMaterialsView);
            },
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  TYPE TOGGLE
  // ═══════════════════════════════════════════════════
  Widget _buildTypeToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            Expanded(
              child: _toggleOption('Products', false),
            ),
            Expanded(
              child: _toggleOption('Raw Materials', true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleOption(String label, bool isMaterials) {
    final isSelected = _isMaterialsView == isMaterials;
    return GestureDetector(
      onTap: () {
        if (_isMaterialsView != isMaterials) {
          HapticFeedback.selectionClick();
          setState(() {
            _isMaterialsView = isMaterials;
            _selectedFilter = 0; // Reset filter on switch
          });
        }
      },
      child: AnimatedContainer(
        duration: 200.ms,
        decoration: BoxDecoration(
          color: isSelected
              ? (isMaterials ? const Color(0xFF795548) : AppColors.primaryNavy)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  FILTER CHIPS
  // ═══════════════════════════════════════════════════
  Widget _buildFilterChips(int total, int lowStock, int outOfStock) {
    final chips = [
      _FilterChipData('All ($total)', 0),
      _FilterChipData('Low stock ($lowStock)', 1),
      _FilterChipData('Out of stock ($outOfStock)', 2),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: chips.map((chip) {
          final isSelected = _selectedFilter == chip.index;
          return Padding(
            padding: EdgeInsets.only(right: chip != chips.last ? 8 : 0),
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _selectedFilter = chip.index);
              },
              child: AnimatedContainer(
                duration: 200.ms,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryNavy : Colors.white,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primaryNavy
                        : AppColors.borderLight,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.primaryNavy.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  chip.label,
                  style: AppTypography.labelMedium.copyWith(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  PRODUCT LIST
  // ═══════════════════════════════════════════════════
  Widget _buildProductList(List<Product> products) {
    if (products.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      children: [
        for (int i = 0; i < products.length; i++) ...[
          GestureDetector(
            key: ValueKey(products[i].id),
            onTap: () {
              HapticFeedback.lightImpact();
              context.pushNamed('ProductDetailScreen', extra: {'productId': products[i].id});
            },
            child: _ProductCard(product: products[i], index: i),
          ),
          if (i < products.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    final hasSearch = _searchQuery.isNotEmpty;
    final hasFilters = _filterResult.sortIndex != 0 ||
        _filterResult.statusFilters.isNotEmpty ||
        _filterResult.categories.isNotEmpty ||
        _filterResult.suppliers.isNotEmpty ||
        _filterResult.minPrice != null ||
        _filterResult.maxPrice != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 48,
                color: AppColors.textTertiary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              hasSearch || hasFilters
                  ? 'No products match your search'
                  : 'No products found',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 6),
            Text(
              hasSearch || hasFilters
                  ? 'Try changing your search or filters'
                  : 'Add your first product to get started',
              style: AppTypography.captionSmall
                  .copyWith(color: AppColors.textTertiary, fontSize: 11),
            ),
            if (hasSearch || hasFilters) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _searchController.clear();
                    _filterResult = const InventoryFilterResult();
                  });
                },
                icon: const Icon(Icons.clear_rounded, size: 16),
                label: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  CSV IMPORT
  // ═══════════════════════════════════════════════════
  Future<void> _importFromCsv() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not read file'), backgroundColor: AppColors.danger),
          );
        }
        return;
      }

      // Reject files over 5 MB to avoid UI freeze
      if (bytes.length > 5 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('CSV file exceeds 5 MB limit'), backgroundColor: AppColors.danger),
          );
        }
        return;
      }

      // Prefer strict UTF-8 first (with optional BOM). Fall back to latin1
      // for Excel/exported files that are not UTF-8 encoded.
      String csvString;
      try {
        csvString = utf8.decode(bytes, allowMalformed: false);
      } catch (_) {
        csvString = latin1.decode(bytes, allowInvalid: true);
      }
      if (csvString.isNotEmpty && csvString.codeUnitAt(0) == 0xFEFF) {
        csvString = csvString.substring(1);
      }
      final rows = const csv_lib.CsvToListConverter().convert(csvString);
      if (rows.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('CSV file is empty or has no data rows'), backgroundColor: AppColors.danger),
          );
        }
        return;
      }

      // Parse header — match columns by name (case-insensitive)
      final header = rows.first.map((e) => e.toString().toLowerCase().trim()).toList();
      int col(String name) => header.indexWhere((h) => h.contains(name));
      final iSku = col('sku');
      final iName = col('name');
      final iVariant = col('variant');
      final iCategory = col('category');
      final iSupplier = col('supplier');
      final iCost = col('cost');
      final iSelling = col('selling');
      final iStock = col('stock');
      final iUnit = col('unit');

      if (iName < 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('CSV must have a "Name" column'), backgroundColor: AppColors.danger),
          );
        }
        return;
      }

      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final defaultUnit = ref.read(appSettingsProvider).defaultUnit;
      final notifier = ref.read(inventoryProvider.notifier);
        final existing = ref.read(inventoryProvider).value ?? [];
        final existingNames = existing
          .map((p) => p.name.trim().toLowerCase())
          .where((n) => n.isNotEmpty)
          .toSet();
        final existingSkus = existing
          .expand((p) => p.variants)
          .map((v) => v.sku.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toSet();

      // Group rows by product name to merge variants
      final productGroups = <String, List<List<dynamic>>>{};
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length <= iName) continue;
        final name = row[iName].toString().trim();
        if (name.isEmpty) continue;
        productGroups.putIfAbsent(name, () => []).add(row);
      }

      var imported = 0;
      var skippedDuplicates = 0;
      for (final entry in productGroups.entries) {
        final name = entry.key;
        final groupRows = entry.value;
        final first = groupRows.first;

        String cellStr(List<dynamic> r, int idx) =>
            idx >= 0 && idx < r.length ? r[idx].toString().trim() : '';
        double cellDbl(List<dynamic> r, int idx) =>
            idx >= 0 && idx < r.length ? (double.tryParse(r[idx].toString().trim()) ?? 0) : 0;
        int cellInt(List<dynamic> r, int idx) =>
            idx >= 0 && idx < r.length ? (int.tryParse(r[idx].toString().trim()) ?? 0) : 0;

        final normalizedName = name.trim().toLowerCase();
        final groupSkus = groupRows
            .map((r) => cellStr(r, iSku).toLowerCase())
            .where((s) => s.isNotEmpty)
            .toSet();
        final hasDuplicateName = existingNames.contains(normalizedName);
        final hasDuplicateSku = groupSkus.any(existingSkus.contains);
        if (hasDuplicateName || hasDuplicateSku) {
          skippedDuplicates++;
          continue;
        }

        final prodId = 'csv_${DateTime.now().millisecondsSinceEpoch}_$imported';

        final variants = <ProductVariant>[];
        for (var vi = 0; vi < groupRows.length; vi++) {
          final r = groupRows[vi];
          final variantName = cellStr(r, iVariant);
          variants.add(ProductVariant(
            id: '${prodId}_v$vi',
            optionValues: variantName.isNotEmpty ? {'Variant': variantName} : const {},
            sku: cellStr(r, iSku),
            costPrice: cellDbl(r, iCost),
            sellingPrice: cellDbl(r, iSelling),
            currentStock: cellInt(r, iStock),
            reorderPoint: 10,
          ));
        }

        final product = Product(
          id: prodId,
          userId: uid,
          name: name,
          category: cellStr(first, iCategory).isNotEmpty ? cellStr(first, iCategory) : 'Imported',
          supplier: cellStr(first, iSupplier),
          unitOfMeasure: cellStr(first, iUnit).isNotEmpty ? cellStr(first, iUnit) : defaultUnit,
          variants: variants,
        );

        await notifier.addProduct(product);
        existingNames.add(normalizedName);
        existingSkus.addAll(groupSkus);
        imported++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              skippedDuplicates > 0
                  ? 'Imported $imported product(s), skipped $skippedDuplicates duplicate(s)'
                  : 'Imported $imported product(s) from CSV',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('CSV import error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to import CSV. Check file format.'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════
  //  ADD STOCK / ADJUST STOCK SHEET
  // ═══════════════════════════════════════════════════
  //  OVERFLOW MENU
  // ═══════════════════════════════════════════════════
  void _showOverflowMenu() {
    showModalBottomSheet(
  useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Inventory Options',
                      style: AppTypography.h3.copyWith(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded,
                          color: AppColors.textTertiary, size: 22),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: AppColors.borderLight.withValues(alpha: 0.5),
              ),
              // Menu items
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Column(
                  children: [
                    _overflowItem(
                      ctx,
                      icon: Icons.upload_file_rounded,
                      label: 'Import from CSV',
                      onTap: () {
                        Navigator.pop(ctx);
                        HapticFeedback.lightImpact();
                        _importFromCsv();
                      },
                    ),
                    _overflowItem(
                      ctx,
                      icon: Icons.download_rounded,
                      label: 'Export Inventory',
                      onTap: () async {
                        Navigator.pop(ctx);
                        HapticFeedback.lightImpact();
                        try {
                          final origin = ShareService.originFrom(context);
                          final reportSvc = ref.read(reportServiceProvider);
                          final shareSvc = ref.read(shareServiceProvider);
                          final currency = ref.read(currencyProvider);
                          final products = await ref.read(inventoryProvider.future);
                          final csvString = reportSvc.exportInventoryCsv(products, currency);
                          await shareSvc.shareCsv(csvString, 'Inventory_export.csv', subject: 'Inventory Export', origin: origin);
                        } catch (e) {
                          debugPrint('Inventory export error: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Something went wrong. Please try again.'), backgroundColor: AppColors.danger));
                          }
                        }
                      },
                    ),
                    // Show "Import from Shopify" when connected
                    if (ref.read(hasShopifyAccessProvider) &&
                        (ref.read(shopifyConnectionProvider).value?.isActive ?? false))
                      _overflowItem(
                        ctx,
                        icon: Icons.storefront_rounded,
                        label: 'Import from Shopify',
                        onTap: () {
                          Navigator.pop(ctx);
                          HapticFeedback.lightImpact();
                          context.push(AppRoutes.shopifyProductMappings);
                        },
                      ),
                    // Show "Sync Inventory" when connected and mode is on-demand
                    if (ref.read(hasShopifyAccessProvider) &&
                        (ref.read(shopifyConnectionProvider).value?.isActive ?? false) &&
                        (ref.read(shopifyConnectionProvider).value?.inventorySyncMode ?? 'on_demand') == 'on_demand')
                      _overflowItem(
                        ctx,
                        icon: Icons.sync_rounded,
                        label: 'Sync Inventory',
                        onTap: () {
                          Navigator.pop(ctx);
                          HapticFeedback.lightImpact();
                          context.push(AppRoutes.shopifyInventorySync);
                        },
                      ),
                    _overflowItem(
                      ctx,
                      icon: Icons.settings_rounded,
                      label: 'Inventory Settings',
                      onTap: () {
                        Navigator.pop(ctx);
                        HapticFeedback.lightImpact();
                        context.pushNamed('InventorySettingsScreen');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overflowItem(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryNavy.withValues(alpha: 0.08),
                ),
                child: Icon(icon, size: 20, color: AppColors.primaryNavy),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  void _showStockActionSheet(
    BuildContext context,
    WidgetRef ref,
    String title,
    String defaultReason,
    bool materialsOnly,
  ) {
    // Filter list based on which tab is active
    final all = ref.read(inventoryProvider).value ?? [];
    final materials = materialsOnly
        ? all.where((p) => p.isMaterial).toList()
        : all.where((p) => !p.isMaterial).toList();
    String? selectedProductId;
    String? selectedVariantId;
    int quantity = 0;
    String reason = defaultReason;
    final bool isAddStock = title == 'Add Stock';

    final reasons = isAddStock
        ? ['Restock', 'Return', 'Correction']
        : ['Correction', 'Damage', 'Loss', 'Return', 'Sale'];

    final quantityCtrl = TextEditingController(text: '0');
    final notifier = ref.read(inventoryProvider.notifier);
    final valMethod = ref.read(appSettingsProvider).valuationMethod;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDDDDD),
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (isAddStock
                                ? AppColors.success
                                : AppColors.accentOrange)
                            .withValues(alpha: 0.1),
                      ),
                      child: Icon(
                        isAddStock
                            ? Icons.add_rounded
                            : Icons.tune_rounded,
                        size: 20,
                        color: isAddStock
                            ? AppColors.success
                            : AppColors.accentOrange,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      title,
                      style: AppTypography.h3.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Product picker
                Text(
                  'SELECT PRODUCT',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.borderLight
                            .withValues(alpha: 0.5)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedProductId,
                      hint: Text(
                        'Choose a raw material...',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textTertiary),
                      ),
                      icon: const Icon(Icons.expand_more_rounded,
                          color: AppColors.textTertiary),
                      isExpanded: true,
                      items: materials
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(
                                  '${p.name}  (${p.currentStock} ${p.unitOfMeasure})',
                                  style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.textPrimary),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                          setSheetState(() {
                            selectedProductId = v;
                            // Auto-select variant
                            if (v != null) {
                              final prod = materials.firstWhere((p) => p.id == v);
                              if (prod.variants.length > 1) {
                                selectedVariantId = null; // force user to pick
                              } else {
                                selectedVariantId = prod.defaultVariant.id;
                              }
                            } else {
                              selectedVariantId = null;
                            }
                          });
                      },
                    ),
                  ),
                ),

                // Variant picker (only for multi-variant products)
                if (selectedProductId != null &&
                    materials.firstWhere((p) => p.id == selectedProductId).variants.length > 1) ...[
                  const SizedBox(height: 12),
                  Text(
                    'SELECT VARIANT',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.borderLight
                              .withValues(alpha: 0.5)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedVariantId,
                        hint: Text(
                          'Choose a variant...',
                          style: AppTypography.bodySmall
                              .copyWith(color: AppColors.textTertiary),
                        ),
                        icon: const Icon(Icons.expand_more_rounded,
                            color: AppColors.textTertiary),
                        isExpanded: true,
                        items: materials
                            .firstWhere((p) => p.id == selectedProductId)
                            .variants
                            .map((v) => DropdownMenuItem(
                                  value: v.id,
                                  child: Text(
                                    '${v.displayName}  (${v.currentStock})',
                                    style: AppTypography.bodySmall.copyWith(
                                        color: AppColors.textPrimary),
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setSheetState(() => selectedVariantId = v),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),

                // Quantity stepper
                Text(
                  'QUANTITY',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderLight),
                    color: AppColors.backgroundLight,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (isAddStock && quantity > 0) {
                            setSheetState(() {
                              quantity--;
                              quantityCtrl.text = '$quantity';
                            });
                          } else if (!isAddStock) {
                            setSheetState(() {
                              quantity--;
                              quantityCtrl.text = '$quantity';
                            });
                          }
                          HapticFeedback.lightImpact();
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: 0.04),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.remove_rounded,
                              size: 22, color: AppColors.textSecondary),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: quantityCtrl,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.numberWithOptions(signed: !isAddStock),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(isAddStock ? r'\d' : r'[-\d]')),
                          ],
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: quantity > 0
                                ? AppColors.success
                                : quantity < 0
                                    ? AppColors.danger
                                    : AppColors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (val) {
                            final parsed = int.tryParse(val);
                            if (parsed != null) {
                              setSheetState(() => quantity = isAddStock ? parsed.abs() : parsed);
                            } else {
                              setSheetState(() => quantity = 0);
                            }
                          },
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setSheetState(() {
                            quantity++;
                            quantityCtrl.text = '$quantity';
                          });
                          HapticFeedback.lightImpact();
                        },
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: 0.04),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.add_rounded,
                              size: 22, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Reason picker
                Text(
                  'REASON',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.borderLight
                            .withValues(alpha: 0.5)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: reason,
                      icon: const Icon(Icons.expand_more_rounded,
                          color: AppColors.textTertiary),
                      isExpanded: true,
                      items: reasons
                          .map((r) => DropdownMenuItem(
                                value: r,
                                child: Text(
                                  r,
                                  style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.textPrimary),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setSheetState(() => reason = v ?? defaultReason),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        selectedProductId != null && selectedVariantId != null && quantity != 0
                            ? () {
                                notifier.adjustStock(
                                      selectedProductId!,
                                      selectedVariantId!,
                                      quantity,
                                      reason,
                                      valuationMethod: valMethod,
                                    );
                                HapticFeedback.mediumImpact();
                                Navigator.pop(ctx);
                              }
                            : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isAddStock
                          ? AppColors.success
                          : AppColors.primaryNavy,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.textTertiary.withValues(alpha: 0.2),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      selectedProductId != null && quantity != 0
                          ? '$title ($quantity units)'
                          : title,
                      style: AppTypography.labelMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => quantityCtrl.dispose());
    });
  }
}

// ═══════════════════════════════════════════════════════════
//  STOCK STATUS CARD
// ═══════════════════════════════════════════════════════════
class _StockStatusCard extends StatelessWidget {
  final int inStock;
  final int lowStock;
  final int outOfStock;

  const _StockStatusCard({
    required this.inStock,
    required this.lowStock,
    required this.outOfStock,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Stock Status',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  'Real-time',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _StatusColumn(
                count: inStock,
                label: 'In Stock',
                color: AppColors.success,
              ),
              _divider(),
              _StatusColumn(
                count: lowStock,
                label: 'Low Stock',
                color: AppColors.warning,
              ),
              _divider(),
              _StatusColumn(
                count: outOfStock,
                label: 'Out Stock',
                color: AppColors.danger,
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 40,
      color: AppColors.borderLight.withValues(alpha: 0.5),
    );
  }
}

class _StatusColumn extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _StatusColumn({
    required this.count,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: count),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Text(
              '$value',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  STOCK VALUE CARD
// ═══════════════════════════════════════════════════════════
class _StockValueCard extends ConsumerWidget {
  final double costValue;
  final double sellingValue;

  const _StockValueCard({required this.costValue, required this.sellingValue});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryNavy, Color(0xFF154360)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryNavy.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: -16,
            left: -16,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentOrange.withValues(alpha: 0.1),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inventory Cost Value',
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${ref.watch(appSettingsProvider).currency} ${_formatNumber(costValue)}',
                    style: AppTypography.h2.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.sell_rounded,
                        size: 12,
                        color: AppColors.accentOrange.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Retail: ${ref.watch(appSettingsProvider).currency} ${_formatNumber(sellingValue)}',
                        style: AppTypography.captionSmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                child: const Icon(Icons.show_chart_rounded,
                    color: Colors.white, size: 22),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 50.ms).slideY(begin: 0.05, end: 0);
  }

  String _formatNumber(double value) {
    if (value >= 1000) {
      final formatted = value.toStringAsFixed(0);
      final result = StringBuffer();
      for (int i = 0; i < formatted.length; i++) {
        if (i > 0 && (formatted.length - i) % 3 == 0) result.write(',');
        result.write(formatted[i]);
      }
      return result.toString();
    }
    return value.toStringAsFixed(0);
  }
}

// ═══════════════════════════════════════════════════════════
//  QUICK ACTION BUTTON
// ═══════════════════════════════════════════════════════════
class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final Color? color;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: isPrimary
              ? (color ?? AppColors.primaryNavy)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isPrimary
              ? null
              : Border.all(color: AppColors.borderLight),
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: (color ?? AppColors.primaryNavy)
                        .withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isPrimary ? Colors.white : AppColors.primaryNavy,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isPrimary ? Colors.white : AppColors.primaryNavy,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PRODUCT CARD
// ═══════════════════════════════════════════════════════════
class _ProductCard extends ConsumerWidget {
  final Product product;
  final int index;

  const _ProductCard({required this.product, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOutOfStock = product.status == StockStatus.outOfStock;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Opacity(
        opacity: isOutOfStock ? 0.7 : 1.0,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product icon / image
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: product.color.withValues(alpha: isOutOfStock ? 0.05 : 0.1),
              ),
              child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: product.imageUrl!,
                        fit: BoxFit.cover,
                        width: 56,
                        height: 56,
                        placeholder: (_, __) => Icon(
                          product.icon,
                          size: 26,
                          color: isOutOfStock
                              ? AppColors.textTertiary
                              : product.color,
                        ),
                        errorWidget: (_, __, ___) => Icon(
                          product.icon,
                          size: 26,
                          color: isOutOfStock
                              ? AppColors.textTertiary
                              : product.color,
                        ),
                      ),
                    )
                  : Icon(
                      product.icon,
                      size: 26,
                      color: isOutOfStock
                          ? AppColors.textTertiary
                          : product.color,
                    ),
            ),
            const SizedBox(width: 12),
            // Product info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product.name,
                              style: AppTypography.labelMedium.copyWith(
                                color: isOutOfStock
                                    ? AppColors.textTertiary
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'SKU: ${product.sku}${product.category.isNotEmpty && !{'shopify import', 'shopify_import'}.contains(product.category.toLowerCase()) ? ' • ${product.category}' : ''}',
                              style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                if (product.supplier.isNotEmpty && product.supplier.toLowerCase() != 'shopify')
                                  Text(
                                    'Supplier: ${product.supplier}',
                                    style: AppTypography.captionSmall.copyWith(
                                      color: AppColors.textTertiary.withValues(alpha: 0.7),
                                      fontSize: 10,
                                    ),
                                  ),
                                if (product.shopifyProductId != null && product.shopifyProductId!.isNotEmpty) ...[
                                  if (product.supplier.isNotEmpty && product.supplier.toLowerCase() != 'shopify') const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF96BF48).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Shopify',
                                      style: AppTypography.captionSmall.copyWith(
                                        color: const Color(0xFF5E8E3E),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${product.currentStock} ${product.unitOfMeasure}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _stockColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _StatusBadge(status: product.status),
                      Text(
                        product.isMaterial
                            ? 'Cost: ${ref.watch(appSettingsProvider).currency} ${product.costPrice.toStringAsFixed(2)}'
                            : '${ref.watch(appSettingsProvider).currency} ${product.sellingPrice.toStringAsFixed(2)}',
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
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(
            duration: 300.ms,
            delay: Duration(milliseconds: 40 * index))
        .slideY(
            begin: 0.03,
            end: 0,
            duration: 300.ms,
            delay: Duration(milliseconds: 40 * index));
  }

  Color get _stockColor {
    switch (product.status) {
      case StockStatus.inStock:
        return AppColors.textPrimary;
      case StockStatus.lowStock:
        return AppColors.warning;
      case StockStatus.outOfStock:
        return AppColors.danger;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final StockStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      StockStatus.inStock => ('In stock', AppColors.success),
      StockStatus.lowStock => ('Low stock', AppColors.warning),
      StockStatus.outOfStock => ('Out of stock', AppColors.danger),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipData {
  final String label;
  final int index;
  const _FilterChipData(this.label, this.index);
}
