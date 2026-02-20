import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/supplier_model.dart';
import 'add_supplier_screen.dart';
import 'record_purchase_screen.dart';
import 'record_payment_screen.dart';
import 'supplier_detail_screen.dart';
import 'payments_summary_screen.dart';
import 'purchases_summary_screen.dart';

/// Suppliers Overview — summary, quick actions, filter chips, supplier list.
class SuppliersOverviewScreen extends ConsumerStatefulWidget {
  const SuppliersOverviewScreen({super.key});

  @override
  ConsumerState<SuppliersOverviewScreen> createState() =>
      _SuppliersOverviewScreenState();
}

class _SuppliersOverviewScreenState
    extends ConsumerState<SuppliersOverviewScreen> {
  int _filterIndex = 0; // 0=All, 1=Balance due, 2=Overdue, 3=Recently used

  // ── Advanced filter state ──
  int _sortMode = 0; // 0=Recent, 1=Balance High→Low, 2=A-Z, 3=Overdue
  int _statusFilter = 0; // 0=All, 1=Has Balance, 2=Overdue, 3=Paid
  final Set<String> _selectedCategories = {};
  final _minBalanceCtrl = TextEditingController();
  final _maxBalanceCtrl = TextEditingController();
  bool _advancedActive = false;

  @override
  void dispose() {
    _minBalanceCtrl.dispose();
    _maxBalanceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = ref.watch(suppliersProvider);

    // Filtered list
    final filtered = _applyFilter(suppliers);

    // Stats
    final totalSuppliers = suppliers.length;
    final totalOutstanding =
        suppliers.fold<double>(0, (sum, s) => sum + s.balance);
    final overdueCount = suppliers.where((s) => s.isOverdue).length;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary strip
                    _SummaryStrip(
                      totalSuppliers: totalSuppliers,
                      totalOutstanding: totalOutstanding,
                      overdueCount: overdueCount,
                    ).animate().fadeIn(duration: 250.ms),

                    // Summary Cards
                    _buildSummaryCards()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 50.ms),

                    // Quick actions
                    _buildQuickActions()
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 50.ms),

                    // Filter chips
                    _buildFilterChips(overdueCount)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 80.ms),

                    // Supplier cards
                    ...List.generate(filtered.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: _SupplierCard(supplier: filtered[i])
                            .animate()
                            .fadeIn(
                                duration: 200.ms,
                                delay: (100 + i * 40).ms)
                            .slideY(begin: 0.04),
                      );
                    }),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Supplier> _applyFilter(List<Supplier> all) {
    var result = List<Supplier>.from(all);

    // ── Chip filter ──
    switch (_filterIndex) {
      case 1:
        result = result.where((s) => s.hasDue).toList();
        break;
      case 2:
        result = result.where((s) => s.isOverdue).toList();
        break;
      case 3:
        result.sort(
            (a, b) => b.lastTransaction.compareTo(a.lastTransaction));
        return result; // skip advanced if using "recently used" chip
    }

    // ── Advanced filters (when sheet applied) ──
    if (_advancedActive) {
      // Status
      switch (_statusFilter) {
        case 1:
          result = result.where((s) => s.hasDue).toList();
          break;
        case 2:
          result = result.where((s) => s.isOverdue).toList();
          break;
        case 3:
          result = result.where((s) => s.isPaid).toList();
          break;
      }

      // Categories
      if (_selectedCategories.isNotEmpty) {
        result = result
            .where((s) => _selectedCategories.contains(s.category))
            .toList();
      }

      // Balance range
      final minB =
          double.tryParse(_minBalanceCtrl.text.replaceAll(',', ''));
      final maxB =
          double.tryParse(_maxBalanceCtrl.text.replaceAll(',', ''));
      if (minB != null) {
        result = result.where((s) => s.balance >= minB).toList();
      }
      if (maxB != null) {
        result = result.where((s) => s.balance <= maxB).toList();
      }

      // Sort
      switch (_sortMode) {
        case 0:
          result.sort(
              (a, b) => b.lastTransaction.compareTo(a.lastTransaction));
          break;
        case 1:
          result.sort((a, b) => b.balance.compareTo(a.balance));
          break;
        case 2:
          result.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          break;
        case 3:
          result.sort((a, b) {
            if (a.isOverdue && !b.isOverdue) return -1;
            if (!a.isOverdue && b.isOverdue) return 1;
            return b.daysOverdue.compareTo(a.daysOverdue);
          });
          break;
      }
    }

    return result;
  }

  // ═══════════════════════════════════════════════════════
  //  FILTER & SORT SHEET
  // ═══════════════════════════════════════════════════════
  void _showFilterSheet(List<Supplier> suppliers) {
    // Collect unique categories
    final allCategories =
        suppliers.map((s) => s.category).toSet().toList()..sort();

    // Temporary state for the sheet
    int tempSort = _sortMode;
    int tempStatus = _statusFilter;
    final tempCategories = Set<String>.from(_selectedCategories);
    final tempMinCtrl =
        TextEditingController(text: _minBalanceCtrl.text);
    final tempMaxCtrl =
        TextEditingController(text: _maxBalanceCtrl.text);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.88,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Handle + Header ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Filter & Sort',
                            style: TextStyle(
                              color: AppColors.primaryNavy,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close_rounded),
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                  Divider(
                      height: 1,
                      color:
                          AppColors.borderLight.withValues(alpha: 0.5)),

                  // ── Scrollable content ──
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── SORT BY ──
                          Text(
                            'Sort By',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ..._sortOptions.asMap().entries.map((e) {
                            final i = e.key;
                            final label = e.value;
                            final selected = tempSort == i;
                            return GestureDetector(
                              onTap: () =>
                                  setSheetState(() => tempSort = i),
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 12),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      label,
                                      style: TextStyle(
                                        color: selected
                                            ? AppColors.primaryNavy
                                            : AppColors.textSecondary,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: selected
                                              ? const Color(0xFFE67E22)
                                              : AppColors.borderLight,
                                          width: 2,
                                        ),
                                      ),
                                      child: selected
                                          ? Center(
                                              child: Container(
                                                width: 12,
                                                height: 12,
                                                decoration:
                                                    const BoxDecoration(
                                                  color:
                                                      Color(0xFFE67E22),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            )
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),

                          const SizedBox(height: 20),

                          // ── SUPPLIER STATUS ──
                          Text(
                            'Supplier Status',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                _statusOptions.asMap().entries.map((e) {
                              final i = e.key;
                              final label = e.value;
                              final selected = tempStatus == i;
                              return GestureDetector(
                                onTap: () => setSheetState(
                                    () => tempStatus = i),
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.primaryNavy
                                        : Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(14),
                                    border: Border.all(
                                      color: selected
                                          ? Colors.transparent
                                          : AppColors.borderLight,
                                    ),
                                  ),
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 24),

                          // ── CATEGORY ──
                          Text(
                            'Category',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: allCategories.map((cat) {
                              final selected =
                                  tempCategories.contains(cat);
                              return GestureDetector(
                                onTap: () {
                                  setSheetState(() {
                                    if (selected) {
                                      tempCategories.remove(cat);
                                    } else {
                                      tempCategories.add(cat);
                                    }
                                  });
                                },
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFFFFF7ED)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xFFFED7AA)
                                          : AppColors.borderLight,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        cat,
                                        style: TextStyle(
                                          color: selected
                                              ? const Color(0xFFE67E22)
                                              : AppColors.textSecondary,
                                          fontSize: 13,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                      ),
                                      if (selected) ...[
                                        const SizedBox(width: 4),
                                        Icon(Icons.close_rounded,
                                            size: 14,
                                            color: const Color(
                                                0xFFE67E22)),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 24),

                          // ── BALANCE RANGE ──
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Outstanding Balance Range ',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                TextSpan(
                                  text: '(EGP)',
                                  style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontWeight: FontWeight.w400,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: tempMinCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    hintText: 'Min',
                                    hintStyle: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 14,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: AppColors.borderLight),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: AppColors.borderLight),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: const Color(0xFFE67E22)),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 12),
                                  ),
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12),
                                child: Text('–',
                                    style: TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 16)),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: tempMaxCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    hintText: 'Max',
                                    hintStyle: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 14,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: AppColors.borderLight),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: AppColors.borderLight),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                          color: const Color(0xFFE67E22)),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 12),
                                  ),
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),

                  // ── Footer: Apply + Reset ──
                  Container(
                    padding: EdgeInsets.fromLTRB(20, 14, 20,
                        MediaQuery.of(ctx).padding.bottom + 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        top: BorderSide(
                            color: AppColors.borderLight
                                .withValues(alpha: 0.5)),
                      ),
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            setState(() {
                              _sortMode = tempSort;
                              _statusFilter = tempStatus;
                              _selectedCategories
                                ..clear()
                                ..addAll(tempCategories);
                              _minBalanceCtrl.text = tempMinCtrl.text;
                              _maxBalanceCtrl.text = tempMaxCtrl.text;
                              _advancedActive = true;
                            });
                            Navigator.of(ctx).pop();
                          },
                          child: Container(
                            width: double.infinity,
                            padding:
                                const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE67E22),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE67E22)
                                      .withValues(alpha: 0.25),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'Apply Filters',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _sortMode = 0;
                              _statusFilter = 0;
                              _selectedCategories.clear();
                              _minBalanceCtrl.clear();
                              _maxBalanceCtrl.clear();
                              _advancedActive = false;
                            });
                            Navigator.of(ctx).pop();
                          },
                          child: Center(
                            child: Text(
                              'Reset',
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static const _sortOptions = [
    'Recent Activity',
    'Balance (High to Low)',
    'A-Z',
    'Overdue Amount',
  ];

  static const _statusOptions = ['All', 'Has Balance Due', 'Overdue', 'Paid'];

  // ═══════════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryNavy,
          ),
          Expanded(
            child: Text(
              'Suppliers',
              style: AppTypography.h1.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w800,
                fontSize: 22,
                letterSpacing: -0.3,
              ),
            ),
          ),
          IconButton(
            onPressed: () => HapticFeedback.lightImpact(),
            icon: const Icon(Icons.search_rounded),
            color: AppColors.primaryNavy,
          ),
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              _showFilterSheet(ref.read(suppliersProvider));
            },
            icon: const Icon(Icons.tune_rounded),
            color: AppColors.primaryNavy,
          ),
          IconButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const AddSupplierScreen()),
              );
            },
            icon: const Icon(Icons.add_rounded),
            color: AppColors.primaryNavy,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  SUMMARY CARDS
  // ═══════════════════════════════════════════════════════
  Widget _buildSummaryCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: _summaryNavCard(
              title: 'Payments',
              subtitle: 'EGP 82.4k',
              icon: Icons.payments_rounded,
              color: AppColors.primaryNavy,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PaymentsSummaryScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _summaryNavCard(
              title: 'Purchases',
              subtitle: 'EGP 124.5k',
              icon: Icons.shopping_bag_rounded,
              color: const Color(0xFFE67E22),
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PurchasesSummaryScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryNavCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.borderLight.withValues(alpha: 0.4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                Icon(Icons.arrow_forward_rounded,
                    color: AppColors.textTertiary, size: 16),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  QUICK ACTIONS
  // ═══════════════════════════════════════════════════════
  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _quickActionPill(
              icon: Icons.add_rounded,
              label: 'Add Supplier',
              filled: true,
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const AddSupplierScreen()),
                );
              },
            ),
            const SizedBox(width: 10),
            _quickActionPill(
              icon: Icons.shopping_cart_rounded,
              label: 'Record Purchase',
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const RecordPurchaseScreen()),
                );
              },
            ),
            const SizedBox(width: 10),
            _quickActionPill(
              icon: Icons.payments_rounded,
              label: 'Record Payment',
              onTap: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const RecordPaymentScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickActionPill({
    required IconData icon,
    required String label,
    bool filled = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: filled ? const Color(0xFFE67E22) : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: filled
              ? null
              : Border.all(color: AppColors.primaryNavy),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color:
                        const Color(0xFFE67E22).withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: filled ? Colors.white : AppColors.primaryNavy),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: filled ? Colors.white : AppColors.primaryNavy,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  FILTER CHIPS
  // ═══════════════════════════════════════════════════════
  Widget _buildFilterChips(int overdueCount) {
    final chips = [
      'All',
      'With balance due',
      'Overdue ($overdueCount)',
      'Recently used',
    ];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const BouncingScrollPhysics(),
          itemCount: chips.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final selected = _filterIndex == i;
            final isOverdue = i == 2;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _filterIndex = i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryNavy
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: isOverdue && !selected
                      ? Border.all(
                          color: const Color(0xFFDC2626)
                              .withValues(alpha: 0.3))
                      : null,
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: AppColors.primaryNavy
                                .withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: Text(
                  chips[i],
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : isOverdue
                            ? const Color(0xFFDC2626)
                            : AppColors.textSecondary,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SUMMARY STRIP
// ═══════════════════════════════════════════════════════
class _SummaryStrip extends StatelessWidget {
  final int totalSuppliers;
  final double totalOutstanding;
  final int overdueCount;

  const _SummaryStrip({
    required this.totalSuppliers,
    required this.totalOutstanding,
    required this.overdueCount,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'en');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryNavy.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              _stat('Suppliers', '$totalSuppliers', null),
              VerticalDivider(
                  color: AppColors.borderLight.withValues(alpha: 0.5),
                  width: 1),
              _stat('Outstanding', fmt.format(totalOutstanding), 'EGP'),
              VerticalDivider(
                  color: AppColors.borderLight.withValues(alpha: 0.5),
                  width: 1),
              _stat('Overdue', '$overdueCount', null,
                  valueColor: overdueCount > 0
                      ? const Color(0xFFDC2626)
                      : null),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value, String? prefix,
      {Color? valueColor}) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          if (prefix != null)
            Text(
              prefix,
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.primaryNavy,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SUPPLIER CARD
// ═══════════════════════════════════════════════════════
class _SupplierCard extends StatelessWidget {
  final Supplier supplier;

  const _SupplierCard({required this.supplier});

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('MMM dd');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SupplierDetailScreen(supplier: supplier),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryNavy.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: supplier.avatarBg,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    supplier.initials,
                    style: TextStyle(
                      color: supplier.avatarTextColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
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
                      supplier.name,
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          supplier.category,
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '•',
                            style: TextStyle(
                              color: AppColors.borderLight,
                              fontSize: 10,
                            ),
                          ),
                        ),
                        Text(
                          'Last: ${dateFormatter.format(supplier.lastTransaction)}',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Badge
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: supplier.isPaid
                          ? const Color(0xFFF1F5F9)
                          : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      supplier.isPaid
                          ? 'Paid'
                          : 'EGP ${NumberFormat('#,##0').format(supplier.balance)} due',
                      style: TextStyle(
                        color: supplier.isPaid
                            ? AppColors.textTertiary
                            : const Color(0xFF92400E),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (supplier.isOverdue) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Overdue ${supplier.daysOverdue}d',
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
