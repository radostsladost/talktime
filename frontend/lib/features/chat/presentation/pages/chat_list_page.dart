import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/chat/data/conversation_service.dart';
import 'package:talktime/shared/models/conversation.dart';
import 'package:talktime/features/chat/presentation/pages/message_list_page.dart';
import 'package:talktime/features/chat/presentation/pages/create_chat.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage>
    with WidgetsBindingObserver {
  late Future<List<Conversation>> _conversationsFuture;
  late String _myId = '';
  late Timer _timer;
  final Logger _logger = Logger(output: ConsoleOutput());

  @override
  void initState() {
    super.initState();
    _conversationsFuture = ConversationService().getConversations();
    _myId = '';
    (AuthService().getCurrentUser()).then(
      (user) => setState(() {
        _myId = user.id;
      }),
    );

    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() {
        _conversationsFuture = ConversationService().getConversations();
      });
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App is reopened from the background
      _conversationsFuture = ConversationService().getConversations();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Talktime'),
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.video_call),
          //   onPressed: () => _startNewCall(context),
          // ),
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
              final name =
                  convo.displayTitle ??
                  convo.participants
                      ?.firstWhere((i) => i.id != _myId)
                      ?.username ??
                  convo.participants?.first?.username ??
                  "UNKNOWN";

              //print("MBError: " + name + " " + _myId);
              return ListTile(
                leading: CircleAvatar(child: Text(name)),
                title: Text(name),
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

  Future<void> _openChat(
    BuildContext context,
    Conversation conversation,
  ) async {
    final auth = new AuthService();
    final user = await auth.getCurrentUser();
    conversation.participants?.sort((a, b) {
      if (a.id == user.id) return 1;
      if (b.id == user.id) return -1;
      return 0;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MessageListPage(conversation: conversation),
      ),
    );
  }

  void _createGroup(BuildContext context) {
    // TODO: Show group creation dialog
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreateConferencePage()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
