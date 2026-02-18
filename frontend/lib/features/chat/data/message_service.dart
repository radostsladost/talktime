import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
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

  /// Get unread message count for a conversation (messages from others not yet read).
  Future<int> getUnreadCount(String conversationId) async {
    try {
      final myUserId = (await AuthService().getCurrentUser()).id;
      return await _localStorage.getUnreadCount(conversationId, myUserId);
    } catch (e) {
      _logger.e('Error fetching unread count: $e');
      return 0;
    }
  }

  /// Saves messages to local storage and updates lastMessageAt for each affected conversation.
  /// Must be used whenever we receive or save messages so chat list sorting stays correct.
  Future<void> _saveMessagesAndUpdateLastMessageAt(
    List<DbModels.Message> messages,
  ) async {
    if (messages.isEmpty) return;
    await _localStorage.saveMessages(messages);
    final byConvo = <String, DbModels.Message>{};
    for (var m in messages) {
      final existing = byConvo[m.conversationId];
      if (existing == null || m.sentAt > existing.sentAt) {
        byConvo[m.conversationId] = m;
      }
    }
    for (var entry in byConvo.entries) {
      await _conversationStorage.updateLastMessageAt(
        entry.key,
        DateTime.fromMillisecondsSinceEpoch(entry.value.sentAt).toIso8601String(),
      );
    }
  }

  /// Persist a single message received in real time (e.g. via WebSocket).
  /// Prevents duplicates via unique externalId in local DB.
  /// Always updates conversation lastMessageAt when we receive messages.
  Future<void> saveMessageFromRealtime(Message message) async {
    if (message.id.isEmpty) return;
    try {
      final dbMessage = DbModels.Message()
        ..externalId = message.id
        ..conversationId = message.conversationId
        ..senderId = message.sender.id
        ..content = message.content
        ..type = getMessageType(message.type)
        ..sentAt = DateTime.parse(message.sentAt).millisecondsSinceEpoch
        ..mediaUrl = message.mediaUrl;
      await _saveMessagesAndUpdateLastMessageAt([dbMessage]);
    } catch (e) {
      _logger.e('Error saving realtime message: $e');
    }
  }

  static const int _messagesPageSize = 50;

  /// Fetches one page of messages from the API for a conversation.
  Future<List<Message>> _fetchMessagesPage(String conversationId, {int skip = 0, int take = _messagesPageSize}) async {
    final response = await _apiClient.get(
      '${ApiConstants.messages}?conversationId=$conversationId&skip=$skip&take=$take',
    );
    final List messagesJson = response['data'] as List;
    return messagesJson
        .map((json) => Message.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Syncs all messages for a conversation from backend to local storage using pagination.
  /// Call when opening a chat and on a timer to keep local DB in sync.
  Future<void> syncConversationMessagesWithPagination(String conversationId) async {
    try {
      await AuthService().refreshTokenIfNeeded();
      int skip = 0;
      int totalSaved = 0;
      while (true) {
        final page = await _fetchMessagesPage(conversationId, skip: skip, take: _messagesPageSize);
        if (page.isEmpty) break;

        final dbMessages = page
            .map(
              (message) => DbModels.Message()
                ..externalId = message.id
                ..conversationId = message.conversationId
                ..senderId = message.sender!.id
                ..content = message.content
                ..type = getMessageType(message.type)
                ..sentAt = DateTime.parse(message.sentAt).millisecondsSinceEpoch
                ..mediaUrl = message.mediaUrl,
            )
            .toList();
        await _saveMessagesAndUpdateLastMessageAt(dbMessages);
        totalSaved += dbMessages.length;
        if (page.length < _messagesPageSize) break;
        skip += _messagesPageSize;
      }
      if (totalSaved > 0) {
        _logger.i('Synced $totalSaved messages for conversation $conversationId (paginated)');
      }
    } catch (e) {
      _logger.e('Error syncing messages for conversation $conversationId: $e');
    }
  }

  /// Syncs one page of messages for a conversation (legacy / simple sync).
  Future<void> syncConversationMessages(String conversationId) async {
    try {
      final page = await _fetchMessagesPage(conversationId, skip: 0, take: _messagesPageSize);
      if (page.isEmpty) return;
      final dbMessages = page
          .map(
            (message) => DbModels.Message()
              ..externalId = message.id
              ..conversationId = message.conversationId
              ..senderId = message.sender!.id
              ..content = message.content
              ..type = getMessageType(message.type)
              ..sentAt = DateTime.parse(message.sentAt).millisecondsSinceEpoch
              ..mediaUrl = message.mediaUrl,
          )
          .toList();
      await _saveMessagesAndUpdateLastMessageAt(dbMessages);
    } catch (e) {
      _logger.e('Error syncing messages for conversation $conversationId: $e');
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
              ..sentAt = DateTime.parse(message.sentAt).millisecondsSinceEpoch
              ..mediaUrl = message.mediaUrl,
          )
          .toList();

      await _saveMessagesAndUpdateLastMessageAt(messages);

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

  /// Mark all messages in the conversation from others as read (e.g. when user opens the chat).
  Future<void> markConversationAsRead(String conversationId) async {
    try {
      final myUserId = (await AuthService().getCurrentUser()).id;
      await _localStorage.markConversationAsRead(conversationId, myUserId);
    } catch (e) {
      _logger.e('Error marking conversation as read: $e');
    }
  }

  /// Send a new message to a conversation
  Future<Message> sendMessage(
    String conversationId,
    String content, {
    String type = 'text',
    String? mediaUrl,
  }) async {
    try {
      _logger.i('Sending message to conversation: $conversationId');
      final body = {
        'conversationId': conversationId,
        'content': content,
        'type': type,
      };
      if (mediaUrl != null) {
        body['mediaUrl'] = mediaUrl;
      }

      final response = await _apiClient.post(
        ApiConstants.messages,
        body: body,
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
        ..sentAt = DateTime.parse(message.sentAt).millisecondsSinceEpoch
        ..mediaUrl = message.mediaUrl;

      await _saveMessagesAndUpdateLastMessageAt([dbMessage]);

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
      case MessageType.image:
        return DbModels.MessageSchemaMessageType.image;
      case MessageType.gif:
        return DbModels.MessageSchemaMessageType.gif;
      case MessageType.file:
        return DbModels.MessageSchemaMessageType.file;
      case MessageType.audio:
        return DbModels.MessageSchemaMessageType.audio;
      case MessageType.video:
        return DbModels.MessageSchemaMessageType.video;
    }
  }

  // ==================== Device Sync Methods ====================

  /// Export messages for sync to another device
  /// Returns a list of SyncMessageDto that can be sent to another device
  Future<List<SyncMessageDto>> exportMessagesForSync({
    String? conversationId,
    int? sinceTimestamp,
    int limit = 500,
  }) async {
    try {
      _logger.i('Exporting messages for sync: conversationId=$conversationId, since=$sinceTimestamp, limit=$limit');
      
      List<DbModels.Message> messages;
      
      if (conversationId != null && conversationId.isNotEmpty) {
        // Export messages for a specific conversation
        messages = await _localStorage.getMessages(
          conversationId,
          offset: 0,
          limit: limit,
        );
        
        // Filter by timestamp if provided
        if (sinceTimestamp != null && sinceTimestamp > 0) {
          messages = messages.where((m) => m.sentAt > sinceTimestamp).toList();
        }
      } else {
        // Export all messages across all conversations
        messages = await _localStorage.getAllMessagesForSync(
          sinceTimestamp: sinceTimestamp,
          limit: limit,
        );
      }
      
      _logger.i('Found ${messages.length} messages to export for sync');
      
      if (messages.isEmpty) {
        _logger.i('No messages to export');
        return [];
      }
      
      // Convert to SyncMessageDto
      final syncMessages = messages.map((m) => SyncMessageDto(
        id: m.externalId,
        conversationId: m.conversationId,
        senderId: m.senderId,
        senderUsername: '', // We don't store sender username locally, will be filled by receiver
        senderAvatarUrl: null,
        content: m.content,
        type: _messageTypeToString(m.type),
        sentAtTimestamp: m.sentAt,
        mediaUrl: m.mediaUrl,
        thumbnailUrl: null,
        readAtTimestamp: m.readAt,
      )).toList();
      
      _logger.i('Exporting ${syncMessages.length} messages for sync');
      return syncMessages;
    } catch (e) {
      _logger.e('Error exporting messages for sync: $e');
      return [];
    }
  }

  /// Import messages from another device
  /// Takes a list of SyncMessageDto and saves them to local storage
  Future<void> importMessagesFromSync(List<SyncMessageDto> syncMessages) async {
    if (syncMessages.isEmpty) return;
    
    try {
      _logger.i('Importing ${syncMessages.length} messages from sync');
      
      final messages = syncMessages.map((m) => DbModels.Message()
        ..externalId = m.id
        ..conversationId = m.conversationId
        ..senderId = m.senderId
        ..content = m.content
        ..type = _stringToMessageType(m.type)
        ..sentAt = m.sentAtTimestamp
        ..mediaUrl = m.mediaUrl
        ..readAt = m.readAtTimestamp,
      ).toList();
      
      await _saveMessagesAndUpdateLastMessageAt(messages);

      _logger.i('Successfully imported ${syncMessages.length} messages from sync');
    } catch (e) {
      _logger.e('Error importing messages from sync: $e');
    }
  }

  /// Handle incoming device sync request
  /// Exports messages and sends them back to the requesting device
  Future<void> handleDeviceSyncRequest(DeviceSyncRequest request) async {
    try {
      _logger.i('=== HANDLING SYNC REQUEST ===');
      _logger.i('From device: ${request.requestingDeviceId}');
      _logger.i('ConversationId: ${request.conversationId}');
      _logger.i('SinceTimestamp: ${request.sinceTimestamp}');
      _logger.i('ChunkSize: ${request.chunkSize}');
      
      // Check how many messages we have locally
      final totalLocalMessages = await _localStorage.getMessageCount();
      _logger.i('Total messages in local storage: $totalLocalMessages');
      
      final messages = await exportMessagesForSync(
        conversationId: request.conversationId,
        sinceTimestamp: request.sinceTimestamp,
        limit: request.chunkSize > 0 ? request.chunkSize : 500,
      );
      
      _logger.i('Messages to send: ${messages.length}');
      
      if (messages.isEmpty) {
        _logger.i('No messages to sync - sending empty response');
        // Send empty response to let the other device know sync is complete
        await WebSocketManager().sendDeviceSyncData(
          toDeviceId: request.requestingDeviceId,
          conversationId: request.conversationId,
          messages: [],
          chunkIndex: 0,
          totalChunks: 1,
          isLastChunk: true,
        );
        return;
      }
      
      // Split into chunks
      final chunkSize = request.chunkSize > 0 ? request.chunkSize : 100;
      final totalChunks = (messages.length / chunkSize).ceil();
      
      _logger.i('Sending ${messages.length} messages in $totalChunks chunks (chunkSize: $chunkSize)');
      
      for (var i = 0; i < totalChunks; i++) {
        final start = i * chunkSize;
        final end = (start + chunkSize > messages.length) ? messages.length : start + chunkSize;
        final chunk = messages.sublist(start, end);
        
        _logger.i('Sending chunk ${i + 1}/$totalChunks with ${chunk.length} messages');
        
        await WebSocketManager().sendDeviceSyncData(
          toDeviceId: request.requestingDeviceId,
          conversationId: request.conversationId,
          messages: chunk,
          chunkIndex: i,
          totalChunks: totalChunks,
          isLastChunk: i == totalChunks - 1,
        );
        
        // Small delay between chunks to avoid overwhelming
        if (i < totalChunks - 1) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }
      
      _logger.i('=== SYNC COMPLETE: Sent ${messages.length} messages in $totalChunks chunks ===');
    } catch (e, stackTrace) {
      _logger.e('Error handling sync request: $e');
      _logger.e('Stack trace: $stackTrace');
    }
  }

  /// Handle incoming sync data chunk
  Future<void> handleDeviceSyncData(DeviceSyncChunk chunk) async {
    try {
      _logger.i('Handling sync data chunk ${chunk.chunkIndex}/${chunk.totalChunks}');
      
      if (chunk.messages.isNotEmpty) {
        await importMessagesFromSync(chunk.messages);
      }
      
      if (chunk.isLastChunk) {
        _logger.i('Device sync completed');
      }
    } catch (e) {
      _logger.e('Error handling sync data: $e');
    }
  }

  String _messageTypeToString(DbModels.MessageSchemaMessageType type) {
    switch (type) {
      case DbModels.MessageSchemaMessageType.text:
        return 'text';
      case DbModels.MessageSchemaMessageType.image:
        return 'image';
      case DbModels.MessageSchemaMessageType.gif:
        return 'gif';
      case DbModels.MessageSchemaMessageType.file:
        return 'file';
      case DbModels.MessageSchemaMessageType.audio:
        return 'audio';
      case DbModels.MessageSchemaMessageType.video:
        return 'video';
    }
  }

  DbModels.MessageSchemaMessageType _stringToMessageType(String type) {
    switch (type.toLowerCase()) {
      case 'text':
        return DbModels.MessageSchemaMessageType.text;
      case 'image':
        return DbModels.MessageSchemaMessageType.image;
      case 'gif':
        return DbModels.MessageSchemaMessageType.gif;
      case 'file':
        return DbModels.MessageSchemaMessageType.file;
      case 'audio':
        return DbModels.MessageSchemaMessageType.audio;
      case 'video':
        return DbModels.MessageSchemaMessageType.video;
      default:
        return DbModels.MessageSchemaMessageType.text;
    }
  }

  /// Dispose resources
  void dispose() {
    _apiClient.dispose();
  }
}
