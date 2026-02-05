import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:talktime/core/navigation_manager.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/chat/data/conversation_service.dart';
import 'package:talktime/features/chat/data/message_service.dart';
import 'package:talktime/features/chat/presentation/pages/message_list_page.dart';
import 'package:talktime/features/chat/presentation/pages/create_conversation.dart';
import 'package:talktime/features/chat/presentation/pages/create_group_chat.dart';
import 'package:talktime/features/saved_messages/presentation/pages/saved_messages_page.dart';
import 'package:talktime/features/settings/presentation/pages/settings_page.dart';
import 'package:talktime/shared/models/conversation.dart';
import 'package:talktime/shared/models/message.dart';
import 'package:talktime/shared/models/user.dart';

/// Responsive split view: on wide screens (>=768px) shows chats on left
/// and messages on right. On narrow screens, behaves like the regular chat list.
class ChatSplitView extends StatefulWidget {
  const ChatSplitView({super.key});

  @override
  State<ChatSplitView> createState() => _ChatSplitViewState();
}

class _ChatSplitViewState extends State<ChatSplitView>
    with WidgetsBindingObserver {
  late Future<List<Conversation>> _conversationsFuture;
  late String _myId = '';
  late Timer _timer;
  final Logger _logger = Logger(output: ConsoleOutput());
  final Map<String, Message> _lastMessageMap = {};

  // Currently selected conversation for split view
  Conversation? _selectedConversation;
  // Track which panel to show when no conversation is selected
  String? _rightPanelOverride; // 'saved', 'settings', null

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

  bool get _isWideScreen =>
      MediaQuery.of(context).size.width >= 768;

  @override
  Widget build(BuildContext context) {
    if (_isWideScreen) {
      return _buildSplitView();
    } else {
      return _buildMobileView();
    }
  }

  Widget _buildSplitView() {
    return Scaffold(
      body: Row(
        children: [
          // Left panel - Chat list
          SizedBox(
            width: 360,
            child: _buildChatListPanel(),
          ),
          // Divider
          VerticalDivider(width: 1, thickness: 1),
          // Right panel - Messages or placeholder
          Expanded(
            child: _buildRightPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileView() {
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
      body: _buildConversationList(),
      floatingActionButton: _buildFABs(),
    );
  }

  Widget _buildChatListPanel() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Talktime'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              if (_isWideScreen) {
                setState(() {
                  _selectedConversation = null;
                  _rightPanelOverride = 'settings';
                });
              } else {
                _openSettings();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Saved Messages entry
          _buildSavedMessagesEntry(),
          const Divider(height: 1),
          // Conversations list
          Expanded(child: _buildConversationList()),
        ],
      ),
      floatingActionButton: _buildFABs(),
    );
  }

  Widget _buildSavedMessagesEntry() {
    final isSelected =
        _rightPanelOverride == 'saved' && _selectedConversation == null;

    return Material(
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
          : null,
      child: ListTile(
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
        onTap: () {
          if (_isWideScreen) {
            setState(() {
              _selectedConversation = null;
              _rightPanelOverride = 'saved';
            });
          } else {
            NavigationManager().openSavedMessages();
          }
        },
      ),
    );
  }

  Widget _buildConversationList() {
    return FutureBuilder<List<Conversation>>(
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
          return const Center(child: Text('Start a new conversation'));
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

            final isSelected = _selectedConversation?.id == convo.id;

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: isSelected
                  ? Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withOpacity(0.3)
                  : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
                      : Theme.of(context).dividerColor.withOpacity(0.2),
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
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    name.isEmpty ? "?" : name[0].toUpperCase(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                  ),
                ),
                title: Text(
                  name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                subtitle: Text(
                  lastMessage.content,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatTimeAgo(lastMessage.sentAt),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.6),
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
    );
  }

  Widget _buildRightPanel() {
    if (_rightPanelOverride == 'saved' && _selectedConversation == null) {
      return const SavedMessagesPage();
    }
    if (_rightPanelOverride == 'settings' && _selectedConversation == null) {
      return const SettingsPage();
    }
    if (_selectedConversation != null) {
      return MessageListPage(
        key: ValueKey(_selectedConversation!.id),
        conversation: _selectedConversation!,
      );
    }

    // Placeholder when nothing is selected
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.15),
          ),
          const SizedBox(height: 16),
          Text(
            'Select a chat to start messaging',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFABs() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FloatingActionButton(
          heroTag: "NewGroup",
          child: const Icon(Icons.group),
          onPressed: () => _createGroup(),
        ),
        const SizedBox(height: 8),
        FloatingActionButton(
          heroTag: "NewConversation",
          child: const Icon(Icons.edit),
          onPressed: () => _createConversation(),
        ),
      ],
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
    final auth = AuthService();
    final user = await auth.getCurrentUser();
    conversation.participants?.sort((a, b) {
      if (a.id == user.id) return 1;
      if (b.id == user.id) return -1;
      return 0;
    });

    if (!mounted) return;

    if (_isWideScreen) {
      setState(() {
        _selectedConversation = conversation;
        _rightPanelOverride = null;
      });
    } else {
      NavigationManager().openMessagesList(conversation);
    }
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
