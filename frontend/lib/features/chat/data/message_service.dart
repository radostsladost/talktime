import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/features/chat/data/local_message_storage.dart';
import 'package:talktime/shared/models/message.dart';
import 'package:logger/logger.dart';

import 'package:talktime/features/chat/data/models/message.dart' as DbModels;

/// Service for managing messages
class MessageService {
  final ApiClient _apiClient = ApiClient();
  final Logger _logger = Logger();

  // Inject or instantiate your local storage
  final LocalMessageStorage _localStorage = LocalMessageStorage();

  /// Get messages for a specific conversation
  /// Supports pagination with skip and take parameters
  Future<List<Message>> getMessages(
    String conversationId, {
    int skip = 0,
    int take = 50,
  }) async {
    try {
      // 1. Read directly from local DB
      final messages = await _localStorage.getMessages(
        conversationId,
        offset: skip,
        limit: take,
      );

      return messages.map((message) => Message.fromDb(message)).toList();
    } catch (e) {
      _logger.e('Error fetching messages: $e');
      rethrow;
    }
  }

  /// Syncs new data: Fetch from API -> Save to Local
  /// Call this on app start, socket notification, or background task.
  Future<void> syncPendingMessages() async {
    try {
      _logger.i('Syncing pending messages from backend...');

      // 1. Fetch from API
      final response = await _apiClient.get(ApiConstants.pendingMessages);
      final List messagesJson = response['data'] as List;

      if (messagesJson.isEmpty) return;

      final messages = messagesJson
          .map((json) => Message.fromJson(json as Map<String, dynamic>))
          .map(
            (message) => DbModels.Message().initFields(
              message.id,
              message.conversationId,
              message.sender?.id ?? "",
              message.content,
              message.type as DbModels.MessageSchemaMessageType,
              message.sentAt,
            ),
          )
          .toList();

      // 2. CRITICAL: Save to Local Storage immediately
      // Since backend deletes them, if we crash here without saving, data is lost.
      await _localStorage.saveMessages(messages);

      _logger.i('Synced and saved ${messages.length} messages');

      // 3. (Optional) Confirm delivery to backend if your API requires specific ACKs
      // Usually "pending" endpoints auto-delete on success, but if you have
      // specific 'markAsDelivered' calls, do them here parallel to saving.
      for (var msg in messages) {
        markAsDelivered(msg.externalId).ignore(); // Fire and forget
      }
    } catch (e) {
      _logger.e('Error syncing messages: $e');
      // Do not rethrow; we don't want to crash the syncing cycle usually.
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
