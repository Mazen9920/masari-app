import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/navigation/app_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/gateway_receivable_model.dart';
import '../../shared/utils/safe_pop.dart';

/// Dashboard for payment-gateway receivables — money a processor (e.g. Paymob)
/// has collected but not yet settled to the bank. Mirrors the loans/salaries
/// dashboards but on the asset side.
class GatewayReceivablesDashboardScreen extends ConsumerWidget {
  const GatewayReceivablesDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receivables = ref.watch(gatewayReceivablesProvider);
    final currency = ref.watch(appSettingsProvider).currency;
    final fmt = NumberFormat('#,##0.00', 'en');
    final dateFmt = DateFormat('MMM d, yyyy');

    final active = receivables.where((r) => r.isActive).toList();
    final totalPending =
        active.fold<double>(0, (s, r) => s + r.pendingBalance);
    final totalSettled =
        receivables.fold<double>(0, (s, r) => s + r.totalSettled);

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
        title: const Text('Payment Gateway Receivables',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add gateway',
            onPressed: () => context.push(AppRoutes.addGatewayReceivable),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Total pending header ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryNavy, Color(0xFF3B5BDB)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Pending (uncleared)',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Text('$currency ${fmt.format(totalPending)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                    '${active.length} gateway${active.length == 1 ? '' : 's'} · settled to date $currency ${fmt.format(totalSettled)}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (receivables.isEmpty)
            _emptyState(context)
          else
            ...receivables.map((r) =>
                _gatewayCard(context, r, currency, fmt, dateFmt)),
        ],
      ),
      floatingActionButton: receivables.isEmpty
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.primaryNavy,
              onPressed: () => context.push(AppRoutes.addGatewayReceivable),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text('Add gateway',
                  style: TextStyle(color: Colors.white)),
            ),
    );
  }

  Widget _emptyState(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Icon(Icons.credit_card_off_rounded,
                size: 56, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            const Text('No payment gateways yet',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Add a gateway (e.g. Paymob) and its uncleared balance to track\nwhat the processor owes you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryNavy),
              onPressed: () =>
                  context.push(AppRoutes.addGatewayReceivable),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add gateway'),
            ),
          ],
        ),
      );

  Widget _gatewayCard(BuildContext context, GatewayReceivable r,
      String currency, NumberFormat fmt, DateFormat dateFmt) {
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
          onTap: () => context.push(AppRoutes.editGatewayReceivable,
              extra: {'receivable': r}),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.chartGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.account_balance_rounded,
                      color: AppColors.chartGreen),
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
                              r.gatewayName.isEmpty
                                  ? 'Gateway'
                                  : r.gatewayName,
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (!r.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.textTertiary
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Closed',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textTertiary)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        r.lastSettlementDate != null
                            ? 'Last settlement ${dateFmt.format(r.lastSettlementDate!)}'
                            : 'No settlements yet',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$currency ${fmt.format(r.pendingBalance)}',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryNavy)),
                    const Text('pending',
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
