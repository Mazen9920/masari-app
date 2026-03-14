import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/transaction_model.dart';
import '../../shared/models/category_data.dart';
import 'add_category_sheet.dart';
import 'categories_filter_sheet.dart';
import '../../shared/widgets/async_value_widget.dart';
import 'categorize_transactions_sheet.dart';
import '../../shared/utils/safe_pop.dart';

class CategoriesListScreen extends ConsumerStatefulWidget {
  const CategoriesListScreen({super.key});

  @override
  ConsumerState<CategoriesListScreen> createState() => _CategoriesListScreenState();
}

class _CategoriesListScreenState extends ConsumerState<CategoriesListScreen> {
  bool _isExpense = true;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  CategoryFilterResult _categoryFilter = const CategoryFilterResult();

  // ─── Computed Data ───
  List<Transaction> get _transactions => ref.watch(transactionsProvider).value ?? [];

  List<Transaction> get _filteredByType {
    final timeFiltered = _transactions.where((t) => 
      !t.excludeFromPL &&
      t.dateTime.year == _selectedMonth.year && 
      t.dateTime.month == _selectedMonth.month
    );
    if (_isExpense) {
      return timeFiltered.where((t) => !t.isIncome).toList();
    } else {
      return timeFiltered.where((t) => t.isIncome).toList();
    }
  }

  double get _totalAmount =>
      _filteredByType.fold(0.0, (sum, t) => sum + t.amount.abs());

  List<_CategoryBreakdown> get _breakdowns {
    final map = <String, _CategoryBreakdown>{};

    for (final tx in _filteredByType) {
      final name = CategoryData.findById(tx.categoryId).name;
      final existing = map[name];
      if (existing != null) {
        map[name] = _CategoryBreakdown(
          category: CategoryData.findById(tx.categoryId),
          totalAmount: existing.totalAmount + tx.amount.abs(),
          transactionCount: existing.transactionCount + 1,
        );
      } else {
        map[name] = _CategoryBreakdown(
          category: CategoryData.findById(tx.categoryId),
          totalAmount: tx.amount.abs(),
          transactionCount: 1,
        );
      }
    }

    final list = map.values.toList();

    // Sort according to the filter sheet setting
    switch (_categoryFilter.sortBy) {
      case CategorySortBy.highestAmount:
        list.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
      case CategorySortBy.lowestAmount:
        list.sort((a, b) => a.totalAmount.compareTo(b.totalAmount));
      case CategorySortBy.mostTransactions:
        list.sort((a, b) => b.transactionCount.compareTo(a.transactionCount));
      case CategorySortBy.nameAZ:
        list.sort((a, b) => a.category.name.compareTo(b.category.name));
    }

    // Hide categories with zero spending when requested
    if (_categoryFilter.hideEmpty) {
      return list.where((b) => b.totalAmount > 0).toList();
    }

    return list;
  }

