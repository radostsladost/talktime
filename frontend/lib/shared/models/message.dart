import 'package:equatable/equatable.dart';
import 'package:talktime/shared/models/user.dart';
import 'package:talktime/features/chat/data/models/message.dart' as DbModels;

enum MessageType { text }

class Message extends Equatable {
  final String id;
  final String conversationId;
  final User sender;
  final String content;
  final MessageType type;
  final String sentAt;
  final String? readAt;

  const Message({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    this.type = MessageType.text,
    required this.sentAt,
    this.readAt = null,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      conversationId: json['conversationId'],
      sender: User.fromJson(json['sender']),
      content: json['content'],
      type: MessageType.text,
      sentAt: json['sentAt'],
    );
  }

  factory Message.fromDb(DbModels.Message msg) {
    return Message(
      id: msg.externalId,
      conversationId: msg.conversationId,
      sender: User.byId(msg.senderId),
      content: msg.content,
      type: MessageType.text,
      sentAt: DateTime.fromMillisecondsSinceEpoch(msg.sentAt).toIso8601String(),
      readAt: msg.readAt != null
          ? DateTime.fromMillisecondsSinceEpoch(msg.readAt!).toIso8601String()
          : null,
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
  ];
}
