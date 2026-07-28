import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/models/accrued_expense_model.dart';
import '../../shared/models/category_data.dart';
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

  bool _recordInPL = true; // post the P&L expense on add
  bool _saving = false;

  /// When the cost was incurred — decides which month's P&L it lands in.
  late DateTime _accrualDate;

  /// Optional payment deadline, drives the overdue flag.
  DateTime? _dueDate;

  /// Real expense category for the P&L breakdown.
  String? _categoryId;

  late AccrualRecurrence _recurrence;

  final _fmt = NumberFormat('#,##0.00', 'en');
  final _dateFmt = DateFormat('MMM d, yyyy');
  final _monthFmt = DateFormat('MMMM yyyy');

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _isEdit = e != null;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _amountCtrl = TextEditingController(
        text: e != null ? e.totalAccrued.toStringAsFixed(2) : '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _accrualDate = e?.accrualDate ?? DateTime.now();
    _dueDate = e?.dueDate;
    _categoryId = e?.categoryId;
    _recurrence = e?.recurrence ?? AccrualRecurrence.none;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  /// Always read the latest record so payments recorded here update the
  /// summary immediately instead of showing the snapshot we opened with.
  AccruedExpense? get _live {
    if (widget.expense == null) return null;
    final list = ref.watch(accruedExpensesProvider);
    for (final e in list) {
      if (e.id == widget.expense!.id) return e;
    }
    return widget.expense;
  }

  // ═══════════════════════════════════════════════════════
  // ACTIONS
  // ═══════════════════════════════════════════════════════

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final notifier = ref.read(accruedExpensesProvider.notifier);
    final base = _live;
    final entered = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    // The field is the TOTAL accrued; outstanding is that minus what's paid.
    final alreadyPaid = base?.totalPaid ?? 0;
    final outstanding = (entered - alreadyPaid).clamp(0.0, double.maxFinite);

    final expense = AccruedExpense(
      id: base?.id ?? '',
      name: _nameCtrl.text.trim(),
      amount: outstanding,
      originalAmount: entered,
      accrualDate: _accrualDate,
      dueDate: _dueDate,
      categoryId: _categoryId,
      recurrence: _recurrence,
      period: base?.period,
      recurringSourceId: base?.recurringSourceId,
      // Status follows the balance — no manual toggle to get out of sync.
      status: outstanding <= 0.01 && _isEdit
          ? AccruedExpenseStatus.settled
          : AccruedExpenseStatus.active,
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
        const SnackBar(
            content: Text('Failed to save'),
            backgroundColor: AppColors.chartRed),
      );
    }
  }

  Future<void> _delete() async {
    final e = _live;
    if (e == null) return;
    final currency = ref.read(appSettingsProvider).currency;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete accrual?'),
        content: Text(
          'Deletes "${e.name}" and everything linked to it:\n\n'
          '• the $currency ${_fmt.format(e.totalAccrued)} expense in your P&L\n'
          '• ${e.payments.length} payment${e.payments.length == 1 ? '' : 's'} '
          'and their cash transactions\n\n'
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
    await ref.read(accruedExpensesProvider.notifier).remove(e.id);
    if (mounted) context.safePop();
  }

  /// Record a new payment against this accrual.
  Future<void> _recordPayment() async {
    final e = _live;
    if (e == null) return;
    await _paymentSheet(expense: e);
  }

  /// Edit or delete an existing payment.
  Future<void> _editPayment(
      AccruedExpense expense, AccruedExpensePayment payment) async {
    await _paymentSheet(expense: expense, existing: payment);
  }

  /// One sheet for both recording and editing a payment.
  Future<void> _paymentSheet({
    required AccruedExpense expense,
    AccruedExpensePayment? existing,
  }) async {
    final isEditing = existing != null;
    final currency = ref.read(appSettingsProvider).currency;
    final amountCtrl = TextEditingController(
        text: (existing?.amount ?? expense.amount).toStringAsFixed(2));
    final noteCtrl = TextEditingController(text: existing?.note ?? '');
    DateTime date = existing?.date ?? DateTime.now();
    bool postCash = true;

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
                    Expanded(
                      child: Text(
                          isEditing ? 'Edit payment' : 'Record payment',
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700)),
                    ),
                    if (isEditing)
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: AppColors.chartRed),
                        tooltip: 'Delete payment',
                        onPressed: () => Navigator.pop(ctx, 'delete'),
                      ),
                  ],
                ),
                Text('Outstanding $currency ${_fmt.format(expense.amount)}',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.textTertiary)),
                const SizedBox(height: 16),
                TextField(
                  controller: amountCtrl,
                  autofocus: !isEditing,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                  ],
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    prefixText: '$currency  ',
                    filled: true,
                    fillColor: const Color(0xFFF5F6F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
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
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Note (optional)',
                    hintStyle: const TextStyle(fontSize: 14),
                    filled: true,
                    fillColor: const Color(0xFFF5F6F8),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                if (!isEditing)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: postCash,
                    onChanged: (v) => setSt(() => postCash = v ?? true),
                    dense: true,
                    title: const Text('Deduct from Cash & Bank',
                        style: TextStyle(fontSize: 13.5)),
                    subtitle: Text(
                      postCash
                          ? 'Posts a cash outflow on that date.'
                          : 'Only lowers the liability.',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                const SizedBox(height: 12),
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
                    child: Text(isEditing ? 'Save changes' : 'Record payment',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;
    final notifier = ref.read(accruedExpensesProvider.notifier);

    if (action == 'delete' && existing != null) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete payment?'),
          content: Text(
              'Removes the $currency ${_fmt.format(existing.amount)} payment '
              'and its cash transaction, and adds the amount back to what you '
              'owe.'),
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
        await notifier.deletePayment(expense.id, existing.id);
      }
      return;
    }

    final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (amt <= 0) return;
    final note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();

    if (isEditing) {
      await notifier.updatePayment(
        expense.id,
        existing.copyWith(amount: amt, date: date, note: note),
      );
    } else {
      await notifier.recordPayment(
        expense.id,
        AccruedExpensePayment(
            id: const Uuid().v4(), amount: amt, date: date, note: note),
        postCash: postCash,
      );
    }
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
        title: Text(_isEdit ? 'Edit Accrual' : 'New Accrual',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          if (_isEdit)
            IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Delete accrual',
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

            _section('Details', [
              _field(
                label: 'What is it for?',
                child: TextFormField(
                  controller: _nameCtrl,
                  decoration: _dec('e.g. Office rent'),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              _field(
                label: 'Total amount',
                hint: _isEdit && (live?.totalPaid ?? 0) > 0
                    ? 'Full amount accrued — payments are tracked separately'
                    : null,
                child: TextFormField(
                  controller: _amountCtrl,
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
                    final d = double.tryParse(v.trim());
                    if (d == null) return 'Invalid number';
                    if (d <= 0) return 'Must be more than 0';
                    return null;
                  },
                ),
              ),
              _field(label: 'Expense category', child: _categoryField()),
            ]),

            _section('Timing', [
              _field(
                label: 'Expense date',
                hint: 'Books to ${_monthFmt.format(_accrualDate)} in your P&L',
                child: _dateField(
                  value: _accrualDate,
                  onPick: (d) => setState(() => _accrualDate = d),
                ),
              ),
              _field(
                label: 'Due date',
                hint: _dueHint(),
                child: _dateField(
                  value: _dueDate,
                  hint: 'No due date',
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  onPick: (d) => setState(() => _dueDate = d),
                  onClear: () => setState(() => _dueDate = null),
                ),
              ),
              _field(
                label: 'Repeats',
                hint: _recurrence == AccrualRecurrence.monthly
                    ? 'A new accrual is created automatically each month'
                    : null,
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AccrualRecurrence>(
                    style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(
                          value: AccrualRecurrence.none,
                          icon: Icon(Icons.looks_one_rounded, size: 16),
                          label: Text('One-off')),
                      ButtonSegment(
                          value: AccrualRecurrence.monthly,
                          icon: Icon(Icons.repeat_rounded, size: 16),
                          label: Text('Monthly')),
                    ],
                    selected: {_recurrence},
                    onSelectionChanged: (s) =>
                        setState(() => _recurrence = s.first),
                  ),
                ),
              ),
            ]),

            // What this will actually do to the books — no surprises.
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

            if (_isEdit && live != null) _paymentsSection(live, currency),
          ],
        ),
      ),
    );
  }

  /// Live balance summary shown while editing.
  Widget _balanceCard(AccruedExpense e, String currency) {
    final accent = e.isSettled
        ? AppColors.chartGreen
        : e.isOverdue
            ? AppColors.chartRed
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
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.isSettled ? 'SETTLED' : 'STILL OWED',
                      style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700,
                          color: accent)),
                  const SizedBox(height: 3),
                  Text('$currency ${_fmt.format(e.amount)}',
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.bold)),
                ],
              ),
              const Spacer(),
              if (!e.isSettled)
                FilledButton.icon(
                  onPressed: _recordPayment,
                  icon: const Icon(Icons.payments_rounded, size: 16),
                  label: const Text('Pay'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryNavy,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
            ],
          ),
          if (e.totalPaid > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: e.progressPct,
                minHeight: 5,
                backgroundColor: Colors.grey.shade200,
                valueColor:
                    const AlwaysStoppedAnimation(AppColors.chartGreen),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Paid $currency ${_fmt.format(e.totalPaid)}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.chartGreen)),
                Text('of $currency ${_fmt.format(e.totalAccrued)}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textTertiary)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Plain-English preview of the entries this will create.
  Widget _impactCard(String currency) {
    final amt = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final cats = ref.watch(categoriesProvider).value ?? const <CategoryData>[];
    final catName = _categoryId == null
        ? 'Accrued Expense'
        : (cats.where((c) => c.id == _categoryId).firstOrNull?.name ??
            'Accrued Expense');

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
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded,
                  size: 15, color: AppColors.primaryNavy),
              const SizedBox(width: 7),
              const Text('What this does',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryNavy)),
            ],
          ),
          const SizedBox(height: 10),
          _impactLine(
            Icons.trending_down_rounded,
            _recordInPL
                ? 'Books a $currency ${_fmt.format(amt)} "$catName" expense in '
                    '${_monthFmt.format(_accrualDate)} (non-cash)'
                : 'No P&L entry — the cost is already booked elsewhere',
          ),
          _impactLine(Icons.account_balance_rounded,
              'Adds $currency ${_fmt.format(amt)} to what you owe on the balance sheet'),
          _impactLine(Icons.payments_rounded,
              'Cash only moves later, when you record a payment'),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _recordInPL,
            onChanged: (v) => setState(() => _recordInPL = v),
            title: const Text('Record expense in P&L now',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
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
                      fontSize: 12, height: 1.35, color: AppColors.textSecondary)),
            ),
          ],
        ),
      );

  Widget _paymentsSection(AccruedExpense e, String currency) {
    final payments = e.payments.toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Payments (${payments.length})',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (!e.isSettled)
                TextButton.icon(
                  onPressed: _recordPayment,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Add', style: TextStyle(fontSize: 13)),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
            ],
          ),
          if (payments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('No payments recorded yet.',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 13)),
            )
          else
            ...payments.map((p) => InkWell(
                  onTap: () => _editPayment(e, p),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.chartGreen
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 17, color: AppColors.chartGreen),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_dateFmt.format(p.date),
                                  style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500)),
                              Text(
                                p.note?.isNotEmpty == true
                                    ? p.note!
                                    : (p.transactionId != null
                                        ? 'Cash paid'
                                        : 'Liability only'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.textTertiary),
                              ),
                            ],
                          ),
                        ),
                        Text('$currency ${_fmt.format(p.amount)}',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right_rounded,
                            size: 17, color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  String? _dueHint() {
    final d = _dueDate;
    if (d == null) return null;
    final today = DateTime.now();
    final days = DateTime(d.year, d.month, d.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    if (days < 0) return 'Overdue by ${-days} day${days == -1 ? '' : 's'}';
    if (days == 0) return 'Due today';
    return 'Due in $days day${days == 1 ? '' : 's'}';
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

  /// Tappable date field; shows [hint] and a clear button when null.
  Widget _dateField({
    required DateTime? value,
    required void Function(DateTime) onPick,
    VoidCallback? onClear,
    String hint = 'Select date',
    DateTime? firstDate,
    DateTime? lastDate,
  }) {
    return GestureDetector(
      onTap: () async {
        final first = firstDate ?? DateTime(2020);
        final last = lastDate ?? DateTime.now();
        final seed = value ?? DateTime.now();
        // Keep initialDate inside [first, last] — outside it throws.
        final initial = seed.isBefore(first)
            ? first
            : (seed.isAfter(last) ? last : seed);
        final d = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: first,
          lastDate: last,
        );
        if (d != null) onPick(d);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value != null ? _dateFmt.format(value) : hint,
                style: TextStyle(
                  fontSize: 14,
                  color: value != null
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ),
            if (value != null && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close_rounded,
                    size: 18, color: AppColors.textTertiary),
              )
            else
              const Icon(Icons.calendar_today_rounded,
                  size: 17, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  /// Expense-category picker so accruals break out properly in the P&L.
  Widget _categoryField() {
    final cats = ref.watch(categoriesProvider).value ?? const <CategoryData>[];
    final expenseCats = cats.where((c) => c.isExpense).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value:
              expenseCats.any((c) => c.id == _categoryId) ? _categoryId : null,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          hint: const Text('Accrued Expense (general)',
              style: TextStyle(fontSize: 14)),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Accrued Expense (general)',
                  style: TextStyle(fontSize: 14)),
            ),
            ...expenseCats.map((c) => DropdownMenuItem<String?>(
                  value: c.id,
                  child: Text(c.name,
                      style: const TextStyle(fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: (v) => setState(() => _categoryId = v),
        ),
      ),
    );
  }

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
