import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/accrued_expense_model.dart';
import '../../shared/utils/safe_pop.dart';

/// Add or edit an accrued expense.
/// Pass `extra: {'expense': AccruedExpense}` for edit mode.
class AddEditAccruedExpenseScreen extends ConsumerStatefulWidget {
  final AccruedExpense? expense;
  const AddEditAccruedExpenseScreen({super.key, this.expense});

  @override
  ConsumerState<AddEditAccruedExpenseScreen> createState() =>
      _AddEditAccruedExpenseScreenState();
}

class _AddEditAccruedExpenseScreenState
    extends ConsumerState<AddEditAccruedExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  late final bool _isEdit;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _notesCtrl;
  late AccruedExpenseStatus _status;
  bool _recordInPL = true; // post the P&L expense on add
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _isEdit = e != null;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _amountCtrl = TextEditingController(
        text: e != null ? e.amount.toStringAsFixed(2) : '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _status = e?.status ?? AccruedExpenseStatus.active;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  AccruedExpense? get _live {
    if (widget.expense == null) return null;
    final list = ref.watch(accruedExpensesProvider);
    for (final e in list) {
      if (e.id == widget.expense!.id) return e;
    }
    return widget.expense;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final notifier = ref.read(accruedExpensesProvider.notifier);
    final base = widget.expense;
    final expense = AccruedExpense(
      id: base?.id ?? '',
      name: _nameCtrl.text.trim(),
      amount: double.tryParse(_amountCtrl.text.trim()) ?? 0,
      status: _status,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdAt: base?.createdAt ?? DateTime.now(),
      expenseTransactionId: base?.expenseTransactionId,
      payments: base?.payments ?? const [],
    );
    final ok = _isEdit
        ? await notifier.updateExpense(expense)
        : await notifier.add(expense, postExpense: _recordInPL);
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
        title: const Text('Delete accrual?'),
        content: const Text(
            'Removes the accrual and its linked transactions (the recognized '
            'expense and any payments).'),
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
        .read(accruedExpensesProvider.notifier)
        .remove(widget.expense!.id);
    if (mounted) context.safePop();
  }

  Future<void> _recordPayment() async {
    final amountCtrl = TextEditingController();
    DateTime date = DateTime.now();
    bool postCash = true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Record payment'),
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
                decoration: const InputDecoration(labelText: 'Amount paid'),
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
                title: const Text('Deduct from Cash & Bank',
                    style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  postCash
                      ? 'Posts the payment as a cash outflow.'
                      : 'Only lowers the liability (log the cash yourself).',
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
    await ref.read(accruedExpensesProvider.notifier).recordPayment(
          widget.expense!.id,
          AccruedExpensePayment(
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
        title: Text(_isEdit ? 'Edit Accrual' : 'Add Accrual',
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
            _label('What is it for?'),
            TextFormField(
              controller: _nameCtrl,
              decoration: _dec('e.g. Accrued rent — June'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            _label(_isEdit ? 'Outstanding amount' : 'Amount accrued'),
            TextFormField(
              controller: _amountCtrl,
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
            const SizedBox(height: 16),

            // Record-in-P&L toggle (add only).
            if (!_isEdit)
              Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12)),
                child: SwitchListTile(
                  value: _recordInPL,
                  onChanged: (v) => setState(() => _recordInPL = v),
                  title: const Text('Record expense in P&L now',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _recordInPL
                        ? 'Recognizes the cost now (reduces profit) and adds the liability.'
                        : 'Only adds the liability — use if you already booked the expense elsewhere.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            _label('Status'),
            SegmentedButton<AccruedExpenseStatus>(
              segments: const [
                ButtonSegment(
                    value: AccruedExpenseStatus.active,
                    label: Text('Active')),
                ButtonSegment(
                    value: AccruedExpenseStatus.settled,
                    label: Text('Settled')),
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

            if (_isEdit) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text('Payments',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.chartRed,
                        visualDensity: VisualDensity.compact),
                    onPressed: _recordPayment,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Pay'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (live == null || live.payments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No payments yet.',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 13)),
                )
              else
                ...(live.payments.toList()
                      ..sort((a, b) => b.date.compareTo(a.date)))
                    .map((p) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.north_east_rounded,
                                  color: AppColors.chartRed, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(dateFmt.format(p.date),
                                      style: const TextStyle(fontSize: 13))),
                              Text('- $currency ${fmt.format(p.amount)}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.chartRed)),
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
