import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:talktime/shared/models/message.dart';
import 'package:talktime/shared/models/user.dart';

/// A saved message wraps any content the user wants to bookmark.
class SavedItem {
  final String id;
  final String content;
  final String? mediaUrl;
  final MessageType type;
  final String savedAt;
  final String? sourceConversationId;
  final String? sourceSenderName;

  const SavedItem({
    required this.id,
    required this.content,
    this.mediaUrl,
    this.type = MessageType.text,
    required this.savedAt,
    this.sourceConversationId,
    this.sourceSenderName,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'mediaUrl': mediaUrl,
        'type': type.name,
        'savedAt': savedAt,
        'sourceConversationId': sourceConversationId,
        'sourceSenderName': sourceSenderName,
      };

  factory SavedItem.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['type'] ?? 'text').toString().toLowerCase();
    MessageType type;
    switch (typeStr) {
      case 'image':
        type = MessageType.image;
        break;
      case 'gif':
        type = MessageType.gif;
        break;
      case 'file':
        type = MessageType.file;
        break;
      default:
        type = MessageType.text;
    }

    return SavedItem(
      id: json['id'] ?? '',
      content: json['content'] ?? '',
      mediaUrl: json['mediaUrl'],
      type: type,
      savedAt: json['savedAt'] ?? DateTime.now().toIso8601String(),
      sourceConversationId: json['sourceConversationId'],
      sourceSenderName: json['sourceSenderName'],
    );
  }
}

class SavedMessagesService {
  static final SavedMessagesService _instance =
      SavedMessagesService._internal();
  factory SavedMessagesService() => _instance;
  SavedMessagesService._internal();

  static const String _storageKey = 'saved_messages';

  Future<List<SavedItem>> getSavedItems() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final List<dynamic> jsonList = json.decode(jsonStr);
      return jsonList.map((e) => SavedItem.fromJson(e)).toList()
        ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    } catch (e) {
      return [];
    }
  }

  Future<void> saveMessage(Message message) async {
    final items = await getSavedItems();

    // Don't save duplicates
    if (items.any((item) => item.id == message.id)) return;

    final newItem = SavedItem(
      id: message.id,
      content: message.content,
      mediaUrl: message.mediaUrl,
      type: message.type,
      savedAt: DateTime.now().toIso8601String(),
      sourceConversationId: message.conversationId,
      sourceSenderName: message.sender.username,
    );

    items.insert(0, newItem);
    await _persist(items);
  }

  Future<void> saveCustomText(String text) async {
    final items = await getSavedItems();

    final newItem = SavedItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: text,
      savedAt: DateTime.now().toIso8601String(),
    );

    items.insert(0, newItem);
    await _persist(items);
  }

  Future<void> deleteItem(String id) async {
    final items = await getSavedItems();
    items.removeWhere((item) => item.id == id);
    await _persist(items);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<bool> isMessageSaved(String messageId) async {
    final items = await getSavedItems();
    return items.any((item) => item.id == messageId);
  }

  Future<void> _persist(List<SavedItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(items.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, jsonStr);
  }
}
