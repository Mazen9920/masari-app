import '../../shared/models/purchase_model.dart';
import '../services/result.dart';

/// Contract for purchase data operations.
abstract class PurchaseRepository {
  /// Fetches purchases, optionally filtered by supplier and paginated.
  Future<Result<List<Purchase>>> getPurchases({
    String? supplierId,
    int? limit,
    String? startAfterId,
  });

  /// Fetches a single purchase by ID.
  Future<Result<Purchase>> getPurchaseById(String id);

  /// Creates a new purchase.
  Future<Result<Purchase>> createPurchase(Purchase purchase);

  /// Updates an existing purchase.
  Future<Result<Purchase>> updatePurchase(String id, Purchase updated);

  /// Deletes a purchase by ID.
  Future<Result<void>> deletePurchase(String id);
}
