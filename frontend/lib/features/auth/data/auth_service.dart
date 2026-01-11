import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/shared/models/user.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient();

  /// Login with email and password
  Future<AuthResponse> login(String email, String password) async {
    final response = await _apiClient.post(
      ApiConstants.login,
      body: {'email': email, 'password': password},
      requiresAuth: false,
    );

    final accessToken = response['accessToken'] as String;
    final refreshToken = response['refreshToken'] as String;
    final accessTokenExpires = DateTime.parse(
      response['accessTokenExpires'] as String,
    );
    final refreshTokenExpires = DateTime.parse(
      response['refreshTokenExpires'] as String,
    );
    final userData = response['user'] as Map<String, dynamic>;
    final user = User.fromJson(userData);

    // Save all tokens and their expiration times
    await _apiClient.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpires: accessTokenExpires,
      refreshTokenExpires: refreshTokenExpires,
    );

    return AuthResponse(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpires: accessTokenExpires,
      refreshTokenExpires: refreshTokenExpires,
      user: user,
    );
  }

  /// Register a new user
  Future<AuthResponse> register(
    String username,
    String email,
    String password,
  ) async {
    final response = await _apiClient.post(
      ApiConstants.register,
      body: {'username': username, 'email': email, 'password': password},
      requiresAuth: false,
    );

    final accessToken = response['accessToken'] as String;
    final refreshToken = response['refreshToken'] as String;
    final accessTokenExpires = DateTime.parse(
      response['accessTokenExpires'] as String,
    );
    final refreshTokenExpires = DateTime.parse(
      response['refreshTokenExpires'] as String,
    );
    final userData = response['user'] as Map<String, dynamic>;
    final user = User.fromJson(userData);

    // Save all tokens and their expiration times
    await _apiClient.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpires: accessTokenExpires,
      refreshTokenExpires: refreshTokenExpires,
    );

    return AuthResponse(
      accessToken: accessToken,
      refreshToken: refreshToken,
      accessTokenExpires: accessTokenExpires,
      refreshTokenExpires: refreshTokenExpires,
      user: user,
    );
  }

  /// Logout current user
  /// Revokes the current refresh token on the server
  Future<void> logout() async {
    try {
      // Get the current refresh token to revoke it
      final refreshToken = await _apiClient.getRefreshToken();

      if (refreshToken != null) {
        await _apiClient.post(
          ApiConstants.logout,
          body: {'refreshToken': refreshToken},
          requiresAuth: true,
        );
      } else {
        // If no refresh token, just call logout without body
        await _apiClient.post(ApiConstants.logout, requiresAuth: true);
      }
    } catch (e) {
      // Continue with logout even if API call fails
    } finally {
      // Clear all local tokens
      await _apiClient.clearAllTokens();
    }
  }

  /// Logout from all devices
  /// Revokes all refresh tokens for the current user
  Future<void> logoutAll() async {
    try {
      await _apiClient.post(ApiConstants.logoutAll, requiresAuth: true);
    } catch (e) {
      // Continue with logout even if API call fails
    } finally {
      // Clear all local tokens
      await _apiClient.clearAllTokens();
    }
  }

  /// Revoke a specific refresh token
  Future<void> revokeToken(String refreshToken) async {
    await _apiClient.post(
      ApiConstants.revokeToken,
      body: {'refreshToken': refreshToken},
      requiresAuth: true,
    );
  }

  /// Get current user information
  Future<User> getCurrentUser() async {
    final response = await _apiClient.get(ApiConstants.me, requiresAuth: true);

    return User.fromJson(response);
  }

  /// Check if user is authenticated (has valid token)
  Future<bool> isAuthenticated() async {
    // First check if we have tokens stored
    final accessToken = await _apiClient.getToken();
    if (accessToken == null) {
      return false;
    }

    // Check if refresh token is expired (access token will be refreshed automatically)
    if (await _apiClient.isRefreshTokenExpired()) {
      await _apiClient.clearAllTokens();
      return false;
    }

    await refreshTokenIfNeeded();

    // Try to get current user to verify tokens are valid
    try {
      await getCurrentUser();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Refresh the access token
  Future<bool> refreshTokenIfNeeded() async {
    if (await needsTokenRefresh()) {
      await refreshToken();
      return true;
    }
    return false;
  }

  /// Check if tokens need to be refreshed
  Future<bool> needsTokenRefresh() async {
    return await _apiClient.isAccessTokenExpired();
  }

  /// Manually refresh the access token
  Future<bool> refreshToken() async {
    return await _apiClient.refreshAccessToken();
  }

  /// Get the current access token
  Future<String?> getAccessToken() async {
    return await _apiClient.getToken();
  }

  /// Get the current refresh token
  Future<String?> getRefreshToken() async {
    return await _apiClient.getRefreshToken();
  }
}

/// Response model for login/register
class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpires;
  final DateTime refreshTokenExpires;
  final User user;

  AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpires,
    required this.refreshTokenExpires,
    required this.user,
  });

  /// Check if access token is expired
  bool get isAccessTokenExpired => DateTime.now().isAfter(accessTokenExpires);

  /// Check if refresh token is expired
  bool get isRefreshTokenExpired => DateTime.now().isAfter(refreshTokenExpires);

  /// Get remaining time for access token
  Duration get accessTokenRemainingTime =>
      accessTokenExpires.difference(DateTime.now());

  /// Get remaining time for refresh token
  Duration get refreshTokenRemainingTime =>
      refreshTokenExpires.difference(DateTime.now());
}

/// Deprecated: Use AuthResponse instead
/// Kept for backward compatibility
@Deprecated('Use AuthResponse instead')
class LoginResponse {
  final String token;
  final User user;

  LoginResponse({required this.token, required this.user});
}
