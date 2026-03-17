import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/purchase_model.dart';
import '../../shared/models/supplier_model.dart';
import '../transactions/transactions_list_screen.dart';
import '../../shared/models/transaction_model.dart';
import 'purchase_detail_screen.dart';

/// Purchases Summary Dashboard — overview of supplier purchase activity.
class PurchasesSummaryScreen extends ConsumerWidget {
  const PurchasesSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(currencyProvider);
    final purchases = ref.watch(purchasesProvider);
    final fmt = NumberFormat('#,##0');

    // Compute stats from real data
    final now = DateTime.now();
    final thisMonth = purchases.where((p) =>
        p.date.year == now.year && p.date.month == now.month).toList();
    final totalThisMonth = thisMonth.fold<double>(0, (s, p) => s + p.total);
    final totalItems = thisMonth.fold<int>(0, (s, p) => s + p.items.length);
    final avgOrder = thisMonth.isEmpty ? 0.0 : totalThisMonth / thisMonth.length;

    // Recent 5 purchases
    final sorted = List<Purchase>.from(purchases)
      ..sort((a, b) => b.date.compareTo(a.date));
    final recent = sorted.take(5).toList();

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _HeroCard(fmt: fmt, currency: currency, total: totalThisMonth)
                        .animate()
                        .fadeIn(duration: 300.ms)
                        .slideY(begin: 0.04),
                    const SizedBox(height: 16),
                    _StatsRow(fmt: fmt, currency: currency, totalItems: totalItems, avgOrder: avgOrder)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 20),
                    _TrendsChart(purchases: purchases)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 100.ms),
                    const SizedBox(height: 20),
                    _RecentPurchases(fmt: fmt, currency: currency, recent: recent)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 140.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom:
              BorderSide(color: AppColors.borderLight.withValues(alpha: 0.4)),
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
            child: Center(
              child: Text(
                'Purchases Summary',
                style: AppTypography.h2.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48), // balance
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  HERO CARD
// ═══════════════════════════════════════════════════════
class _HeroCard extends StatelessWidget {
  final NumberFormat fmt;
  final String currency;
  final double total;
  const _HeroCard({required this.fmt, required this.currency, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFE67E22), // Orange for Purchases
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE67E22).withValues(alpha: 0.25),
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
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
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
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shopping_bag_rounded,
                      color: Colors.white.withValues(alpha: 0.7), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Total Purchases (${DateFormat('MMM').format(DateTime.now())})',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '$currency ${fmt.format(total)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 36,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shopping_bag_rounded,
                        color: Colors.white.withValues(alpha: 0.9), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'This month',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SECONDARY STATS
// ═══════════════════════════════════════════════════════
class _StatsRow extends StatelessWidget {
  final NumberFormat fmt;
  final String currency;
  final int totalItems;
  final double avgOrder;
  const _StatsRow({required this.fmt, required this.currency, required this.totalItems, required this.avgOrder});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _statCard('Items Ordered', totalItems.toDouble(), '',
            AppColors.primaryNavy, Icons.inventory_2_rounded, fmt, isCurrency: false)),
        const SizedBox(width: 12),
        Expanded(child: _statCard('Avg. Order', avgOrder, '',
            const Color(0xFF27AE60), Icons.receipt_rounded, fmt, isCurrency: true)),
      ],
    );
  }

  Widget _statCard(String label, double amount, String sub, Color color,
      IconData icon, NumberFormat fmt, {bool isCurrency = true}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.borderLight.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                label,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isCurrency ? '$currency ${fmt.format(amount)}' : fmt.format(amount),
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              sub,
              style: TextStyle(
                color: sub.startsWith('+') ? const Color(0xFF27AE60) : const Color(0xFFC0392B),
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  PURCHASE TRENDS (bar chart)
// ═══════════════════════════════════════════════════════
class _TrendsChart extends StatelessWidget {
  final List<Purchase> purchases;
  const _TrendsChart({required this.purchases});

  @override
  Widget build(BuildContext context) {
    // Compute last 6 months of totals
    final now = DateTime.now();
    final monthLabels = <String>[];
    final monthTotals = <double>[];
    for (int i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      monthLabels.add(DateFormat('MMM').format(m));
      final total = purchases
          .where((p) => p.date.year == m.year && p.date.month == m.month)
          .fold<double>(0, (s, p) => s + p.total);
      monthTotals.add(total);
    }
    final maxTotal = monthTotals.fold<double>(1, (a, b) => a > b ? a : b);
    final heights = monthTotals.map((t) => (t / maxTotal).clamp(0.05, 1.0)).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.borderLight.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Purchase Volume',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Text(
                'Last 6 Months',
                style: TextStyle(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(6, (i) {
                final isCurrent = i == 5;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionallySizedBox(
                              heightFactor: heights[i],
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE67E22),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4)),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          monthLabels[i],
                          style: TextStyle(
                            color: isCurrent
                                ? AppColors.textPrimary
                                : AppColors.textTertiary,
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  RECENT PURCHASES LIST
// ═══════════════════════════════════════════════════════
class _RecentPurchases extends ConsumerWidget {
  final NumberFormat fmt;
  final String currency;
  final List<Purchase> recent;
  const _RecentPurchases({required this.fmt, required this.currency, required this.recent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider).value ?? <Supplier>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Purchases',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TransactionsListScreen(
                        showBackButton: true,
                        pageTitle: 'All Purchases',
                        initialFilter: TransactionFilter(
                          type: TransactionType.expense,
                          onlySuppliers: true,
                        ),
                      ),
                    ),
                  );
                },
                child: Text(
                  'See All',
                  style: TextStyle(
                    color: AppColors.primaryNavy,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.borderLight.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: recent.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No purchases yet',
                        style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                      ),
                    ),
                  ]
                : recent.asMap().entries.map((e) {
              final p = e.value;
              final isLast = e.key == recent.length - 1;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  final supplier = suppliers.cast<Supplier?>().firstWhere(
                    (s) => s!.id == p.supplierId,
                    orElse: () => null,
                  );
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PurchaseDetailScreen(purchase: p, supplier: supplier),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : Border(
                            bottom: BorderSide(
                              color: AppColors.borderLight
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.receipt_rounded,
                            color: AppColors.textSecondary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.supplierName,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${DateFormat('MMM dd').format(p.date)} • ${p.referenceNo}',
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$currency ${fmt.format(p.total)}',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
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
    );
  }
}
