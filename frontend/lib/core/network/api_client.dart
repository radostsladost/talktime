import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talktime/core/constants/api_constants.dart';

class ApiClient {
  final http.Client _client = http.Client();
  final Logger _logger = Logger(output: ConsoleOutput());

  static const String _accessTokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _accessTokenExpiresKey = 'access_token_expires';
  static const String _refreshTokenExpiresKey = 'refresh_token_expires';

  // Flag to prevent multiple simultaneous refresh attempts
  bool _isRefreshing = false;

  /// Get stored access token
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  /// Save access token
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessTokenKey, token);
  }

  /// Clear access token
  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
  }

  /// Get stored refresh token
  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  /// Save refresh token
  Future<void> saveRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, token);
  }

  /// Clear refresh token
  Future<void> clearRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_refreshTokenKey);
  }

  /// Save token expiration times
  Future<void> saveTokenExpiration({
    DateTime? accessTokenExpires,
    DateTime? refreshTokenExpires,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (accessTokenExpires != null) {
      await prefs.setString(
        _accessTokenExpiresKey,
        accessTokenExpires.toIso8601String(),
      );
    }
    if (refreshTokenExpires != null) {
      await prefs.setString(
        _refreshTokenExpiresKey,
        refreshTokenExpires.toIso8601String(),
      );
    }
  }

  /// Get access token expiration time
  Future<DateTime?> getAccessTokenExpiration() async {
    final prefs = await SharedPreferences.getInstance();
    final expiresStr = prefs.getString(_accessTokenExpiresKey);
    if (expiresStr == null) return null;
    return DateTime.tryParse(expiresStr);
  }

  /// Get refresh token expiration time
  Future<DateTime?> getRefreshTokenExpiration() async {
    final prefs = await SharedPreferences.getInstance();
    final expiresStr = prefs.getString(_refreshTokenExpiresKey);
    if (expiresStr == null) return null;
    return DateTime.tryParse(expiresStr);
  }

  /// Check if access token is expired or about to expire (within 1 minute)
  Future<bool> isAccessTokenExpired() async {
    final expires = await getAccessTokenExpiration();
    if (expires == null) return true;
    return DateTime.now().isAfter(expires.subtract(const Duration(minutes: 1)));
  }

  /// Check if refresh token is expired
  Future<bool> isRefreshTokenExpired() async {
    final expires = await getRefreshTokenExpiration();
    if (expires == null) return true;
    return DateTime.now().isAfter(expires);
  }

  /// Save all tokens and their expiration times
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required DateTime accessTokenExpires,
    required DateTime refreshTokenExpires,
  }) async {
    await saveToken(accessToken);
    await saveRefreshToken(refreshToken);
    await saveTokenExpiration(
      accessTokenExpires: accessTokenExpires,
      refreshTokenExpires: refreshTokenExpires,
    );
  }

  /// Clear all tokens and expiration times
  Future<void> clearAllTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_accessTokenExpiresKey);
    await prefs.remove(_refreshTokenExpiresKey);
  }

  /// Attempt to refresh the access token using the refresh token
  Future<bool> refreshAccessToken() async {
    if (_isRefreshing) {
      // Wait for the ongoing refresh to complete
      await Future.delayed(const Duration(milliseconds: 100));
      return await getToken() != null;
    }

    _isRefreshing = true;

    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) {
        _logger.w('No refresh token available');
        return false;
      }

      // Check if refresh token is expired
      if (await isRefreshTokenExpired()) {
        _logger.w('Refresh token is expired');
        await clearAllTokens();
        return false;
      }

      final uri = Uri.parse(
        '${ApiConstants.baseUrl}${ApiConstants.refreshToken}',
      );
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;

        final newAccessToken = body['accessToken'] as String;
        final newRefreshToken = body['refreshToken'] as String;
        final accessTokenExpires = DateTime.parse(
          body['accessTokenExpires'] as String,
        );
        final refreshTokenExpires = DateTime.parse(
          body['refreshTokenExpires'] as String,
        );

        await saveTokens(
          accessToken: newAccessToken,
          refreshToken: newRefreshToken,
          accessTokenExpires: accessTokenExpires,
          refreshTokenExpires: refreshTokenExpires,
        );

        _logger.i('Tokens refreshed successfully');
        return true;
      } else {
        _logger.e(
          'Failed to refresh token: ${response.statusCode} ${response.body}',
        );
        // await clearAllTokens();
        return false;
      }
    } catch (e) {
      _logger.e('Error refreshing token: $e');
      await clearAllTokens();
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  /// Build headers with authentication
  Future<Map<String, String>> _buildHeaders({bool includeAuth = true}) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (includeAuth) {
      // Check if access token is expired and refresh if needed
      if (await isAccessTokenExpired()) {
        final refreshed = await refreshAccessToken();
        if (!refreshed) {
          _logger.w('Could not refresh expired access token');
        }
      }

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

    final headers = await _buildHeaders(includeAuth: requiresAuth);

    try {
      final response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      // Handle 401 by attempting token refresh and retry
      if (response.statusCode == 401 && requiresAuth) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _buildHeaders(includeAuth: true);
          final retryResponse = await _client
              .get(uri, headers: newHeaders)
              .timeout(const Duration(seconds: 30));
          return _processResponse(retryResponse);
        }
      }

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

    final headers = await _buildHeaders(includeAuth: requiresAuth);

    try {
      final response = await _client
          .delete(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      // Handle 401 by attempting token refresh and retry
      if (response.statusCode == 401 && requiresAuth) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _buildHeaders(includeAuth: true);
          final retryResponse = await _client
              .delete(uri, headers: newHeaders)
              .timeout(const Duration(seconds: 30));
          return _processResponse(retryResponse);
        }
      }

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

    final headers = await _buildHeaders(includeAuth: requiresAuth);

    try {
      final response = await _client
          .post(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30));

      // Handle 401 by attempting token refresh and retry
      if (response.statusCode == 401 && requiresAuth) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _buildHeaders(includeAuth: true);
          final retryResponse = await _client
              .post(
                uri,
                headers: newHeaders,
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(const Duration(seconds: 30));
          return _processResponse(retryResponse);
        }
      }

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

    final headers = await _buildHeaders(includeAuth: requiresAuth);

    try {
      final response = await _client
          .put(
            uri,
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30));

      // Handle 401 by attempting token refresh and retry
      if (response.statusCode == 401 && requiresAuth) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          final newHeaders = await _buildHeaders(includeAuth: true);
          final retryResponse = await _client
              .put(
                uri,
                headers: newHeaders,
                body: body != null ? jsonEncode(body) : null,
              )
              .timeout(const Duration(seconds: 30));
          return _processResponse(retryResponse);
        }
      }

      return _processResponse(response);
    } catch (e) {
      _logger.e('PUT request failed: $uri $e');
      rethrow;
    }
  }

  Map<String, dynamic> _processResponse(http.Response response) {
    final statusCode = response.statusCode;

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
