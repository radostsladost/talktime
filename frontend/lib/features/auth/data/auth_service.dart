import 'dart:ui';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/core/global_key.dart';
import 'package:talktime/shared/models/user.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient();

  /// Get Firebase Cloud Messaging token
  Future<String?> _getFcmToken() async {
    try {
      // Request permission for notifications
      // if (kIsWeb || Platform.isWindows || Platform.isAndroid) {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      // }

      // Get the FCM token
      final token = await FirebaseMessaging.instance.getToken();
      return token;
    } catch (e) {
      Logger().e('Failed to get FCM token: $e');
      return null;
    }
  }

  /// Register Firebase token with the backend
  Future<void> _registerFirebaseToken(String? token) async {
    if (token == null || token.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    var deviceIdVal = prefs.getString('deviceId');
    if (deviceIdVal == null || deviceIdVal.isEmpty) {
      final rng = Random();
      deviceIdVal =
          (rng.nextDouble() + 0.001).toString().substring(2) +
          (rng.nextDouble() + 0.001).toString().substring(2);
      await prefs.setString('deviceId', deviceIdVal);
    }

    try {
      DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
      String deviceId = "unknown";
      String deviceInfo = "";
      if (kIsWeb) {
        deviceId = "web";
        deviceInfo = (await deviceInfoPlugin.webBrowserInfo).userAgent!;
      } else {
        deviceInfo = deviceInfo;
        if (Platform.isIOS) {
          deviceId = 'ios';
          deviceInfo = (await deviceInfoPlugin.iosInfo).utsname.machine;
        } else if (Platform.isAndroid) {
          deviceId = 'android';
          deviceInfo = (await deviceInfoPlugin.androidInfo).name;
        } else if (Platform.isWindows) {
          deviceId = 'windows';
          deviceInfo = (await deviceInfoPlugin.windowsInfo).productName;
        } else if (Platform.isLinux) {
          deviceId = 'linux';
          deviceInfo = (await deviceInfoPlugin.linuxInfo).prettyName;
        } else if (Platform.isMacOS) {
          deviceId = 'macOS';
          deviceInfo = (await deviceInfoPlugin.macOsInfo).computerName;
        } else {
          deviceInfo = Platform.operatingSystem;
        }
      }
      deviceId = '$deviceId-$deviceIdVal';

      await _apiClient.post(
        ApiConstants.registerFirebaseToken,
        body: {'token': token, 'deviceId': deviceId, 'deviceInfo': deviceInfo},
        requiresAuth: true,
      );
      Logger().i('Firebase token registered successfully');
    } catch (e) {
      Logger().e('Failed to register Firebase token: $e');
      // Don't throw - this is not critical for login/registration
    }
  }

  /// Login with email and password
  Future<AuthResponse> login(String email, String password) async {
    // Get FCM token before login
    final fcmToken = await _getFcmToken();

    final body = {'email': email, 'password': password};

    // Add FCM token if available
    if (fcmToken != null) {
      body['firebaseToken'] = fcmToken;
      body['deviceId'] = Platform.isAndroid ? 'android' : 'ios';
      body['deviceInfo'] = Platform.operatingSystem;
    }

    final response = await _apiClient.post(
      ApiConstants.login,
      body: body,
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

    // Register FCM token if not already sent (fallback)
    if (fcmToken != null) {
      await _registerFirebaseToken(fcmToken);
    }

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
    // Get FCM token before registration
    final fcmToken = await _getFcmToken();

    final body = {'username': username, 'email': email, 'password': password};

    // Add FCM token if available
    if (fcmToken != null) {
      body['firebaseToken'] = fcmToken;
      body['deviceId'] = Platform.isAndroid ? 'android' : 'ios';
      body['deviceInfo'] = Platform.operatingSystem;
    }

    final response = await _apiClient.post(
      ApiConstants.register,
      body: body,
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
      Logger().e('no access token');
      return false;
    }

    // Check if refresh token is expired (access token will be refreshed automatically)
    if (await _apiClient.isRefreshTokenExpired()) {
      Logger().e('Refresh token expired');
      await _apiClient.clearAllTokens();
      return false;
    }

    await refreshTokenIfNeeded();

    // Try to get current user to verify tokens are valid
    try {
      await getCurrentUser();
      return true;
    } catch (e) {
      Logger().e('token invalid');
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

  /// Register Firebase Cloud Messaging token
  /// Call this when the app is already authenticated and opened
  Future<void> registerFirebaseToken() async {
    final fcmToken = await _getFcmToken();
    if (fcmToken != null) {
      await _registerFirebaseToken(fcmToken);
    }
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
