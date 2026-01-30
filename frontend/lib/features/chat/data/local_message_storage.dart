import 'dart:async';

import 'package:logger/web.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:talktime/features/chat/data/database/database_helper.dart';

import 'package:talktime/features/chat/data/models/message.dart';
import 'package:talktime/shared/models/message.dart' hide Message;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

class LocalMessageStorage {
  static final LocalMessageStorage _instance = LocalMessageStorage._internal();
  factory LocalMessageStorage() => _instance;
  LocalMessageStorage._internal();
  DatabaseHelper _databaseHelper = DatabaseHelper();

  Future<Database> _getDb() async {
    return await _databaseHelper.getDb();
  }

  /// Save a list of messages (Upsert: Insert or Update)
  Future<void> saveMessages(List<Message>? messages) async {
    if (messages == null || messages.isEmpty) {
      return;
    }

    var db = await _getDb();
    for (var message in messages) {
      var id = await db.insert(
        'message',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print('Inserted message with ID: $id');
    }
  }

  /// Get messages for a conversation from LOCAL storage
  // ... (rest of file for getMessages, getMessageById, deleteMessage)
  /// Get messages for a conversation from LOCAL storage
  Future<List<Message>> getMessages(
    String conversationId, {
    int offset = 0,
    int limit = 50,
  }) async {
    var db = await _getDb();
    final List<Map<String, Object?>> messages = await db.query(
      'message',
      where: 'conversationId = ?',
      whereArgs: [conversationId],
      orderBy: 'sentAt DESC',
      limit: limit,
      offset: offset,
    );
    return messages.map((e) => Message.fromMap(e)).toList();
  }

  /// Get a specific message by external ID
  Future<Message?> getMessageById(String messageId) async {
    var db = await _getDb();
    final List<Map<String, Object?>> messages = await db.query(
      'message',
      where: 'externalId = ?',
      whereArgs: [messageId],
      orderBy: 'sentAt DESC',
      limit: 1,
    );
    return messages.map((e) => Message.fromMap(e)).first;
  }

  /// Delete specific message locally
  Future<void> deleteMessage(String messageId) async {
    var db = await _getDb();
    await db.delete('message', where: 'externalId = ?', whereArgs: [messageId]);
  }

  /// Mark a specific message as read in local storage
  Future<void> markAsRead(String messageExternalId) async {
    var db = await _getDb();
    await db.update(
      'message',
      {'readAt': DateTime.now().millisecondsSinceEpoch},
      where: 'externalId = ?',
      whereArgs: [messageExternalId],
    );
  }

  /// Get all messages across all conversations for sync
  /// Optionally filter by sinceTimestamp (messages newer than this timestamp)
  Future<List<Message>> getAllMessagesForSync({
    int? sinceTimestamp,
    int limit = 500,
  }) async {
    var db = await _getDb();
    
    String? where;
    List<Object?>? whereArgs;
    
    if (sinceTimestamp != null && sinceTimestamp > 0) {
      where = 'sentAt > ?';
      whereArgs = [sinceTimestamp];
    }
    
    final List<Map<String, Object?>> messages = await db.query(
      'message',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'sentAt DESC',
      limit: limit,
    );
    return messages.map((e) => Message.fromMap(e)).toList();
  }

  /// Get count of all messages in local storage
  Future<int> getMessageCount() async {
    var db = await _getDb();
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM message');
    return result.first['count'] as int? ?? 0;
  }
}
