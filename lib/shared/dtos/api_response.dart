/// Standard generic API response wrapper.
/// Adjust this to match your backend's exact response shape (e.g. data/meta, success flag).
class ApiResponse<T> {
  final T? data;
  final String? message;
  final bool success;
  
  // E.g. pagination or other metadata
  final Map<String, dynamic>? meta;

  const ApiResponse({
    this.data,
    this.message,
    required this.success,
    this.meta,
  });

  factory ApiResponse.fromJson(
    Map<String, dynamic> json, 
    T Function(Map<String, dynamic>)? fromJsonT
  ) {
    // Determine the success state, assuming 200 checks are handled by ApiClient
    // but the backend might return `{"success": true}` or similar
    final success = json['success'] as bool? ?? true;
    
    T? parsedData;
    if (json.containsKey('data') && json['data'] != null) {
      if (fromJsonT != null && json['data'] is Map<String, dynamic>) {
        parsedData = fromJsonT(json['data'] as Map<String, dynamic>);
      } else {
        // Handle list or primitive data types
        parsedData = json['data'] as T?;
      }
    }

    return ApiResponse(
      success: success,
      message: json['message'] as String?,
      data: parsedData,
      meta: json['meta'] as Map<String, dynamic>?,
    );
  }
}
