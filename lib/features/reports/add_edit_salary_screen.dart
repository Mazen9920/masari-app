import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/salary_model.dart';
import '../../shared/utils/safe_pop.dart';

/// Screen for creating or editing an employee salary.
/// Pass `extra: {'salary': Salary}` for edit mode.
class AddEditSalaryScreen extends ConsumerStatefulWidget {
  final Salary? salary;
  const AddEditSalaryScreen({super.key, this.salary});

  @override
  ConsumerState<AddEditSalaryScreen> createState() =>
      _AddEditSalaryScreenState();
}

class _AddEditSalaryScreenState extends ConsumerState<AddEditSalaryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final bool _isEdit;

  late final TextEditingController _nameCtrl;
  late final TextEditingController _roleCtrl;
  late final TextEditingController _salaryCtrl;
  late final TextEditingController _notesCtrl;

  late SalaryType _type;
  late SalaryStatus _status;
  late PaymentFrequency _frequency;
  late DateTime _startDate;
  DateTime? _endDate;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.salary;
    _isEdit = s != null;
    _nameCtrl = TextEditingController(text: s?.employeeName ?? '');
    _roleCtrl = TextEditingController(text: s?.role ?? '');
    _salaryCtrl = TextEditingController(
        text: s != null ? s.monthlySalary.toStringAsFixed(2) : '');
    _notesCtrl = TextEditingController(text: s?.notes ?? '');
    _type = s?.type ?? SalaryType.fullTime;
    _status = s?.status ?? SalaryStatus.active;
    _frequency = s?.frequency ?? PaymentFrequency.monthly;
    _startDate = s?.startDate ?? DateTime.now();
    _endDate = s?.endDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _salaryCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final monthlySalary = double.tryParse(_salaryCtrl.text.trim()) ?? 0;
    final now = DateTime.now();

    if (_isEdit) {
      final updated = widget.salary!.copyWith(
        employeeName: _nameCtrl.text.trim(),
        role: _roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim(),
        type: _type,
        monthlySalary: monthlySalary,
        status: _status,
        frequency: _frequency,
        startDate: _startDate,
        endDate: _endDate,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        updatedAt: now,
      );
      await ref.read(salariesProvider.notifier).updateSalary(updated);
    } else {
      final salary = Salary(
        id: '',
        employeeName: _nameCtrl.text.trim(),
        role: _roleCtrl.text.trim().isEmpty ? null : _roleCtrl.text.trim(),
        type: _type,
        monthlySalary: monthlySalary,
        status: _status,
        frequency: _frequency,
        startDate: _startDate,
        endDate: _endDate,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        createdAt: now,
      );
      await ref.read(salariesProvider.notifier).add(salary);
    }

    if (mounted) context.safePop();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final currency = settings.currency;
    final monthlySalary = double.tryParse(_salaryCtrl.text.trim()) ?? 0;
    final annualSalary = monthlySalary * 12;
    final dateFmt = DateFormat('MMM d, yyyy');

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Employee' : 'Add Employee',
            style: AppTypography.labelMedium.copyWith(fontSize: 17)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.safePop(),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isEdit ? 'Save' : 'Add',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.chartGreen)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
          children: [
            // ── Employee Name ──
            _fieldLabel('Employee Name *'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
              decoration: _inputDecoration('e.g. Ahmed Hassan'),
            ),
            const SizedBox(height: 16),

            // ── Role ──
            _fieldLabel('Role / Title'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _roleCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: _inputDecoration('e.g. Sales Manager'),
            ),
            const SizedBox(height: 16),

            // ── Employee Type ──
            _fieldLabel('Employee Type'),
            const SizedBox(height: 6),
            DropdownButtonFormField<SalaryType>(
              initialValue: _type,
              items: SalaryType.values
                  .map((t) => DropdownMenuItem(
                        value: t,
                        child: Text('${t.icon} ${t.label}'),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
              decoration: _inputDecoration(null),
            ),
            const SizedBox(height: 16),

            // ── Monthly Salary ──
            _fieldLabel('Monthly Salary *'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _salaryCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return 'Must be > 0';
                return null;
              },
              onChanged: (_) => setState(() {}),
              decoration: _inputDecoration('0.00'),
            ),
            const SizedBox(height: 16),

            // ── Payment Frequency ──
            _fieldLabel('Payment Frequency'),
            const SizedBox(height: 6),
            DropdownButtonFormField<PaymentFrequency>(
              initialValue: _frequency,
              items: PaymentFrequency.values
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(f.label),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _frequency = v);
              },
              decoration: _inputDecoration(null),
            ),
            const SizedBox(height: 16),

            // ── Start Date ──
            _fieldLabel('Start Date'),
            const SizedBox(height: 6),
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
                    Expanded(
                      child: Text(dateFmt.format(_startDate),
                          style: AppTypography.bodyMedium),
                    ),
                    const Icon(Icons.calendar_today_rounded,
                        size: 18, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── End Date (optional) ──
            _fieldLabel('End Date (optional)'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _endDate ?? DateTime.now(),
                  firstDate: _startDate,
                  lastDate: DateTime(2040),
                );
                if (d != null) setState(() => _endDate = d);
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
                    Expanded(
                      child: Text(
                          _endDate != null
                              ? dateFmt.format(_endDate!)
                              : 'Not set (ongoing)',
                          style: AppTypography.bodyMedium.copyWith(
                              color: _endDate != null
                                  ? null
                                  : AppColors.textTertiary)),
                    ),
                    if (_endDate != null)
                      GestureDetector(
                        onTap: () => setState(() => _endDate = null),
                        child: const Icon(Icons.clear_rounded,
                            size: 18, color: AppColors.textTertiary),
                      )
                    else
                      const Icon(Icons.calendar_today_rounded,
                          size: 18, color: AppColors.textTertiary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Status ──
            _fieldLabel('Status'),
            const SizedBox(height: 6),
            DropdownButtonFormField<SalaryStatus>(
              initialValue: _status,
              items: SalaryStatus.values
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s.label),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _status = v);
              },
              decoration: _inputDecoration(null),
            ),
            const SizedBox(height: 16),

            // ── Notes ──
            _fieldLabel('Notes'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: _inputDecoration('Optional notes about this employee'),
            ),
            const SizedBox(height: 24),

            // ── Live Preview ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.chartGreen.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.chartGreen.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Salary Preview',
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.chartGreen, fontSize: 13)),
                  const SizedBox(height: 12),
                  _previewRow('Monthly Salary',
                      '$currency ${NumberFormat('#,##0.00', 'en').format(monthlySalary)}'),
                  _previewRow('Annual Salary',
                      '$currency ${NumberFormat('#,##0.00', 'en').format(annualSalary)}'),
                  _previewRow('Type', '${_type.icon} ${_type.label}'),
                  _previewRow('Frequency', _frequency.label),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(text,
        style: AppTypography.labelMedium.copyWith(fontSize: 13));
  }

  InputDecoration _inputDecoration(String? hint) {
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
}
