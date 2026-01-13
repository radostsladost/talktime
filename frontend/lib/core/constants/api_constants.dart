import 'package:talktime/core/config/environment.dart';

/// API Constants for TalkTime backend
/// All endpoints are prefixed with /api as per the backend configuration
class ApiConstants {
  // Base URL from environment configuration
  static String get baseUrl => Environment.apiBaseUrl;

  // WebSocket base URL
  static String get wsBaseUrl => Environment.wsBaseUrl;

  // API prefix - all endpoints start with /api
  static const String apiPrefix = '/api';

  // ==================== Auth Endpoints ====================
  static const String auth = '$apiPrefix/auth';
  static const String login = '$auth/login';
  static const String register = '$auth/register';
  static const String logout = '$auth/logout';
  static const String logoutAll = '$auth/logout-all';
  static const String me = '$auth/me';
  static const String updateProfile = '$auth/me';
  static const String refreshToken = '$auth/refresh';
  static const String revokeToken = '$auth/revoke';

  // ==================== Conversation Endpoints ====================
  static const String conversations = '$apiPrefix/conversations';

  // Get conversation by ID
  static String conversationById(String id) => '$conversations/$id';

  // Add participant to conversation
  static String addParticipant(String conversationId) =>
      '$conversations/$conversationId/participants';

  // Remove participant from conversation
  static String removeParticipant(
    String conversationId,
    String participantId,
  ) => '$conversations/$conversationId/participants/$participantId';

  // Search user
  static String searchUserByQuery(String userName) =>
      '$conversations/search/user?userName=$userName';

  // ==================== Message Endpoints ====================
  static const String messages = '$apiPrefix/messages';
  static const String pendingMessages = '$messages/pending';

  // Mark message as delivered
  static String markMessageDelivered(String messageId) =>
      '$messages/$messageId/delivered';

  // Delete message
  static String deleteMessage(String messageId) => '$messages/$messageId';

  // ==================== User Endpoints ====================
  static const String users = '$apiPrefix/users';

  // Get user by ID
  static String userById(String id) => '$users/$id';

  // ==================== SignalR Hub Endpoint ====================
  // WebSocket endpoint for real-time communication (calls, messages)
  static const String signalingHub = '/hubs/talktime';

  // ==================== WebSocket URLs ====================

  /// Get the full SignalR WebSocket URL with authentication
  /// The access token is passed as a query parameter for SignalR authentication
  static String getSignalingUrl(String accessToken) {
    return '$wsBaseUrl$signalingHub?access_token=$accessToken';
  }

  /// Get the full SignalR WebSocket URL with authentication
  /// The access token is passed as a query parameter for SignalR authentication
  static String getSignalingUrlWithNoToken() {
    return '$wsBaseUrl$signalingHub';
  }

  // ==================== Helper Methods ====================

  /// Get full URL for any endpoint
  static String getFullUrl(String endpoint) {
    return '$baseUrl$endpoint';
  }

  /// Get full WebSocket URL
  static String getFullWsUrl(String endpoint) {
    return '$wsBaseUrl$endpoint';
  }

  // ==================== Configuration ====================

  /// Print API configuration (for debugging)
  static void printConfig() {
    if (Environment.enableLogging) {
      print('=== API Configuration ===');
      print('Base URL: $baseUrl');
      print('WebSocket URL: $wsBaseUrl');
      print('SignalR Hub: $signalingHub');
      print('========================');
    }
  }
}
