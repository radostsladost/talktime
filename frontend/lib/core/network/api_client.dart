import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:talktime/core/constants/api_constants.dart';

class ApiClient {
  final http.Client _client = http.Client();
  final Logger _logger = Logger();

  Future<Map<String, dynamic>> get(String endpoint) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    _logger.i('GET $uri');
    
    final response = await _client.get(uri).timeout(const Duration(seconds: 10));
    return _processResponse(response);
  }

  Future<Map<String, dynamic>> post(String endpoint, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
    _logger.i('POST $uri | body: $body');
    
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));
    return _processResponse(response);
  }

  Map<String, dynamic> _processResponse(http.Response response) {
    final statusCode = response.statusCode;
    final body = jsonDecode(response.body) as Map<String, dynamic>;

    if (statusCode >= 200 && statusCode < 300) {
      return body;
    } else {
      _logger.e('API Error: $statusCode | $body');
      throw ApiException(statusCode, body['message'] ?? 'Unknown error');
    }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
}