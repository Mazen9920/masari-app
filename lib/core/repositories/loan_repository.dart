import '../../shared/models/loan_model.dart';
import '../services/result.dart';

/// Abstract contract for loan persistence.
abstract class LoanRepository {
  Future<Result<List<Loan>>> getAll();
  Future<Result<Loan>> getById(String id);
  Future<Result<Loan>> create(Loan loan);
  Future<Result<Loan>> update(Loan loan);
  Future<Result<void>> delete(String id);
}
