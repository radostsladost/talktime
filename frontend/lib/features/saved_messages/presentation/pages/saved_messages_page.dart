import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart' show WebHtmlElementStrategy;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:talktime/features/saved_messages/data/saved_messages_service.dart';
import 'package:talktime/shared/models/message.dart';

class SavedMessagesPage extends StatefulWidget {
  const SavedMessagesPage({super.key});

  @override
  State<SavedMessagesPage> createState() => _SavedMessagesPageState();
}

class _SavedMessagesPageState extends State<SavedMessagesPage> {
  final SavedMessagesService _service = SavedMessagesService();
  List<SavedItem> _items = [];
  bool _isLoading = true;
  final _textController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _textController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final items = await _service.getSavedItems();
    if (!mounted) return;
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _addCustomText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    await _service.saveCustomText(text);
    await _loadItems();
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _inputFocusNode.requestFocus();
      });
    }
  }

  Future<void> _deleteItem(SavedItem item) async {
    await _service.deleteItem(item.id);
    await _loadItems();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Item removed from saved messages')),
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Saved Messages'),
        content:
            const Text('Are you sure you want to delete all saved messages?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _service.clearAll();
      await _loadItems();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Messages'),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear all',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Saved items list
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bookmark_outline,
                                size: 64,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No saved messages yet',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.5),
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Save messages from chats or add notes here',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.4),
                                    ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _items.length,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return _buildSavedItem(item);
                          },
                        ),
                ),

                // Input area for adding notes
                _buildInputArea(),
              ],
            ),
    );
  }

  Widget _buildImageWidget(String imageUrl, MessageType type) {
    final isGif = type == MessageType.gif ||
        imageUrl.toLowerCase().contains('.gif') ||
        imageUrl.contains('giphy.com');
    final useHtmlImageForGif = kIsWeb && isGif;

    if (useHtmlImageForGif) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: 250,
        height: 200,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            height: 100,
            color: Colors.grey[200],
            child: const Center(child: CircularProgressIndicator()),
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          height: 80,
          color: Colors.grey[200],
          child: const Icon(Icons.broken_image, size: 40),
        ),
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      );
    }
    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        height: 100,
        color: Colors.grey[200],
        child: const Center(child: CircularProgressIndicator()),
      ),
      errorWidget: (context, url, error) => Container(
        height: 80,
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image, size: 40),
      ),
    );
  }

  Widget _buildSavedItem(SavedItem item) {
    final isImage =
        item.type == MessageType.image || item.type == MessageType.gif;

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => _deleteItem(item),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          onLongPress: () => _showItemOptions(item),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source info
                if (item.sourceSenderName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(
                          Icons.reply,
                          size: 14,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'From ${item.sourceSenderName}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ],
                    ),
                  ),

                // Content
                if (isImage && item.mediaUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 250, maxHeight: 200),
                      child: _buildImageWidget(item.mediaUrl!, item.type),
                    ),
                  )
                else
                  Text(
                    item.content,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),

                const SizedBox(height: 6),

                // Timestamp
                Text(
                  _formatDate(item.savedAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showItemOptions(SavedItem item) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy text'),
              onTap: () {
                Navigator.pop(context);
                // Copy to clipboard would go here
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete',
                  style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deleteItem(item);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              onKeyEvent: (FocusNode node, KeyEvent event) {
                if (event is! KeyDownEvent ||
                    event.logicalKey != LogicalKeyboardKey.enter) {
                  return KeyEventResult.ignored;
                }
                if (HardwareKeyboard.instance.isShiftPressed) {
                  final text = _textController.text;
                  final sel = _textController.selection;
                  final offset = sel.baseOffset.clamp(0, text.length);
                  _textController.value = TextEditingValue(
                    text: text.replaceRange(offset, offset, '\n'),
                    selection: TextSelection.collapsed(offset: offset + 1),
                  );
                  return KeyEventResult.handled;
                }
                _addCustomText();
                return KeyEventResult.handled;
              },
              child: TextField(
                focusNode: _inputFocusNode,
                controller: _textController,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Add a note...',
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                onSubmitted: (_) => _addCustomText(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _addCustomText,
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoString) {
    try {
      final date = DateTime.parse(isoString);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inDays == 0) {
        return 'Today ${DateFormat('HH:mm').format(date)}';
      } else if (diff.inDays == 1) {
        return 'Yesterday ${DateFormat('HH:mm').format(date)}';
      } else if (diff.inDays < 7) {
        return DateFormat('EEEE HH:mm').format(date);
      } else {
        return DateFormat('MMM d, yyyy HH:mm').format(date);
      }
    } catch (e) {
      return '';
    }
  }
}
