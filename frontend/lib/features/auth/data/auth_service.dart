import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient();

  Future<String> login(String email, String password) async {
    final response = await _apiClient.post(
      ApiConstants.auth + '/login',
      body: {'email': email, 'password': password},
    );
    return response['token'] as String;
  }
}