import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/shared/models/user.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient();

  /// Login with email and password
  Future<LoginResponse> login(String email, String password) async {
    final response = await _apiClient.post(
      ApiConstants.login,
      body: {'email': email, 'password': password},
      requiresAuth: false,
    );

    final token = response['token'] as String;
    final userData = response['user'] as Map<String, dynamic>;
    final user = User.fromJson(userData);

    // Save token for future requests
    await _apiClient.saveToken(token);

    return LoginResponse(token: token, user: user);
  }

  /// Register a new user
  Future<LoginResponse> register(
    String username,
    String email,
    String password,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.register,
      body: {'username': username, 'email': email, 'password': password},
      requiresAuth: false,
    );

    final token = response['token'] as String;
    final userData = response['user'] as Map<String, dynamic>;
    final user = User.fromJson(userData);

    // Save token for future requests
    await _apiClient.saveToken(token);

    return LoginResponse(token: token, user: user);
  }

  /// Logout current user
  Future<void> logout() async {
    try {
      await _apiClient.post(ApiConstants.logout, requiresAuth: true);
    } catch (e) {
      // Continue with logout even if API call fails
    } finally {
      // Clear local token
      await _apiClient.clearToken();
    }
  }

  /// Get current user information
  Future<User> getCurrentUser() async {
    final response = await _apiClient.get(ApiConstants.me, requiresAuth: true);

    return User.fromJson(response);
  }

  /// Check if user is authenticated (has valid token)
  Future<bool> isAuthenticated() async {
    try {
      await getCurrentUser();
      return true;
    } catch (e) {
      return false;
    }
  }
}

/// Response model for login/register
class LoginResponse {
  final String token;
  final User user;

  LoginResponse({required this.token, required this.user});
}
