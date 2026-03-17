import '../../../shared/models/category_data.dart';
import '../../../shared/dtos/api_response.dart';
import '../../services/api_client.dart';
import '../../services/result.dart';
import '../category_repository.dart';

class ApiCategoryRepository implements CategoryRepository {
  final ApiClient _client;

  ApiCategoryRepository(this._client);

  @override
  Future<Result<List<CategoryData>>> getCategories() async {
    try {
      final responseMap = await _client.get('/categories');
      
      // We process the list manually since ApiResponse generic fromJson expects Map.
      // Assuming backend format: { "success": true, "data": [{...}, {...}] }
      final success = responseMap['success'] as bool? ?? true;
      final message = responseMap['message'] as String?;
      
      if (success) {
        final data = responseMap['data'] as List<dynamic>? ?? [];
        final categories = data
            .map((e) => CategoryData.fromJson(e as Map<String, dynamic>))
            .toList();
        return Result.success(categories);
      } else {
        return Result.failure(message ??  'Failed to fetch categories');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<CategoryData>> getCategoryById(String id) async {
    try {
      final responseMap = await _client.get('/categories/$id');
      final response = ApiResponse<CategoryData>.fromJson(
        responseMap,
        (json) => CategoryData.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ?? 'Category not found');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<CategoryData>> createCategory(CategoryData category) async {
    try {
      final responseMap = await _client.post('/categories', body: category.toJson());
      final response = ApiResponse<CategoryData>.fromJson(
        responseMap,
        (json) => CategoryData.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ??  'Failed to create category');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<CategoryData>> updateCategory(CategoryData updated) async {
    try {
      final responseMap = await _client.put(
        '/categories/${updated.id}',
        body: updated.toJson(),
      );
      final response = ApiResponse<CategoryData>.fromJson(
        responseMap,
        (json) => CategoryData.fromJson(json),
      );

      if (response.success && response.data != null) {
        return Result.success(response.data!);
      } else {
        return Result.failure(response.message ??  'Failed to update category');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }

  @override
  Future<Result<void>> deleteCategory(String id) async {
    try {
      final responseMap = await _client.delete('/categories/$id');
      final response = ApiResponse<dynamic>.fromJson(responseMap, null);

      if (response.success) {
        return Result.success(null);
      } else {
        return Result.failure(response.message ??  'Failed to delete category');
      }
    } on ApiException catch (e) {
      return Result.failure(e.message);
    } catch (e) {
      return Result.failure( 'An unexpected error occurred: $e');
    }
  }
}
