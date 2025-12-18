import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/shared/models/message.dart';
import 'package:logger/logger.dart';

/// Service for managing messages
class MessageService {
  final ApiClient _apiClient = ApiClient();
  final Logger _logger = Logger();

  /// Get messages for a specific conversation
  /// Supports pagination with skip and take parameters
  Future<List<Message>> getMessages(
    String conversationId, {
    int skip = 0,
    int take = 50,
  }) async {
    try {
      _logger.i('Fetching messages for conversation: $conversationId');
      final response = await _apiClient.get(
        '${ApiConstants.messages}?conversationId=$conversationId&skip=$skip&take=$take',
      );

      final List messagesJson = response['data'] as List;
      final messages = messagesJson
          .map((json) => Message.fromJson(json as Map<String, dynamic>))
          .toList();

      _logger.i('Fetched ${messages.length} messages');
      return messages;
    } catch (e) {
      _logger.e('Error fetching messages: $e');
      rethrow;
    }
  }

  /// Send a new message to a conversation
  Future<Message> sendMessage(
    String conversationId,
    String content, {
    String type = 'text',
  }) async {
    try {
      _logger.i('Sending message to conversation: $conversationId');
      final response = await _apiClient.post(
        ApiConstants.messages,
        body: {
          'conversationId': conversationId,
          'content': content,
          'type': type,
        },
      );

      final message = Message.fromJson(
        response['data'] as Map<String, dynamic>,
      );
      _logger.i('Message sent successfully: ${message.id}');
      return message;
    } catch (e) {
      _logger.e('Error sending message: $e');
      rethrow;
    }
  }

  /// Get pending messages (messages received while offline)
  Future<List<Message>> getPendingMessages() async {
    try {
      _logger.i('Fetching pending messages');
      final response = await _apiClient.get(ApiConstants.pendingMessages);

      final List messagesJson = response['data'] as List;
      final messages = messagesJson
          .map((json) => Message.fromJson(json as Map<String, dynamic>))
          .toList();

      _logger.i('Fetched ${messages.length} pending messages');
      return messages;
    } catch (e) {
      _logger.e('Error fetching pending messages: $e');
      rethrow;
    }
  }

  /// Mark a message as delivered
  Future<void> markAsDelivered(String messageId) async {
    try {
      _logger.i('Marking message as delivered: $messageId');
      await _apiClient.post(ApiConstants.markMessageDelivered(messageId));
      _logger.i('Message marked as delivered');
    } catch (e) {
      _logger.e('Error marking message as delivered: $e');
      rethrow;
    }
  }

  /// Delete a message (only sender can delete)
  Future<void> deleteMessage(String messageId) async {
    try {
      _logger.i('Deleting message: $messageId');
      await _apiClient.delete(ApiConstants.deleteMessage(messageId));
      _logger.i('Message deleted successfully');
    } catch (e) {
      _logger.e('Error deleting message: $e');
      rethrow;
    }
  }

  /// Dispose resources
  void dispose() {
    _apiClient.dispose();
  }
}
