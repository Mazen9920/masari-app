import '../../shared/models/production_order_model.dart';
import '../services/result.dart';

/// Contract for production order (manufacturing run) operations.
abstract class ProductionOrderRepository {
  Future<Result<List<ProductionOrder>>> getOrders({int? limit});
  Future<Result<List<ProductionOrder>>> getOrdersForProduct(String productId);
  Future<Result<ProductionOrder>> createOrder(ProductionOrder order);
  Future<Result<ProductionOrder>> updateOrder(ProductionOrder order);
  Future<Result<void>> deleteOrder(String id);
}
