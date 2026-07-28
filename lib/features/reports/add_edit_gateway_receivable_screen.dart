import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/gateway_receivable_model.dart';
import '../../shared/utils/safe_pop.dart';

/// Add or edit a payment-gateway receivable account.
/// Pass `extra: {'receivable': GatewayReceivable}` for edit mode.
class AddEditGatewayReceivableScreen extends ConsumerStatefulWidget {
  final GatewayReceivable? receivable;
  const AddEditGatewayReceivableScreen({super.key, this.receivable});

  @override
  ConsumerState<AddEditGatewayReceivableScreen> createState() =>
      _AddEditGatewayReceivableScreenState();
}

class _AddEditGatewayReceivableScreenState
    extends ConsumerState<AddEditGatewayReceivableScreen> {
  final _formKey = GlobalKey<FormState>();
  late final bool _isEdit;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _balanceCtrl;
  late final TextEditingController _feeCtrl;
  late final TextEditingController _notesCtrl;
  late GatewayReceivableStatus _status;
  int? _settlementDays;
  bool _saving = false;

  final _fmt = NumberFormat('#,##0.00', 'en');
  final _dateFmt = DateFormat('MMM d, yyyy');

  /// Common payout cycles — most gateways fall into one of these.
  static const _cycles = <int?, String>{
    null: 'Not set',
    1: 'Daily',
    2: '2 days',
    7: 'Weekly',
    14: '2 weeks',
    30: 'Monthly',
  };

  @override
  void initState() {
    super.initState();
    final r = widget.receivable;
    _isEdit = r != null;
    _nameCtrl = TextEditingController(text: r?.gatewayName ?? '');
    _balanceCtrl = TextEditingController(
        text: r != null ? r.pendingBalance.toStringAsFixed(2) : '');
    _feeCtrl = TextEditingController(
        text: r?.feePercent != null ? r!.feePercent!.toString() : '');
    _notesCtrl = TextEditingController(text: r?.notes ?? '');
    _status = r?.status ?? GatewayReceivableStatus.active;
    _settlementDays = r?.settlementDays;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    _feeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// Always read the latest record so settlements made here update the summary
  /// immediately instead of showing the snapshot we opened with.
  GatewayReceivable? get _live {
    if (widget.receivable == null) return null;
    final list = ref.watch(gatewayReceivablesProvider);
    for (final r in list) {
      if (r.id == widget.receivable!.id) return r;
    }
    return widget.receivable;
  }

  // ═══════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final notifier = ref.read(gatewayReceivablesProvider.notifier);
    final base = _live;

    final receivable = GatewayReceivable(
      id: base?.id ?? '',
      gatewayName: _nameCtrl.text.trim(),
      pendingBalance: double.tryParse(_balanceCtrl.text.trim()) ?? 0,
      settlementDays: _settlementDays,
      feePercent: double.tryParse(_feeCtrl.text.trim()),
      status: _status,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdAt: base?.createdAt ?? DateTime.now(),
      collections: base?.collections ?? const [],
      settlements: base?.settlements ?? const [],
    );

    final ok = _isEdit
        ? await notifier.updateReceivable(receivable)
        : await notifier.add(receivable);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      context.safePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to save'),
          backgroundColor: AppColors.chartRed));
    }
  }

  Future<void> _delete() async {
    final r = _live;
    if (r == null) return;
    final currency = ref.read(appSettingsProvider).currency;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete gateway?'),
        content: Text(
          'Deletes "${r.gatewayName}" and everything linked to it:\n\n'
          '• ${r.settlements.length} settlement'
          '${r.settlements.length == 1 ? '' : 's'} and their cash + fee '
          'transactions\n'
          '• $currency ${_fmt.format(r.pendingBalance)} still pending\n\n'
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.chartRed)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await ref.read(gatewayReceivablesProvider.notifier).remove(r.id);
    if (mounted) context.safePop();
  }

  /// Edit or delete an existing settlement.
  Future<void> _editSettlement(
      GatewayReceivable r, GatewaySettlement s) async {
    final currency = ref.read(appSettingsProvider).currency;
    final amountCtrl = TextEditingController(text: s.amount.toStringAsFixed(2));
    final feeCtrl = TextEditingController(text: s.fee.toStringAsFixed(2));
    final noteCtrl = TextEditingController(text: s.note ?? '');
    DateTime date = s.date;

    double gross() => double.tryParse(amountCtrl.text.trim()) ?? 0;
    double fee() => double.tryParse(feeCtrl.text.trim()) ?? 0;

    final action = await showModalBottomSheet<String>(
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
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Edit settlement',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: AppColors.chartRed),
                        tooltip: 'Delete settlement',
                        onPressed: () => Navigator.pop(ctx, 'delete'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _label('Gross cleared'),
                  TextField(
                    controller: amountCtrl,
                    onChanged: (_) => setSt(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                    ],
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: _dec('0.00', prefix: '$currency  '),
                  ),
                  const SizedBox(height: 12),
                  _label('Gateway fee'),
                  TextField(
                    controller: feeCtrl,
                    onChanged: (_) => setSt(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                    ],
                    decoration: _dec('0.00', prefix: '$currency  '),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.chartGreen.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Text('Lands in bank',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.chartGreen)),
                        const Spacer(),
                        Text(
                          '$currency ${_fmt.format((gross() - fee()).clamp(0, double.maxFinite))}',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.chartGreen),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setSt(() => date = d);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F6F8),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 16),
                          const SizedBox(width: 10),
                          Text(_dateFmt.format(date),
                              style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: _dec('Note (optional)'),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, 'save'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryNavy,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Save changes',
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

    if (!mounted || action == null) return;
    final notifier = ref.read(gatewayReceivablesProvider.notifier);

    if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete settlement?'),
          content: Text(
              'Removes the $currency ${_fmt.format(s.amount)} settlement, its '
              'cash entry and its fee expense, and adds the amount back to '
              'what the gateway owes you.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete',
                  style: TextStyle(color: AppColors.chartRed)),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await notifier.deleteSettlement(r.id, s.id);
      }
      return;
    }

    final g = gross();
    if (g <= 0) return;
    await notifier.updateSettlement(
      r.id,
      s.copyWith(
        amount: g,
        fee: fee(),
        date: date,
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      ),
    );
  }

  Future<void> _deleteCollection(
      GatewayReceivable r, GatewayCollection c) async {
    final currency = ref.read(appSettingsProvider).currency;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove entry?'),
        content: Text(
            'Removes the $currency ${_fmt.format(c.amount)} collected on '
            '${_dateFmt.format(c.date)} and lowers the balance again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(color: AppColors.chartRed)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref
        .read(gatewayReceivablesProvider.notifier)
        .deleteCollection(r.id, c.id);
  }

  // ═══════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(appSettingsProvider).currency;
    final live = _live;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: AppColors.primaryNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => context.safePop()),
        title: Text(_isEdit ? 'Edit Gateway' : 'New Gateway',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          if (_isEdit)
            IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Delete gateway',
                onPressed: _delete),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
          children: [
            if (live != null) _balanceCard(live, currency),

            _section('Gateway', [
              _field(
                label: 'Name',
                child: TextFormField(
                  controller: _nameCtrl,
                  decoration: _dec('e.g. Paymob, Fawry, Stripe'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              _field(
                label: 'Pending balance',
                hint: _isEdit
                    ? 'Settlements and collections keep this up to date'
                    : 'What the gateway is holding right now',
                child: TextFormField(
                  controller: _balanceCtrl,
                  decoration: _dec('0.00', prefix: '$currency '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                  ],
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (double.tryParse(v.trim()) == null) return 'Invalid';
                    return null;
                  },
                ),
              ),
            ]),

            _section('Terms', [
              _field(
                label: 'Fee %',
                hint: 'Pre-fills the fee when you record a settlement',
                child: TextFormField(
                  controller: _feeCtrl,
                  decoration: _dec('e.g. 2.5', prefix: '% '),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                  ],
                ),
              ),
              _field(
                label: 'Payout cycle',
                hint: _settlementDays == null
                    ? 'Set this to get warned when a payout is late'
                    : 'Flagged if nothing arrives for $_settlementDays days',
                child: Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: _cycles.entries.map((e) {
                    final sel = _settlementDays == e.key;
                    return GestureDetector(
                      onTap: () => setState(() => _settlementDays = e.key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: sel
                              ? AppColors.primaryNavy
                              : const Color(0xFFF5F6F8),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(e.value,
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: sel
                                    ? Colors.white
                                    : AppColors.textSecondary)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              _field(
                label: 'Status',
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<GatewayReceivableStatus>(
                    style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(
                          value: GatewayReceivableStatus.active,
                          label: Text('Active')),
                      ButtonSegment(
                          value: GatewayReceivableStatus.closed,
                          label: Text('Closed')),
                    ],
                    selected: {_status},
                    onSelectionChanged: (s) =>
                        setState(() => _status = s.first),
                  ),
                ),
              ),
            ]),

            if (!_isEdit) _impactCard(currency),

            _section('Notes', [
              _field(
                label: null,
                child: TextFormField(
                  controller: _notesCtrl,
                  decoration: _dec('Anything worth remembering'),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ]),

            if (_isEdit && live != null) _historySection(live, currency),
          ],
        ),
      ),
    );
  }

  Widget _balanceCard(GatewayReceivable r, String currency) {
    final accent = r.settlementOverdue
        ? AppColors.chartRed
        : r.isCleared
            ? AppColors.chartGreen
            : AppColors.primaryNavy;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.settlementOverdue ? 'PAYOUT OVERDUE' : 'AWAITING SETTLEMENT',
              style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: accent)),
          const SizedBox(height: 3),
          Text('$currency ${_fmt.format(r.pendingBalance)}',
              style:
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          if (r.totalSettled > 0) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _stat('Settled', '$currency ${_fmt.format(r.totalSettled)}',
                    AppColors.textPrimary),
                _stat('Fees', '$currency ${_fmt.format(r.totalFees)}',
                    AppColors.chartOrange),
                _stat('Banked',
                    '$currency ${_fmt.format(r.totalCashReceived)}',
                    AppColors.chartGreen),
              ],
            ),
            if (r.effectiveFeeRate > 0) ...[
              const SizedBox(height: 8),
              Text(
                  'Effective fee rate ${r.effectiveFeeRate.toStringAsFixed(2)}%',
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textTertiary)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 10.5, color: AppColors.textTertiary)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ],
        ),
      );

  /// Plain-English preview of what this account does to the books.
  Widget _impactCard(String currency) {
    final amt = double.tryParse(_balanceCtrl.text.trim()) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_rounded,
                  size: 15, color: AppColors.primaryNavy),
              SizedBox(width: 7),
              Text('What this does',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryNavy)),
            ],
          ),
          const SizedBox(height: 10),
          _impactLine(Icons.savings_rounded,
              'Adds $currency ${_fmt.format(amt)} to what you own on the balance sheet'),
          _impactLine(Icons.receipt_long_rounded,
              'No P&L entry — the revenue was already booked when the sales happened'),
          _impactLine(Icons.account_balance_rounded,
              'When you settle, only the amount NET of fees is added to Cash & Bank'),
        ],
      ),
    );
  }

  Widget _impactLine(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 13, color: AppColors.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.textSecondary)),
            ),
          ],
        ),
      );

  /// Settlements and collections, newest first.
  Widget _historySection(GatewayReceivable r, String currency) {
    final settlements = r.settlements.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final collections = r.collections.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SETTLEMENTS (${settlements.length})',
              style: const TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textTertiary)),
          const SizedBox(height: 6),
          if (settlements.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text('No payouts recorded yet.',
                  style:
                      TextStyle(color: AppColors.textTertiary, fontSize: 13)),
            )
          else
            ...settlements.map((s) => InkWell(
                  onTap: () => _editSettlement(r, s),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color:
                                AppColors.chartGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(Icons.south_west_rounded,
                              size: 16, color: AppColors.chartGreen),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_dateFmt.format(s.date),
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500)),
                              Text(
                                s.fee > 0
                                    ? 'Fee $currency ${_fmt.format(s.fee)} '
                                        '(${s.feeRate.toStringAsFixed(1)}%)'
                                    : (s.note ?? 'No fee'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textTertiary),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('+$currency ${_fmt.format(s.netAmount)}',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.chartGreen)),
                            if (s.fee > 0)
                              Text('of ${_fmt.format(s.amount)}',
                                  style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textTertiary)),
                          ],
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right_rounded,
                            size: 17, color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                )),
          if (collections.isNotEmpty) ...[
            const Divider(height: 20),
            Text('COLLECTED (${collections.length})',
                style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary)),
            const SizedBox(height: 4),
            ...collections.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primaryNavy.withValues(alpha: 0.09),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.north_east_rounded,
                            size: 16, color: AppColors.primaryNavy),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_dateFmt.format(c.date),
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500)),
                            if (c.note != null)
                              Text(c.note!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.textTertiary)),
                          ],
                        ),
                      ),
                      Text('$currency ${_fmt.format(c.amount)}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            size: 16, color: AppColors.textTertiary),
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Remove entry',
                        onPressed: () => _deleteCollection(r, c),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  // ── Building blocks ──────────────────────────────────────

  Widget _section(String title, List<Widget> children) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _field({String? label, String? hint, required Widget child}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (label != null) ...[
              Text(label,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 6),
            ],
            child,
            if (hint != null) ...[
              const SizedBox(height: 5),
              Text(hint,
                  style: const TextStyle(
                      fontSize: 11.5, color: AppColors.textTertiary)),
            ],
          ],
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
      );

  InputDecoration _dec(String hint, {String? prefix}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.textTertiary),
        prefixText: prefix,
        filled: true,
        fillColor: const Color(0xFFF5F6F8),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primaryNavy, width: 1.5),
        ),
      );
}
