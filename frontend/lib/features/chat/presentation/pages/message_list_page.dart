import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/call/presentation/pages/call_page.dart';
import 'package:talktime/features/call/presentation/pages/conference_page.dart';
import 'package:talktime/features/chat/data/conversation_service.dart';
import 'package:talktime/features/chat/data/message_service.dart';
import 'package:talktime/features/chat/data/realtime_message_service.dart';
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
  late List<Message> _messagesFuture = List.empty();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late String _myId = '';
  late Timer _syncTimer;
  late MessageService _messageService;
  late RealTimeMessageService _realTimeMessageService;
  final Logger _logger = Logger(output: ConsoleOutput());

  @override
  void initState() {
    super.initState();
    _messageService = MessageService();
    _messageService.getMessages(widget.conversation.id).then((messages) {
      _messagesFuture = messages;
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
          // mngr.onUserOnline(_handleUserOnline);
          // mngr.onUserOffline(_handleUserOffline);
          // mngr.onTypingIndicator(_handleTypingIndicator);
        })
        .catchError((error) {
          _logger.e('WebSocketManager initialization error: $error');
        });
  }

  _onSignalMsgReceived(Message p1) {
    setState(() {
      _messagesFuture.add(p1);
    });
    _syncMessages();
  }

  Future<void> _syncMessages() async {
    await _messageService
        .syncPendingMessages(widget.conversation.id)
        .catchError((error) {
          _logger.e('Error syncing messages: $error');
        });
    _messagesFuture = await _messageService.getMessages(widget.conversation.id);
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
    final ft = List<Message>.from(_messagesFuture);
    setState(() {
      _messagesFuture = ft;
    });

    // Send to backend (fire and forget for now)
    try {
      await _messageService.sendMessage(widget.conversation.id, content);
      // After sending, refresh the message list to get the real message from backend
      _syncMessages();
    } catch (e) {
      // TODO: Show error and retry
      // Revert optimistic update if send fails
      setState(() {
        _messagesFuture = ft;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uId = _myId;
    final name =
        widget.conversation.displayTitle ??
        widget.conversation.participants
            ?.firstWhere((i) => i.id != uId)
            ?.username ??
        widget.conversation.participants?.first?.username ??
        "UNKNOWN";
    final msgs = Future.value(_messagesFuture);

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
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
          // Messages List
          Expanded(
            child: FutureBuilder<List<Message>>(
              future: msgs,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final messages = snapshot.data!;
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // So latest messages are at bottom
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    final isOwn =
                        message.sender.id == 'u1' || message.sender.id == uId;
                    // Simplified; use auth service later
                    return _buildMessageTile(message, isOwn);
                  },
                );
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isOwn ? Colors.blue : Colors.grey[300],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isOwn ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
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

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
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
