import 'dart:convert';
import 'package:http/http.dart' as http;

/// API client configuration for backend communication.
/// Currently a placeholder — will be configured when a backend is chosen.
///
/// Usage:
///   final client = ApiClient(baseUrl: 'https://api.revvo-app.com/v1');
///   final response = await client.get('/transactions');
class ApiClient {
  final String baseUrl;
  final String? _authToken;
  final Duration timeout;

  ApiClient({
    required this.baseUrl,
    String? authToken,
    this.timeout = const Duration(seconds: 30),
  }) : _authToken = authToken;

  /// Default headers for all requests.
  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  /// Creates a new client with an updated auth token.
  ApiClient withToken(String token) {
    return ApiClient(
      baseUrl: baseUrl,
      authToken: token,
      timeout: timeout,
    );
  }

  /// Full URL builder.
  Uri _buildUri(String path, {Map<String, String>? queryParams}) {
    return Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
  }

  // ─── HTTP methods ───

  /// GET request.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    return _request(() => http.get(
          _buildUri(path, queryParams: queryParams),
          headers: _headers,
        ));
  }

  /// POST request.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _request(() => http.post(
          _buildUri(path),
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  /// PUT request.
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _request(() => http.put(
          _buildUri(path),
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  /// PATCH request.
  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _request(() => http.patch(
          _buildUri(path),
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  /// DELETE request.
  Future<Map<String, dynamic>> delete(String path) async {
    return _request(() => http.delete(
          _buildUri(path),
          headers: _headers,
        ));
  }

  /// Generic request handler with error mapping
  Future<Map<String, dynamic>> _request(Future<http.Response> Function() requestAction) async {
    try {
      final response = await requestAction().timeout(timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return {};
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        String message =  'API Error: ${response.statusCode}';
        try {
          final body = jsonDecode(response.body);
          if (body['message'] != null) {
            message = body['message'].toString();
          } else if (body['error'] != null) {
            message = body['error'].toString();
          }
        } catch (_) {
          // Body not JSON
          message = response.body.isNotEmpty ? response.body : message;
        }
        throw ApiException(message, statusCode: response.statusCode);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException( 'Network error: ${e.toString()}');
    }
  }
}

class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
