import 'dart:developer';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/repository_providers.dart';
import '../models/recurring_transaction_model.dart';

class ScheduledTransactionsNotifier extends Notifier<List<RecurringTransaction>> {
  @override
  List<RecurringTransaction> build() {
    _loadFromFirestore();
    return [];
  }

  Future<void> _loadFromFirestore() async {
    final repo = ref.read(recurringTransactionRepositoryProvider);
    final result = await repo.getRecurringTransactions();
    if (result.isSuccess && result.data != null) {
      state = result.data!;
    } else {
      log('Failed to load recurring transactions: ${result.error}');
    }
  }

  Future<void> addTransaction(RecurringTransaction transaction) async {
    state = [...state, transaction];
    final repo = ref.read(recurringTransactionRepositoryProvider);
    final result = await repo.createRecurringTransaction(transaction);
    if (!result.isSuccess) {
      log('Failed to persist recurring transaction: ${result.error}');
      state = state.where((t) => t.id != transaction.id).toList();
    }
  }

  Future<void> updateTransaction(RecurringTransaction updated) async {
    final previous = state;
    state = [
      for (final t in state)
        if (t.id == updated.id) updated else t
    ];
    final repo = ref.read(recurringTransactionRepositoryProvider);
    final result = await repo.updateRecurringTransaction(updated.id, updated);
    if (!result.isSuccess) {
      log('Failed to update recurring transaction: ${result.error}');
      state = previous;
    }
  }

  Future<void> deleteTransaction(String id) async {
    final previous = state;
    state = state.where((t) => t.id != id).toList();
    final repo = ref.read(recurringTransactionRepositoryProvider);
    final result = await repo.deleteRecurringTransaction(id);
    if (!result.isSuccess) {
      log('Failed to delete recurring transaction: ${result.error}');
      state = previous;
    }
  }

  Future<void> toggleActive(String id) async {
    final target = state.firstWhere((t) => t.id == id);
    final newActive = !target.isActive;
    final previous = state;
    state = [
      for (final t in state)
        if (t.id == id) t.copyWith(isActive: newActive) else t
    ];
    final repo = ref.read(recurringTransactionRepositoryProvider);
    final result = await repo.toggleActive(id, newActive);
    if (!result.isSuccess) {
      log('Failed to toggle recurring transaction: ${result.error}');
      state = previous;
    }
  }

  Future<void> refresh() async {
    await _loadFromFirestore();
  }
}

final scheduledTransactionsProvider =
    NotifierProvider<ScheduledTransactionsNotifier, List<RecurringTransaction>>(() {
  return ScheduledTransactionsNotifier();
});
