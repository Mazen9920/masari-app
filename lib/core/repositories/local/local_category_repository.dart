import '../../../shared/models/category_data.dart';
import '../category_repository.dart';
import '../../services/result.dart';

/// Local in-memory implementation of [CategoryRepository].
class LocalCategoryRepository implements CategoryRepository {
  final List<CategoryData> _categories = [];

  @override
  Future<Result<List<CategoryData>>> getCategories() async {
    return Result.success(List.from(_categories));
  }

  @override
  Future<Result<CategoryData>> getCategoryById(String id) async {
    try {
      final cat = _categories.firstWhere((c) => c.id == id);
      return Result.success(cat);
    } catch (_) {
      return Result.failure('Category not found');
    }
  }

  @override
  Future<Result<CategoryData>> createCategory(CategoryData category) async {
    _categories.add(category);
    return Result.success(category);
  }

  @override
  Future<Result<CategoryData>> updateCategory(
      String oldName, CategoryData updated) async {
    final index = _categories.indexWhere((c) => c.name == oldName);
    if (index == -1) return Result.failure('Category not found');
    _categories[index] = updated;
    return Result.success(updated);
  }

  @override
  Future<Result<void>> deleteCategory(String name) async {
    _categories.removeWhere((c) => c.name == name);
    return Result.success(null);
  }
}
