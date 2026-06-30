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
  late final TextEditingController _notesCtrl;
  late GatewayReceivableStatus _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.receivable;
    _isEdit = r != null;
    _nameCtrl = TextEditingController(text: r?.gatewayName ?? '');
    _balanceCtrl = TextEditingController(
        text: r != null ? r.pendingBalance.toStringAsFixed(2) : '');
    _notesCtrl = TextEditingController(text: r?.notes ?? '');
    _status = r?.status ?? GatewayReceivableStatus.active;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// The live receivable (reflects settlements recorded while on this screen).
  GatewayReceivable? get _live {
    if (widget.receivable == null) return null;
    final list = ref.watch(gatewayReceivablesProvider);
    for (final r in list) {
      if (r.id == widget.receivable!.id) return r;
    }
    return widget.receivable;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final notifier = ref.read(gatewayReceivablesProvider.notifier);
    final base = widget.receivable;
    final receivable = GatewayReceivable(
      id: base?.id ?? '',
      gatewayName: _nameCtrl.text.trim(),
      pendingBalance: double.tryParse(_balanceCtrl.text.trim()) ?? 0,
      status: _status,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdAt: base?.createdAt ?? DateTime.now(),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save')),
      );
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete gateway?'),
        content: const Text(
            'This removes the gateway and its linked settlement transactions.'),
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
    await ref
        .read(gatewayReceivablesProvider.notifier)
        .remove(widget.receivable!.id);
    if (mounted) context.safePop();
  }

  Future<void> _recordSettlement() async {
    final amountCtrl = TextEditingController();
    DateTime date = DateTime.now();
    bool postCash = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Record settlement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                ],
                decoration: const InputDecoration(
                    labelText: 'Amount received', prefixText: ''),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Date: '),
                  TextButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (d != null) setSt(() => date = d);
                    },
                    child: Text(DateFormat('MMM d, yyyy').format(date)),
                  ),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: postCash,
                onChanged: (v) => setSt(() => postCash = v ?? true),
                title: const Text('Add to Cash & Bank',
                    style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  postCash
                      ? 'Posts the amount as a cash inflow.'
                      : 'Only lowers the receivable (log the cash yourself).',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Record')),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) return;
    await ref.read(gatewayReceivablesProvider.notifier).recordSettlement(
          widget.receivable!.id,
          GatewaySettlement(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            amount: amount,
            date: date,
          ),
          postCash: postCash,
        );
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(appSettingsProvider).currency;
    final fmt = NumberFormat('#,##0.00', 'en');
    final dateFmt = DateFormat('MMM d, yyyy');
    final live = _live;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: AppColors.primaryNavy,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => context.safePop()),
        title: Text(_isEdit ? 'Edit Gateway' : 'Add Gateway',
            style:
                const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          if (_isEdit)
            IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: _delete),
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _label('Gateway name'),
            TextFormField(
              controller: _nameCtrl,
              decoration: _dec('e.g. Paymob'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            _label('Pending (uncleared) balance'),
            TextFormField(
              controller: _balanceCtrl,
              decoration: _dec('0.00', prefix: '$currency '),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (double.tryParse(v.trim()) == null) return 'Invalid';
                return null;
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'What the gateway has collected from online/card sales but not yet '
              'settled to your bank. Update this as it changes; record settlements '
              'below as the gateway pays out.',
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 16),
            _label('Status'),
            SegmentedButton<GatewayReceivableStatus>(
              segments: const [
                ButtonSegment(
                    value: GatewayReceivableStatus.active,
                    label: Text('Active')),
                ButtonSegment(
                    value: GatewayReceivableStatus.closed,
                    label: Text('Closed')),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            const SizedBox(height: 16),
            _label('Notes (optional)'),
            TextFormField(
              controller: _notesCtrl,
              decoration: _dec('Notes'),
              maxLines: 2,
            ),

            // ── Settlements (edit mode) ──
            if (_isEdit) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text('Settlements received',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.chartGreen,
                        visualDensity: VisualDensity.compact),
                    onPressed: _recordSettlement,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Record'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (live == null || live.settlements.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No settlements recorded yet.',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 13)),
                )
              else
                ...(live.settlements.toList()
                      ..sort((a, b) => b.date.compareTo(a.date)))
                    .map((s) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.south_west_rounded,
                                  color: AppColors.chartGreen, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(dateFmt.format(s.date),
                                      style: const TextStyle(fontSize: 13))),
                              Text('+ $currency ${fmt.format(s.amount)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.chartGreen)),
                            ],
                          ),
                        )),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
      );

  InputDecoration _dec(String hint, {String? prefix}) => InputDecoration(
        hintText: hint,
        prefixText: prefix,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      );
}
