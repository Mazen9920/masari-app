import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/models/payment_model.dart';
import '../../shared/models/supplier_model.dart';
import 'payment_detail_screen.dart';
import '../transactions/transactions_list_screen.dart';
import '../../shared/models/transaction_model.dart';

/// Payments Summary Dashboard — overview of supplier payment activity.

String _localizedMethodName(String method, AppLocalizations l10n) {
  switch (method) {
    case 'Cash': return l10n.cash;
    case 'Bank Transfer': return l10n.bankTransfer;
    case 'InstaPay': return l10n.instaPay;
    case 'Vodafone Cash': return l10n.vodafoneCash;
    default: return method;
  }
}

class PaymentsSummaryScreen extends ConsumerWidget {
  const PaymentsSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currency = ref.watch(currencyProvider);
    final payments = ref.watch(paymentsProvider).value ?? [];
    final purchases = ref.watch(purchasesProvider).value ?? [];
    final fmt = NumberFormat('#,##0');

    // Compute stats from real data
    final now = DateTime.now();
    final thisMonth = payments.where((p) =>
        p.date.year == now.year && p.date.month == now.month).toList();
    final totalThisMonth = thisMonth.fold<double>(0, (s, p) => s + p.amount);
    final totalPaid = payments.fold<double>(0, (s, p) => s + p.amount);
    final totalPurchases = purchases.fold<double>(0, (s, p) => s + p.total);
    final outstanding = (totalPurchases - totalPaid).clamp(0.0, double.infinity);

    // Recent 5 payments
    final sorted = List<Payment>.from(payments)
      ..sort((a, b) => b.date.compareTo(a.date));
    final recent = sorted.take(5).toList();

    // Method breakdown
    final methodCounts = <String, int>{};
    for (final p in payments) {
      methodCounts[p.method] = (methodCounts[p.method] ?? 0) + 1;
    }
    final totalCount = payments.length.clamp(1, double.infinity).toDouble();

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, l10n),
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
                    _StatsRow(fmt: fmt, currency: currency, paid: totalPaid, outstanding: outstanding)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 60.ms),
                    const SizedBox(height: 20),
                    _TrendsChart(payments: payments)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 100.ms),
                    const SizedBox(height: 20),
                    _PaymentMethods(methodCounts: methodCounts, totalCount: totalCount)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 140.ms),
                    const SizedBox(height: 20),
                    _RecentPayments(fmt: fmt, currency: currency, recent: recent)
                        .animate()
                        .fadeIn(duration: 250.ms, delay: 180.ms),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
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
                l10n.paymentsSummary,
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
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
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy,
        borderRadius: BorderRadius.circular(20),
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
                  Icon(Icons.calendar_month_rounded,
                      color: Colors.white.withValues(alpha: 0.7), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    l10n.totalPaymentsMonth(DateFormat('MMM').format(DateTime.now())),
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
                    Icon(Icons.calendar_month_rounded,
                        color: Colors.white.withValues(alpha: 0.9), size: 14),
                    const SizedBox(width: 6),
                    Text(
                      l10n.periodThisMonth,
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
  final double paid;
  final double outstanding;
  const _StatsRow({required this.fmt, required this.currency, required this.paid, required this.outstanding});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(child: _statCard(l10n.paidLabel, paid,
            AppColors.success, Icons.check_circle_rounded, fmt)),
        const SizedBox(width: 12),
        Expanded(child: _statCard(l10n.outstanding, outstanding,
            AppColors.accentOrange, Icons.pending_rounded, fmt)),
      ],
    );
  }

  Widget _statCard(String label, double amount, Color color,
      IconData icon, NumberFormat fmt) {
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
            '$currency ${fmt.format(amount)}',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  PAYMENT TRENDS (bar chart)
// ═══════════════════════════════════════════════════════
class _TrendsChart extends StatelessWidget {
  final List<Payment> payments;
  const _TrendsChart({required this.payments});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now();
    final monthLabels = <String>[];
    final monthTotals = <double>[];
    for (int i = 5; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      monthLabels.add(DateFormat('MMM').format(m));
      final total = payments
          .where((p) => p.date.year == m.year && p.date.month == m.month)
          .fold<double>(0, (s, p) => s + p.amount);
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
                l10n.paymentTrends,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Text(
                l10n.lastSixMonths,
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
                                  color: AppColors.primaryNavy,
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
                                ? AppColors.primaryNavy
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
//  PAYMENT METHODS
// ═══════════════════════════════════════════════════════
class _PaymentMethods extends StatelessWidget {
  final Map<String, int> methodCounts;
  final double totalCount;
  const _PaymentMethods({required this.methodCounts, required this.totalCount});

  IconData _iconFor(String method) {
    switch (method.toLowerCase()) {
      case 'bank transfer': return Icons.account_balance_rounded;
      case 'instapay': return Icons.bolt_rounded;
      case 'cash': return Icons.payments_rounded;
      case 'check': return Icons.receipt_rounded;
      default: return Icons.payment_rounded;
    }
  }

  Color _colorFor(int index) {
    const colors = [Color(0xFF2563EB), AppColors.shopifyPurple, Color(0xFF059669), AppColors.accentOrange];
    return colors[index % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final methods = methodCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(
            l10n.paymentMethodsLabel,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
        SizedBox(
          height: 100,
          child: methods.isEmpty
              ? Center(child: Text(l10n.noDataLabel, style: TextStyle(color: AppColors.textTertiary, fontSize: 13)))
              : ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: methods.asMap().entries.map((e) {
              final method = e.value.key;
              final count = e.value.value;
              final pct = (count / totalCount * 100).round();
              final progress = count / totalCount;
              final color = _colorFor(e.key);
              return Padding(
                padding: EdgeInsets.only(right: e.key < methods.length - 1 ? 10 : 0),
                child: _methodCard(_localizedMethodName(method, l10n), '$pct%', progress, _iconFor(method), color),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _methodCard(String label, String pct, double progress,
      IconData icon, Color color) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(14),
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
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              Text(
                pct,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.borderLight.withValues(alpha: 0.3),
              color: color,
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  RECENT PAYMENTS LIST
// ═══════════════════════════════════════════════════════
class _RecentPayments extends ConsumerWidget {
  final NumberFormat fmt;
  final String currency;
  final List<Payment> recent;
  const _RecentPayments({required this.fmt, required this.currency, required this.recent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
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
                l10n.recentPayments,
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
                      builder: (_) => TransactionsListScreen(
                        showBackButton: true,
                        pageTitle: l10n.allPayments,
                        initialFilter: TransactionFilter(
                          type: TransactionType.expense,
                          onlySuppliers: true,
                        ),
                      ),
                    ),
                  );
                },
                child: Text(
                  l10n.seeAllLabel,
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
                        l10n.noPaymentsYet,
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
                      builder: (_) => PaymentDetailScreen(payment: p, supplier: supplier),
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
                        child: Icon(Icons.payments_rounded,
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
                              '${DateFormat('MMM dd').format(p.date)} • ${_localizedMethodName(p.method, l10n)}',
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '- $currency ${fmt.format(p.amount)}',
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
