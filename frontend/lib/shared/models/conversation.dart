import 'package:equatable/equatable.dart';
import 'package:talktime/shared/models/user.dart';

enum ConversationType { direct, group }

class Conversation extends Equatable {
  final String id;
  final ConversationType type;
  final String? name; // null for DMs
  final List<User> participants;
  final String? lastMessage;
  final String? lastMessageAt;

  const Conversation({
    required this.id,
    required this.type,
    this.name,
    required this.participants,
    this.lastMessage,
    this.lastMessageAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final participants = (json['participants'] as List)
        .map((p) => User.fromJson(p))
        .toList();

    return Conversation(
      id: json['id'],
      type: json['type'] == 'group'
          ? ConversationType.group
          : ConversationType.direct,
      name: json['name'],
      participants: participants,
      lastMessage: json['lastMessage'],
      lastMessageAt: json['lastMessageAt'],
    );
  }

  String? get displayTitle {
    if (type == ConversationType.group) return name ?? 'Group';
    return null;
  }

  String get displaySubtitle {
    return lastMessage ?? '';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type == ConversationType.group ? 'group' : 'direct',
      'name': name,
      'participants': participants.map((p) => p.id).toList(),
      'lastMessage': lastMessage,
      'lastMessageAt': lastMessageAt,
    };
  }

  @override
  List<Object?> get props => [
    id,
    type,
    name,
    participants,
    lastMessage,
    lastMessageAt,
  ];
}
