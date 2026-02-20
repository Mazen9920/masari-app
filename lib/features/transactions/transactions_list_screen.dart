import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/transaction_model.dart';
import '../dashboard/widgets/recent_transactions.dart';
import 'transaction_detail_screen.dart';
import 'widgets/transaction_filter_sheet.dart';
import 'widgets/transaction_search_delegate.dart';

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

  final _periods = const ['All', 'This Week', 'This Month', 'Last Month', 'Custom'];

  @override
  void initState() {
    super.initState();
    if (widget.initialFilter != null) {
      _filter = widget.initialFilter!;
    }
  }

  List<Transaction> get _allTransactions => ref.watch(transactionsProvider);

  List<Transaction> get _filteredTransactions {
    var list = List<Transaction>.from(_allTransactions);

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

    // Filter by categories
    if (_filter.selectedCategories.isNotEmpty) {
      list = list
          .where((t) => _filter.selectedCategories.contains(t.category.name))
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

  Map<String, List<Transaction>> get _groupedTransactions {
    final map = <String, List<Transaction>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final tx in _filteredTransactions) {
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
      _filteredTransactions.where((t) => t.isIncome).fold(0.0, (sum, t) => sum + t.amount);

  double get _totalExpenses =>
      _filteredTransactions.where((t) => !t.isIncome).fold(0.0, (sum, t) => sum + t.amount.abs());

  void _openFilter() async {
    HapticFeedback.lightImpact();
    final result = await showModalBottomSheet<TransactionFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TransactionFilterSheet(initialFilter: _filter),
    );
    if (result != null) {
      setState(() => _filter = result);
    }
  }

  void _openSearch() {
    HapticFeedback.lightImpact();
    showSearch(
      context: context,
      delegate: TransactionSearchDelegate(transactions: _allTransactions),
    );
  }

  void _onTransactionTap(Transaction tx) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransactionDetailScreen(
          transaction: TransactionItem(
            title: tx.title,
            subtitle: '${_formatMonthDay(tx.dateTime)}, ${tx.formattedTime}',
            amount: tx.amount,
            icon: tx.category.icon,
            iconBgColor: tx.category.bgColor,
            iconColor: tx.category.color,
            category: tx.category.name,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            _buildPeriodPills(),
            _buildSummaryBar(),
            Expanded(child: _buildTransactionsList()),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════
  Widget _buildHeader() {
    final hasBack = widget.showBackButton;
    return Padding(
      padding: EdgeInsets.fromLTRB(hasBack ? 8 : 20, 8, 12, 4),
      child: Row(
        children: [
          if (hasBack)
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
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
              _headerButton(Icons.search_rounded, _openSearch),
              const SizedBox(width: 2),
              Stack(
                children: [
                  _headerButton(Icons.filter_list_rounded, _openFilter),
                  if (!_filter.isDefault)
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
                            '${_filter.activeCount}',
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
            onTap: () {
              HapticFeedback.lightImpact();
              setState(() => _selectedPeriodIndex = index);
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
                    '+\$${_totalIncome.toStringAsFixed(2)}',
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
                    '-\$${_totalExpenses.toStringAsFixed(2)}',
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
      for (final tx in entry.value) {
        final i = animIndex++;
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
      }
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 100, top: 8),
      children: items,
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
class _TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback onTap;

  const _TransactionTile({
    required this.transaction,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                  color: transaction.category.bgColor,
                ),
                child: Icon(
                  transaction.category.icon,
                  color: transaction.category.color,
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
                        transaction.category.name,
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
                    transaction.formattedAmount,
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
