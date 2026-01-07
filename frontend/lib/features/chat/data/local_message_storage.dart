import 'package:isar/isar.dart';
import 'package:talktime/features/chat/data/models/message.dart';
import 'package:talktime/shared/models/message.dart' hide Message;
import 'package:path_provider/path_provider.dart';

class LocalMessageStorage {
  late Future<Isar> db;

  LocalMessageStorage() {
    db = _initDb();
  }

  Future<Isar> _initDb() async {
    final dir = await getApplicationDocumentsDirectory();
    if (Isar.instanceNames.isEmpty) {
      return await Isar.open(
        [MessageSchema], // Ensure your Message model is generated with Isar
        directory: dir.path,
      );
    }
    return Isar.getInstance()!;
  }

  /// Save a list of messages (Upsert: Insert or Update)
  Future<void> saveMessages(List<Message> messages) async {
    final isar = await db;
    await isar.writeTxn(() async {
      await isar.messages.putAll(messages);
    });
  }

  /// Get messages for a conversation from LOCAL storage
  Future<List<Message>> getMessages(
    String conversationId, {
    int offset = 0,
    int limit = 50,
  }) async {
    final isar = await db;
    return await isar.messages
        .filter()
        .conversationIdEqualTo(conversationId)
        .sortBySentAtDesc()
        .offset(offset)
        .limit(limit)
        .findAll();
  }

  /// Delete specific message locally
  Future<void> deleteMessage(String messageId) async {
    final isar = await db;
    // Assuming messageId is mapped to Isar Id or you query by string ID
    await isar.writeTxn(() async {
      await isar.messages.filter().externalIdEqualTo(messageId).deleteAll();
    });
  }
}
