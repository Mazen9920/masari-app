import '../../shared/models/category_data.dart';
import '../services/result.dart';

/// Contract for category data operations.
abstract class CategoryRepository {
  /// Fetches all categories (default + user-created).
  Future<Result<List<CategoryData>>> getCategories();

  /// Fetches a single category by ID.
  Future<Result<CategoryData>> getCategoryById(String id);

  /// Creates a new user-defined category.
  Future<Result<CategoryData>> createCategory(CategoryData category);

  /// Updates an existing category.
  Future<Result<CategoryData>> updateCategory(
      String oldName, CategoryData updated);

  /// Deletes a category by name.
  Future<Result<void>> deleteCategory(String name);
}
