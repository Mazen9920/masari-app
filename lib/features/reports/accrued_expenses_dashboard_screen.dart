import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/navigation/app_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/accrued_expense_model.dart';
import '../../shared/utils/safe_pop.dart';

/// Dashboard for accrued expenses — costs incurred but not yet paid. A
/// liability; mirrors the loans/salaries dashboards.
class AccruedExpensesDashboardScreen extends ConsumerWidget {
  const AccruedExpensesDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(accruedExpensesProvider);
    final currency = ref.watch(appSettingsProvider).currency;
    final fmt = NumberFormat('#,##0.00', 'en');
    final dateFmt = DateFormat('MMM d, yyyy');

    final active = expenses.where((e) => e.isActive).toList();
    final totalOwed = active.fold<double>(0, (s, e) => s + e.amount);
    final totalPaid = expenses.fold<double>(0, (s, e) => s + e.totalPaid);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: AppColors.primaryNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.safePop(),
        ),
        title: const Text('Accrued Expenses',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add accrual',
            onPressed: () => context.push(AppRoutes.addAccruedExpense),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFB91C1C), Color(0xFFEF4444)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Owed (unpaid)',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text('$currency ${fmt.format(totalOwed)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                    '${active.length} accrual${active.length == 1 ? '' : 's'} · paid to date $currency ${fmt.format(totalPaid)}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (expenses.isEmpty)
            _emptyState(context)
          else
            ...expenses
                .map((e) => _card(context, e, currency, fmt, dateFmt)),
        ],
      ),
      floatingActionButton: expenses.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.primaryNavy,
              onPressed: () => context.push(AppRoutes.addAccruedExpense),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Add accrual',
                  style: TextStyle(color: Colors.white)),
            ),
    );
  }

  Widget _emptyState(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(Icons.receipt_long_rounded,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            const Text('No accrued expenses',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Track costs you\'ve incurred but not paid yet\n(e.g. accrued rent, utilities, interest).',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryNavy),
              onPressed: () => context.push(AppRoutes.addAccruedExpense),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add accrual'),
            ),
          ],
        ),
      );

  Widget _card(BuildContext context, AccruedExpense e, String currency,
      NumberFormat fmt, DateFormat dateFmt) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(AppRoutes.editAccruedExpense,
              extra: {'expense': e}),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.chartRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: AppColors.chartRed),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.name.isEmpty ? 'Accrual' : e.name,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (!e.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.chartGreen
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Settled',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.chartGreen)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        e.lastPaymentDate != null
                            ? 'Last payment ${dateFmt.format(e.lastPaymentDate!)}'
                            : 'No payments yet',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$currency ${fmt.format(e.amount)}',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.chartRed)),
                    const Text('owed',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textTertiary)),
                  ],
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
