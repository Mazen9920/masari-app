import '../../shared/models/conversion_order_model.dart';
import '../services/result.dart';

/// Contract for conversion order (breakdown audit trail) operations.
abstract class ConversionOrderRepository {
  Future<Result<List<ConversionOrder>>> getOrders({int? limit});
  Future<Result<List<ConversionOrder>>> getOrdersForProduct(String productId);
  Future<Result<ConversionOrder>> createOrder(ConversionOrder order);
  Future<Result<void>> deleteOrder(String id);
}
