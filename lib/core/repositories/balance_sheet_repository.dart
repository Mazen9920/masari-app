import '../../shared/models/balance_sheet_entries.dart';
import '../services/result.dart';

abstract class BalanceSheetRepository {
  Future<Result<BalanceSheetEntries>> getEntries();
  Future<Result<BalanceSheetEntries>> saveEntries(BalanceSheetEntries entries);
  Future<Result<void>> deleteEntries();
}
