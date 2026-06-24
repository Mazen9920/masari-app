import '../../shared/models/fixed_asset_model.dart';
import '../services/result.dart';

/// Abstract contract for fixed-asset persistence.
abstract class FixedAssetRepository {
  Future<Result<List<FixedAsset>>> getAll();
  Future<Result<FixedAsset>> getById(String id);
  Future<Result<FixedAsset>> create(FixedAsset asset);
  Future<Result<FixedAsset>> update(FixedAsset asset);
  Future<Result<void>> delete(String id);
}
