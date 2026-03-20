import '../../../shared/models/transaction_model.dart';
import '../transaction_repository.dart';
import '../../services/result.dart';
import '../../../shared/models/category_data.dart';

/// Local in-memory implementation of [TransactionRepository].
/// Uses sample data. Will be replaced by API implementation later.
class LocalTransactionRepository implements TransactionRepository {
  final List<Transaction> _transactions = [];

  @override
  Future<Result<List<Transaction>>> getTransactions({
    TransactionFilter? filter,
    int? limit,
    String? startAfterId,
  }) async {
    var list = List<Transaction>.from(_transactions);

    if (filter != null) {
      // Type filter
      if (filter.type == TransactionType.income) {
        list = list.where((t) => t.isIncome).toList();
      } else if (filter.type == TransactionType.expense) {
        list = list.where((t) => !t.isIncome).toList();
      }

      // Amount range
      list = list
          .where((t) =>
              t.amount.abs() >= filter.amountRange.start &&
              t.amount.abs() <= filter.amountRange.end)
          .toList();

      // Category filter — match by category ID
      if (filter.selectedCategories.isNotEmpty) {
        list = list
            .where(
                (t) => filter.selectedCategories.contains(t.categoryId) ||
                       filter.selectedCategories.contains(CategoryData.findById(t.categoryId).name))
            .toList();
      }

      // Supplier-only filter
      if (filter.onlySuppliers) {
        list = list.where((t) => t.supplierId != null).toList();
      }
    }

    // Apply cursor-based pagination
    if (startAfterId != null) {
      final idx = list.indexWhere((t) => t.id == startAfterId);
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
  Future<Result<Transaction>> getTransactionById(String id) async {
    try {
      final tx = _transactions.firstWhere((t) => t.id == id);
      return Result.success(tx);
    } catch (_) {
      return Result.failure('Transaction not found');
    }
  }

  @override
  Future<Result<Transaction>> createTransaction(
      Transaction transaction) async {
    _transactions.insert(0, transaction);
    return Result.success(transaction);
  }

  @override
  Future<Result<Transaction>> updateTransaction(
      Transaction transaction) async {
    final index = _transactions.indexWhere((t) => t.id == transaction.id);
    if (index == -1) return Result.failure('Transaction not found');
    _transactions[index] = transaction;
    return Result.success(transaction);
  }

  @override
  Future<Result<void>> deleteTransaction(String id) async {
    _transactions.removeWhere((t) => t.id == id);
    return Result.success(null);
  }

  @override
  Future<Result<void>> reassignCategory(
      String oldCategoryId, String newCategoryId) async {
    for (var i = 0; i < _transactions.length; i++) {
      if (_transactions[i].categoryId == oldCategoryId) {
        _transactions[i] =
            _transactions[i].copyWith(categoryId: newCategoryId);
      }
    }
    return Result.success(null);
  }
}
