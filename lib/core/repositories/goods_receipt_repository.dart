import '../../shared/models/goods_receipt_model.dart';
import '../services/result.dart';

/// Contract for goods receipt data operations.
abstract class GoodsReceiptRepository {
  /// Fetches all goods receipts for the current user.
  Future<Result<List<GoodsReceipt>>> getReceipts({int? limit, String? startAfterId});

  /// Fetches receipts for a specific supplier.
  Future<Result<List<GoodsReceipt>>> getReceiptsForSupplier(String supplierId);

  /// Fetches a single receipt by ID.
  Future<Result<GoodsReceipt>> getReceiptById(String id);

  /// Creates a new goods receipt.
  Future<Result<GoodsReceipt>> createReceipt(GoodsReceipt receipt);

  /// Updates an existing receipt (e.g., confirm / reject).
  Future<Result<GoodsReceipt>> updateReceipt(String id, GoodsReceipt updated);

  /// Deletes a receipt by ID.
  Future<Result<void>> deleteReceipt(String id);
}
