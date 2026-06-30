import '../../shared/models/accrued_expense_model.dart';
import '../services/result.dart';

/// Abstract contract for accrued-expense persistence.
abstract class AccruedExpenseRepository {
  Future<Result<List<AccruedExpense>>> getAll();
  Future<Result<AccruedExpense>> getById(String id);
  Future<Result<AccruedExpense>> create(AccruedExpense expense);
  Future<Result<AccruedExpense>> update(AccruedExpense expense);
  Future<Result<void>> delete(String id);
}
