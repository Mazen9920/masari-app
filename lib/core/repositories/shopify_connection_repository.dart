import '../../shared/models/shopify_connection_model.dart';
import '../services/result.dart';

/// Contract for Shopify connection data operations.
abstract class ShopifyConnectionRepository {
  /// Fetches the current user's Shopify connection, if any.
  Future<Result<ShopifyConnection?>> getConnection();

  /// Same as [getConnection] but forces a server round-trip.
  Future<Result<ShopifyConnection?>> getConnectionFromServer();

  /// Creates or replaces the Shopify connection for the current user.
  Future<Result<ShopifyConnection>> saveConnection(ShopifyConnection connection);

  /// Updates specific fields on the existing connection.
  Future<Result<ShopifyConnection>> updateConnection(
      String docId, ShopifyConnection updated);

  /// Deletes the connection (disconnect from Shopify).
  Future<Result<void>> deleteConnection(String docId);

  /// Streams the connection document for real-time status updates.
  Stream<ShopifyConnection?> watchConnection();
}
