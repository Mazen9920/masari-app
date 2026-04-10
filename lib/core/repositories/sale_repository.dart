import '../../shared/models/sale_model.dart';
import '../../shared/models/transaction_model.dart' as models;
import '../services/result.dart';

/// Lightweight DTO describing a stock deduction tied to a sale line item.
class StockDeduction {
  final String productId;
  final String variantId;
  final int quantity; // positive = units to deduct
  final String valuationMethod; // 'fifo', 'lifo', or 'average'

  const StockDeduction({
    required this.productId,
    required this.variantId,
    required this.quantity,
    this.valuationMethod = 'fifo',
  });
}

/// Contract for sale data operations.
abstract class SaleRepository {
  /// Fetches all sales for the current user, optionally paginated.
  /// When [startDate] and/or [endDate] are provided the query is bounded
  /// server-side so only matching documents are read from Firestore.
  Future<Result<List<Sale>>> getSales({
    int? limit,
    String? startAfterId,
    DateTime? startDate,
    DateTime? endDate,
  });

  /// Fetches all sales whose date falls within [start, end].
  /// Uses server-side date filtering (no pagination needed for bounded ranges).
  Future<Result<List<Sale>>> getSalesInRange({
    required DateTime start,
    required DateTime end,
  });

  /// Fetches a single sale by ID.
  Future<Result<Sale>> getSaleById(String id);

  /// Creates a new sale.
  Future<Result<Sale>> createSale(Sale sale);

  /// Creates a sale and its associated transactions (revenue + COGS) atomically.
  /// All documents are written in a single Firestore batch to prevent partial writes.
  Future<Result<Sale>> createSaleWithTransactions(
      Sale sale, List<models.Transaction> transactions);

  /// Creates a sale, its transactions, AND deducts stock — all in one atomic
  /// Firestore transaction. If any product has insufficient stock the entire
  /// operation is rolled back.
  Future<Result<Sale>> createSaleWithTransactionsAndStock(
      Sale sale,
      List<models.Transaction> transactions,
      List<StockDeduction> stockDeductions);

  /// Offline-safe version of [createSaleWithTransactionsAndStock] that uses
  /// batch writes instead of a Firestore transaction. Reads product documents
  /// from the local cache and writes sale + transactions + stock updates via
  /// `batch.commit()`. Not truly atomic (reads are not locked) but allows the
  /// operation to complete while offline.
  Future<Result<Sale>> createSaleWithTransactionsAndStockBatch(
      Sale sale,
      List<models.Transaction> transactions,
      List<StockDeduction> stockDeductions);

  /// Updates an existing sale.
  Future<Result<Sale>> updateSale(String id, Sale updated);

  /// Deletes a sale by ID.
  Future<Result<void>> deleteSale(String id);

  /// Clears any in-memory cache for range queries.
  void clearRangeCache() {}
}
