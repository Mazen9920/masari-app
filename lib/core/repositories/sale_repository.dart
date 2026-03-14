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
  Future<Result<List<Sale>>> getSales({int? limit, String? startAfterId});

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

  /// Updates an existing sale.
  Future<Result<Sale>> updateSale(String id, Sale updated);

  /// Deletes a sale by ID.
  Future<Result<void>> deleteSale(String id);
}
