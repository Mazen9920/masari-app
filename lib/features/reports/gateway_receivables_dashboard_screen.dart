import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/navigation/app_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/gateway_receivable_model.dart';
import '../../shared/utils/safe_pop.dart';

/// Payment-gateway receivables — money processors (Paymob, Fawry…) have
/// collected but not yet settled to the bank.
///
/// Action-first: settling is the everyday job, so each account carries a
/// one-tap **Settle** button instead of burying it in the edit form.
class GatewayReceivablesDashboardScreen extends ConsumerStatefulWidget {
  const GatewayReceivablesDashboardScreen({super.key});

  @override
  ConsumerState<GatewayReceivablesDashboardScreen> createState() =>
      _GatewayReceivablesDashboardScreenState();
}

class _GatewayReceivablesDashboardScreenState
    extends ConsumerState<GatewayReceivablesDashboardScreen> {
  final _fmt = NumberFormat('#,##0', 'en');
  final _fmt2 = NumberFormat('#,##0.00', 'en');
  final _dateFmt = DateFormat('MMM d, yyyy');

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(gatewayReceivablesProvider);
    final currency = ref.watch(appSettingsProvider).currency;

    final active = all.where((r) => r.isActive).toList();
    final pending = active.fold<double>(0, (s, r) => s + r.pendingBalance);
    final stuck = active.where((r) => r.settlementOverdue).toList();
    final fees = all.fold<double>(0, (s, r) => s + r.totalFees);
    final banked = all.fold<double>(0, (s, r) => s + r.totalCashReceived);

    // Overdue payouts first, then biggest exposure.
    final sorted = [...all]..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        if (a.settlementOverdue != b.settlementOverdue) {
          return a.settlementOverdue ? -1 : 1;
        }
        return b.pendingBalance.compareTo(a.pendingBalance);
      });

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: CustomScrollView(
        slivers: [
          _appBar(currency, pending, stuck.length, banked),
          if (all.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _empty())
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
                child: Row(
                  children: [
                    Text(
                        '${active.length} gateway${active.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 0.3)),
                    const Spacer(),
                    if (fees > 0)
                      Text('Fees paid $currency ${_fmt.format(fees)}',
                          style: const TextStyle(
                              fontSize: 11.5, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _card(sorted[i], currency),
                childCount: sorted.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primaryNavy,
        onPressed: () => context.push(AppRoutes.addGatewayReceivable),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Add gateway',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _appBar(
      String currency, double pending, int stuckCount, double banked) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 190,
      backgroundColor: AppColors.primaryNavy,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.safePop(),
      ),
      title: const Text('Gateway Receivables',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryNavy, Color(0xFF1E3A5F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 96, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('AWAITING SETTLEMENT',
                  style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('$currency ${_fmt.format(pending)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 33,
                        fontWeight: FontWeight.bold,
                        height: 1.1)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (stuckCount > 0)
                    _pill('$stuckCount overdue payout',
                        const Color(0xFFEF4444), Icons.warning_amber_rounded)
                  else if (banked > 0)
                    _pill('$currency ${_fmt.format(banked)} banked',
                        const Color(0xFF10B981), Icons.check_circle_rounded)
                  else
                    _pill('Nothing settled yet', const Color(0xFF64748B),
                        Icons.schedule_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color, IconData icon) => Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: Colors.white),
              const SizedBox(width: 5),
              Flexible(
                child: Text(text,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );

  Widget _card(GatewayReceivable r, String currency) {
    final accent = !r.isActive
        ? AppColors.textTertiary
        : r.settlementOverdue
            ? AppColors.chartRed
            : r.isCleared
                ? AppColors.chartGreen
                : AppColors.primaryNavy;
    final days = r.daysSinceLastSettlement;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: r.settlementOverdue
                ? AppColors.chartRed.withValues(alpha: 0.35)
                : Colors.grey.shade200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push(AppRoutes.editGatewayReceivable,
              extra: {'receivable': r}),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(Icons.account_balance_wallet_rounded,
                          size: 19, color: accent),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                    r.gatewayName.isEmpty
                                        ? 'Gateway'
                                        : r.gatewayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600)),
                              ),
                              if (!r.isActive) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('Closed',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.textTertiary)),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _subtitle(r, days),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: r.settlementOverdue
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: r.settlementOverdue
                                  ? AppColors.chartRed
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('$currency ${_fmt.format(r.pendingBalance)}',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        const Text('pending',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.textTertiary)),
                      ],
                    ),
                  ],
                ),
                if (r.totalFees > 0) ...[
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      const Icon(Icons.percent_rounded,
                          size: 12, color: AppColors.chartOrange),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Fees $currency ${_fmt.format(r.totalFees)} '
                          '(${r.effectiveFeeRate.toStringAsFixed(1)}%) · '
                          'banked $currency ${_fmt.format(r.totalCashReceived)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textTertiary),
                        ),
                      ),
                    ],
                  ),
                ],
                if (r.isActive) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _addCollection(r, currency),
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('Collected',
                            style: TextStyle(fontSize: 12.5)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                      ),
                      const SizedBox(width: 4),
                      FilledButton.icon(
                        onPressed: r.pendingBalance <= 0.01
                            ? null
                            : () => _settle(r, currency),
                        icon: const Icon(Icons.account_balance_rounded,
                            size: 15),
                        label: const Text('Settle',
                            style: TextStyle(
                                fontSize: 12.5, fontWeight: FontWeight.w600)),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primaryNavy,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(GatewayReceivable r, int? days) {
    if (r.settlementOverdue) {
      final cycle = r.settlementDays;
      return days == null
          ? 'Never settled — expected every $cycle d'
          : 'Last payout $days days ago — expected every $cycle d';
    }
    if (days != null) {
      return days == 0 ? 'Settled today' : 'Last payout $days d ago';
    }
    if (r.feePercent != null) {
      return '${r.feePercent!.toStringAsFixed(1)}% fee';
    }
    return 'No payouts yet';
  }

  // ── Settle ───────────────────────────────────────────────

  /// Records a payout. The amount is the GROSS cleared from the receivable;
  /// the fee is deducted so only the NET is added to the bank — the figure
  /// that actually arrives.
  Future<void> _settle(GatewayReceivable r, String currency) async {
    final amountCtrl =
        TextEditingController(text: r.pendingBalance.toStringAsFixed(2));
    final feeCtrl = TextEditingController(
      text: r.feePercent != null
          ? (r.pendingBalance * r.feePercent! / 100).toStringAsFixed(2)
          : '0.00',
    );
    final noteCtrl = TextEditingController();
    DateTime date = DateTime.now();
    bool postCash = true;

    double gross() => double.tryParse(amountCtrl.text.trim()) ?? 0;
    double fee() => double.tryParse(feeCtrl.text.trim()) ?? 0;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Settle ${r.gatewayName}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  Text('Pending $currency ${_fmt2.format(r.pendingBalance)}',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textTertiary)),
                  const SizedBox(height: 16),
                  _sheetLabel('Gross cleared'),
                  TextField(
                    controller: amountCtrl,
                    autofocus: true,
                    onChanged: (_) => setSt(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                    ],
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: _sheetDec(currency),
                  ),
                  const SizedBox(height: 12),
                  _sheetLabel('Gateway fee'),
                  TextField(
                    controller: feeCtrl,
                    onChanged: (_) => setSt(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                    ],
                    style: const TextStyle(fontSize: 16),
                    decoration: _sheetDec(currency),
                  ),
                  const SizedBox(height: 10),
                  // The number that actually lands in the bank.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.chartGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_rounded,
                            size: 16, color: AppColors.chartGreen),
                        const SizedBox(width: 8),
                        const Text('Lands in bank',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.chartGreen)),
                        const Spacer(),
                        Text(
                          '$currency ${_fmt2.format((gross() - fee()).clamp(0, double.maxFinite))}',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.chartGreen),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _dateRow(ctx, date, (d) => setSt(() => date = d)),
                  const SizedBox(height: 10),
                  _noteField(noteCtrl),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: postCash,
                    onChanged: (v) => setSt(() => postCash = v ?? true),
                    dense: true,
                    title: const Text('Add to Cash & Bank',
                        style: TextStyle(fontSize: 13.5)),
                    subtitle: const Text(
                        'Posts the net as cash in, and the fee as an expense.',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryNavy,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Record settlement',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (ok != true) return;
    final g = gross();
    if (g <= 0) return;
    final done =
        await ref.read(gatewayReceivablesProvider.notifier).recordSettlement(
              r.id,
              GatewaySettlement(
                id: const Uuid().v4(),
                amount: g,
                fee: fee(),
                date: date,
                note:
                    noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              ),
              postCash: postCash,
            );
    if (!mounted) return;
    _toast(done ? 'Settlement recorded' : 'Could not record settlement', done);
  }

  /// Record money the gateway collected (raises the receivable).
  Future<void> _addCollection(GatewayReceivable r, String currency) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    DateTime date = DateTime.now();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('${r.gatewayName} collected',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const Text(
                    'Raises what the gateway owes you. No P&L entry — the '
                    'revenue was already booked at the sale.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                  ],
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: _sheetDec(currency),
                ),
                const SizedBox(height: 12),
                _dateRow(ctx, date, (d) => setSt(() => date = d)),
                const SizedBox(height: 10),
                _noteField(noteCtrl),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryNavy,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Add to balance',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (ok != true) return;
    final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amt <= 0) return;
    final done =
        await ref.read(gatewayReceivablesProvider.notifier).recordCollection(
              r.id,
              GatewayCollection(
                id: const Uuid().v4(),
                amount: amt,
                date: date,
                note:
                    noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              ),
            );
    if (!mounted) return;
    _toast(done ? 'Balance updated' : 'Could not update balance', done);
  }

  // ── Shared bits ──────────────────────────────────────────

  Widget _sheetLabel(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
      );

  Widget _dateRow(
          BuildContext ctx, DateTime date, void Function(DateTime) onPick) =>
      InkWell(
        onTap: () async {
          final d = await showDatePicker(
            context: ctx,
            initialDate: date,
            firstDate: DateTime(2000),
            lastDate: DateTime.now(),
          );
          if (d != null) onPick(d);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6F8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 16),
              const SizedBox(width: 10),
              Text(_dateFmt.format(date), style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      );

  Widget _noteField(TextEditingController c) => TextField(
        controller: c,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Note (optional)',
          hintStyle: const TextStyle(fontSize: 14),
          filled: true,
          fillColor: const Color(0xFFF5F6F8),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      );

  InputDecoration _sheetDec(String currency) => InputDecoration(
        prefixText: '$currency  ',
        filled: true,
        fillColor: const Color(0xFFF5F6F8),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  void _toast(String msg, bool good) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: good ? AppColors.chartGreen : AppColors.chartRed,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Widget _empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primaryNavy.withValues(alpha: 0.07),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  size: 34, color: AppColors.primaryNavy),
            ),
            const SizedBox(height: 18),
            const Text('No gateways yet',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Track money processors like Paymob or Fawry have collected but '
              'not yet paid into your bank. Fees are recorded separately, so '
              'your cash balance stays accurate.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 13, height: 1.45),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => context.push(AppRoutes.addGatewayReceivable),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add your first gateway'),
            ),
          ],
        ),
      );
}
