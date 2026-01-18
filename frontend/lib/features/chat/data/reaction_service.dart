import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/shared/models/message.dart';
import 'package:logger/logger.dart';

/// Service for managing message reactions
class ReactionService {
  final ApiClient _apiClient = ApiClient();
  final Logger _logger = Logger(output: ConsoleOutput());

  /// Get reactions for a message
  Future<List<Reaction>> getReactions(
    String messageId,
    String conversationId,
  ) async {
    try {
      final response = await _apiClient.get(
        ApiConstants.getReactions(messageId, conversationId),
      );

      final List reactionsJson = response['data'] as List;
      return reactionsJson
          .map((json) => Reaction.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.e('Error fetching reactions: $e');
      rethrow;
    }
  }

  /// Add a reaction to a message
  Future<Reaction> addReaction(
    String messageId,
    String emoji,
    String conversationId,
  ) async {
    try {
      _logger.i('Adding reaction $emoji to message: $messageId');
      final response = await _apiClient.post(
        ApiConstants.reactions,
        body: {
          'messageId': messageId,
          'emoji': emoji,
          'conversationId': conversationId,
        },
      );

      return Reaction.fromJson(response['data'] as Map<String, dynamic>);
    } catch (e) {
      _logger.e('Error adding reaction: $e');
      rethrow;
    }
  }

  /// Remove a reaction from a message
  Future<void> removeReaction(
    String messageId,
    String emoji,
    String conversationId,
  ) async {
    try {
      _logger.i('Removing reaction $emoji from message: $messageId');
      await _apiClient.delete(
        ApiConstants.reactions,
        body: {
          'messageId': messageId,
          'emoji': emoji,
          'conversationId': conversationId,
        },
      );
    } catch (e) {
      _logger.e('Error removing reaction: $e');
      rethrow;
    }
  }

  /// Toggle a reaction - add if not present, remove if present
  Future<void> toggleReaction(
    String messageId,
    String emoji,
    String currentUserId,
    List<Reaction> currentReactions,
    String conversationId,
  ) async {
    final hasReacted = currentReactions.any(
      (r) => r.emoji == emoji && r.userId == currentUserId,
    );

    if (hasReacted) {
      await removeReaction(messageId, emoji, conversationId);
    } else {
      await addReaction(messageId, emoji, conversationId);
    }
  }

  void dispose() {
    _apiClient.dispose();
  }
}
