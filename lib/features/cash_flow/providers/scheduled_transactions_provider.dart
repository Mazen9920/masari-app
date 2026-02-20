import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recurring_transaction_model.dart';

class ScheduledTransactionsNotifier extends Notifier<List<RecurringTransaction>> {
  @override
  List<RecurringTransaction> build() {
    return _initialData;
  }

  static final List<RecurringTransaction> _initialData = [
    RecurringTransaction(
      id: '1',
      title: 'Office Rent',
      amount: 15000,
      isIncome: false,
      frequency: RecurrenceFrequency.monthly,
      nextDueDate: DateTime.now().add(const Duration(days: 2)), // Mock due date
      category: 'Rent',
      isActive: true,
    ),
    RecurringTransaction(
      id: '2',
      title: 'Team Salaries',
      amount: 42000,
      isIncome: false,
      frequency: RecurrenceFrequency.monthly,
      nextDueDate: DateTime.now().add(const Duration(days: 10)),
      category: 'Salaries',
      isActive: true,
    ),
     RecurringTransaction(
      id: '3',
      title: 'Client Retainer',
      amount: 20000,
      isIncome: true,
      frequency: RecurrenceFrequency.monthly,
      nextDueDate: DateTime.now().add(const Duration(days: 5)),
      category: 'Sales',
      isActive: true,
    ),
  ];

  void addTransaction(RecurringTransaction transaction) {
    state = [...state, transaction];
  }

  void updateTransaction(RecurringTransaction updated) {
    state = [
      for (final t in state)
        if (t.id == updated.id) updated else t
    ];
  }

  void deleteTransaction(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  void toggleActive(String id) {
     state = [
      for (final t in state)
        if (t.id == id) t.copyWith(isActive: !t.isActive) else t
    ];
  }
}

final scheduledTransactionsProvider =
    NotifierProvider<ScheduledTransactionsNotifier, List<RecurringTransaction>>(() {
  return ScheduledTransactionsNotifier();
});
