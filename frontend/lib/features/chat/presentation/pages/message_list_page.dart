import 'package:flutter/material.dart';
import 'package:talktime/features/call/presentation/pages/call_page.dart';
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
  late Future<List<Message>> _messagesFuture;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _messagesFuture = MessageService().getMessages(widget.conversation.id);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
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
    final ft = (await _messagesFuture);
    setState(() {
      _messagesFuture = Future.value([...ft, newMessage]);
    });

    // Send to backend (fire and forget for now)
    try {
      await MessageService().sendMessage(widget.conversation.id, content);
    } catch (e) {
      // TODO: Show error and retry
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.conversation.displayTitle),
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
              future: _messagesFuture,
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
                    return _buildMessageTile(message);
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

  Widget _buildMessageTile(Message message) {
    final isOwn =
        message.sender.id == 'u1'; // Simplified; use auth service later

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
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText: 'Message ${widget.conversation.displayTitle}',
                filled: true,
                fillColor: Colors.grey[100],
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
          conversationId: widget.conversation.id,
          initialParticipants: [],
          isCreator: false,
        ),
      ),
    );
  }
}
