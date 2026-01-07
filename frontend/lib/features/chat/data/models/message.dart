import 'package:isar/isar.dart';

part 'message.g.dart';

enum MessageSchemaMessageType { text }

@collection
class Message {
  Id id = Isar.autoIncrement; // you can also use id = null to auto increment
  String externalId = "";
  String conversationId = "";
  String senderId = "";
  String content = "";
  @enumerated
  MessageSchemaMessageType type = MessageSchemaMessageType.text;
  String sentAt = "";

  Message initFields(
    String externalId,
    String conversationId,
    String senderId,
    String content,
    MessageSchemaMessageType type,
    String sentAt,
  ) {
    this.externalId = externalId;
    this.conversationId = conversationId;
    this.senderId = senderId;
    this.content = content;
    this.type = type;
    this.sentAt = sentAt;
    return this;
  }
}
