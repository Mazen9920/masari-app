import '../../../shared/models/supplier_model.dart';
import '../../../shared/dtos/api_response.dart';
import '../../services/api_client.dart';
import '../../services/result.dart';
import '../supplier_repository.dart';

class ApiSupplierRepository implements SupplierRepository {
  final ApiClient _client;

  ApiSupplierRepository(this._client);

  @override
  Future<Result<List<Supplier>>> getSuppliers({
    int? limit,
    String? startAfterId,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (limit != null) queryParams['limit'] = limit.toString();
      if (startAfterId != null) queryParams['startAfterId'] = startAfterId;

      final responseMap = await _client.get('/suppliers', queryParams: queryParams);
      
      final success = responseMap['success'] as bool? ?? true;
      final message = responseMap['message'] as String?;
      
      if (success) {
        final data = responseMap['data'] as List<dynamic>? ?? [];
        final suppliers = data
            .map((e) => Supplier.fromJson(e as Map<String, dynamic>))
            .toList();
        return Result.success(suppliers);
      } else {
        return Result.failure(message ??  'Failed to fetch suppliers');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<Supplier>> getSupplierById(String id) async {
    try {
      final responseMap = await _client.get('/suppliers/$id');
      final response = ApiResponse<Supplier>.fromJson(
        responseMap,
        (json) => Supplier.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ?? 'Supplier not found');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<Supplier>> createSupplier(Supplier supplier) async {
    try {
      final responseMap = await _client.post('/suppliers', body: supplier.toJson());
      final response = ApiResponse<Supplier>.fromJson(
        responseMap,
        (json) => Supplier.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ??  'Failed to create supplier');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<Supplier>> updateSupplier(String id, Supplier updated) async {
    try {
      final responseMap = await _client.put(
        '/suppliers/$id',
        body: updated.toJson(),
      );
      final response = ApiResponse<Supplier>.fromJson(
        responseMap,
        (json) => Supplier.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ??  'Failed to update supplier');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<void>> deleteSupplier(String id) async {
    try {
      final responseMap = await _client.delete('/suppliers/$id');
      final response = ApiResponse<dynamic>.fromJson(responseMap, null);

      if (response.success) {
        return Result.success(null);
      } else {
        return Result.failure(response.message ??  'Failed to delete supplier');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<Supplier>> recordPayment(String id, double amount) async {
    try {
      final responseMap = await _client.post(
        '/suppliers/$id/payments',
        body: {'amount': amount},
      );
      final response = ApiResponse<Supplier>.fromJson(
        responseMap,
        (json) => Supplier.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ??  'Failed to record payment');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<Supplier>> recordPurchase(String id, double amount, {DateTime? dueDate}) async {
    try {
      final body = <String, dynamic>{'amount': amount};
      if (dueDate != null) body['due_date'] = dueDate.toIso8601String();

      final responseMap = await _client.post(
        '/suppliers/$id/purchases',
        body: body,
      );
      final response = ApiResponse<Supplier>.fromJson(
        responseMap,
        (json) => Supplier.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ?? 'Failed to record purchase');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure('An unexpected error occurred: $e');
    }
  }
}
