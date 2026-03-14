import '../../shared/models/supplier_model.dart';
import '../services/result.dart';

/// Contract for supplier data operations.
abstract class SupplierRepository {
  /// Fetches all suppliers, optionally paginated.
  Future<Result<List<Supplier>>> getSuppliers({
    int? limit,
    String? startAfterId,
  });

  /// Fetches a single supplier by ID.
  Future<Result<Supplier>> getSupplierById(String id);

  /// Creates a new supplier.
  Future<Result<Supplier>> createSupplier(Supplier supplier);

  /// Updates an existing supplier.
  Future<Result<Supplier>> updateSupplier(String id, Supplier updated);

  /// Deletes a supplier by ID.
  Future<Result<void>> deleteSupplier(String id);

  /// Records a payment against a supplier's balance.
  Future<Result<Supplier>> recordPayment(String id, double amount);
}
