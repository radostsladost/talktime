import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/chat/data/local_conversation_storage.dart';
import 'package:talktime/shared/models/conversation.dart';
import 'package:talktime/shared/models/user.dart';
import 'package:logger/logger.dart';

/// Service for managing conversations (chats)
class ConversationService {
  final ApiClient _apiClient = ApiClient();
  final Logger _logger = Logger(output: ConsoleOutput());
  final LocalConversationStorage _localStorage = LocalConversationStorage();

  /// Search user
  Future<List<User>> searchUser(String query) async {
    try {
      final response = await _apiClient.post(
        ApiConstants.searchUserByQuery(query),
      );

      final List usersJson = response['data'] as List;
      final users = usersJson
          .map((json) => User.fromJson(json as Map<String, dynamic>))
          .toList();

      // _logger.d('Fetched ${users.length} conversations');
      return users;
    } catch (e) {
      _logger.e('Error fetching conversations: $e');
      rethrow;
    }
  }

  /// Get all conversations for the current user
  Future<List<Conversation>> getConversations() async {
    try {
      // First try to get from local storage
      try {
        final localConversations = await _localStorage.getConversations();
        if (localConversations.isNotEmpty) {
          return localConversations;
        }
      } catch (e) {
        _logger.w('No local conversations found, fetching from API: $e');
      }

      await AuthService().refreshTokenIfNeeded();

      _logger.d('Fetching conversations from API');
      final response = await _apiClient.get(ApiConstants.conversations);

      final List conversationsJson = response['data'] as List;
      final conversations = conversationsJson
          .map((json) => Conversation.fromJson(json as Map<String, dynamic>))
          .toList();

      // Save to local storage
      await _localStorage.saveConversations(conversations);

      _logger.d('Fetched ${conversations.length} conversations');
      return conversations;
    } catch (e) {
      _logger.e('Error fetching conversations: $e');
      rethrow;
    }
  }

  /// Get a specific conversation by ID
  Future<Conversation> getConversationById(String id) async {
    try {
      // First try to get from local storage
      try {
        final localConversation = await _localStorage
            .getConversationByExternalId(id);
        if (localConversation != null) {
          return localConversation;
        }
      } catch (e) {
        _logger.w('No local conversation found for $id, fetching from API: $e');
      }

      _logger.d('Fetching conversation: $id');
      final response = await _apiClient.get(ApiConstants.conversationById(id));

      final conversation = Conversation.fromJson(
        response['data'] as Map<String, dynamic>,
      );

      // Save to local storage
      await _localStorage.saveConversation(conversation);

      return conversation;
    } catch (e) {
      _logger.e('Error fetching conversation $id: $e');
      rethrow;
    }
  }

  /// Create a new direct conversation (1-on-1 chat)
  Future<Conversation> createDirectConversation(String otherUserId) async {
    try {
      _logger.d('Creating direct conversation with user: $otherUserId');
      final response = await _apiClient.post(
        ApiConstants.conversations,
        body: {
          'type': 'direct',
          'participantIds': [otherUserId],
        },
      );

      final conversation = Conversation.fromJson(
        response['data'] as Map<String, dynamic>,
      );

      // Save to local storage
      await _localStorage.saveConversation(conversation);

      _logger.d('Created direct conversation: ${conversation.id}');
      return conversation;
    } catch (e) {
      _logger.e('Error creating direct conversation: $e');
      rethrow;
    }
  }

  /// Create a new group conversation
  Future<Conversation> createGroup(List<String> userIds, String name) async {
    try {
      _logger.d('Creating group conversation: $name');
      final response = await _apiClient.post(
        ApiConstants.conversations,
        body: {'type': 'group', 'name': name, 'participantIds': userIds},
      );

      final conversation = Conversation.fromJson(
        response['data'] as Map<String, dynamic>,
      );

      // Save to local storage
      await _localStorage.saveConversation(conversation);

      _logger.d('Created group conversation: ${conversation.id}');
      return conversation;
    } catch (e) {
      _logger.e('Error creating group conversation: $e');
      rethrow;
    }
  }

  /// Update conversation (rename group)
  Future<Conversation> updateConversation(String id, String name) async {
    try {
      _logger.d('Updating conversation $id with name: $name');
      await _apiClient.put(
        ApiConstants.conversationById(id),
        body: {'name': name},
      );

      // Fetch updated conversation
      final conversation = await getConversationById(id);

      // The getConversationById already saves to local storage
      return conversation;
    } catch (e) {
      _logger.e('Error updating conversation $id: $e');
      rethrow;
    }
  }

  /// Delete a conversation
  Future<void> deleteConversation(String id) async {
    try {
      _logger.d('Deleting conversation: $id');
      await _apiClient.delete(ApiConstants.conversationById(id));

      // Also delete from local storage
      await _localStorage.deleteConversation(id);

      _logger.d('Successfully deleted conversation: $id');
    } catch (e) {
      _logger.e('Error deleting conversation $id: $e');
      rethrow;
    }
  }

  /// Add a participant to a group conversation
  Future<void> addParticipant(String conversationId, String userId) async {
    try {
      _logger.d('Adding user $userId to conversation $conversationId');
      await _apiClient.post(
        ApiConstants.addParticipant(conversationId),
        body: {'userId': userId},
      );
      _logger.d('Successfully added participant');
    } catch (e) {
      _logger.e('Error adding participant: $e');
      rethrow;
    }
  }

  /// Remove a participant from a group conversation
  Future<void> removeParticipant(String conversationId, String userId) async {
    try {
      _logger.d('Removing user $userId from conversation $conversationId');
      await _apiClient.delete(
        ApiConstants.removeParticipant(conversationId, userId),
      );
      _logger.d('Successfully removed participant');
    } catch (e) {
      _logger.e('Error removing participant: $e');
      rethrow;
    }
  }

  /// Dispose resources
  void dispose() {
    _apiClient.dispose();
  }
}
