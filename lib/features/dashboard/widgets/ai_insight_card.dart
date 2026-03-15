import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../core/navigation/app_router.dart';
import '../providers/dashboard_state_provider.dart';
import '../../../shared/models/category_data.dart';

/// A data-driven insight generated from real financial data.
class _Insight {
  final String headline;
  final String boldPart;
  final String detail;
  final String ctaLabel;
  final String? routeName;
  final String? routePath;

  const _Insight({
    required this.headline,
    required this.boldPart,
    required this.detail,
    required this.ctaLabel,
    this.routeName,
    this.routePath,
  });
}

/// Hero card showing a data-driven financial insight.
/// Gradient background: Navy → Blue → subtle purple.
class AIInsightCard extends ConsumerStatefulWidget {
  const AIInsightCard({super.key});

  @override
  ConsumerState<AIInsightCard> createState() => _AIInsightCardState();
}

class _AIInsightCardState extends ConsumerState<AIInsightCard> {
  bool _dismissed = false;

  _Insight? _generateInsight() {
    final ds = ref.watch(dashboardStateProvider);
    final range = ds.range;
    final currency = ref.watch(appSettingsProvider).currency;
    final fmt = NumberFormat.compactCurrency(symbol: '$currency ');

    final allTxns = ref.watch(transactionsProvider).value ?? [];
    final inventory = ref.watch(inventoryProvider).value ?? [];

    // Categories excluded from P&L (CF investing activities / BS only)
    const plExcludedCats = {'cat_investments'};

    bool inPL(t) => !t.excludeFromPL && !plExcludedCats.contains(t.categoryId);

    // Current period data
    final curTxns = allTxns
        .where((t) =>
            inPL(t) &&
            !t.dateTime.isBefore(range.start) &&
            !t.dateTime.isAfter(range.end))
        .toList();
    final prevTxns = allTxns
        .where((t) =>
            inPL(t) &&
            !t.dateTime.isBefore(range.previousStart) &&
            !t.dateTime.isAfter(range.previousEnd))
        .toList();

    // Revenue (accrual basis — operating income only)
    final curRevenue = curTxns
        .where((t) => t.isIncome)
        .fold<double>(0, (sum, t) => sum + t.amount.abs());
    final prevRevenue = prevTxns
        .where((t) => t.isIncome)
        .fold<double>(0, (sum, t) => sum + t.amount.abs());
    final curExpenses = curTxns
        .where((t) => !t.isIncome)
        .fold<double>(0, (sum, t) => sum + t.amount.abs());
    final prevExpenses = prevTxns
        .where((t) => !t.isIncome)
        .fold<double>(0, (sum, t) => sum + t.amount.abs());

    final vsLabel = ds.period.vsLabel;

    // 1) Check for biggest expense category spike
    if (curTxns.isNotEmpty && prevTxns.isNotEmpty) {
      final curByCategory = <String, double>{};
      final prevByCategory = <String, double>{};
      for (final t in curTxns.where((t) => !t.isIncome)) {
        curByCategory[t.categoryId] =
            (curByCategory[t.categoryId] ?? 0) + t.amount.abs();
      }
      for (final t in prevTxns.where((t) => !t.isIncome)) {
        prevByCategory[t.categoryId] =
            (prevByCategory[t.categoryId] ?? 0) + t.amount.abs();
      }

      String? spikeCat;
      double spikeAmt = 0;
      double spikePct = 0;
      for (final entry in curByCategory.entries) {
        final prev = prevByCategory[entry.key] ?? 0;
        if (prev > 0) {
          final pct = (entry.value - prev) / prev * 100;
          if (pct > 20 && entry.value > spikeAmt) {
            spikeCat = entry.key;
            spikeAmt = entry.value;
            spikePct = pct;
          }
        }
      }

      if (spikeCat != null) {
        final catName = CategoryData.findById(spikeCat).name;
        return _Insight(
          headline: 'Your $catName spending is up ',
          boldPart: '${spikePct.toStringAsFixed(0)}% $vsLabel.',
          detail:
              'You spent ${fmt.format(spikeAmt)} on $catName this period, compared to ${fmt.format(prevByCategory[spikeCat] ?? 0)} in the previous period.',
          ctaLabel: 'View Transactions',
          routeName: 'TransactionsListScreen',
        );
      }
    }

    // 2) Revenue drop alert
    if (prevRevenue > 0) {
      final revChange = (curRevenue - prevRevenue) / prevRevenue * 100;
      if (revChange < -15) {
        return _Insight(
          headline: 'Revenue has dropped ',
          boldPart: '${revChange.abs().toStringAsFixed(0)}% $vsLabel.',
          detail:
              'Current revenue is ${fmt.format(curRevenue)} compared to ${fmt.format(prevRevenue)} in the previous period. Consider reviewing your sales strategy.',
          ctaLabel: 'View Sales',
          routeName: 'SalesListScreen',
        );
      }
    }

    // 3) Low stock alert
    final lowStockProducts = inventory.where((p) {
      final totalStock =
          p.variants.fold<int>(0, (sum, v) => sum + v.currentStock);
      final reorderPoint =
          p.variants.fold<int>(0, (sum, v) => sum + v.reorderPoint);
      return totalStock > 0 && totalStock <= reorderPoint;
    }).toList();
    if (lowStockProducts.length >= 2) {
      return _Insight(
        headline: 'You have ',
        boldPart: '${lowStockProducts.length} products running low on stock.',
        detail:
            '${lowStockProducts.take(3).map((p) => p.name).join(', ')}${lowStockProducts.length > 3 ? ' and more' : ''} need restocking soon to avoid stockouts.',
        ctaLabel: 'Check Inventory',
        routeName: 'InventoryListScreen',
      );
    }

    // 4) Profit margin insight
    if (curRevenue > 0 && curExpenses > 0) {
      final margin = (curRevenue - curExpenses) / curRevenue * 100;
      if (margin < 20) {
        return _Insight(
          headline: 'Your profit margin is ',
          boldPart: '${margin.toStringAsFixed(1)}% this period.',
          detail:
              'With ${fmt.format(curRevenue)} in revenue and ${fmt.format(curExpenses)} in expenses, your margin is tight. Look for ways to reduce costs or increase prices.',
          ctaLabel: 'View Analytics',
          routePath: AppRoutes.reports,
        );
      }
    }

    // 5) Revenue growth — positive insight
    if (prevRevenue > 0 && curRevenue > prevRevenue) {
      final growth = (curRevenue - prevRevenue) / prevRevenue * 100;
      if (growth > 10) {
        return _Insight(
          headline: 'Revenue is growing — up ',
          boldPart: '${growth.toStringAsFixed(0)}% $vsLabel!',
          detail:
              'You earned ${fmt.format(curRevenue)} this period, compared to ${fmt.format(prevRevenue)} previously. Keep up the momentum.',
          ctaLabel: 'View Sales',
          routeName: 'SalesListScreen',
        );
      }
    }

    // 6) Expense reduction — positive insight
    if (prevExpenses > 0 && curExpenses < prevExpenses) {
      final reduction = (prevExpenses - curExpenses) / prevExpenses * 100;
      if (reduction > 10) {
        return _Insight(
          headline: 'Expenses are down ',
          boldPart: '${reduction.toStringAsFixed(0)}% $vsLabel.',
          detail:
              'You spent ${fmt.format(curExpenses)} this period vs ${fmt.format(prevExpenses)} previously. Great cost management!',
          ctaLabel: 'View Transactions',
          routeName: 'TransactionsListScreen',
        );
      }
    }

    // No meaningful insight to show
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();

    final insight = _generateInsight();
    if (insight == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryNavy,
            AppColors.secondaryBlue,
            Color(0xFF7C3AED), // subtle purple accent
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryNavy.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Badge + close button ───
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'MASARI AI INSIGHT',
                        style: AppTypography.captionSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _dismissed = true),
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.7),
                    size: 22,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ─── Insight text ───
            RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  height: 1.4,
                  fontFamily: 'Inter',
                ),
                children: [
                  TextSpan(text: insight.headline),
                  TextSpan(
                    text: insight.boldPart,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white.withValues(alpha: 0.4),
                      decorationStyle: TextDecorationStyle.solid,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            Text(
              insight.detail,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w300,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 18),

            // ─── CTA button ───
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (insight.routeName != null || insight.routePath != null)
                    ? () {
                        if (insight.routeName != null) {
                          context.pushNamed(insight.routeName!);
                        } else if (insight.routePath != null) {
                          context.go(insight.routePath!);
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.accentOrange,
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      insight.ctaLabel,
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.accentOrange,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      size: 18,
                      color: AppColors.accentOrange,
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
}
