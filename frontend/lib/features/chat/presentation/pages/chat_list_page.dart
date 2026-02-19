import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:talktime/core/navigation_manager.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
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
  void Function(String, ConferenceParticipant, String)? _conferenceParticipantCallback;

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

    _conferenceParticipantCallback = (_, __, ___) {
      if (mounted) setState(() {});
    };
    WebSocketManager().onConferenceParticipant(_conferenceParticipantCallback!);
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
    WebSocketManager().initialize().then((_) {
      for (final c in conversations) {
        WebSocketManager().requestRoomParticipants(c.id);
      }
    });
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
                    final inCallParticipants =
                        WebSocketManager().getConferenceParticipants(convo.id);

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
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (inCallParticipants.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: _buildInCallAvatars(
                                    context, inCallParticipants),
                              ),
                            Text(
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
                          ],
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

  static const double _inCallAvatarSize = 18;
  static const double _inCallAvatarOverlap = -5;

  Widget _buildInCallAvatars(
    BuildContext context,
    List<ConferenceParticipant> participants,
  ) {
    const maxAvatars = 4;
    final show = participants.take(maxAvatars).toList();
    final extra =
        participants.length > maxAvatars ? participants.length - maxAvatars : 0;
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < show.length; i++)
          Container(
            margin: EdgeInsets.only(
              left: i == 0 ? 0 : _inCallAvatarOverlap,
            ),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: theme.colorScheme.surface,
                width: 1.2,
              ),
            ),
            child: CircleAvatar(
              radius: _inCallAvatarSize / 2,
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              child: Text(
                (show[i].username.isNotEmpty
                    ? show[i].username[0].toUpperCase()
                    : '?'),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        if (extra > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              '+$extra',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        const SizedBox(width: 6),
        Icon(
          Icons.mic,
          size: 14,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 2),
        Text(
          'In call',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    if (_conferenceParticipantCallback != null) {
      WebSocketManager()
          .removeConferenceParticipantCallback(_conferenceParticipantCallback!);
    }
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
