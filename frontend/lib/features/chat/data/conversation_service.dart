import 'package:talktime/core/network/api_client.dart';
import 'package:talktime/core/constants/api_constants.dart';
import 'package:talktime/shared/models/conversation.dart';
import 'package:talktime/shared/models/user.dart';

/*
class ConversationService {
  final ApiClient _apiClient = ApiClient();

  Future<List<Conversation>> getConversations() async {
    final response = await _apiClient.get(ApiConstants.conversations);
    final List conversationsJson = response['data'] as List;
    return conversationsJson
        .map((json) => Conversation.fromJson(json))
        .toList();
  }

  Future<Conversation> createGroup(List<String> userIds, String name) async {
    final response = await _apiClient.post(
      ApiConstants.conversations,
      body: {'type': 'group', 'name': name, 'participantIds': userIds},
    );
    return Conversation.fromJson(response['data']);
  }
}
*/

// MOCK
class ConversationService {
  final ApiClient _apiClient = ApiClient();

  Future<List<Conversation>> getConversations() async {
    final List<Conversation> _mock = [
      Conversation(
        id: 'c1',
        type: ConversationType.direct,
        name: 'DM',
        participants: [User(id: 'u1', username: 'John')],
        lastMessage: 'Hellow',
        lastMessageAt: DateTime.now().toString(),
      ),
      Conversation(
        id: 'c2',
        type: ConversationType.direct,
        name: 'DM',
        participants: [User(id: 'u1', username: 'Sanya')],
        lastMessage: 'Hellow',
        lastMessageAt: DateTime.now().toString(),
      ),
      Conversation(
        id: 'c3',
        type: ConversationType.direct,
        name: 'DM',
        participants: [User(id: 'u1', username: 'Vadim')],
        lastMessage: 'Hellow',
        lastMessageAt: DateTime.now().toString(),
      ),
      Conversation(
        id: 'c4',
        type: ConversationType.direct,
        name: 'DM',
        participants: [User(id: 'u1', username: 'Sergay')],
        lastMessage: 'Hellow',
        lastMessageAt: DateTime.now().toString(),
      ),
    ];
    return _mock;
  }

  Future<Conversation> createGroup(List<String> userIds, String name) async {
    final response = await _apiClient.post(
      ApiConstants.conversations,
      body: {'type': 'group', 'name': name, 'participantIds': userIds},
    );
    return Conversation.fromJson(response['data']);
  }
}
