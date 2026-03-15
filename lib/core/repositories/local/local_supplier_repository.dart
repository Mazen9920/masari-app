import '../../../shared/models/supplier_model.dart';
import '../supplier_repository.dart';
import '../../services/result.dart';

/// Local in-memory implementation of [SupplierRepository].
class LocalSupplierRepository implements SupplierRepository {
  final List<Supplier> _suppliers = [];

  @override
  Future<Result<List<Supplier>>> getSuppliers({
    int? limit,
    String? startAfterId,
  }) async {
    var list = List<Supplier>.from(_suppliers);
    
    // Apply cursor-based pagination
    if (startAfterId != null) {
      final idx = list.indexWhere((s) => s.id == startAfterId);
      if (idx != -1 && idx + 1 < list.length) {
        list = list.sublist(idx + 1);
      } else {
        return Result.success([]);
      }
    }
    if (limit != null && limit < list.length) {
      list = list.sublist(0, limit);
    }
    
    return Result.success(list);
  }

  @override
  Future<Result<Supplier>> getSupplierById(String id) async {
    try {
      final supplier = _suppliers.firstWhere((s) => s.id == id);
      return Result.success(supplier);
    } catch (_) {
      return Result.failure('Supplier not found');
    }
  }

  @override
  Future<Result<Supplier>> createSupplier(Supplier supplier) async {
    _suppliers.add(supplier);
    return Result.success(supplier);
  }

  @override
  Future<Result<Supplier>> updateSupplier(String id, Supplier updated) async {
    final index = _suppliers.indexWhere((s) => s.id == id);
    if (index == -1) return Result.failure('Supplier not found');
    _suppliers[index] = updated;
    return Result.success(updated);
  }

  @override
  Future<Result<void>> deleteSupplier(String id) async {
    _suppliers.removeWhere((s) => s.id == id);
    return Result.success(null);
  }

  @override
  Future<Result<Supplier>> recordPayment(String id, double amount) async {
    final index = _suppliers.indexWhere((s) => s.id == id);
    if (index == -1) return Result.failure('Supplier not found');

    final supplier = _suppliers[index];
    final updated = supplier.copyWith(
      balance: (supplier.balance - amount).clamp(0.0, double.infinity),
    );
    _suppliers[index] = updated;
    return Result.success(updated);
  }

  @override
  Future<Result<Supplier>> recordPurchase(String id, double amount, {DateTime? dueDate}) async {
    final index = _suppliers.indexWhere((s) => s.id == id);
    if (index == -1) return Result.failure('Supplier not found');

    final supplier = _suppliers[index];
    final updated = supplier.copyWith(
      balance: supplier.balance + amount,
      lastTransaction: DateTime.now(),
      dueDate: dueDate != null &&
              (supplier.dueDate == null || dueDate.isAfter(supplier.dueDate!))
          ? dueDate
          : supplier.dueDate,
    );
    _suppliers[index] = updated;
    return Result.success(updated);
  }
}
