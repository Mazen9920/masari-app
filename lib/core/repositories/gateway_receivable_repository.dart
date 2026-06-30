import '../../shared/models/gateway_receivable_model.dart';
import '../services/result.dart';

/// Abstract contract for payment-gateway receivable persistence.
abstract class GatewayReceivableRepository {
  Future<Result<List<GatewayReceivable>>> getAll();
  Future<Result<GatewayReceivable>> getById(String id);
  Future<Result<GatewayReceivable>> create(GatewayReceivable receivable);
  Future<Result<GatewayReceivable>> update(GatewayReceivable receivable);
  Future<Result<void>> delete(String id);
}
