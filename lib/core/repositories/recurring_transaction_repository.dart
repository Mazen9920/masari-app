import '../../features/cash_flow/models/recurring_transaction_model.dart';
import '../services/result.dart';

/// Contract for recurring transaction data operations.
abstract class RecurringTransactionRepository {
  /// Fetches all recurring transactions for the current user.
  Future<Result<List<RecurringTransaction>>> getRecurringTransactions();

  /// Creates a new recurring transaction.
  Future<Result<RecurringTransaction>> createRecurringTransaction(
    RecurringTransaction transaction,
  );

  /// Updates an existing recurring transaction.
  Future<Result<RecurringTransaction>> updateRecurringTransaction(
    String id,
    RecurringTransaction updated,
  );

  /// Deletes a recurring transaction by ID.
  Future<Result<void>> deleteRecurringTransaction(String id);

  /// Toggles the active state of a recurring transaction.
  Future<Result<RecurringTransaction>> toggleActive(String id, bool active);
}
