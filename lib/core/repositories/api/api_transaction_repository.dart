import '../../../shared/models/transaction_model.dart';
import '../../../shared/dtos/api_response.dart';
import '../../services/api_client.dart';
import '../../services/result.dart';
import '../transaction_repository.dart';

class ApiTransactionRepository implements TransactionRepository {
  final ApiClient _client;

  ApiTransactionRepository(this._client);

  @override
  Future<Result<List<Transaction>>> getTransactions({
    TransactionFilter? filter,
    int? limit,
    String? startAfterId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (filter != null) {
        if (filter.selectedCategories.isNotEmpty) {
          queryParams['categories'] = filter.selectedCategories.join(',');
        }
        if (filter.period != null) {
          queryParams['period'] = filter.period!;
        }
        queryParams['minAmount'] = filter.amountRange.start.toString();
        queryParams['maxAmount'] = filter.amountRange.end.toString();
        if (filter.onlySuppliers) {
          queryParams['onlySuppliers'] = 'true';
        }
        if (filter.type.name != 'all') {
          queryParams['type'] = filter.type.name;
        }
      }
      
      if (limit != null) queryParams['limit'] = limit.toString();
      if (startAfterId != null) queryParams['startAfterId'] = startAfterId;
      if (startDate != null) queryParams['startDate'] = startDate.toIso8601String();
      if (endDate != null) queryParams['endDate'] = endDate.toIso8601String();

      final responseMap = await _client.get('/transactions', queryParams: queryParams);
      
      final success = responseMap['success'] as bool? ?? true;
      final message = responseMap['message'] as String?;

      if (success) {
        final data = responseMap['data'] as List<dynamic>? ?? responseMap['items'] as List<dynamic>? ?? [];
        final transactions = data
            .map((e) => Transaction.fromJson(e as Map<String, dynamic>))
            .toList();
        return Result.success(transactions);
      } else {
        return Result.failure(message ??  'Failed to fetch transactions');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<Transaction>> getTransactionById(String id) async {
    try {
      final responseMap = await _client.get('/transactions/$id');
      final response = ApiResponse<Transaction>.fromJson(
        responseMap,
        (json) => Transaction.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ?? 'Transaction not found');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<Transaction>> createTransaction(Transaction transaction) async {
    try {
      final responseMap = await _client.post('/transactions', body: transaction.toJson());
      final response = ApiResponse<Transaction>.fromJson(
        responseMap,
        (json) => Transaction.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ??  'Failed to create transaction');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<Transaction>> updateTransaction(Transaction transaction) async {
    try {
      final responseMap = await _client.put(
        '/transactions/${transaction.id}',
        body: transaction.toJson(),
      );
      final response = ApiResponse<Transaction>.fromJson(
        responseMap,
        (json) => Transaction.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ??  'Failed to update transaction');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<void>> deleteTransaction(String id) async {
    try {
      final responseMap = await _client.delete('/transactions/$id');
      final response = ApiResponse<dynamic>.fromJson(responseMap, null);

      if (response.success) {
        return Result.success(null);
      } else {
        return Result.failure(response.message ??  'Failed to delete transaction');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<void>> reassignCategory(
      String oldCategoryId, String newCategoryId) async {
    // API implementation would call a dedicated endpoint.
    // For now, this is a no-op as the Firestore repo is used in production.
    return Result.success(null);
  }

  @override
  Future<Result<List<Transaction>>> getTransactionsInRange({
    required DateTime start,
    required DateTime end,
  }) async {
    // Not implemented – Firestore repo is used in production.
    return Result.success([]);
  }

  @override
  void clearRangeCache() {}
}
