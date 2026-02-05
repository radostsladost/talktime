import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:talktime/core/navigation_manager.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/chat/data/conversation_service.dart';
import 'package:talktime/features/chat/data/message_service.dart';
import 'package:talktime/features/chat/presentation/pages/create_group_chat.dart';
import 'package:talktime/shared/models/conversation.dart';
import 'package:talktime/shared/models/message.dart';
import 'package:talktime/shared/models/user.dart';

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
  final Map<String, Message> _lastMessageMap = {};

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
      _conversationsFuture
          .then((_) async {
            await _fetchLastMessages();
          })
          .then((_) async {
            await ConversationService().syncConversations();
          })
          .catchError((error) {
            _logger.e('Error fetching conversations $error');
          });
    });

    _conversationsFuture
        .then((_) async {
          await _fetchLastMessages();
        })
        .then((_) async {
          await ConversationService().syncConversations();
        })
        .catchError((error) {
          _logger.e('Error fetching conversations $error');
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App is reopened from the background
      _conversationsFuture = ConversationService().getConversations();
      _conversationsFuture
          .then((_) async {
            await ConversationService().syncConversations();
          })
          .then((_) async {
            await _fetchLastMessages();
          })
          .catchError((error) {
            _logger.e('Error fetching conversations $error');
          });
    }
  }

  Future<void> _fetchLastMessages() async {
    final conversations = await _conversationsFuture;
    for (final conversation in conversations) {
      final lastMessage = await MessageService().getLastMessage(
        conversation.id,
      );
      setState(() {
        if (lastMessage != null) _lastMessageMap[conversation.id] = lastMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Talktime'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _openSettings(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Saved Messages entry
          _buildSavedMessagesEntry(),
          const Divider(height: 1),
          // Conversations list
          Expanded(
            child: FutureBuilder<List<Conversation>>(
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
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemBuilder: (context, index) {
                    final convo = conversations[index];
                    final name =
                        convo.displayTitle ??
                        convo.participants
                            ?.firstWhere((i) => i.id != _myId)
                            ?.username ??
                        convo.participants?.first?.username ??
                        "UNKNOWN";
                    final lastMessage =
                        _lastMessageMap[convo.id] ??
                        Message(
                          id: '0',
                          content: convo.lastMessage ?? "",
                          conversationId: convo.id,
                          sender:
                              convo.participants?.first ??
                              User(id: '0', username: 'Unknown'),
                          sentAt: convo.lastMessageAt ?? "",
                        );

                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color:
                              Theme.of(context).dividerColor.withOpacity(0.2),
                        ),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withOpacity(0.1),
                          foregroundColor:
                              Theme.of(context).colorScheme.primary,
                          child: Text(
                            name.isEmpty ? "?" : name[0].toUpperCase(),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 18,
                                ),
                          ),
                        ),
                        title: Text(
                          name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        subtitle: Text(
                          lastMessage.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _formatTimeAgo(lastMessage.sentAt),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.6),
                                  ),
                            ),
                          ],
                        ),
                        onTap: () => _openChat(convo),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "NewGroup",
            child: const Icon(Icons.group),
            onPressed: () => _createGroup(),
          ),
          SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "NewConversation",
            child: const Icon(Icons.edit),
            onPressed: () => _createConversation(),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedMessagesEntry() {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      leading: CircleAvatar(
        backgroundColor:
            Theme.of(context).colorScheme.primary.withOpacity(0.1),
        foregroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.bookmark),
      ),
      title: Text(
        'Saved Messages',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      subtitle: Text(
        'Your bookmarks and notes',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      onTap: () => NavigationManager().openSavedMessages(),
    );
  }

  String _formatTimeAgo(String? isoString) {
    if (isoString == null) return '';
    try {
      final messageTime = DateTime.parse(isoString);
      final now = DateTime.now();
      final difference = now.difference(messageTime);

      if (difference.inSeconds < 60) return 'now';
      if (difference.inMinutes < 60) return '${difference.inMinutes}m';
      if (difference.inHours < 24) return '${difference.inHours}h';
      if (difference.inDays < 7) return '${difference.inDays}d';
      return '${messageTime.month}/${messageTime.day}';
    } catch (e) {
      return '';
    }
  }

  Future<void> _openChat(Conversation conversation) async {
    final auth = new AuthService();
    final user = await auth.getCurrentUser();
    conversation.participants?.sort((a, b) {
      if (a.id == user.id) return 1;
      if (b.id == user.id) return -1;
      return 0;
    });

    if (!mounted) return;

    NavigationManager().openMessagesList(conversation);
  }

  void _createConversation() {
    NavigationManager().openCreateConversation();
  }

  void _createGroup() {
    NavigationManager().openCreateGroup();
  }

  void _openSettings() {
    NavigationManager().openSettings();
  }

  @override
  void dispose() {
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
