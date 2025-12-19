import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:talktime/features/chat/data/conversation_service.dart';
import 'package:talktime/shared/models/conversation.dart';
import 'package:talktime/features/call/presentation/pages/call_page.dart';
import 'package:talktime/features/chat/presentation/pages/message_list_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  late Future<List<Conversation>> _conversationsFuture;

  @override
  void initState() {
    super.initState();
    _conversationsFuture = ConversationService().getConversations();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.video_call),
            onPressed: () => _startNewCall(context),
          ),
        ],
      ),
      body: FutureBuilder<List<Conversation>>(
        future: _conversationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final conversations = snapshot.data!;
          if (conversations.isEmpty) {
            return Center(child: Text('Start a new conversation'));
          }

          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final convo = conversations[index];
              return ListTile(
                leading: CircleAvatar(child: Text(convo.displayTitle)),
                title: Text(convo.displayTitle),
                subtitle: Text(convo.displaySubtitle),
                trailing: Text(convo.lastMessageAt ?? ''),
                onTap: () => _openChat(context, convo),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: "ChatsList",
        child: const Icon(Icons.edit),
        onPressed: () => _createGroup(context),
      ),
    );
  }

  void _openChat(BuildContext context, Conversation conversation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MessageListPage(conversation: conversation),
      ),
    );
  }

  void _createGroup(BuildContext context) {
    // TODO: Show group creation dialog
  }

  void _startNewCall(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CallPage(
          isOutgoing: true,
          peerName: 'Alex',
          peerId: 'user-id-here', // Replace with actual user ID
          callType: CallType.video,
        ),
      ),
    );
  }
}
