import 'package:talktime/shared/models/conversation.dart';
import 'package:talktime/shared/models/user.dart';

class ConversationService {
  Future<List<Conversation>> getConversations() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return [
      Conversation(
        id: '1',
        type: ConversationType.direct,
        participants: [const User(id: 'u2', username: 'Alex')],
        lastMessage: 'Hey! Want to hop on a call?',
        lastMessageAt: '10:30 AM',
      ),
      Conversation(
        id: '2',
        type: ConversationType.group,
        name: 'Project Team',
        participants: [
          const User(id: 'u3', username: 'Sam'),
          const User(id: 'u4', username: 'Taylor'),
        ],
        lastMessage: 'Screen share at 3 PM',
        lastMessageAt: '9:15 AM',
      ),
    ];
  }
}