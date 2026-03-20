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
import 'edit_category_screen.dart';

class CategoryDetailScreen extends ConsumerWidget {
  final CategoryData category;
  final DateTime? month;

  const CategoryDetailScreen({super.key, required this.category, this.month});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final allTransactions = ref.watch(transactionsProvider).value ?? [];

    // Watch the live category from provider (so edits reflect immediately)
    final categories = ref.watch(categoriesProvider).value ?? [];
    final liveCategory = categories.firstWhere(
      (c) => c.id == category.id,
      orElse: () => category,
    );

    final categoryTx = allTransactions
        .where((t) => t.categoryId == liveCategory.id)
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    // Filter to selected month for budget calculations
    final budgetMonth = month ?? DateTime.now();
    final monthTx = categoryTx.where((t) =>
        t.dateTime.year == budgetMonth.year && t.dateTime.month == budgetMonth.month).toList();

    final totalSpend = monthTx.fold(0.0, (sum, t) => sum + t.amount.abs());
    final budget = liveCategory.budgetLimit ?? 0.0;
    final usedPercent = budget > 0 ? (totalSpend / budget * 100).clamp(0.0, 100.0).toInt() : 0;
    final remaining = budget > 0 ? (budget - totalSpend).clamp(0.0, double.infinity) : 0.0;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, ref, liveCategory),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SpendCard(
                      category: liveCategory,
                      totalSpend: totalSpend,
                      budget: budget,
                      usedPercent: usedPercent,
                      remaining: remaining,
                      transactionCount: monthTx.length,
                      currency: currency,
                    ),
                    const SizedBox(height: 16),
                    _BudgetControl(
                      category: liveCategory,
                      currency: currency,
                      onBudgetChanged: (newBudget) {
                        final updated = liveCategory.copyWith(
                          budgetLimit: newBudget,
                          updatedAt: DateTime.now(),
                        );
                        ref.read(categoriesProvider.notifier).updateCategory(updated);
                      },
                    ),
                    const SizedBox(height: 20),
                    _TrendChart(
                      category: liveCategory,
                      allCategoryTransactions: categoryTx,
                      currency: currency,
                    ),
                    const SizedBox(height: 24),
                    _TransactionsList(
                      transactions: categoryTx,
                      currency: currency,
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

  Widget _buildHeader(BuildContext context, WidgetRef ref, CategoryData liveCategory) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryNavy,
          ),
          Expanded(
            child: Text(
              liveCategory.name,
              textAlign: TextAlign.center,
              style: AppTypography.h3.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EditCategoryScreen(category: liveCategory),
              ),
            );
          },
          icon: const Icon(Icons.edit_rounded),
          color: AppColors.primaryNavy,
        ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  BUDGET CONTROL — inline set/edit budget
// ═══════════════════════════════════════════════════════════
class _BudgetControl extends StatefulWidget {
  final CategoryData category;
  final String currency;
  final ValueChanged<double?> onBudgetChanged;

  const _BudgetControl({
    required this.category,
    required this.currency,
    required this.onBudgetChanged,
  });

  @override
  State<_BudgetControl> createState() => _BudgetControlState();
}

class _BudgetControlState extends State<_BudgetControl> {
  bool _isEditing = false;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.category.budgetLimit?.toStringAsFixed(0) ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _BudgetControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.category.budgetLimit != widget.category.budgetLimit) {
      _controller.text = widget.category.budgetLimit?.toStringAsFixed(0) ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveBudget() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      widget.onBudgetChanged(null);
      HapticFeedback.mediumImpact();
    } else {
      final value = double.tryParse(text.replaceAll(',', ''));
      if (value != null && value > 0) {
        widget.onBudgetChanged(value);
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.heavyImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a valid budget amount')),
        );
        return;
      }
    }
    setState(() => _isEditing = false);
  }

  @override
  Widget build(BuildContext context) {
    final hasBudget = widget.category.budgetLimit != null && widget.category.budgetLimit! > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
      ),
      child: _isEditing ? _buildEditMode() : _buildViewMode(hasBudget),
    );
  }

  Widget _buildViewMode(bool hasBudget) {
    return Row(
      children: [
        Icon(
          Icons.account_balance_wallet_rounded,
          size: 20,
          color: hasBudget ? AppColors.primaryNavy : AppColors.textTertiary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Monthly Budget',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hasBudget
                    ? '${widget.currency} ${widget.category.budgetLimit!.toStringAsFixed(0)}'
                    : 'No budget set',
                style: AppTypography.labelMedium.copyWith(
                  color: hasBudget ? AppColors.primaryNavy : AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _isEditing = true);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.accentOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              hasBudget ? 'Edit' : 'Set Budget',
              style: TextStyle(
                color: AppColors.accentOrange,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SET MONTHLY BUDGET',
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: AppTypography.labelLarge.copyWith(
            color: AppColors.primaryNavy,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            prefixText: '${widget.currency} ',
            prefixStyle: AppTypography.labelLarge.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
            hintText: '0',
            filled: true,
            fillColor: AppColors.backgroundLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accentOrange, width: 2),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
          onSubmitted: (_) => _saveBudget(),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.category.budgetLimit != null) ...[
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  widget.onBudgetChanged(null);
                  setState(() => _isEditing = false);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    'Remove',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
            GestureDetector(
              onTap: () => setState(() => _isEditing = false),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: _saveBudget,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accentOrange,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  SPEND CARD
// ═══════════════════════════════════════════════════════════
class _SpendCard extends StatelessWidget {
  final CategoryData category;
  final double totalSpend;
  final double budget;
  final int usedPercent;
  final double remaining;
  final int transactionCount;
  final String currency;

  const _SpendCard({
    required this.category,
    required this.totalSpend,
    required this.budget,
    required this.usedPercent,
    required this.remaining,
    required this.transactionCount,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final isNearLimit = usedPercent >= 80;
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          // Header with icon
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: category.displayColor.withValues(alpha: 0.12),
                ),
                child: Icon(category.iconData, size: 22, color: category.displayColor),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CURRENT SPEND',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${months[now.month - 1]} ${now.year}',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Amount
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$currency ${totalSpend.toStringAsFixed(0)}',
                style: AppTypography.h1.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/ ${budget.toStringAsFixed(0)}',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),
          Text(
            '$transactionCount transaction${transactionCount != 1 ? 's' : ''} this month',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),

          const SizedBox(height: 18),

          // Progress bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$usedPercent% Used',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isNearLimit ? AppColors.accentOrange : AppColors.primaryNavy,
                ),
              ),
              Text(
                '$currency ${remaining.toStringAsFixed(0)} Left',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(50),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: usedPercent / 100),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, value, _) {
                return SizedBox(
                  height: 8,
                  child: LinearProgressIndicator(
                    value: value,
                    backgroundColor: const Color(0xFFF0F1F3),
                    valueColor: AlwaysStoppedAnimation(
                      isNearLimit ? AppColors.accentOrange : AppColors.primaryNavy,
                    ),
                  ),
                );
              },
            ),
          ),

          if (isNearLimit) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.warning_rounded, size: 14, color: AppColors.accentOrange),
                const SizedBox(width: 4),
                Text(
                  'Approaching budget limit',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.accentOrange,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.04, end: 0);
  }
}

