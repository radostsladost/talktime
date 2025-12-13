import 'package:talktime/shared/models/message.dart';
import 'package:talktime/shared/models/user.dart';

/*
class MessageService {
  final ApiClient _apiClient = ApiClient();

  Future<List<Message>> getMessages(String conversationId) async {
    final response = await _apiClient.get(
      '${ApiConstants.messages}?conversationId=$conversationId',
    );
    final List messagesJson = response['data'] as List;
    return messagesJson.map((json) => Message.fromJson(json)).toList();
  }

  Future<Message> sendMessage(String conversationId, String content) async {
    final response = await _apiClient.post(
      ApiConstants.messages,
      body: {'conversationId': conversationId, 'content': content},
    );
    return Message.fromJson(response['data']);
  }
}
*/

/* MOCK */
class MessageService {
  // Simulate conversation history
  final Map<String, List<Message>> _mockMessages = {
    '1': [
      Message(
        id: 'm1',
        conversationId: '1',
        sender: const User(id: 'u1', username: 'You'),
        content: 'Hey Alex!',
        sentAt: '2025-12-08T10:00:00Z',
      ),
      Message(
        id: 'm2',
        conversationId: '1',
        sender: const User(id: 'u2', username: 'Alex'),
        content: 'Hello! How are you?',
        sentAt: '2025-12-08T10:01:00Z',
      ),
      Message(
        id: 'm3',
        conversationId: '1',
        sender: const User(id: 'u1', username: 'You'),
        content: 'Doing well! Want to hop on a quick call?',
        sentAt: '2025-12-08T10:02:00Z',
      ),
    ],
    '2': [
      Message(
        id: 'm10',
        conversationId: '2',
        sender: const User(id: 'u3', username: 'Sam'),
        content: 'Team standup at 3?',
        sentAt: '2025-12-08T09:00:00Z',
      ),
    ],
  };

  Future<List<Message>> getMessages(String conversationId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _mockMessages[conversationId] ?? [];
  }

  Future<Message> sendMessage(String conversationId, String content) async {
    await Future.delayed(const Duration(milliseconds: 200));

    final newMessage = Message(
      id: 'mock_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: conversationId,
      sender: const User(id: 'u1', username: 'You'),
      content: content,
      sentAt: DateTime.now().toIso8601String(),
    );

    // Add to mock list
    _mockMessages.update(
      conversationId,
      (list) => [...list, newMessage],
      ifAbsent: () => [newMessage],
    );

    return newMessage;
  }
}
