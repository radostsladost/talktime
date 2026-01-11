import 'dart:async';
import 'dart:io' show Platform;

import 'package:collection/collection.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji_picker;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/call/presentation/pages/conference_page.dart';
import 'package:talktime/features/chat/data/message_service.dart';
import 'package:talktime/shared/models/conversation.dart';
import 'package:talktime/shared/models/message.dart';
import 'package:talktime/shared/models/user.dart';

class MessageListPage extends StatefulWidget {
  final Conversation conversation;

  const MessageListPage({super.key, required this.conversation});

  @override
  State<MessageListPage> createState() => _MessageListPageState();
}

class _MessageListPageState extends State<MessageListPage> {
  late List<Message> _messages = List.empty();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late String _myId = '';
  late Timer _syncTimer;
  late MessageService _messageService;
  final Logger _logger = Logger(output: ConsoleOutput());
  List<ConferenceParticipant> _conferenceParticipants = [];
  bool _isEmojiPickerVisible = false;

  @override
  void initState() {
    super.initState();
    _messageService = MessageService();
    _messageService.getMessages(widget.conversation.id).then((messages) {
      setState(() {
        _messages = messages;
      });
    });
    _myId = '';
    (AuthService().getCurrentUser()).then(
      (user) => setState(() {
        _myId = user.id;
      }),
    );

    // Start periodic sync for this conversation
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _syncMessages();
    });

    // Sync immediately when page loads
    _syncMessages();

    WebSocketManager()
        .initialize()
        .then((_) {
          final mngr = WebSocketManager();
          mngr.joinConversation(widget.conversation.id);
          mngr.onMessageReceived(_onSignalMsgReceived);
          mngr.onUserOffline((userId) {
            // Only trigger update if this user is part of our conversation
            if (widget.conversation.participants?.any((p) => p.id == userId) ==
                true) {
              Future.delayed(
                const Duration(milliseconds: 300),
                () => setState(() {}),
              );
            }
          });
          mngr.onUserOnline((userId) {
            // Only trigger update if this user is part of our conversation
            if (widget.conversation.participants?.any((p) => p.id == userId) ==
                true) {
              Future.delayed(
                const Duration(milliseconds: 300),
                () => setState(() {}),
              );
            }
          });
          mngr.onConferenceParticipant(_onConferenceParticipantUpdate);
          // Load initial conference participants if any
          setState(() {
            _conferenceParticipants = mngr.getConferenceParticipants(
              widget.conversation.id,
            );
          });
          //TODO: mngr.onTypingIndicator(_handleTypingIndicator);
        })
        .catchError((error) {
          _logger.e('WebSocketManager initialization error: $error');
        });
  }

  _onSignalMsgReceived(Message p1) {
    setState(() {
      _messages.insert(0, p1);
    });
    _syncMessages();
  }

  void _onConferenceParticipantUpdate(
    String roomId,
    ConferenceParticipant participant,
    String action,
  ) {
    if (roomId == widget.conversation.id) {
      final participants = WebSocketManager().getConferenceParticipants(
        widget.conversation.id,
      );
      // Only update if participants have actually changed
      if (!listEquals(_conferenceParticipants, participants)) {
        setState(() {
          _conferenceParticipants = participants;
        });
      }
    }
  }

  Future<void> _syncMessages() async {
    await _messageService
        .syncPendingMessages(widget.conversation.id)
        .catchError((error) {
          _logger.e('Error syncing messages: $error');
        });

    _messageService.getMessages(widget.conversation.id).then((messages) {
      // Only update if messages have actually changed
      if (!listEquals(_messages, messages)) {
        setState(() {
          _messages = messages;
        });
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _syncTimer?.cancel();
    _messageService.dispose();
    super.dispose();

    final mngr = WebSocketManager();
    mngr.leaveConversation(widget.conversation.id);
    mngr.removeMessageReceivedCallback(_onSignalMsgReceived);
    mngr.removeConferenceParticipantCallback(_onConferenceParticipantUpdate);
  }

  void _sendMessage() async {
    final content = _textController.text.trim();
    if (content.isEmpty) return;

    // Clear input
    _textController.clear();

    // Optimistic update: add message locally
    final newMessage = Message(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      conversationId: widget.conversation.id,
      sender: const User(id: 'u1', username: 'You'),
      content: content,
      sentAt: DateTime.now().toIso8601String(),
    );

    // Refresh UI with new message
    // final ft = List<Message>.from(_messages);
    // ft.insert(0, newMessage);
    // setState(() {
    //   _messages = ft;
    // });

    // Send to backend (fire and forget for now)
    try {
      await _messageService.sendMessage(widget.conversation.id, content);
      // After sending, refresh the message list to get the real message from backend
      await _syncMessages();
    } catch (e) {
      // TODO: Show error and retry
      // Revert optimistic update if send fails
      // setState(() {
      //   _messages = ft;
      // });
    }
  }

  User? get firstOtherUser =>
      widget.conversation.participants?.firstWhere((i) => i.id != _myId);
  String get title =>
      widget.conversation.displayTitle ??
      firstOtherUser?.username ??
      widget.conversation.participants?.first?.username ??
      "UNKNOWN";
  Object? get online =>
      (widget.conversation.participants.length <= 2 && firstOtherUser != null
      ? (WebSocketManager().onlineStates.containsKey(firstOtherUser!.id) == true
            ? WebSocketManager().onlineStates[firstOtherUser!.id]
            : false)
      : WebSocketManager().onlineStates.values.length);

  @override
  Widget build(BuildContext context) {
    final uId = _myId;
    final onlineText = online is bool
        ? (online == true ? 'Online' : 'Offline')
        : '${widget.conversation.participants.length} members' +
              ((online as int) > 2 ? '(${online} online)' : '');
    final onlineColor = online is bool
        ? (online == true
              ? Colors.green
              : Theme.of(context).textTheme.labelSmall?.color)
        : Theme.of(context).textTheme.labelSmall?.color;
    final msgs = Future.value(_messages);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(title),
            Text(
              onlineText,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: onlineColor),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.video_call),
            onPressed: () => _startCall(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Conference indicator
          if (_conferenceParticipants.isNotEmpty) _buildConferenceIndicator(),

          // Messages List
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isOwn =
                    message.sender.id == 'u1' || message.sender.id == _myId;
                return _buildMessageTile(message, isOwn);
              },
            ),
          ),

          // Message Input
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageTile(Message message, bool isOwn) {
    return Padding(
      key: Key(message.id),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: isOwn
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isOwn)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: CircleAvatar(
                radius: 16,
                child: Text(message.sender.username[0]),
              ),
            ),
          Flexible(
            child: Container(
              key: Key(message.id), // Add key for better performance
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isOwn ? Colors.blue : Colors.grey[300],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isOwn ? Colors.white : Colors.black,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm').format(DateTime.parse(message.sentAt)),
                    style: TextStyle(
                      color: isOwn ? Colors.white70 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isOwn) const SizedBox(width: 44), // Match avatar width + padding
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    final name =
        widget.conversation.displayTitle ??
        widget.conversation.participants
            ?.firstWhere((i) => i.id != _myId)
            ?.username ??
        widget.conversation.participants?.first?.username ??
        "UNKNOWN";

    return Column(
      children: [
        // Emoji Picker (conditionally shown)
        if (_isEmojiPickerVisible)
          SizedBox(
            height: 250,
            child: emoji_picker.EmojiPicker(
              onEmojiSelected:
                  (emoji_picker.Category? category, emoji_picker.Emoji emoji) {
                    // Insert emoji at cursor position (or end)
                    final text = _textController.text;
                    if (text.length == 0) {
                      _textController.value = TextEditingValue(
                        text: emoji.emoji,
                        selection: TextSelection.collapsed(
                          offset: emoji.emoji.length,
                        ),
                      );
                      return;
                    }

                    final cursor = _textController.selection.baseOffset;
                    final newText = text.replaceRange(
                      cursor,
                      cursor,
                      emoji.emoji,
                    );
                    _textController.value = TextEditingValue(
                      text: newText,
                      selection: TextSelection.collapsed(
                        offset: cursor + emoji.emoji.length,
                      ),
                    );
                  },
              onBackspacePressed: () {
                final text = _textController.text;
                final selection = _textController.selection;
                final cursor = selection.baseOffset;
                if (text.length < 1 || cursor <= 0) {
                  return;
                }

                // Use .characters to treat each visual character as 1 unit
                final characters = text.characters;

                // Ensure cursor doesn't exceed character length
                final safeCursor = cursor > characters.length
                    ? characters.length
                    : cursor;

                // Delete the character BEFORE the cursor
                final newCharacters = characters.toList();
                newCharacters.removeAt(safeCursor - 1);

                final newText = newCharacters.join('');

                // Update controller
                _textController.value = TextEditingValue(
                  text: newText,
                  selection: TextSelection.collapsed(offset: safeCursor - 1),
                );
              },
              config: emoji_picker.Config(
                height: 280,
                // Customize appearance via modular configs:
                emojiViewConfig: emoji_picker.EmojiViewConfig(
                  emojiSizeMax: 32,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  // Note: bgColor is now in view configs or handled via theme
                ),
                categoryViewConfig: emoji_picker.CategoryViewConfig(
                  iconColor: Theme.of(context).colorScheme.onSurface,
                  iconColorSelected: Theme.of(context).colorScheme.primary,
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  // Category icons are now set via viewOrderConfig
                ),
                bottomActionBarConfig: emoji_picker.BottomActionBarConfig(
                  showBackspaceButton: true,
                ),
                searchViewConfig: emoji_picker.SearchViewConfig(
                  hintText: 'Search emojis...',
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  buttonIconColor: Theme.of(context).colorScheme.onSurface,
                ),
                // viewOrderConfig: emoji_picker.ViewOrderConfig(
                //   showSearchView: true,
                //   showSkinToneActionBar: true,
                //   // You can reorder tabs if needed
                // ),
                // Locale (optional)
                locale: const Locale('en'),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  _isEmojiPickerVisible
                      ? Icons.keyboard
                      : Icons.insert_emoticon_outlined,
                ),
                onPressed: () {
                  setState(() {
                    _isEmojiPickerVisible = !_isEmojiPickerVisible;
                  });
                },
              ),
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    hintText: 'Message ${name}',
                    filled: true,
                    // fillColor: Colors.grey[100],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              IconButton(icon: const Icon(Icons.send), onPressed: _sendMessage),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConferenceIndicator() {
    return GestureDetector(
      onTap: () => _startCall(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          border: Border(
            bottom: BorderSide(color: Colors.green.shade200, width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.videocam, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            // Stacked avatars like Telegram
            SizedBox(
              width: _conferenceParticipants.length > 3
                  ? 60
                  : _conferenceParticipants.length * 20.0,
              height: 24,
              child: Stack(
                children: [
                  for (
                    int i = 0;
                    i < _conferenceParticipants.length && i < 3;
                    i++
                  )
                    Positioned(
                      left: i * 14.0,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.green.shade50,
                            width: 2,
                          ),
                        ),
                        child: CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.green.shade300,
                          child: Text(
                            _conferenceParticipants[i].username[0]
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _conferenceParticipants.length == 1
                    ? '${_conferenceParticipants.first.username} is in a call'
                    : '${_conferenceParticipants.length} people in a call',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              'Tap to join',
              style: TextStyle(color: Colors.green.shade600, fontSize: 12),
            ),
            Icon(Icons.chevron_right, color: Colors.green.shade600, size: 18),
          ],
        ),
      ),
    );
  }

  void _startCall() {
    // Navigate to call screen
    // TODO: Pass real peer info based on conversation
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConferencePage(
          roomId: widget.conversation.id,
          initialParticipants: [],
        ),
      ),
    );
  }
}
