import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/shared/models/conversation.dart';
import 'package:logger/logger.dart';

/// Service for managing conversations (chats)
class ConversationService {
  final ApiClient _apiClient = ApiClient();
  final Logger _logger = Logger();

  /// Get all conversations for the current user
  Future<List<Conversation>> getConversations() async {
    try {
      _logger.i('Fetching conversations');
      final response = await _apiClient.get(ApiConstants.conversations);

      final List conversationsJson = response['data'] as List;
      final conversations = conversationsJson
          .map((json) => Conversation.fromJson(json as Map<String, dynamic>))
          .toList();

      _logger.i('Fetched ${conversations.length} conversations');
      return conversations;
    } catch (e) {
      _logger.e('Error fetching conversations: $e');
      rethrow;
    }
  }

  /// Get a specific conversation by ID
  Future<Conversation> getConversationById(String id) async {
    try {
      _logger.i('Fetching conversation: $id');
      final response = await _apiClient.get(ApiConstants.conversationById(id));

      return Conversation.fromJson(response['data'] as Map<String, dynamic>);
    } catch (e) {
      _logger.e('Error fetching conversation $id: $e');
      rethrow;
    }
  }

  /// Create a new direct conversation (1-on-1 chat)
  Future<Conversation> createDirectConversation(String otherUserId) async {
    try {
      _logger.i('Creating direct conversation with user: $otherUserId');
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
      _logger.i('Created direct conversation: ${conversation.id}');
      return conversation;
    } catch (e) {
      _logger.e('Error creating direct conversation: $e');
      rethrow;
    }
  }

  /// Create a new group conversation
  Future<Conversation> createGroup(List<String> userIds, String name) async {
    try {
      _logger.i('Creating group conversation: $name');
      final response = await _apiClient.post(
        ApiConstants.conversations,
        body: {'type': 'group', 'name': name, 'participantIds': userIds},
      );

      final conversation = Conversation.fromJson(
        response['data'] as Map<String, dynamic>,
      );
      _logger.i('Created group conversation: ${conversation.id}');
      return conversation;
    } catch (e) {
      _logger.e('Error creating group conversation: $e');
      rethrow;
    }
  }

  /// Update conversation (rename group)
  Future<Conversation> updateConversation(String id, String name) async {
    try {
      _logger.i('Updating conversation $id with name: $name');
      await _apiClient.put(
        ApiConstants.conversationById(id),
        body: {'name': name},
      );

      // Fetch updated conversation
      return await getConversationById(id);
    } catch (e) {
      _logger.e('Error updating conversation $id: $e');
      rethrow;
    }
  }

  /// Delete a conversation
  Future<void> deleteConversation(String id) async {
    try {
      _logger.i('Deleting conversation: $id');
      await _apiClient.delete(ApiConstants.conversationById(id));
      _logger.i('Successfully deleted conversation: $id');
    } catch (e) {
      _logger.e('Error deleting conversation $id: $e');
      rethrow;
    }
  }

  /// Add a participant to a group conversation
  Future<void> addParticipant(String conversationId, String userId) async {
    try {
      _logger.i('Adding user $userId to conversation $conversationId');
      await _apiClient.post(
        ApiConstants.addParticipant(conversationId),
        body: {'userId': userId},
      );
      _logger.i('Successfully added participant');
    } catch (e) {
      _logger.e('Error adding participant: $e');
      rethrow;
    }
  }

  /// Remove a participant from a group conversation
  Future<void> removeParticipant(String conversationId, String userId) async {
    try {
      _logger.i('Removing user $userId from conversation $conversationId');
      await _apiClient.delete(
        ApiConstants.removeParticipant(conversationId, userId),
      );
      _logger.i('Successfully removed participant');
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
