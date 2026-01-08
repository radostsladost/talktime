enum MessageSchemaMessageType { text }

class Message {
  int id = 0; // you can also use id = null to auto increment
  String externalId = "";
  String conversationId = "";
  String senderId = "";
  String content = "";
  MessageSchemaMessageType type = MessageSchemaMessageType.text;
  int sentAt = 0;

  Message();

  Message.initFields(
    String externalId,
    String conversationId,
    String senderId,
    String content,
    MessageSchemaMessageType type,
    int sentAt,
  ) {
    this.externalId = externalId;
    this.conversationId = conversationId;
    this.senderId = senderId;
    this.content = content;
    this.type = type;
    this.sentAt = sentAt;
  }

  // Convert a Dog into a Map. The keys must correspond to the names of the
  // columns in the database.
  Map<String, Object?> toMap() {
    return {
      'id': id > 0 ? id : null,
      'externalId': externalId,
      'conversationId': conversationId,
      'senderId': senderId,
      'content': content,
      'type': type.index,
      'sentAt': sentAt,
    };
  }

  // Convert a Dog into a Map. The keys must correspond to the names of the
  // columns in the database.
  Message.fromMap(Map<String, Object?> map) {
    id = map['id'] as int;
    externalId = (map['externalId'] ?? '') as String;
    conversationId = (map['conversationId'] ?? '') as String;
    senderId = (map['senderId'] ?? '') as String;
    content = (map['content'] ?? '') as String;

    var typ = int.parse(map['type']?.toString() ?? '0');
    type = typ >= 0 && typ < MessageSchemaMessageType.values.length
        ? MessageSchemaMessageType.values[typ]
        : MessageSchemaMessageType.text;
    sentAt = (map['sentAt'] ?? 0) as int;
  }

  // Implement toString to make it easier to see information about
  // each dog when using the print statement.
  @override
  String toString() {
    return 'Message{'
        ' id: $id,'
        ' externalId: $externalId,'
        ' conversationId: $conversationId,'
        ' senderId: $senderId,'
        ' content: $content,'
        ' type: $type,'
        ' sentAt: $sentAt'
        '}';
  }
}
