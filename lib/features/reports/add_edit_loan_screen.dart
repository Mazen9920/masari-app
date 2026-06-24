import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/loan_model.dart';
import '../../shared/utils/safe_pop.dart';

/// Screen for creating or editing a loan.
/// Pass `extra: {'loan': Loan}` for edit mode.
class AddEditLoanScreen extends ConsumerStatefulWidget {
  final Loan? loan;
  const AddEditLoanScreen({super.key, this.loan});

  @override
  ConsumerState<AddEditLoanScreen> createState() => _AddEditLoanScreenState();
}

class _AddEditLoanScreenState extends ConsumerState<AddEditLoanScreen> {
  final _formKey = GlobalKey<FormState>();
  late final bool _isEdit;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _lenderCtrl;
  late final TextEditingController _principalCtrl;
  late final TextEditingController _interestCtrl;
  late final TextEditingController _termCtrl;
  late final TextEditingController _notesCtrl;

  late LoanType _type;
  late LoanStatus _status;
  late DateTime _startDate;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final l = widget.loan;
    _isEdit = l != null;
    _nameCtrl = TextEditingController(text: l?.name ?? '');
    _lenderCtrl = TextEditingController(text: l?.lender ?? '');
    _principalCtrl = TextEditingController(
        text: l != null ? l.principalAmount.toStringAsFixed(2) : '');
    _interestCtrl = TextEditingController(
        text: l != null ? l.interestRate.toStringAsFixed(2) : '0');
    _termCtrl = TextEditingController(
        text: l != null ? l.termMonths.toString() : '12');
    _notesCtrl = TextEditingController(text: l?.notes ?? '');
    _type = l?.type ?? LoanType.bankLoan;
    _status = l?.status ?? LoanStatus.active;
    _startDate = l?.startDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _lenderCtrl.dispose();
    _principalCtrl.dispose();
    _interestCtrl.dispose();
    _termCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final principal = double.tryParse(_principalCtrl.text.trim()) ?? 0;
    final interest = double.tryParse(_interestCtrl.text.trim()) ?? 0;
    final term = int.tryParse(_termCtrl.text.trim()) ?? 12;
    final now = DateTime.now();

    if (_isEdit) {
      final updated = widget.loan!.copyWith(
        name: _nameCtrl.text.trim(),
        lender:
            _lenderCtrl.text.trim().isEmpty ? null : _lenderCtrl.text.trim(),
        type: _type,
        principalAmount: principal,
        interestRate: interest,
        termMonths: term,
        startDate: _startDate,
        status: _status,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        updatedAt: now,
      );
      await ref.read(loansProvider.notifier).updateLoan(updated);
    } else {
      final loan = Loan(
        id: '',
        name: _nameCtrl.text.trim(),
        lender:
            _lenderCtrl.text.trim().isEmpty ? null : _lenderCtrl.text.trim(),
        type: _type,
        principalAmount: principal,
        interestRate: interest,
        termMonths: term,
        startDate: _startDate,
        status: _status,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        createdAt: now,
      );
      await ref.read(loansProvider.notifier).add(loan);
    }

    setState(() => _saving = false);
    if (mounted) context.safePop();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM d, yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Loan' : 'Add Loan',
            style: AppTypography.labelMedium.copyWith(fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primaryNavy,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.safePop(),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Save',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.chartBlue)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Name ──
            _label('Loan Name *'),
            _textField(
              _nameCtrl,
              hint: 'e.g. Equipment Financing',
              validator: (v) =>
                  (v?.trim().isEmpty ?? true) ? 'Name is required' : null,
            ),
            const SizedBox(height: 14),

            // ── Lender ──
            _label('Lender'),
            _textField(_lenderCtrl, hint: 'e.g. CIB, Banque Misr'),
            const SizedBox(height: 14),

            // ── Type ──
            _label('Loan Type'),
            DropdownButtonFormField<LoanType>(
              initialValue: _type,
              decoration: _inputDecoration(),
              items: LoanType.values
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text('${t.icon} ${t.label}')))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 14),

            // ── Principal Amount ──
            _label('Principal Amount *'),
            _textField(
              _principalCtrl,
              hint: '0.00',
              keyboard:
                  const TextInputType.numberWithOptions(decimal: true),
              formatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ],
              validator: (v) {
                final n = double.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 14),

            // ── Interest Rate ──
            _label('Interest Rate (% per year)'),
            _textField(
              _interestCtrl,
              hint: '0.00',
              keyboard:
                  const TextInputType.numberWithOptions(decimal: true),
              formatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
              ],
            ),
            const SizedBox(height: 14),

            // ── Term ──
            _label('Term (months)'),
            _textField(
              _termCtrl,
              hint: '12',
              keyboard: TextInputType.number,
              formatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                if (n == null || n <= 0) return 'Enter valid months';
                return null;
              },
            ),
            const SizedBox(height: 14),

            // ── Start Date ──
            _label('Start Date'),
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _startDate,
                  firstDate: DateTime(2010),
                  lastDate: DateTime(2040),
                );
                if (d != null) setState(() => _startDate = d);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded,
                        size: 18, color: AppColors.textTertiary),
                    const SizedBox(width: 10),
                    Text(dateFmt.format(_startDate),
                        style: AppTypography.bodyMedium),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Status ──
            _label('Status'),
            DropdownButtonFormField<LoanStatus>(
              initialValue: _status,
              decoration: _inputDecoration(),
              items: LoanStatus.values
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            const SizedBox(height: 14),

            // ── Notes ──
            _label('Notes'),
            _textField(_notesCtrl, hint: 'Optional notes', maxLines: 3),
            const SizedBox(height: 30),

            // ── Preview ──
            _loanPreview(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _loanPreview() {
    final principal = double.tryParse(_principalCtrl.text.trim()) ?? 0;
    final rate = double.tryParse(_interestCtrl.text.trim()) ?? 0;
    final term = int.tryParse(_termCtrl.text.trim()) ?? 12;
    final interest = principal * (rate / 100) * (term / 12);
    final total = principal + interest;
    final monthly = term > 0 ? total / term : 0.0;
    final fmt = NumberFormat('#,##0.00', 'en');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Loan Preview',
              style: AppTypography.labelMedium.copyWith(fontSize: 13)),
          const SizedBox(height: 10),
          _previewRow('Principal', fmt.format(principal)),
          _previewRow('Total Interest', fmt.format(interest)),
          const Divider(height: 16),
          _previewRow('Total Due', fmt.format(total)),
          _previewRow('Monthly Payment', fmt.format(monthly)),
        ],
      ),
    );
  }

  Widget _previewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTypography.caption
                  .copyWith(color: AppColors.textTertiary)),
          Text(value, style: AppTypography.labelMedium.copyWith(fontSize: 13)),
        ],
      ),
    );
  }

  // ── Form helpers ──

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text,
          style:
              AppTypography.labelMedium.copyWith(fontSize: 13)),
    );
  }

  Widget _textField(
    TextEditingController controller, {
    String? hint,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: formatters,
      validator: validator,
      maxLines: maxLines,
      decoration: _inputDecoration(hint: hint),
    );
  }

  InputDecoration _inputDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }
}
