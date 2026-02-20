import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
import '../../cash_flow/models/recurring_transaction_model.dart';
import '../../cash_flow/providers/scheduled_transactions_provider.dart';

class AddRecurringSheet extends ConsumerStatefulWidget {
  final RecurringTransaction? transaction;
  const AddRecurringSheet({super.key, this.transaction});

  @override
  ConsumerState<AddRecurringSheet> createState() => _AddRecurringSheetState();
}

class _AddRecurringSheetState extends ConsumerState<AddRecurringSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  
  bool _isIncome = false;
  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  DateTime _nextDueDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.transaction != null) {
      final t = widget.transaction!;
      _titleController.text = t.title;
      _amountController.text = t.amount.toString(); // Remove formatting
      _isIncome = t.isIncome;
      _frequency = t.frequency;
      _nextDueDate = t.nextDueDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.transaction != null ? 'Edit Scheduled Transaction' : 'New Recurring Transaction',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: AppColors.textTertiary,
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Toggle Type
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildTypeToggle('Expense', !_isIncome, Colors.red),
                  ),
                  Expanded(
                    child: _buildTypeToggle('Income', _isIncome, Colors.green),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Title
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title (e.g., Office Rent)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Amount
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount (EGP)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.attach_money_rounded),
              ),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Frequency & Date
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<RecurrenceFrequency>(
                    value: _frequency,
                    decoration: InputDecoration(
                      labelText: 'Frequency',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: RecurrenceFrequency.values.map((f) {
                      return DropdownMenuItem(
                        value: f,
                        child: Text(f.name[0].toUpperCase() + f.name.substring(1)),
                      );
                    }).toList(),
                    onChanged: (v) => setState(() => _frequency = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _nextDueDate,
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2030),
                      );
                      if (picked != null) setState(() => _nextDueDate = picked);
                    },
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(DateFormat('MMM d').format(_nextDueDate)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Save Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryNavy,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save Scheduled Transaction', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeToggle(String label, bool isSelected, Color color) {
    return GestureDetector(
      onTap: () {
        setState(() => _isIncome = label == 'Income');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSelected ? color : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      if (widget.transaction != null) {
        // Update existing
        final updated = widget.transaction!.copyWith(
          title: _titleController.text,
          amount: double.parse(_amountController.text),
          isIncome: _isIncome,
          frequency: _frequency,
          nextDueDate: _nextDueDate,
        );
        ref.read(scheduledTransactionsProvider.notifier).updateTransaction(updated);
      } else {
        // Create new
        final transaction = RecurringTransaction(
          id: const Uuid().v4(),
          title: _titleController.text,
          amount: double.parse(_amountController.text),
          isIncome: _isIncome,
          frequency: _frequency,
          nextDueDate: _nextDueDate,
        );
        ref.read(scheduledTransactionsProvider.notifier).addTransaction(transaction);
      }
      Navigator.pop(context);
    }
  }
}
