import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/product_model.dart';
import 'inventory_filter_sheet.dart';
import 'add_product_screen.dart';
import 'product_detail_screen.dart';
import 'inventory_settings_screen.dart';

class InventoryListScreen extends ConsumerStatefulWidget {
  const InventoryListScreen({super.key});

  @override
  ConsumerState<InventoryListScreen> createState() =>
      _InventoryListScreenState();
}

class _InventoryListScreenState extends ConsumerState<InventoryListScreen> {
  int _selectedFilter = 0; // 0=All, 1=LowStock, 2=OutOfStock
  bool _isMaterialsView = false; // Toggle state
  bool _isSearchVisible = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Product> get _filteredProducts {
    final products = ref.read(inventoryProvider);
    var list = products.where((p) {
      // 1. Filter by Type (Product vs Material)
      if (p.isMaterial != _isMaterialsView) return false;

      // 2. Filter by Search
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!p.name.toLowerCase().contains(q) &&
            !p.sku.toLowerCase().contains(q) &&
            !p.category.toLowerCase().contains(q)) {
          return false;
        }
      }

      // 3. Filter by Stock Status
      switch (_selectedFilter) {
        case 1:
          return p.status == StockStatus.lowStock;
        case 2:
          return p.status == StockStatus.outOfStock;
        default:
          return true;
      }
    }).toList();
    return list;
  }

  int _countByStatus(StockStatus status) {
    final products = ref.read(inventoryProvider);
    return products
        .where((p) => p.status == status && p.isMaterial == _isMaterialsView)
        .length;
  }

  double _calculateTotalValue() {
    final products = ref.read(inventoryProvider);
    return products
        .where((p) => p.isMaterial == _isMaterialsView)
        .fold(0.0, (sum, p) => sum + p.totalValue);
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(inventoryProvider);
    final filtered = _filteredProducts;
    final inStock = _countByStatus(StockStatus.inStock);
    final lowStock = _countByStatus(StockStatus.lowStock);
    final outOfStock = _countByStatus(StockStatus.outOfStock);
    final totalValue = _calculateTotalValue();

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            _buildTypeToggle(),
            if (_isSearchVisible) _buildSearchBar(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
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
                    _StockValueCard(totalValue: totalValue),
                    const SizedBox(height: 16),
                    _buildQuickActions(),
                    const SizedBox(height: 16),
                    _buildFilterChips(products.length, lowStock, outOfStock),
                    const SizedBox(height: 16),
                    _buildProductList(filtered),
                  ],
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
            onPressed: () => Navigator.of(context).pop(),
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
          _headerButton(Icons.filter_list_rounded, () {
            HapticFeedback.lightImpact();
            showInventoryFilterSheet(context);
          }),
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        onChanged: (v) => setState(() => _searchQuery = v),
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
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddProductScreen()),
              );
            },
          ),
          const SizedBox(width: 10),
          _QuickActionButton(
            icon: Icons.inventory_2_rounded,
            label: 'Add Stock',
            onTap: () {
              HapticFeedback.lightImpact();
              _showStockActionSheet(context, ref, 'Add Stock', 'Restock');
            },
          ),
          const SizedBox(width: 10),
          _QuickActionButton(
            icon: Icons.tune_rounded,
            label: 'Adjust Stock',
            onTap: () {
              HapticFeedback.lightImpact();
              _showStockActionSheet(context, ref, 'Adjust Stock', 'Correction');
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
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ProductDetailScreen(productId: products[i].id),
                ),
              );
            },
            child: _ProductCard(product: products[i], index: i),
          ),
          if (i < products.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
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
              'No products found',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: 6),
            Text(
              'Try changing your filter or add new products',
              style: AppTypography.captionSmall
                  .copyWith(color: AppColors.textTertiary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  ADD STOCK / ADJUST STOCK SHEET
  // ═══════════════════════════════════════════════════
  //  OVERFLOW MENU
  // ═══════════════════════════════════════════════════
  void _showOverflowMenu() {
    showModalBottomSheet(
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
                      label: 'Import from Excel/CSV',
                      onTap: () {
                        Navigator.pop(ctx);
                        HapticFeedback.lightImpact();
                      },
                    ),
                    _overflowItem(
                      ctx,
                      icon: Icons.download_rounded,
                      label: 'Export Inventory',
                      onTap: () {
                        Navigator.pop(ctx);
                        HapticFeedback.lightImpact();
                      },
                    ),
                    _overflowItem(
                      ctx,
                      icon: Icons.settings_rounded,
                      label: 'Inventory Settings',
                      onTap: () {
                        Navigator.pop(ctx);
                        HapticFeedback.lightImpact();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const InventorySettingsScreen(),
                          ),
                        );
                      },
                    ),
                    _overflowItem(
                      ctx,
                      icon: Icons.print_rounded,
                      label: 'Print Labels',
                      onTap: () {
                        Navigator.pop(ctx);
                        HapticFeedback.lightImpact();
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
  ) {
    final products = ref.read(inventoryProvider);
    String? selectedProductId;
    int quantity = 0;
    String reason = defaultReason;
    final bool isAddStock = title == 'Add Stock';

    final reasons = isAddStock
        ? ['Restock', 'Return', 'Correction']
        : ['Correction', 'Damage', 'Loss', 'Return', 'Sale'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Padding(
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
                        'Choose a product...',
                        style: AppTypography.bodySmall
                            .copyWith(color: AppColors.textTertiary),
                      ),
                      icon: const Icon(Icons.expand_more_rounded,
                          color: AppColors.textTertiary),
                      isExpanded: true,
                      items: products
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text(
                                  '${p.name}  (${p.currentStock})',
                                  style: AppTypography.bodySmall.copyWith(
                                      color: AppColors.textPrimary),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setSheetState(() => selectedProductId = v),
                    ),
                  ),
                ),
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
                            setSheetState(() => quantity--);
                          } else if (!isAddStock) {
                            setSheetState(() => quantity--);
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
                        child: Center(
                          child: Text(
                            '${isAddStock ? '+' : ''}$quantity',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: quantity > 0
                                  ? AppColors.success
                                  : quantity < 0
                                      ? AppColors.danger
                                      : AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setSheetState(() => quantity++);
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
                        selectedProductId != null && quantity != 0
                            ? () {
                                ref
                                    .read(inventoryProvider.notifier)
                                    .adjustStock(
                                      selectedProductId!,
                                      quantity,
                                      reason,
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
    );
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
class _StockValueCard extends StatelessWidget {
  final double totalValue;

  const _StockValueCard({required this.totalValue});

  @override
  Widget build(BuildContext context) {
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
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estimated Value',
                    style: AppTypography.bodySmall.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'EGP ${_formatNumber(totalValue)}',
                    style: AppTypography.h2.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
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
class _ProductCard extends StatelessWidget {
  final Product product;
  final int index;

  const _ProductCard({required this.product, required this.index});

  @override
  Widget build(BuildContext context) {
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
            // Product icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: product.color.withValues(alpha: isOutOfStock ? 0.05 : 0.1),
              ),
              child: Icon(
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
                              'SKU: ${product.sku} • ${product.category}',
                              style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              'Supplier: ${product.supplier}',
                              style: AppTypography.captionSmall.copyWith(
                                color: AppColors.textTertiary.withValues(alpha: 0.7),
                                fontSize: 10,
                              ),
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
                            ? 'Cost: EGP ${product.costPrice.toStringAsFixed(2)}'
                            : 'EGP ${product.sellingPrice.toStringAsFixed(2)}',
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
