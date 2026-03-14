import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recurring_transaction_model.dart';

class ScheduledTransactionsNotifier extends Notifier<List<RecurringTransaction>> {
  @override
  List<RecurringTransaction> build() {
    return [];
  }

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
