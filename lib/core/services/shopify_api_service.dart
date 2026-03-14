import 'package:cloud_functions/cloud_functions.dart' hide Result;

import 'result.dart';

/// Low-level Shopify Admin API service.
///
/// Every call goes via the `shopifyProxy` Cloud Function so the
/// Shopify access token never leaves the server.
class ShopifyApiService {
  final FirebaseFunctions _functions;

  ShopifyApiService({FirebaseFunctions? functions})
      : _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'us-central1');

  HttpsCallable get _proxy => _functions.httpsCallable(
        'shopifyProxy',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );

  // ── Orders ───────────────────────────────────────────────

  /// Fetches Shopify orders created between [since] and [until].
  ///
  /// Returns a list of raw Shopify order JSON maps.
  Future<Result<List<Map<String, dynamic>>>> fetchOrders({
    DateTime? since,
    DateTime? until,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (since != null) params['since'] = since.toIso8601String();
      if (until != null) params['until'] = until.toIso8601String();

      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'fetchOrders',
        'params': params,
      });

      final orders = (result.data['orders'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      return Result.success(orders);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(e.message ??  'Failed to fetch Shopify orders');
    } catch (e) {
      return Result.failure( 'Failed to fetch Shopify orders: $e');
    }
  }

  /// Updates fields on a Shopify order (e.g. note, tags).
  ///
  /// [orderId] is the Shopify numeric order ID.
  /// [fields] is a map of top-level order fields to update.
  Future<Result<Map<String, dynamic>>> updateOrder({
    required String orderId,
    required Map<String, dynamic> fields,
  }) async {
    try {
      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'updateOrder',
        'params': {
          'orderId': orderId,
          'fields': fields,
        },
      });
      return Result.success(result.data);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(e.message ??  'Failed to update Shopify order');
    } catch (e) {
      return Result.failure( 'Failed to update Shopify order: $e');
    }
  }

  // ── Products ─────────────────────────────────────────────

  /// Fetches all Shopify products with their variants.
  ///
  /// Optionally filters by comma-separated [productIds].
  Future<Result<List<Map<String, dynamic>>>> fetchProducts({
    String? productIds,
  }) async {
    try {
      final params = <String, dynamic>{};
      if (productIds != null) params['productIds'] = productIds;

      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'fetchProducts',
        'params': params,
      });

      final products = (result.data['products'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      return Result.success(products);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(e.message ??  'Failed to fetch Shopify products');
    } catch (e) {
      return Result.failure( 'Failed to fetch Shopify products: $e');
    }
  }

  /// Updates a Shopify product's title and/or variant prices/SKUs.
  Future<Result<Map<String, dynamic>>> updateProduct({
    required String shopifyProductId,
    String? title,
    List<Map<String, dynamic>>? variants,
  }) async {
    try {
      final params = <String, dynamic>{
        'productId': shopifyProductId,
      };
      if (title != null) params['title'] = title;
      if (variants != null) params['variants'] = variants;

      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'updateProduct',
        'params': params,
      });
      return Result.success(result.data);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(
        e.message ??  'Failed to update Shopify product',
      );
    } catch (e) {
      return Result.failure( 'Failed to update Shopify product: $e');
    }
  }

  // ── Inventory ────────────────────────────────────────────

  /// Sets the absolute stock level for a Shopify inventory item
  /// at the given [locationId].
  Future<Result<Map<String, dynamic>>> updateInventoryLevel({
    required String inventoryItemId,
    required String locationId,
    required int available,
  }) async {
    try {
      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'updateInventoryLevel',
        'params': {
          'inventoryItemId': inventoryItemId,
          'locationId': locationId,
          'available': available,
        },
      });
      return Result.success(result.data);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(
        e.message ??  'Failed to update Shopify inventory',
      );
    } catch (e) {
      return Result.failure( 'Failed to update Shopify inventory: $e');
    }
  }

  /// Gets the current stock levels for a list of inventory item IDs.
  ///
  /// Returns a list of `{ inventory_item_id, location_id, available }` maps.
  Future<Result<List<Map<String, dynamic>>>> getInventoryLevels({
    required List<String> inventoryItemIds,
    List<String>? locationIds,
  }) async {
    try {
      final params = <String, dynamic>{
        'inventoryItemIds': inventoryItemIds,
      };
      if (locationIds != null) params['locationIds'] = locationIds;

      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'getInventoryLevels',
        'params': params,
      });

      final levels = (result.data['inventory_levels'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      return Result.success(levels);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(
        e.message ??  'Failed to get Shopify inventory levels',
      );
    } catch (e) {
      return Result.failure( 'Failed to get Shopify inventory levels: $e');
    }
  }

  // ── Inventory Items ──────────────────────────────────────

  /// Fetches inventory items by their IDs (includes cost data).
  ///
  /// Returns a list of `{ id, cost, sku, tracked, ... }` maps.
  Future<Result<List<Map<String, dynamic>>>> getInventoryItems({
    required List<String> inventoryItemIds,
  }) async {
    try {
      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'getInventoryItems',
        'params': <String, dynamic>{
          'inventoryItemIds': inventoryItemIds,
        },
      });

      final items = (result.data['inventory_items'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      return Result.success(items);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(
        e.message ??  'Failed to get Shopify inventory items',
      );
    } catch (e) {
      return Result.failure( 'Failed to get Shopify inventory items: $e');
    }
  }

  // ── Locations ─────────────────────────────────────────────

  /// Fetches all Shopify locations for the connected store.
  ///
  /// Returns a list of `{ id, name, active, primary }` maps.
  Future<Result<List<Map<String, dynamic>>>> fetchLocations() async {
    try {
      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'fetchLocations',
        'params': <String, dynamic>{},
      });

      final locations = (result.data['locations'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      return Result.success(locations);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(
        e.message ??  'Failed to fetch Shopify locations',
      );
    } catch (e) {
      return Result.failure( 'Failed to fetch Shopify locations: $e');
    }
  }

  // ── Fulfillments ─────────────────────────────────────────

  /// Creates a fulfillment (marks items as shipped) on a Shopify order.
  Future<Result<Map<String, dynamic>>> createFulfillment({
    required String orderId,
    String? trackingNumber,
    String? trackingCompany,
    String? trackingUrl,
    List<String>? lineItemIds,
  }) async {
    try {
      final params = <String, dynamic>{
        'orderId': orderId,
      };
      if (trackingNumber != null) {
        params['trackingNumber'] = trackingNumber;
      }
      if (trackingCompany != null) {
        params['trackingCompany'] = trackingCompany;
      }
      if (trackingUrl != null) params['trackingUrl'] = trackingUrl;
      if (lineItemIds != null) params['lineItemIds'] = lineItemIds;

      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'createFulfillment',
        'params': params,
      });
      return Result.success(result.data);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(
        e.message ??  'Failed to create Shopify fulfillment',
      );
    } catch (e) {
      return Result.failure( 'Failed to create Shopify fulfillment: $e');
    }
  }

  // ── Cancel Order ─────────────────────────────────────────

  /// Cancels a Shopify order.
  ///
  /// [orderId] is the Shopify numeric order ID.
  /// [reason] is optional (e.g. 'customer', 'inventory', 'fraud', 'other').
  Future<Result<Map<String, dynamic>>> cancelOrder({
    required String orderId,
    String? reason,
  }) async {
    try {
      final params = <String, dynamic>{
        'orderId': orderId,
      };
      if (reason != null) params['reason'] = reason;

      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'cancelOrder',
        'params': params,
      });
      return Result.success(result.data);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(
        e.message ??  'Failed to cancel Shopify order',
      );
    } catch (e) {
      return Result.failure( 'Failed to cancel Shopify order: $e');
    }
  }

  // ── Mark Order as Paid ───────────────────────────────────

  /// Marks a Shopify order as paid by creating a capture transaction
  /// for the outstanding amount.
  ///
  /// [orderId] is the Shopify numeric order ID.
  Future<Result<Map<String, dynamic>>> markOrderPaid({
    required String orderId,
  }) async {
    try {
      final result = await _proxy.call<Map<String, dynamic>>({
        'action': 'markOrderPaid',
        'params': {
          'orderId': orderId,
        },
      });
      return Result.success(result.data);
    } on FirebaseFunctionsException catch (e) {
      return Result.failure(
        e.message ??  'Failed to mark Shopify order as paid',
      );
    } catch (e) {
      return Result.failure( 'Failed to mark Shopify order as paid: $e');
    }
  }
}
