import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/chat/data/local_message_storage.dart';
import 'package:talktime/shared/models/message.dart';
import 'package:logger/logger.dart';

import 'package:talktime/features/chat/data/local_conversation_storage.dart';
import 'package:talktime/features/chat/data/models/message.dart' as DbModels;

/// Service for managing messages
class MessageService {
  final ApiClient _apiClient = ApiClient();
  final Logger _logger = Logger(output: ConsoleOutput());

  // Inject or instantiate your local storage
  final LocalMessageStorage _localStorage = LocalMessageStorage();
  final LocalConversationStorage _conversationStorage =
      LocalConversationStorage();

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

  /// Get messages for a specific conversation
  /// Supports pagination with skip and take parameters
  Future<Message?> getLastMessage(String conversationId) async {
    try {
      // 1. Read directly from local DB
      final messages = await _localStorage.getMessages(
        conversationId,
        offset: 0,
        limit: 1,
      );

      return messages.map((message) => Message.fromDb(message)).firstOrNull;
    } catch (e) {
      _logger.e('Error fetching messages: $e');
      rethrow;
    }
  }

  /// Syncs new messages for a specific conversation from backend to local storage
  /// Call this when you want to sync messages for a specific conversation
  Future<void> syncConversationMessages(String conversationId) async {
    try {
      _logger.i('Syncing messages for conversation: $conversationId');

      // 1. Fetch from API
      final response = await _apiClient.get(
        '${ApiConstants.messages}?conversationId=$conversationId',
      );
      final List messagesJson = response['data'] as List;

      if (messagesJson.isEmpty) return;

      final messages = messagesJson
          .map((json) => Message.fromJson(json as Map<String, dynamic>))
          .map(
            (message) => DbModels.Message()
              ..externalId = message.id
              ..conversationId = message.conversationId
              ..senderId = message.sender!.id
              ..content = message.content
              ..type = getMessageType(message.type)
              ..sentAt = DateTime.parse(message.sentAt).millisecondsSinceEpoch,
          )
          .toList();

      // 2. Save to Local Storage
      await _localStorage.saveMessages(messages);

      // 3. Update conversation lastMessageAt if messages exist
      if (messages.isNotEmpty) {
        final lastMessage = messages.reduce(
          (a, b) => a.sentAt > b.sentAt ? a : b,
        );
        await _conversationStorage.updateLastMessageAt(
          conversationId,
          DateTime.fromMillisecondsSinceEpoch(
            lastMessage.sentAt,
          ).toIso8601String(),
        );
      }

      _logger.i(
        'Synced and saved ${messages.length} messages for conversation $conversationId',
      );
    } catch (e) {
      _logger.e('Error syncing messages for conversation $conversationId: $e');
      // Do not rethrow; we don't want to crash the syncing cycle usually.
    }
  }

  /// Syncs pending messages for all conversations
  /// Call this on app start, socket notification, or background task.
  Future<void> syncPendingMessages(String conversationId) async {
    List<DbModels.Message> messages = [];
    try {
      // _logger.i('Syncing pending messages for conversation: $conversationId');
      await AuthService().refreshTokenIfNeeded();

      // 1. Fetch from API for specific conversation
      final response = await _apiClient.get(
        '${ApiConstants.pendingMessages}?conversationId=$conversationId',
      );
      final List messagesJson = response['data'] as List;

      if (messagesJson.isEmpty) {
        // _logger.i('No pending messages for conversation: $conversationId');
        return;
      }

      messages = messagesJson
          .map((json) => Message.fromJson(json as Map<String, dynamic>))
          .map(
            (message) => DbModels.Message()
              ..externalId = message.id
              ..conversationId = message.conversationId
              ..senderId = message.sender!.id
              ..content = message.content
              ..type = getMessageType(message.type)
              ..sentAt = DateTime.parse(message.sentAt).millisecondsSinceEpoch,
          )
          .toList();

      // 2. Save to Local Storage immediately
      await _localStorage.saveMessages(messages);

      // 3. Update conversation lastMessageAt if messages exist
      if (messages.isNotEmpty) {
        final lastMessage = messages.reduce(
          (a, b) => a.sentAt > b.sentAt ? a : b,
        );
        await _conversationStorage.updateLastMessageAt(
          conversationId,
          DateTime.fromMillisecondsSinceEpoch(
            lastMessage.sentAt,
          ).toIso8601String(),
        );
      }

      _logger.i(
        'Synced and saved ${messages.length} pending messages for conversation: $conversationId',
      );
    } catch (e) {
      _logger.e(
        'Error syncing pending messages for conversation $conversationId: $e',
      );
      // Do not rethrow; we don't want to crash the syncing cycle usually.
    }

    try {
      // 3. Mark messages as delivered to backend
      for (var msg in messages) {
        markAsDelivered(msg.externalId).ignore(); // Fire and forget
      }
    } catch (e) {
      _logger.e(
        'Error marking messages as delivered for conversation $conversationId: $e',
      );
      // Do not rethrow; we don't want to crash the syncing cycle usually.
    }
  }

  Future<void> markAsRead(Message message) {
    if (message.readAt != null) return Future.value();
    return _localStorage.markAsRead(message.id);
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

      // Immediately save to local storage for optimistic UI update
      final dbMessage = DbModels.Message()
        ..externalId = message.id
        ..conversationId = message.conversationId
        ..senderId = message.sender?.id ?? ""
        ..content = message.content
        ..type = getMessageType(message.type)
        ..sentAt = DateTime.parse(message.sentAt).millisecondsSinceEpoch;

      await _localStorage.saveMessages([dbMessage]);

      // Update conversation lastMessageAt
      await _conversationStorage.updateLastMessageAt(
        conversationId,
        message.sentAt,
      );

      // Notify WebSocket that we've sent a message (this will trigger any needed updates)
      // We can also send acknowledgments if needed
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

      // _logger.i('Fetched ${messages.length} pending messages');
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
      // Don't rethrow to prevent sync from failing
    }
  }

  /// Delete a message (only sender can delete)
  Future<void> deleteMessage(String messageId) async {
    try {
      _logger.i('Deleting message: $messageId');
      await _apiClient.delete(ApiConstants.deleteMessage(messageId));

      // Also delete from local storage
      await _localStorage.deleteMessage(messageId);

      _logger.i('Message deleted successfully');
    } catch (e) {
      _logger.e('Error deleting message: $e');
      rethrow;
    }
  }

  DbModels.MessageSchemaMessageType getMessageType(MessageType type) {
    switch (type) {
      case MessageType.text:
        return DbModels.MessageSchemaMessageType.text;
      default:
        throw ArgumentError('Invalid message type');
    }
  }

  /// Dispose resources
  void dispose() {
    _apiClient.dispose();
  }
}