  String get _monthLabel {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[_selectedMonth.month - 1]} ${_selectedMonth.year}';
  }

  String? get _topCategoryName =>
      _breakdowns.isNotEmpty ? _breakdowns.first.category.name : null;

  int get _topCategoryPercent {
    if (_breakdowns.isEmpty || _totalAmount == 0) return 0;
    return ((_breakdowns.first.totalAmount / _totalAmount) * 100).round();
  }

  void _previousMonth() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
  }

  // Inside _CategoriesListScreenState
  void _recalculateData(List<Transaction> transactions) {
    // This method would typically update state variables based on the new transactions list.
    // For now, we'll just ensure the getters (_filteredByType, _totalAmount, _breakdowns)
    // are implicitly re-evaluated when `transactionsAsync` changes.
    // If there were local state variables derived from transactions, they would be updated here.
  }

  // ─── Build ───
  @override
  Widget build(BuildContext context) {
    final transactionsAsync = ref.watch(transactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: AsyncValueWidget<List<Transaction>>(
                    value: transactionsAsync,
                    data: (transactions) {
                      // Re-calculate derived data since we don't have heavy providers for these yet
                      _recalculateData(transactions);
                      
                      final uncategorizedCount = transactions.where((t) => CategoryData.findById(t.categoryId).name == 'Uncategorized').length;

                      return RefreshIndicator(
                        onRefresh: () => ref.read(transactionsProvider.notifier).refresh(),
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics()),
                          child: Column(
                            children: [
                              const SizedBox(height: 4),
                              _buildMonthSelector(),
                              const SizedBox(height: 16),
                              _buildToggle(),
                              const SizedBox(height: 20),
                              _buildSummaryCard(uncategorizedCount),
                              const SizedBox(height: 20),
                              _buildCategoryList(),
                              const SizedBox(height: 140),
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
            // FAB positioned above the bottom nav bar
            Positioned(
              bottom: 100,
              left: 0,
              right: 0,
              child: Center(child: _buildFAB()),
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
    final canPop = Navigator.of(context).canPop();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          if (canPop)
            IconButton(
              onPressed: () => context.safePop(),
              icon: const Icon(Icons.arrow_back_rounded),
              color: AppColors.primaryNavy,
              padding: const EdgeInsets.all(8),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: canPop ? 0 : 8),
              child: Text(
                'Categories',
                style: AppTypography.h1.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(transactionsProvider.notifier).refresh();
              },
              borderRadius: BorderRadius.circular(50),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 24),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                context.pushNamed('BudgetsOverviewScreen');
              },
              borderRadius: BorderRadius.circular(50),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.account_balance_wallet_rounded, color: AppColors.textSecondary, size: 24),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                context.pushNamed('ManageCategoriesScreen');
              },
              borderRadius: BorderRadius.circular(50),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.settings_rounded, color: AppColors.textSecondary, size: 24),
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                HapticFeedback.lightImpact();
                final result = await showCategoriesFilterSheet(
                  context,
                  current: _categoryFilter,
                );
                if (result != null) {
                  setState(() {
                    _categoryFilter = result;
                    // Sync dateRange selection to the month navigator
                    final now = DateTime.now();
                    if (result.dateRange == 'This Month') {
                      _selectedMonth = DateTime(now.year, now.month);
                    } else if (result.dateRange == 'Last Month') {
                      _selectedMonth = DateTime(now.year, now.month - 1);
                    } else if (result.dateRange == 'Quarter to Date') {
                      // Show start of current quarter's month
                      final quarterStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
                      _selectedMonth = DateTime(now.year, quarterStartMonth);
                    }
                  });
                }
              },
              borderRadius: BorderRadius.circular(50),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.tune_rounded, color: AppColors.textSecondary, size: 24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  MONTH SELECTOR
  // ═══════════════════════════════════════════════════
  Widget _buildMonthSelector() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _previousMonth,
              child: Icon(
                Icons.chevron_left_rounded,
                size: 22,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _monthLabel,
              style: AppTypography.labelMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: _nextMonth,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ═══════════════════════════════════════════════════
  //  EXPENSE / INCOME TOGGLE
  // ═══════════════════════════════════════════════════
  Widget _buildToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFEEEFF0),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(child: _toggleButton('Expense', true)),
            Expanded(child: _toggleButton('Income', false)),
          ],
        ),
      ),
    );
  }

  Widget _toggleButton(String label, bool isExpenseMode) {
    final isSelected = _isExpense == isExpenseMode;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _isExpense = isExpenseMode);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: isSelected ? AppColors.primaryNavy : AppColors.textTertiary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  SUMMARY CARD
  // ═══════════════════════════════════════════════════
  Widget _buildSummaryCard(int uncategorizedCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
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
            // Header row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'THIS MONTH',
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    fontSize: 11,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primaryNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Text(
                    'DETAILS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryNavy,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Total amount
            Text(
              '${ref.watch(appSettingsProvider).currency} ${_totalAmount.toStringAsFixed(0)}',
              style: AppTypography.h1.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w800,
                fontSize: 32,
                letterSpacing: -1,
              ),
            ),

            const SizedBox(height: 4),

            // Top category
            if (_topCategoryName != null)
              Row(
                children: [
                  Text(
                    'Top category: ',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                  Text(
                    _topCategoryName!,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.textTertiary.withValues(alpha: 0.5),
                    ),
                  ),
                  Text(
                    '$_topCategoryPercent%',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 16),

            // Uncategorized alert
            if (uncategorizedCount > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.accentOrange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.accentOrange.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.accentOrange.withValues(alpha: 0.15),
                      ),
                      child: const Icon(
                        Icons.priority_high_rounded,
                        size: 18,
                        color: AppColors.accentOrange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$uncategorizedCount Uncategorized',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Please review these transactions',
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        final uncategorized = _transactions
                            .where((t) =>
                                CategoryData.findById(t.categoryId).name ==
                                'Uncategorized')
                            .toList();
                        if (uncategorized.isEmpty || !context.mounted) return;
                        final saved = await showCategorizeTransactionsSheet(
                          context,
                          uncategorized,
                        );
                        if (saved > 0 && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '$saved ${saved == 1 ? 'transaction' : 'transactions'} categorized',
                              ),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          );
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(50),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                          border: Border.all(
                            color: AppColors.accentOrange.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Text(
                          'Review',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.accentOrange,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  // ═══════════════════════════════════════════════════
  //  CATEGORY LIST
  // ═══════════════════════════════════════════════════
  Widget _buildCategoryList() {
    final items = _breakdowns;

    if (items.isEmpty) {
      return _buildEmptyState();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            GestureDetector(
              onTap: () {
                context.pushNamed(
                  'CategoryDetailScreen', 
                  extra: {
                    'category': items[i].category,
                    'month': _selectedMonth,
                  },
                );
              },
              child: _CategoryCard(
                breakdown: items[i],
                total: _totalAmount,
                index: i,
              ),
            ),
            // Insert AI insight card after 2nd item
            if (i == 1) _buildAIInsightCard(),
            if (i < items.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  /// Computes a dynamic insight by comparing the current month's top category
  /// with the previous month. Returns null if there's nothing meaningful.
  String? _computeCategoryInsight() {
    final breakdowns = _breakdowns;
    if (breakdowns.isEmpty) return null;

    final top = breakdowns.first;
    final pct = _totalAmount > 0
        ? (top.totalAmount / _totalAmount * 100).round()
        : 0;

    // Get previous month's data for the same category
    final prevMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    final prevTransactions = _transactions.where((t) =>
        !t.excludeFromPL &&
        t.dateTime.year == prevMonth.year &&
        t.dateTime.month == prevMonth.month &&
        (_isExpense ? !t.isIncome : t.isIncome));

    double prevCatTotal = 0;
    for (final t in prevTransactions) {
      if (CategoryData.findById(t.categoryId).name == top.category.name) {
        prevCatTotal += t.amount.abs();
      }
    }

    final catName = top.category.name;

    // No previous data — show share insight
    if (prevCatTotal == 0 && top.totalAmount > 0) {
      return '$catName is your top ${_isExpense ? "expense" : "income"} category this month, representing $pct% of total.';
    }

    // Compare with previous month
    if (prevCatTotal > 0) {
      final change = ((top.totalAmount - prevCatTotal) / prevCatTotal * 100).round();
      if (change > 0) {
        return '$catName is $change% higher than last month. It accounts for $pct% of total ${_isExpense ? "expenses" : "income"}.';
      } else if (change < 0) {
        return '$catName is ${change.abs()}% lower than last month. It accounts for $pct% of total ${_isExpense ? "expenses" : "income"}.';
      } else {
        return '$catName is unchanged from last month at $pct% of total.';
      }
    }

    return '$catName accounts for $pct% of your total ${_isExpense ? "expenses" : "income"} this month.';
  }

  Widget _buildAIInsightCard() {
    // Compute dynamic insight from actual data
    final insight = _computeCategoryInsight();
    if (insight == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primaryNavy.withValues(alpha: 0.04),
              Colors.transparent,
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primaryNavy.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: AppColors.primaryNavy,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.5,
                      ),
                      children: [
                        const TextSpan(
                          text: 'Insight: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                        TextSpan(text: insight),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('AI Insights — coming soon!')),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ask AI (Coming Soon)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 10,
                          color: AppColors.primaryNavy,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentOrange.withValues(alpha: 0.08),
            ),
            child: Icon(
              Icons.grid_view_rounded,
              size: 36,
              color: AppColors.accentOrange.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No Categories Yet',
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add transactions to see category breakdowns',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).scale(begin: const Offset(0.95, 0.95));
  }

  // ═══════════════════════════════════════════════════
  //  FAB
  // ═══════════════════════════════════════════════════
  Widget _buildFAB() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentOrange.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        heroTag: 'categories_add_fab',
        onPressed: () {
          HapticFeedback.mediumImpact();
          showAddCategorySheet(context);
        },
        backgroundColor: AppColors.accentOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        icon: const Icon(Icons.add_rounded, size: 22),
        label: Text(
          'Add Category',
          style: AppTypography.labelMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  CATEGORY CARD WIDGET
// ═══════════════════════════════════════════════════════════
class _CategoryCard extends ConsumerWidget {
  final _CategoryBreakdown breakdown;
  final double total;
  final int index;

  const _CategoryCard({
    required this.breakdown,
    required this.total,
    required this.index,
  });

  bool get _hasBudget => breakdown.category.budgetLimit != null && breakdown.category.budgetLimit! > 0;
  double get _budget => breakdown.category.budgetLimit ?? 0;

  double get _percentage {
    if (_hasBudget) {
      return (breakdown.totalAmount / _budget).clamp(0.0, 1.0);
    }
    return total > 0 ? (breakdown.totalAmount / total).clamp(0.0, 1.0) : 0.0;
  }
  
  int get _percentInt => (_percentage * 100).round();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        children: [
          // Top row: icon dot + name + amount
          Row(
            children: [
              // Color dot
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: breakdown.category.displayColor,
                ),
              ),
              const SizedBox(width: 12),

              // Name + count
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      breakdown.category.name,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${breakdown.transactionCount} transaction${breakdown.transactionCount != 1 ? 's' : ''}',
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Amount + percentage
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${ref.watch(appSettingsProvider).currency} ${breakdown.totalAmount.toStringAsFixed(0)}',
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (_hasBudget)
                          TextSpan(
                            text: ' / ${_budget.toStringAsFixed(0)}',
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _hasBudget ? '$_percentInt% used' : '$_percentInt% of total',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: SizedBox(
              height: 6,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _percentage),
                duration: Duration(milliseconds: 600 + (index * 100)),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return LinearProgressIndicator(
                    value: value,
                    backgroundColor: const Color(0xFFF0F1F3),
                    valueColor: AlwaysStoppedAnimation(breakdown.category.displayColor),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(
          duration: 350.ms,
          delay: Duration(milliseconds: 60 * index),
        )
        .slideX(
          begin: 0.04,
          end: 0,
          duration: 350.ms,
          delay: Duration(milliseconds: 60 * index),
          curve: Curves.easeOutCubic,
        );
  }
}

// ═══════════════════════════════════════════════════════════
//  DATA MODEL
// ═══════════════════════════════════════════════════════════
class _CategoryBreakdown {
  final CategoryData category;
  final double totalAmount;
  final int transactionCount;

  const _CategoryBreakdown({
    required this.category,
    required this.totalAmount,
    required this.transactionCount,
  });
}
