import '../../shared/models/transaction_model.dart';
import '../services/result.dart';

/// Contract for transaction data operations.
/// Implementations can be local (in-memory), API-based, or cached.
abstract class TransactionRepository {
  /// Fetches all transactions, optionally filtered and paginated.
  /// When [startDate] and/or [endDate] are provided the query is bounded
  /// server-side so only matching documents are read from Firestore.
  Future<Result<List<Transaction>>> getTransactions({
    TransactionFilter? filter,
    int? limit,
    String? startAfterId,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Fetches a single transaction by ID.
  Future<Result<Transaction>> getTransactionById(String id);

  /// Creates a new transaction. Returns the created transaction.
  Future<Result<Transaction>> createTransaction(Transaction transaction);

  /// Updates an existing transaction.
  Future<Result<Transaction>> updateTransaction(Transaction transaction);

  /// Deletes a transaction by ID.
  Future<Result<void>> deleteTransaction(String id);

  /// Fetches all transactions whose date_time falls within [start, end].
  /// Uses server-side date filtering (no pagination needed for bounded ranges).
  Future<Result<List<Transaction>>> getTransactionsInRange({
    required DateTime start,
    required DateTime end,
  });

  /// Reassigns all transactions with [oldCategoryId] to [newCategoryId].
  /// Used when a category is deleted to prevent orphaned references.
  Future<Result<void>> reassignCategory(String oldCategoryId, String newCategoryId);

  /// Clears any in-memory cache for range queries.
  /// Called after mutations to ensure fresh data on next fetch.
  void clearRangeCache() {}
}
