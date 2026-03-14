/// Result wrapper for repository operations.
/// Provides a clean way to handle success/failure without exceptions.
class Result<T> {
  final T? data;
  final String? error;
  final bool isSuccess;

  const Result._({this.data, this.error, required this.isSuccess});

  /// Creates a successful result.
  factory Result.success(T data) => Result._(data: data, isSuccess: true);

  /// Creates a failed result.
  factory Result.failure(String error) =>
      Result._(error: error, isSuccess: false);

  /// Maps the data if successful, otherwise passes the error through.
  Result<R> map<R>(R Function(T data) transform) {
    if (isSuccess) {
      return Result.success(transform(data as T));
    }
    return Result.failure(error ?? 'Unknown error');
  }

  /// Returns data or throws.
  T get dataOrThrow {
    if (isSuccess) return data as T;
    throw Exception(error ??  'Unknown error');
  }
}

/// Pagination metadata for list queries.
class PaginatedResult<T> {
  final List<T> items;
  final int totalCount;
  final int page;
  final int pageSize;
  final bool hasMore;

  const PaginatedResult({
    required this.items,
    required this.totalCount,
    this.page = 1,
    this.pageSize = 20,
    required this.hasMore,
  });
}
