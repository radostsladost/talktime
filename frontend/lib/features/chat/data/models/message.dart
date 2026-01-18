enum MessageSchemaMessageType { text, image, gif, file, audio, video }

class Message {
  int id = 0; // you can also use id = null to auto increment
  String externalId = "";
  String conversationId = "";
  String senderId = "";
  String content = "";
  MessageSchemaMessageType type = MessageSchemaMessageType.text;
  int sentAt = 0;
  int? readAt;
  String? mediaUrl;

  Message();

  Message.initFields(
    String externalId,
    String conversationId,
    String senderId,
    String content,
    MessageSchemaMessageType type,
    int sentAt, {
    String? mediaUrl,
  }) {
    this.externalId = externalId;
    this.conversationId = conversationId;
    this.senderId = senderId;
    this.content = content;
    this.type = type;
    this.sentAt = sentAt;
    this.readAt = null;
    this.mediaUrl = mediaUrl;
  }

  Map<String, Object?> toMap() {
    return {
      'id': id > 0 ? id : null,
      'externalId': externalId,
      'conversationId': conversationId,
      'senderId': senderId,
      'content': content,
      'type': type.index,
      'sentAt': sentAt,
      'readAt': readAt,
      'mediaUrl': mediaUrl,
    };
  }

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
    readAt = map['readAt'] as int?;
    mediaUrl = map['mediaUrl'] as String?;
  }

  @override
  String toString() {
    return 'Message{'
        ' id: $id,'
        ' externalId: $externalId,'
        ' conversationId: $conversationId,'
        ' senderId: $senderId,'
        ' content: $content,'
        ' type: $type,'
        ' sentAt: $sentAt,'
        ' readAt: $readAt,'
        ' mediaUrl: $mediaUrl'
        '}';
  }
}
