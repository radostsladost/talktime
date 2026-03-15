import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:talktime/core/config/environment.dart';
import 'package:talktime/core/navigation_manager.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/call/data/call_service.dart';
import 'package:talktime/features/call/presentation/pages/conference_page.dart';
import 'package:talktime/features/chat/data/conversation_service.dart';
import 'package:talktime/features/chat/data/message_service.dart';
import 'package:talktime/features/chat/presentation/pages/message_list_page.dart';
import 'package:talktime/features/chat/presentation/pages/create_conversation.dart';
import 'package:talktime/features/chat/presentation/pages/create_group_chat.dart';
import 'package:talktime/features/saved_messages/presentation/pages/saved_messages_page.dart';
import 'package:talktime/features/call/data/incoming_call_manager.dart';
import 'package:talktime/features/chat/data/conversation_service.dart';
import 'package:talktime/features/settings/presentation/pages/settings_page.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
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
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late Future<List<Conversation>> _conversationsFuture;
  List<Conversation>? _cachedConversations;
  late String _myId = '';
  late Timer _timer;
  final Logger _logger = Logger(output: ConsoleOutput());
  final Map<String, Message> _lastMessageMap = {};
  final Map<String, int> _unreadCountMap = {};

  // Currently selected conversation for split view
  Conversation? _selectedConversation;
  // Track which panel to show when no conversation is selected
  String? _rightPanelOverride; // 'saved', 'settings', null
  // When call is shown in right panel (desktop)
  String? _callRoomId;
  Conversation? _callConversation;
  StreamSubscription<CallState>? _callStateSubscription;
  TabController? _callPanelTabController;
  // When user accepts an incoming call on wide screen, open chat+call panel instead of full-screen
  String? _pendingAcceptedCallRoomId;
  // Conference participant updates (to refresh in-call avatars on chat list)
  void Function(String, ConferenceParticipant, String)?
  _conferenceParticipantCallback;

  void _startCallInPanel(Conversation conversation) {
    setState(() {
      _callRoomId = conversation.id;
      _callConversation = conversation;
      _selectedConversation = conversation;
      _rightPanelOverride = null;
      _callPanelTabController ??= TabController(length: 2, vsync: this);
    });
    _requestParticipantsNowAndSoon(conversation.id);
  }

  void _disposeCallPanel() {
    _callPanelTabController?.dispose();
    _callPanelTabController = null;
    _callRoomId = null;
    _callConversation = null;
  }

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

    // When call ends, clear in-panel call state
    _callStateSubscription = CallService().callStateStream.listen((state) {
      if (state == CallState.idle && mounted) {
        setState(() => _disposeCallPanel());
        return;
      }

      // Proactively refresh room participants during call connect/join to reduce UI delay.
      final roomId = CallService().currentRoomId;
      if (roomId != null) {
        _requestParticipantsNowAndSoon(roomId);
        if (mounted) setState(() {});
      }
    });

    // On wide screen, accept opens chat+call panel instead of full-screen conference
    IncomingCallManager().setOnCallAccepted((callId, roomId) {
      if (!mounted) return false;
      if (MediaQuery.of(context).size.width < 768) return false;
      if (roomId == null) return false;
      setState(() {
        _pendingAcceptedCallRoomId = roomId;
      });
      return true;
    });

    // Listen for conference participant join/leave so chat list in-call avatars update
    _conferenceParticipantCallback = (_, __, ___) {
      if (mounted) setState(() {});
    };
    WebSocketManager().onConferenceParticipant(_conferenceParticipantCallback!);

    // iOS: show modal if notification permission is not granted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowNotificationPermissionDialog();
    });
  }

  Future<void> _maybeShowNotificationPermissionDialog() async {
    if (kIsWeb || !Platform.isIOS || !mounted) return;
    final shouldPrompt = await AuthService()
        .shouldPromptForNotificationPermission();
    if (!shouldPrompt || !mounted) return;
    final status = await AuthService().getNotificationPermissionStatus();
    if (status == null || !mounted) return;
    if (status != AuthorizationStatus.denied &&
        status != AuthorizationStatus.notDetermined)
      return;

    if (!mounted) return;
    final isDenied = status == AuthorizationStatus.denied;

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(
          isDenied ? 'Notifications are off' : 'Enable notifications',
        ),
        content: Text(
          isDenied
              ? 'To receive calls and messages when the app is in the background, open Settings and allow notifications for ${Environment.appName}.'
              : 'Allow ${Environment.appName} to send you notifications for calls and new messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (isDenied) {
                await openAppSettings();
              } else {
                await AuthService().registerFirebaseToken();
              }
            },
            child: Text(isDenied ? 'Open Settings' : 'Enable'),
          ),
        ],
      ),
    );
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
      final unreadCount = await MessageService().getUnreadCount(
        conversation.id,
      );
      if (lastMessage != null) _lastMessageMap[conversation.id] = lastMessage;
      _unreadCountMap[conversation.id] = unreadCount;
    }
    setState(() {});
    // Request voice-call participants for each chat so we can show "in call" avatars
    WebSocketManager().onConnectionRestored(() {
      for (final c in conversations) {
        WebSocketManager().requestRoomParticipants(c.id);
      }
    });
  }

  void _requestParticipantsNowAndSoon(String roomId) {
    final ws = WebSocketManager();
    ws.requestRoomParticipants(roomId);
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      ws.requestRoomParticipants(roomId);
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      ws.requestRoomParticipants(roomId);
    });
  }

  /// Small avatars row for "in voice call" indicator under chat name
  static const double _inCallAvatarSize = 18;
  static const double _inCallAvatarOverlapPx = 5;

  Widget _buildInCallAvatars(
    BuildContext context,
    List<ConferenceParticipant> participants,
  ) {
    const maxAvatars = 4;
    final show = participants.take(maxAvatars).toList();
    final extra = participants.length > maxAvatars
        ? participants.length - maxAvatars
        : 0;
    final theme = Theme.of(context);
    final step = _inCallAvatarSize - _inCallAvatarOverlapPx;
    final stackWidth = show.isEmpty
        ? 0.0
        : (show.length - 1) * step + _inCallAvatarSize;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: stackWidth,
          height: _inCallAvatarSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < show.length; i++)
                Positioned(
                  left: i * step,
                  child: Container(
                    width: _inCallAvatarSize,
                    height: _inCallAvatarSize,
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
                ),
            ],
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
        Icon(Icons.mic, size: 14, color: theme.colorScheme.primary),
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

  Widget _buildInCallIndicatorOnly(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.mic, size: 14, color: theme.colorScheme.primary),
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

  /// Refresh chat list from local storage so order/last message update in real time after send/receive.
  void _refreshConversationList() {
    if (!mounted) return;
    setState(() {
      _conversationsFuture = ConversationService().getConversations();
    });
    _conversationsFuture
        .then((_) async {
          await _fetchLastMessages();
          if (mounted) setState(() {});
        })
        .catchError((e) {
          _logger.e('Error refreshing conversation list: $e');
        });
  }

  bool get _isWideScreen => MediaQuery.of(context).size.width >= 768;

  @override
  Widget build(BuildContext context) {
    // After accepting an incoming call on wide screen, open conversation and call in panel (one-shot)
    if (_pendingAcceptedCallRoomId != null) {
      final roomId = _pendingAcceptedCallRoomId!;
      _pendingAcceptedCallRoomId = null; // clear so we only schedule once
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ConversationService()
            .getConversationById(roomId)
            .then((conv) {
              if (!mounted) return;
              setState(() => _startCallInPanel(conv));
            })
            .catchError((e) {
              _logger.e('Failed to load conversation for accepted call: $e');
              if (!mounted) return;
              setState(() {});
            });
      });
    }

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
          SizedBox(width: 360, child: _buildChatListPanel()),
          // Divider
          VerticalDivider(width: 1, thickness: 1),
          // Right panel - Messages or placeholder
          Expanded(child: _buildRightPanel()),
        ],
      ),
    );
  }

  Widget _buildMobileView() {
    return Scaffold(
      appBar: AppBar(
        title: const Text(Environment.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _openSettings(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_callRoomId != null && _callConversation != null)
            _buildInCallBanner(),
          _buildSavedMessagesEntry(),
          Expanded(child: _buildConversationList()),
        ],
      ),
      floatingActionButton: _buildFABs(),
    );
  }

  Widget _buildChatListPanel() {
    return Scaffold(
      appBar: AppBar(
        title: const Text(Environment.appName),
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
          // In-call banner: we're in a call with this chat, tap to return
          if (_callRoomId != null && _callConversation != null)
            _buildInCallBanner(),
          // Saved Messages entry
          _buildSavedMessagesEntry(),
          // Conversations list
          Expanded(child: _buildConversationList()),
        ],
      ),
      floatingActionButton: _buildFABs(),
    );
  }

  Widget _buildInCallBanner() {
    final name =
        _callConversation?.displayTitle ??
        _callConversation?.participants
            ?.firstWhere(
              (p) => p.id != _myId,
              orElse: () => User(id: '', username: ''),
            )
            .username ??
        'this chat';
    return Material(
      color: Colors.green.shade50,
      child: InkWell(
        onTap: () {
          if (_isWideScreen) {
            setState(() {
              _selectedConversation = _callConversation;
              _rightPanelOverride = null;
            });
          } else if (_callRoomId != null) {
            NavigationManager().openConference(
              _callRoomId!,
              [],
              conversation: _callConversation,
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.videocam, color: Colors.green.shade700, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'In a call with $name — tap to return',
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.green.shade700),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSavedMessagesEntry() {
    final isSelected =
        _rightPanelOverride == 'saved' && _selectedConversation == null;

    return Material(
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.35)
          : Colors.transparent,
      child: InkWell(
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor:
                        Theme.of(context).colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.bookmark, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Saved Messages',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Your bookmarks and notes',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(
              height: 1,
              thickness: 0.5,
              indent: 72,
              color: Theme.of(context).dividerColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList() {
    return FutureBuilder<List<Conversation>>(
      future: _conversationsFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final list = snapshot.data!;
          if (_cachedConversations != list) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _cachedConversations = list);
            });
          }
        }
        // Use cached list while loading so we don't replace the list with a loader
        final conversations = snapshot.data ?? _cachedConversations;
        if (conversations == null || conversations.isEmpty) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          return const Center(child: Text('Start a new conversation'));
        }
        if (snapshot.hasError && _cachedConversations == null) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        return ListView.builder(
          itemCount: conversations.length,
          padding: EdgeInsets.zero,
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
            final unreadCount = _unreadCountMap[convo.id] ?? 0;
            final inCallParticipants = WebSocketManager()
                .getConferenceParticipants(convo.id);
            final isCurrentCallRoom =
                CallService().currentRoomId == convo.id &&
                CallService().currentState != CallState.idle;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Material(
                  color: isSelected
                      ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withOpacity(0.35)
                      : Colors.transparent,
                  child: InkWell(
                    onTap: () => _openChat(convo),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer,
                            child: Text(
                              name.isEmpty ? '?' : name[0].toUpperCase(),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Content
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Row 1: name + time
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: unreadCount > 0
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _formatTimeAgo(lastMessage.sentAt),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: unreadCount > 0
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                : Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                            fontWeight: unreadCount > 0
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                // Row 2: in-call + preview + unread badge
                                if (inCallParticipants.isNotEmpty ||
                                    isCurrentCallRoom)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: inCallParticipants.isNotEmpty
                                        ? _buildInCallAvatars(
                                            context,
                                            inCallParticipants,
                                          )
                                        : _buildInCallIndicatorOnly(context),
                                  ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        lastMessage.content,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: unreadCount > 0
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .onSurface
                                                  : Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                              fontWeight: unreadCount > 0
                                                  ? FontWeight.w500
                                                  : FontWeight.normal,
                                            ),
                                      ),
                                    ),
                                    if (unreadCount > 0)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          constraints: const BoxConstraints(
                                            minWidth: 22,
                                            minHeight: 22,
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            unreadCount > 99
                                                ? '99+'
                                                : '$unreadCount',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onPrimary,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11,
                                                ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Indented divider aligned with text content
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 72, // 16 padding + 56 avatar
                  color: Theme.of(context).dividerColor,
                ),
              ],
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
    // Desktop: call + chat in right panel when this conversation is in a call
    if (_isWideScreen &&
        _callRoomId != null &&
        _selectedConversation?.id == _callRoomId &&
        _callConversation != null) {
      return _buildCallAndChatPanel();
    }
    if (_selectedConversation != null) {
      return MessageListPage(
        key: ValueKey(_selectedConversation!.id),
        conversation: _selectedConversation!,
        onExit: () {
          setState(() {
            _selectedConversation = null;
          });
        },
        onStartCallInPanel: _isWideScreen ? (c) => _startCallInPanel(c) : null,
        onConversationActivity: _refreshConversationList,
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
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallAndChatPanel() {
    if (_callConversation == null || _callPanelTabController == null) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        TabBar(
          controller: _callPanelTabController,
          labelColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.videocam), text: 'Call'),
            Tab(icon: Icon(Icons.chat), text: 'Chat'),
          ],
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _callPanelTabController,
            children: [
              ConferencePage(
                key: ValueKey('conf_${_callConversation!.id}'),
                roomId: _callRoomId!,
                initialParticipants: [],
                conversation: _callConversation,
              ),
              MessageListPage(
                key: ValueKey(_callConversation!.id),
                conversation: _callConversation!,
                onReturnToCall: () => _callPanelTabController?.animateTo(0),
                onConversationActivity: _refreshConversationList,
                onExit: () {
                  setState(() {
                    _selectedConversation = null;
                    _disposeCallPanel();
                  });
                },
              ),
            ],
          ),
        ),
      ],
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
    // Sort using the already-cached _myId – no network call needed.
    if (_myId.isNotEmpty) {
      conversation.participants?.sort((a, b) {
        if (a.id == _myId) return 1;
        if (b.id == _myId) return -1;
        return 0;
      });
    }

    if (!mounted) return;

    if (_isWideScreen) {
      setState(() {
        _selectedConversation = conversation;
        _rightPanelOverride = null;
      });
      // Refresh unread count after a short delay so badge updates once messages are marked read
      Future.delayed(const Duration(milliseconds: 1500), () async {
        if (!mounted || _selectedConversation?.id != conversation.id) return;
        final count = await MessageService().getUnreadCount(conversation.id);
        if (mounted) setState(() => _unreadCountMap[conversation.id] = count);
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
    if (_conferenceParticipantCallback != null) {
      WebSocketManager().removeConferenceParticipantCallback(
        _conferenceParticipantCallback!,
      );
    }
    _callPanelTabController?.dispose();
    _callStateSubscription?.cancel();
    _timer.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
