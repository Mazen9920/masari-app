import '../../shared/models/salary_model.dart';
import '../services/result.dart';

/// Abstract contract for salary persistence.
abstract class SalaryRepository {
  Future<Result<List<Salary>>> getAll();
  Future<Result<Salary>> getById(String id);
  Future<Result<Salary>> create(Salary salary);
  Future<Result<Salary>> update(Salary salary);
  Future<Result<void>> delete(String id);
}
