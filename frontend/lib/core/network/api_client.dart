import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talktime/core/constants/api_constants.dart';

class ApiClient {
  final http.Client _client = http.Client();
  final Logger _logger = Logger(output: ConsoleOutput());

  static const String _tokenKey = 'auth_token';

  /// Get stored auth token
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  /// Save auth token
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  /// Clear auth token
  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// Build headers with authentication
  Future<Map<String, String>> _buildHeaders({bool includeAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (includeAuth) {
      final token = await getToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  Future<Map<String, dynamic>> get(
    String endpoint, {
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    // _logger.i('GET $uri');

    final headers = await _buildHeaders(includeAuth: requiresAuth);

    try {
      final response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));
      return _processResponse(response);
    } catch (e) {
      _logger.e('GET request failed: $uri $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> delete(
    String endpoint, {
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    // _logger.i('DELETE $uri');

    final headers = await _buildHeaders(includeAuth: requiresAuth);

    try {
      final response = await _client
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 30));
      return _processResponse(response);
    } catch (e) {
      _logger.e('DELETE request failed: $uri $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    // _logger.i('POST $uri | body: $body');

    final headers = await _buildHeaders(includeAuth: requiresAuth);

    try {
      final response = await _client
          .post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30));
      return _processResponse(response);
    } catch (e) {
      _logger.e('POST request failed: $uri $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> put(
    String endpoint, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    // _logger.i('PUT $uri | body: $body');

    final headers = await _buildHeaders(includeAuth: requiresAuth);

    try {
      final response = await _client
          .put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30));
      return _processResponse(response);
    } catch (e) {
      _logger.e('PUT request failed: $uri $e');
      rethrow;
    }
  }

  Map<String, dynamic> _processResponse(http.Response response) {
    final statusCode = response.statusCode;

    // _logger.d('Response Status: $statusCode');
    // _logger.d('Response Body: ${response.body}');

    // Handle empty responses
    if (response.body.isEmpty) {
      if (statusCode >= 200 && statusCode < 300) {
        return {'success': true};
      } else {
        throw ApiException(statusCode, 'Empty response from server');
      }
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      _logger.e('Failed to parse JSON response: $e');
      throw ApiException(statusCode, 'Invalid JSON response: ${response.body}');
    }

    if (statusCode >= 200 && statusCode < 300) {
      return body;
    } else {
      final errorMessage =
          body['message'] ??
          body['error'] ??
          body['title'] ??
          'Unknown error occurred';
      _logger.e('API Error: $statusCode | $errorMessage');
      throw ApiException(statusCode, errorMessage.toString());
    }
  }

  /// Dispose the client
  void dispose() {
    _client.close();
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException(this.statusCode, this.message);

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => statusCode >= 500;
  bool get isBadRequest => statusCode == 400;

  @override
  String toString() => 'ApiException($statusCode): $message';
}