// ═══════════════════════════════════════════════════════════
//  3-MONTH TREND CHART
// ═══════════════════════════════════════════════════════════
class _TrendChart extends StatelessWidget {
  final CategoryData category;
  final List<Transaction> allCategoryTransactions;
  final String currency;

  const _TrendChart({
    required this.category,
    required this.allCategoryTransactions,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    // Build real 3-month trend from transactions
    final now = DateTime.now();
    const monthNames = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final data = <_MonthData>[];
    double maxAmount = 0;
    for (int i = 2; i >= 0; i--) {
      final targetDate = DateTime(now.year, now.month - i, 1);
      final year = targetDate.year;
      final month = targetDate.month;
      final label = monthNames[month - 1];
      final amount = allCategoryTransactions
          .where((t) => t.dateTime.year == year && t.dateTime.month == month)
          .fold(0.0, (sum, t) => sum + t.amount.abs());
      if (amount > maxAmount) maxAmount = amount;
      data.add(_MonthData(label, amount, 0));
    }

    // Calculate height fractions relative to max
    final chartData = data.map((d) {
      final fraction = maxAmount > 0 ? (d.amount / maxAmount).clamp(0.05, 1.0) : 0.05;
      return _MonthData(d.label, d.amount, fraction);
    }).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          Text(
            '3 Month Trend',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: chartData.asMap().entries.map((entry) {
                final i = entry.key;
                final d = entry.value;
                final isCurrent = i == chartData.length - 1;

                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: i > 0 ? 12 : 0,
                      right: i < chartData.length - 1 ? 12 : 0,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          d.amount.toStringAsFixed(0),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isCurrent ? AppColors.primaryNavy : AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: d.heightFraction),
                            duration: Duration(milliseconds: 600 + i * 150),
                            curve: Curves.easeOutCubic,
                            builder: (_, value, _) {
                              return FractionallySizedBox(
                                heightFactor: value,
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isCurrent
                                        ? AppColors.primaryNavy
                                        : AppColors.primaryNavy.withValues(alpha: 0.15 + i * 0.15),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(8),
                                    ),
                                    border: isCurrent
                                        ? Border.all(
                                            color: AppColors.primaryNavy.withValues(alpha: 0.1),
                                            width: 2,
                                          )
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          d.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                            color: isCurrent ? AppColors.primaryNavy : AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms);
  }
}

class _MonthData {
  final String label;
  final double amount;
  final double heightFraction;

  const _MonthData(this.label, this.amount, this.heightFraction);
}

// ═══════════════════════════════════════════════════════════
//  TRANSACTIONS LIST
// ═══════════════════════════════════════════════════════════
class _TransactionsList extends StatelessWidget {
  final List<Transaction> transactions;
  final String currency;

  const _TransactionsList({required this.transactions, required this.currency});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Transactions',
          style: AppTypography.h3.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        if (transactions.isEmpty)
          _buildEmpty()
        else
          ...transactions.asMap().entries.map((entry) {
            final i = entry.key;
            final tx = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TransactionTile(transaction: tx, index: i, currency: currency),
            );
          }),
      ],
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(32),
      width: double.infinity,
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 40,
            color: AppColors.textTertiary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'No transactions yet',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final int index;
  final String currency;

  const _TransactionTile({required this.transaction, required this.index, required this.currency});

  String get _formattedDate {
    final d = transaction.dateTime;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day.toString().padLeft(2, '0')}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: CategoryData.findById(transaction.categoryId).displayColor.withValues(alpha: 0.08),
            ),
            child: Icon(
              CategoryData.findById(transaction.categoryId).iconData,
              size: 20,
              color: CategoryData.findById(transaction.categoryId).displayColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formattedDate,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            transaction.isIncome
                ? '+$currency ${transaction.amount.abs().toStringAsFixed(0)}'
                : '-$currency ${transaction.amount.abs().toStringAsFixed(0)}',
            style: AppTypography.labelMedium.copyWith(
              color: transaction.isIncome ? AppColors.success : AppColors.danger,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(
          duration: 300.ms,
          delay: Duration(milliseconds: 50 * index),
        )
        .slideX(begin: 0.03, end: 0, duration: 300.ms, delay: Duration(milliseconds: 50 * index));
  }
}
