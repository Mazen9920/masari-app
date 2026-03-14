import '../../shared/models/transaction_model.dart';
import '../services/result.dart';

/// Contract for transaction data operations.
/// Implementations can be local (in-memory), API-based, or cached.
abstract class TransactionRepository {
  /// Fetches all transactions, optionally filtered and paginated.
  Future<Result<List<Transaction>>> getTransactions({
    TransactionFilter? filter,
    int? limit,
    String? startAfterId,
  });

  /// Fetches a single transaction by ID.
  Future<Result<Transaction>> getTransactionById(String id);

  /// Creates a new transaction. Returns the created transaction.
  Future<Result<Transaction>> createTransaction(Transaction transaction);

  /// Updates an existing transaction.
  Future<Result<Transaction>> updateTransaction(Transaction transaction);

  /// Deletes a transaction by ID.
  Future<Result<void>> deleteTransaction(String id);
}
