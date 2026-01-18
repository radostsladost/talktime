import 'package:equatable/equatable.dart';
import 'package:talktime/shared/models/user.dart';
import 'package:talktime/features/chat/data/models/message.dart' as DbModels;

enum MessageType { text, image, gif, file, audio, video }

class Reaction extends Equatable {
  final String id;
  final String emoji;
  final String userId;
  final String username;

  const Reaction({
    required this.id,
    required this.emoji,
    required this.userId,
    required this.username,
  });

  factory Reaction.fromJson(Map<String, dynamic> json) {
    return Reaction(
      id: json['id'] ?? '',
      emoji: json['emoji'] ?? '',
      userId: json['userId'] ?? '',
      username: json['username'] ?? '',
    );
  }

  @override
  List<Object?> get props => [id, emoji, userId, username];
}

class Message extends Equatable {
  final String id;
  final String conversationId;
  final User sender;
  final String content;
  final MessageType type;
  final String sentAt;
  final String? readAt;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final List<Reaction> reactions;

  const Message({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    this.type = MessageType.text,
    required this.sentAt,
    this.readAt = null,
    this.mediaUrl,
    this.thumbnailUrl,
    this.reactions = const [],
  });

  factory Message.fromJson(Map<String, dynamic> json) {
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
      case 'audio':
        type = MessageType.audio;
        break;
      case 'video':
        type = MessageType.video;
        break;
      default:
        type = MessageType.text;
    }

    List<Reaction> reactions = [];
    if (json['reactions'] != null) {
      reactions = (json['reactions'] as List)
          .map((r) => Reaction.fromJson(r as Map<String, dynamic>))
          .toList();
    }

    return Message(
      id: json['id'],
      conversationId: json['conversationId'],
      sender: User.fromJson(json['sender']),
      content: json['content'],
      type: type,
      sentAt: json['sentAt'],
      mediaUrl: json['mediaUrl'],
      thumbnailUrl: json['thumbnailUrl'],
      reactions: reactions,
    );
  }

  factory Message.fromDb(DbModels.Message msg) {
    MessageType type;
    switch (msg.type) {
      case DbModels.MessageSchemaMessageType.image:
        type = MessageType.image;
        break;
      case DbModels.MessageSchemaMessageType.gif:
        type = MessageType.gif;
        break;
      default:
        type = MessageType.text;
    }

    return Message(
      id: msg.externalId,
      conversationId: msg.conversationId,
      sender: User.byId(msg.senderId),
      content: msg.content,
      type: type,
      sentAt: DateTime.fromMillisecondsSinceEpoch(msg.sentAt).toIso8601String(),
      readAt: msg.readAt != null
          ? DateTime.fromMillisecondsSinceEpoch(msg.readAt!).toIso8601String()
          : null,
      mediaUrl: msg.mediaUrl,
    );
  }

  Message copyWith({
    String? id,
    String? conversationId,
    User? sender,
    String? content,
    MessageType? type,
    String? sentAt,
    String? readAt,
    String? mediaUrl,
    String? thumbnailUrl,
    List<Reaction>? reactions,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      sender: sender ?? this.sender,
      content: content ?? this.content,
      type: type ?? this.type,
      sentAt: sentAt ?? this.sentAt,
      readAt: readAt ?? this.readAt,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      reactions: reactions ?? this.reactions,
    );
  }

  @override
  List<Object?> get props => [
    id,
    conversationId,
    sender,
    content,
    type,
    sentAt,
    readAt,
    mediaUrl,
    thumbnailUrl,
    reactions,
  ];
}
