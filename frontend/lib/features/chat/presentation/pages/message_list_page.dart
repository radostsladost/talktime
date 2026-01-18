import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart' as emoji_picker;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:giphy_get/giphy_get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:talktime/core/websocket/websocket_manager.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/call/presentation/pages/conference_page.dart';
import 'package:talktime/features/chat/data/conversation_service.dart';
import 'package:talktime/features/chat/data/media_service.dart';
import 'package:talktime/features/chat/data/message_service.dart';
import 'package:talktime/features/chat/data/reaction_service.dart';
import 'package:talktime/shared/models/conversation.dart';
import 'package:talktime/shared/models/message.dart';
import 'package:talktime/shared/models/user.dart';
import 'package:visibility_detector/visibility_detector.dart';

// Common quick reactions like Telegram
const List<String> quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

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
  late ReactionService _reactionService;
  late MediaService _mediaService;
  final Logger _logger = Logger(output: ConsoleOutput());
  Map<String, User> _chatParticipants = {};
  List<ConferenceParticipant> _conferenceParticipants = [];
  bool _isEmojiPickerVisible = false;
  final Map<String, Message> _newMessages = {};
  int _upperBound = 50;
  bool _isSendingMedia = false;

  // Reactions cache - stored separately since messages are ephemeral on backend
  Map<String, List<Reaction>> _messageReactions = {};

  // Giphy API Key - replace with your own
  static const String _giphyApiKey = 'GlVGYHkr3WSBnllca54iNt0yFbjz7L65';

  @override
  void initState() {
    super.initState();
    _messageService = MessageService();
    _reactionService = ReactionService();
    _mediaService = MediaService();
    _loadMessagesWithReactions();
    _myId = '';
    (AuthService().getCurrentUser()).then(
      (user) => setState(() {
        _myId = user.id;
      }),
    );

    // Start periodic sync for this conversation
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
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
              Future.delayed(const Duration(milliseconds: 300), () {
                if (!mounted) return;
                setState(() {});
              });
            }
          });
          mngr.onUserOnline((userId) {
            // Only trigger update if this user is part of our conversation
            if (widget.conversation.participants?.any((p) => p.id == userId) ==
                true) {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (!mounted) return;
                setState(() {});
              });
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

  Future<void> _loadMessagesWithReactions() async {
    try {
      final messages = await _messageService.getMessages(
        widget.conversation.id,
        take: _upperBound,
      );
      setState(() {
        _messages = messages;
      });
      // Fetch reactions for these messages
      await _fetchReactionsForMessages(messages.map((m) => m.id).toList());
    } catch (e) {
      _logger.e('Error loading messages: $e');
    }
  }

  Future<void> _fetchReactionsForMessages(List<String> messageIds) async {
    if (messageIds.isEmpty) return;

    try {
      final reactions = await _reactionService.getReactionsBatch(
        widget.conversation.id,
        messageIds,
      );
      setState(() {
        _messageReactions.addAll(reactions);
      });
    } catch (e) {
      _logger.e('Error fetching reactions: $e');
    }
  }

  List<Reaction> _getReactionsForMessage(String messageId) {
    return _messageReactions[messageId] ?? [];
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

    _messageService.getMessages(widget.conversation.id, take: _upperBound).then(
      (messages) async {
        // Only update if messages have actually changed
        if (!listEquals(_messages, messages)) {
          setState(() {
            _messages = messages;
          });
          // Fetch reactions for new messages
          final newMessageIds = messages
              .where((m) => !_messageReactions.containsKey(m.id))
              .map((m) => m.id)
              .toList();
          if (newMessageIds.isNotEmpty) {
            await _fetchReactionsForMessages(newMessageIds);
          }
        }
      },
    );

    ConversationService().getConversationById(widget.conversation.id).then((
      conversation,
    ) {
      setState(() {
        for (var participant in conversation.participants) {
          _chatParticipants[participant.id] = participant;
        }
      });
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _syncTimer?.cancel();
    _messageService.dispose();
    _reactionService.dispose();
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

    try {
      await _messageService.sendMessage(widget.conversation.id, content);
      await _syncMessages();
    } catch (e) {
      _logger.e('Error sending message: $e');
    }
  }

  Future<void> _sendImageMessage(String imageUrl) async {
    try {
      await _messageService.sendMessage(
        widget.conversation.id,
        '', // Empty content for image
        type: 'image',
        mediaUrl: imageUrl,
      );
      await _syncMessages();
    } catch (e) {
      _logger.e('Error sending image: $e');
    }
  }

  Future<void> _sendGifMessage(String gifUrl) async {
    try {
      await _messageService.sendMessage(
        widget.conversation.id,
        gifUrl, // Store GIF URL in content for now
        type: 'image',
        mediaUrl: gifUrl,
      );
      await _syncMessages();
    } catch (e) {
      _logger.e('Error sending GIF: $e');
    }
  }

  Future<void> _pickAndSendImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );

    if (image == null) return;

    setState(() => _isSendingMedia = true);

    try {
      String? imageUrl;
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        imageUrl = await _mediaService.uploadImageBytes(bytes, image.name);
      } else {
        imageUrl = await _mediaService.uploadImage(File(image.path));
      }

      if (imageUrl != null) {
        await _sendImageMessage(imageUrl);
      } else {
        _showErrorSnackbar('Failed to upload image');
      }
    } catch (e) {
      _logger.e('Error picking/uploading image: $e');
      _showErrorSnackbar('Failed to send image');
    } finally {
      setState(() => _isSendingMedia = false);
    }
  }

  Future<void> _pickAndSendGif() async {
    try {
      final gif = await GiphyGet.getGif(
        context: context,
        apiKey: _giphyApiKey,
        lang: GiphyLanguage.english,
        tabColor: Theme.of(context).colorScheme.primary,
      );

      if (gif != null && gif.images?.original?.url != null) {
        setState(() => _isSendingMedia = true);
        await _sendGifMessage(gif.images!.original!.url!);
        setState(() => _isSendingMedia = false);
      }
    } catch (e) {
      _logger.e('Error picking GIF: $e');
      _showErrorSnackbar('Failed to send GIF');
      setState(() => _isSendingMedia = false);
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  bool _isLoadingExtra = false;
  void _markAsRead(Message message) {
    var index = _messages.indexWhere((m) => m.id == message.id);

    if (index != -1 && index >= _messages.length - 2 && !_isLoadingExtra) {
      _logger.d('Reading messages with upper bounds ${_messages.length - 2}');
      _isLoadingExtra = true;
      _upperBound = _messages.length + 50;
      _messageService
          .getMessages(widget.conversation.id, take: _upperBound)
          .then((messages) async {
            // Find new message IDs that we don't have reactions for
            final newMessageIds = messages
                .where((m) => !_messageReactions.containsKey(m.id))
                .map((m) => m.id)
                .toList();

            setState(() {
              _messages = messages;
            });

            // Fetch reactions for new messages
            if (newMessageIds.isNotEmpty) {
              await _fetchReactionsForMessages(newMessageIds);
            }

            _isLoadingExtra = false;
          })
          .catchError((error) {
            _isLoadingExtra = false;
            _logger.e('Failed to load more messages $error');
            // Handle error
          });
    }

    if (message.readAt != null) {
      return;
    }

    setState(() {
      _newMessages[message.id] = message;
    });
    _messageService.markAsRead(message);
  }

  Future<void> _toggleReaction(Message message, String emoji) async {
    final currentReactions = _getReactionsForMessage(message.id);
    final hasReacted = currentReactions.any(
      (r) => r.emoji == emoji && r.userId == _myId,
    );

    // Optimistic update
    setState(() {
      if (hasReacted) {
        // Remove reaction
        _messageReactions[message.id] = currentReactions
            .where((r) => !(r.emoji == emoji && r.userId == _myId))
            .toList();
      } else {
        // Add reaction
        final newReaction = Reaction(
          id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
          emoji: emoji,
          userId: _myId,
          username: 'You',
        );
        _messageReactions[message.id] = [...currentReactions, newReaction];
      }
    });

    try {
      await _reactionService.toggleReaction(
        message.id,
        emoji,
        _myId,
        currentReactions,
        message.conversationId,
      );
      // Refresh reactions from server to get correct data
      await _fetchReactionsForMessages([message.id]);
    } catch (e) {
      _logger.e('Error toggling reaction: $e');
      // Revert on error
      setState(() {
        _messageReactions[message.id] = currentReactions;
      });
    }
  }

  void _showReactionPicker(Message message) {
    final reactions = _getReactionsForMessage(message.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Quick reactions row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: quickReactions.map((emoji) {
                final hasReacted = reactions.any(
                  (r) => r.emoji == emoji && r.userId == _myId,
                );
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _toggleReaction(message, emoji);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasReacted
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Full emoji picker button
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showFullEmojiPicker(message);
              },
              icon: const Icon(Icons.add_reaction_outlined),
              label: const Text('More reactions'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullEmojiPicker(Message message) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: emoji_picker.EmojiPicker(
          onEmojiSelected: (category, emoji) {
            Navigator.pop(context);
            _toggleReaction(message, emoji.emoji);
          },
          config: emoji_picker.Config(
            height: MediaQuery.of(context).size.height * 0.5,
            emojiViewConfig: emoji_picker.EmojiViewConfig(
              emojiSizeMax: 32,
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
            categoryViewConfig: emoji_picker.CategoryViewConfig(
              iconColor: Theme.of(context).colorScheme.onSurface,
              iconColorSelected: Theme.of(context).colorScheme.primary,
              indicatorColor: Theme.of(context).colorScheme.primary,
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
            searchViewConfig: emoji_picker.SearchViewConfig(
              hintText: 'Search emojis...',
              backgroundColor: Theme.of(context).colorScheme.surface,
              buttonIconColor: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
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

          // Sending media indicator
          if (_isSendingMedia)
            Container(
              padding: const EdgeInsets.all(8),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 8),
                  Text('Sending...'),
                ],
              ),
            ),

          // Message Input
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageTile(Message message, bool isOwn) {
    final isImageMessage =
        message.type == MessageType.image ||
        message.type == MessageType.gif ||
        (message.mediaUrl != null && message.mediaUrl!.isNotEmpty);

    return GestureDetector(
      onLongPress: () => _showReactionPicker(message),
      child: Padding(
        key: Key(message.id),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: isOwn
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: isOwn
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isOwn)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: CircleAvatar(
                      radius: 16,
                      child: Text(
                        (_chatParticipants[message.sender.id]?.username ??
                            message.sender.username)[0],
                      ),
                    ),
                  ),
                Flexible(
                  child: Container(
                    key: Key(message.id),
                    padding: isImageMessage
                        ? const EdgeInsets.all(4)
                        : const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                    decoration: BoxDecoration(
                      color: isOwn ? Colors.blue : Colors.grey[300],
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: VisibilityDetector(
                      key: Key(message.id),
                      onVisibilityChanged: (VisibilityInfo info) {
                        if (info.visibleBounds.size.height > 5) {
                          _markAsRead(message);
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Message content (text or media)
                          if (isImageMessage)
                            _buildImageContent(message)
                          else
                            Text(
                              message.content,
                              style: TextStyle(
                                color: isOwn ? Colors.white : Colors.black,
                                fontSize: 16,
                              ),
                            ),
                          const SizedBox(height: 4),
                          // Timestamp row
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_newMessages.containsKey(message.id) &&
                                  !isOwn)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    right: 4,
                                    top: 2,
                                  ),
                                  child: Icon(
                                    Icons.circle,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primaryContainer,
                                    size: 8,
                                  ),
                                ),
                              Text(
                                DateFormat(
                                  'HH:mm',
                                ).format(DateTime.parse(message.sentAt)),
                                style: TextStyle(
                                  color: isOwn
                                      ? Colors.white70
                                      : Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (isOwn) const SizedBox(width: 10),
              ],
            ),
            // Reactions display
            if (_getReactionsForMessage(message.id).isNotEmpty)
              _buildReactionsDisplay(message, isOwn),
          ],
        ),
      ),
    );
  }

  Widget _buildImageContent(Message message) {
    final imageUrl = message.mediaUrl ?? message.content;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 250, maxHeight: 300),
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            width: 150,
            height: 150,
            color: Colors.grey[200],
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (context, url, error) => Container(
            width: 150,
            height: 100,
            color: Colors.grey[200],
            child: const Icon(Icons.broken_image, size: 40),
          ),
        ),
      ),
    );
  }

  Widget _buildReactionsDisplay(Message message, bool isOwn) {
    // Group reactions by emoji
    final reactions = _getReactionsForMessage(message.id);
    final reactionGroups = <String, List<Reaction>>{};
    for (final reaction in reactions) {
      reactionGroups.putIfAbsent(reaction.emoji, () => []).add(reaction);
    }

    return Padding(
      padding: EdgeInsets.only(
        top: 4,
        left: isOwn ? 0 : 44,
        right: isOwn ? 10 : 0,
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: reactionGroups.entries.map((entry) {
          final emoji = entry.key;
          final reactions = entry.value;
          final hasMyReaction = reactions.any((r) => r.userId == _myId);

          return GestureDetector(
            onTap: () => _toggleReaction(message, emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: hasMyReaction
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: hasMyReaction
                    ? Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1,
                      )
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 14)),
                  if (reactions.length > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${reactions.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: hasMyReaction
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
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
              // Emoji button
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
              // Text input
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    hintText: 'Message ${name}',
                    filled: true,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(30)),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    // Media buttons inside the text field on the right
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // GIF button
                        IconButton(
                          icon: const Icon(Icons.gif_box_outlined),
                          onPressed: _isSendingMedia ? null : _pickAndSendGif,
                          tooltip: 'Send GIF',
                        ),
                        // Photo button
                        IconButton(
                          icon: const Icon(Icons.photo_outlined),
                          onPressed: _isSendingMedia ? null : _pickAndSendImage,
                          tooltip: 'Send Photo',
                        ),
                      ],
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              // Send button
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
