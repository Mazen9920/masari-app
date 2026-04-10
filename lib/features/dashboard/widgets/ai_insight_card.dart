import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../core/navigation/app_router.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/utils/report_constants.dart';
import '../providers/dashboard_state_provider.dart';
import '../providers/dashboard_data_provider.dart';
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

  _Insight? _generateInsight(AppLocalizations l10n) {
    final ds = ref.watch(dashboardStateProvider);
    final range = ds.range;
    final currency = ref.watch(appSettingsProvider).currency;
    final fmt = NumberFormat.compactCurrency(symbol: '$currency ');

    final allTxns = ref.watch(dashboardDataProvider).value?.transactions ?? [];
    final inventory = ref.watch(filteredInventoryProvider).value ?? [];

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
    // Refund transactions (negative cat_sales_revenue) reduce revenue, not add to expenses.
    // Revenue: signed sales_rev + signed shipping + other income.
    // Exclude cat_cogs (it's a cost, not revenue).
    double _revenue(List<dynamic> txns) {
      double r = 0;
      for (final t in txns) {
        if (t.categoryId == 'cat_cogs') continue;
        if (t.categoryId == 'cat_sales_revenue' || t.categoryId == 'cat_shipping') {
          r += t.amount; // signed: positive = income, negative = refund
        } else if (t.isIncome) {
          r += t.amount.abs();
        }
      }
      return r;
    }
    // Expenses: exclude sales/shipping reversals (reduce revenue) and handle COGS reversals.
    double _expenses(List<dynamic> txns) {
      double e = 0;
      for (final t in txns) {
        if (t.categoryId == 'cat_cogs') {
          e -= t.amount; // -(-X)=+X for cost, -(+X)=-X for reversal
        } else if (!t.isIncome &&
            t.categoryId != 'cat_sales_revenue' &&
            t.categoryId != 'cat_shipping') {
          e += t.amount.abs();
        }
      }
      return e;
    }
    final curRevenue = _revenue(curTxns);
    final prevRevenue = _revenue(prevTxns);
    final curExpenses = _expenses(curTxns);
    final prevExpenses = _expenses(prevTxns);

    final vsLabel = ds.period.localizedVsLabel(l10n);

    // 1) Check for biggest expense category spike
    if (curTxns.isNotEmpty && prevTxns.isNotEmpty) {
      final curByCategory = <String, double>{};
      final prevByCategory = <String, double>{};
      for (final t in curTxns) {
        if (t.categoryId == 'cat_sales_revenue' || t.categoryId == 'cat_shipping') continue;
        if (t.categoryId == 'cat_cogs') {
          curByCategory[t.categoryId] = (curByCategory[t.categoryId] ?? 0) - t.amount;
        } else if (!t.isIncome) {
          curByCategory[t.categoryId] = (curByCategory[t.categoryId] ?? 0) + t.amount.abs();
        }
      }
      for (final t in prevTxns) {
        if (t.categoryId == 'cat_sales_revenue' || t.categoryId == 'cat_shipping') continue;
        if (t.categoryId == 'cat_cogs') {
          prevByCategory[t.categoryId] = (prevByCategory[t.categoryId] ?? 0) - t.amount;
        } else if (!t.isIncome) {
          prevByCategory[t.categoryId] = (prevByCategory[t.categoryId] ?? 0) + t.amount.abs();
        }
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
        final catName = CategoryData.findById(spikeCat).localizedName(l10n);
        return _Insight(
          headline: l10n.insightSpendingUp(catName),
          boldPart: '${spikePct.toStringAsFixed(0)}% $vsLabel.',
          detail: l10n.insightSpendingUpDetail(fmt.format(spikeAmt), catName, fmt.format(prevByCategory[spikeCat] ?? 0)),
          ctaLabel: l10n.viewTransactions,
          routeName: 'TransactionsListScreen',
        );
      }
    }

    // 2) Revenue drop alert
    if (prevRevenue > 0) {
      final revChange = (curRevenue - prevRevenue) / prevRevenue * 100;
      if (revChange < -15) {
        return _Insight(
          headline: l10n.insightRevenueDropped,
          boldPart: '${revChange.abs().toStringAsFixed(0)}% $vsLabel.',
          detail: l10n.insightRevenueDropDetail(fmt.format(curRevenue), fmt.format(prevRevenue)),
          ctaLabel: l10n.viewSales,
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
        headline: l10n.insightLowStock,
        boldPart: l10n.insightLowStockBold(lowStockProducts.length),
        detail: l10n.insightLowStockDetail(
            '${lowStockProducts.take(3).map((p) => p.name).join(', ')}${lowStockProducts.length > 3 ? l10n.andMore : ''}'),
        ctaLabel: l10n.checkInventory,
        routeName: 'InventoryListScreen',
      );
    }

    // 4) Profit margin insight
    if (curRevenue > 0 && curExpenses > 0) {
      final margin = (curRevenue - curExpenses) / curRevenue * 100;
      if (margin < 20) {
        return _Insight(
          headline: l10n.insightProfitMargin,
          boldPart: '${margin.toStringAsFixed(1)}% this period.',
          detail: l10n.insightProfitMarginDetail(fmt.format(curRevenue), fmt.format(curExpenses)),
          ctaLabel: l10n.viewAnalytics,
          routePath: AppRoutes.reports,
        );
      }
    }

    // 5) Revenue growth — positive insight
    if (prevRevenue > 0 && curRevenue > prevRevenue) {
      final growth = (curRevenue - prevRevenue) / prevRevenue * 100;
      if (growth > 10) {
        return _Insight(
          headline: l10n.insightRevenueGrowing,
          boldPart: '${growth.toStringAsFixed(0)}% $vsLabel!',
          detail: l10n.insightRevenueGrowDetail(fmt.format(curRevenue), fmt.format(prevRevenue)),
          ctaLabel: l10n.viewSales,
          routeName: 'SalesListScreen',
        );
      }
    }

    // 6) Expense reduction — positive insight
    if (prevExpenses > 0 && curExpenses < prevExpenses) {
      final reduction = (prevExpenses - curExpenses) / prevExpenses * 100;
      if (reduction > 10) {
        return _Insight(
          headline: l10n.insightExpensesDown,
          boldPart: '${reduction.toStringAsFixed(0)}% $vsLabel.',
          detail: l10n.insightExpensesDownDetail(fmt.format(curExpenses), fmt.format(prevExpenses)),
          ctaLabel: l10n.viewTransactions,
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

    final l10n = AppLocalizations.of(context)!;
    final insight = _generateInsight(l10n);
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
            AppColors.shopifyPurple, // subtle purple accent
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
                        l10n.revvoAiInsight,
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
