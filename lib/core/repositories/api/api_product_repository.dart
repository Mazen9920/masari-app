import '../../../shared/models/product_model.dart';
import '../../../shared/dtos/api_response.dart';
import '../../services/api_client.dart';
import '../../services/result.dart';
import '../product_repository.dart';

class ApiProductRepository implements ProductRepository {
  final ApiClient _client;

  ApiProductRepository(this._client);

  @override
  Future<Result<List<Product>>> getProducts({
    int? limit,
    String? startAfterId,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (limit != null) queryParams['limit'] = limit.toString();
      if (startAfterId != null) queryParams['startAfterId'] = startAfterId;

      final responseMap = await _client.get('/products', queryParams: queryParams);
      
      final success = responseMap['success'] as bool? ?? true;
      final message = responseMap['message'] as String?;
      
      if (success) {
        final data = responseMap['data'] as List<dynamic>? ?? [];
        final products = data
            .map((e) => Product.fromJson(e as Map<String, dynamic>))
            .toList();
        return Result.success(products);
      } else {
        return Result.failure(message ?? 'Failed to fetch products');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure('An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<Product>> getProductById(String id) async {
    try {
      final responseMap = await _client.get('/products/$id');
      final response = ApiResponse<Product>.fromJson(
        responseMap,
        (json) => Product.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ?? 'Product not found');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure('An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<Product>> createProduct(Product product) async {
    try {
      final responseMap = await _client.post('/products', body: product.toJson());
      final response = ApiResponse<Product>.fromJson(
        responseMap,
        (json) => Product.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ?? 'Failed to create product');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure('An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<Product>> updateProduct(String id, Product updated, {String modifiedBy = 'masari'}) async {
    try {
      final responseMap = await _client.put(
        '/products/$id',
        body: updated.toJson(),
      );
      final response = ApiResponse<Product>.fromJson(
        responseMap,
        (json) => Product.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ?? 'Failed to update product');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure('An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<void>> deleteProduct(String id) async {
    try {
      final responseMap = await _client.delete('/products/$id');
      final response = ApiResponse<dynamic>.fromJson(responseMap, null);

      if (response.success) {
        return Result.success(null);
      } else {
        return Result.failure(response.message ?? 'Failed to delete product');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure('An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<List<Product>>> getProductsByShopifyProductId(String shopifyProductId) async {
    try {
      final responseMap = await _client.get('/products', queryParams: {'shopify_product_id': shopifyProductId});
      final success = responseMap['success'] as bool? ?? true;
      final message = responseMap['message'] as String?;
      if (success) {
        final data = responseMap['data'] as List<dynamic>? ?? [];
        final products = data.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
        return Result.success(products);
      } else {
        return Result.failure(message ?? 'Failed to fetch products by Shopify ID');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure('An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<Product>> adjustStock(String id, String variantId, int delta, String reason, {double? unitCost, String valuationMethod = 'fifo', String? supplierName, bool clearLegacyLayers = false}) async {
    try {
      final body = <String, dynamic>{'delta': delta, 'reason': reason, 'variant_id': variantId};
      if (unitCost != null) body['unitCost'] = unitCost;
      final responseMap = await _client.post(
        '/products/$id/adjust-stock',
        body: body,
      );
      final response = ApiResponse<Product>.fromJson(
        responseMap,
        (json) => Product.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ?? 'Failed to adjust stock');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure('An unexpected error occurred: $e');
    }
  }
}
