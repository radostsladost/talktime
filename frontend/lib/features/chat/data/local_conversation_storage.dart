import 'dart:async';

import 'package:logger/web.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:talktime/shared/models/conversation.dart';
import 'package:talktime/shared/models/user.dart';
import 'package:talktime/features/chat/data/database/database_helper.dart';

class ConversationParticipant {
  int id = 0;
  int? conversationId;
  String? userExternalId;

  ConversationParticipant();

  ConversationParticipant.fromMap(Map<String, Object?> map) {
    id = map['id'] as int;
    conversationId = map['conversationId'] as int?;
    userExternalId = map['userExternalId'] as String?;
  }

  Map<String, Object?> toMap() {
    return {
      'id': id > 0 ? id : null,
      'conversationId': conversationId,
      'userExternalId': userExternalId,
    };
  }
}

class LocalConversationStorage {
  static final LocalConversationStorage _instance =
      LocalConversationStorage._internal();
  factory LocalConversationStorage() => _instance;
  LocalConversationStorage._internal();
  DatabaseHelper _databaseHelper = DatabaseHelper();

  Future<Database> _getDb() async {
    return await _databaseHelper.getDb();
  }

  /// Save a list of conversations (Upsert: Insert or Update)
  Future<void> saveConversations(List<Conversation> conversations) async {
    if (conversations.isEmpty) return;

    var db = await _getDb();
    await db.transaction((txn) async {
      for (var conversation in conversations) {
        // Save conversation
        final conversationMap = {
          'id': null, // Auto-increment
          'externalId': conversation.id,
          'createdAt': DateTime.now()
              .millisecondsSinceEpoch, // We don't have createdAt in model, use current time
          'lastMessageAt': conversation.lastMessageAt != null
              ? DateTime.parse(
                  conversation.lastMessageAt!,
                ).millisecondsSinceEpoch
              : null,
          'status': 'active', // Default status since not in model
          'name': conversation.name,
          'type': conversation.type == ConversationType.group
              ? 'group'
              : 'direct',
        };

        var byId = (await txn.query(
          'conversation',
          where: 'externalId = ?',
          whereArgs: [conversation.id],
        )).firstOrNull;
        int? conversationId;

        if (byId == null) {
          conversationId = await txn.insert(
            'conversation',
            conversationMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          conversationMap['id'] = byId['id'];
          conversationId = await txn.update(
            'conversation',
            conversationMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
            where: 'id = ?',
            whereArgs: [byId['id']],
          );
        }

        // Save participants
        if (conversation.participants.isNotEmpty) {
          // First, remove existing participants for this conversation
          await txn.delete(
            'conversation_participant',
            where: 'conversationId = ?',
            whereArgs: [conversationId],
          );

          // Then add new participants
          for (var participant in conversation.participants) {
            await txn.insert(
              'conversation_participant',
              {
                'conversationId': conversationId,
                'userExternalId': participant.id,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

            var user = (await txn.query(
              'user',
              where: 'externalId = ?',
              whereArgs: [participant.id],
            )).firstOrNull;
            if (user == null) {
              await txn.insert('user', {
                'externalId': participant.id,
                'username': participant.username,
                'avatarUrl': participant.avatarUrl,
                'isOnline': 0,
                'email': null,
              }, conflictAlgorithm: ConflictAlgorithm.replace);
            } else {
              await txn.update(
                'user',
                {
                  'externalId': participant.id,
                  'username': participant.username,
                  'avatarUrl': participant.avatarUrl,
                  'isOnline': 0,
                  'email': null,
                },
                where: 'externalId = ?',
                whereArgs: [participant.id],
              );
            }
          }
        }
      }
    });
  }

  /// Save a single conversation
  Future<void> saveConversation(Conversation conversation) async {
    await saveConversations([conversation]);
  }

  /// Get all conversations from local storage
  Future<List<Conversation>> getConversations() async {
    var db = await _getDb();

    // Get conversations
    final List<Map<String, Object?>> conversations = await db.query(
      'conversation',
      orderBy: 'lastMessageAt DESC',
    );

    final List<Conversation> result = [];
    for (var convMap in conversations) {
      final conversation = _mapToConversation(convMap);

      // Get participants for this conversation
      final List<Map<String, Object?>> participants = await db.query(
        'conversation_participant',
        where: 'conversationId = ?',
        whereArgs: [convMap['id']],
      );

      // Create participant User objects from external IDs
      List<User> participantUsers = [];
      for (var participant in participants) {
        final user = (await db.query(
          'user',
          where: 'externalId = ?',
          whereArgs: [participant['userExternalId'] as String?],
        )).firstOrNull;
        if (user != null) {
          participantUsers.add(
            User(
              id: user['externalId'] as String,
              username: user['username'] as String,
              avatarUrl: user['avatarUrl'] as String?,
            ),
          );
        } else {
          participantUsers.add(User(id: '', username: '', avatarUrl: null));
        }
      }

      // Create new conversation with participants
      result.add(
        Conversation(
          id: conversation.id,
          type: participantUsers.length > 2
              ? ConversationType.group
              : ConversationType.direct,
          name: conversation.name,
          participants: participantUsers,
          lastMessage: conversation.lastMessage,
          lastMessageAt: conversation.lastMessageAt,
        ),
      );
    }

    return result;
  }

  /// Get a specific conversation by external ID
  Future<Conversation?> getConversationByExternalId(String externalId) async {
    var db = await _getDb();
    final List<Map<String, Object?>> conversations = await db.query(
      'conversation',
      where: 'externalId = ?',
      whereArgs: [externalId],
      limit: 1,
    );

    if (conversations.isEmpty) return null;

    final conversation = _mapToConversation(conversations.first);

    // Get participants
    final List<Map<String, Object?>> participants = await db.query(
      'conversation_participant',
      where: 'conversationId = ?',
      whereArgs: [conversations.first['id']],
    );

    // Create participant User objects from external IDs
    List<User> participantUsers = [];
    for (var participant in participants) {
      final user = (await db.query(
        'user',
        where: 'externalId = ?',
        whereArgs: [participant['userExternalId'] as String?],
      )).firstOrNull;
      if (user != null) {
        participantUsers.add(
          User(
            id: user['externalId'] as String,
            username: user['username'] as String,
            avatarUrl: user['avatarUrl'] as String?,
          ),
        );
      } else {
        participantUsers.add(User(id: '', username: '', avatarUrl: null));
      }
    }

    return Conversation(
      id: conversation.id,
      type: conversation.type,
      name: conversation.name,
      participants: participantUsers,
      lastMessage: conversation.lastMessage,
      lastMessageAt: conversation.lastMessageAt,
    );
  }

  /// Update the last message timestamp for a conversation
  Future<void> updateLastMessageAt(
    String externalId,
    String lastMessageAt,
  ) async {
    var db = await _getDb();
    await db.update(
      'conversation',
      {'lastMessageAt': DateTime.parse(lastMessageAt).millisecondsSinceEpoch},
      where: 'externalId = ?',
      whereArgs: [externalId],
    );
  }

  /// Delete a conversation locally
  Future<void> deleteConversation(String externalId) async {
    var db = await _getDb();
    await db.transaction((txn) async {
      // First get the conversation ID
      final List<Map<String, Object?>> conversations = await txn.query(
        'conversation',
        where: 'externalId = ?',
        whereArgs: [externalId],
        columns: ['id'],
      );

      if (conversations.isEmpty) return;

      final conversationId = conversations.first['id'] as int;

      // Delete conversation participants
      await txn.delete(
        'conversation_participant',
        where: 'conversationId = ?',
        whereArgs: [conversationId],
      );

      // Delete conversation
      await txn.delete(
        'conversation',
        where: 'externalId = ?',
        whereArgs: [externalId],
      );
    });
  }

  Conversation _mapToConversation(Map<String, Object?> map) {
    // Create a basic conversation with empty participants
    // The actual participants will be added separately
    return Conversation(
      id: (map['externalId'] ?? '') as String,
      type: ConversationType
          .direct, // Default to direct, will be updated from API
      name: map['name'] as String?,
      participants: [],
      lastMessageAt: map['lastMessageAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              map['lastMessageAt'] as int,
            ).toIso8601String()
          : null,
      lastMessage: null,
    );
  }
}
