import 'package:equatable/equatable.dart';
import 'package:talktime/shared/models/user.dart';

enum MessageType { text }

class Message extends Equatable {
  final String id;
  final String conversationId;
  final User sender;
  final String content;
  final MessageType type;
  final String sentAt;

  const Message({
    required this.id,
    required this.conversationId,
    required this.sender,
    required this.content,
    this.type = MessageType.text,
    required this.sentAt,
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

  @override
  List<Object?> get props => [
    id,
    conversationId,
    sender,
    content,
    type,
    sentAt,
  ];
}
