import 'dart:async';

import 'package:logger/web.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'package:talktime/features/chat/data/models/message.dart';
import 'package:talktime/shared/models/message.dart' hide Message;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class LocalMessageStorage {
  LocalMessageStorage();

  Future<Database> _initDb() async {
    sqfliteFfiInit();
    var factory = databaseFactoryFfi;
    var dbPath = !kIsWeb
        ? join(await factory.getDatabasesPath(), 'msg_database.db')
        : 'msg_database.db';

    final database = await factory.openDatabase(
      // Set the path to the database. Note: Using the `join` function from the
      // `path` package is best practice to ensure the path is correctly
      // constructed for each platform.
      dbPath,
      options: OpenDatabaseOptions(
        onCreate: (db, version) {
          // Run the CREATE TABLE statement on the database.
          return db.execute(
            'CREATE TABLE message(id INTEGER PRIMARY KEY,'
            'externalId TEXT, '
            'conversationId TEXT, '
            'senderId TEXT, '
            'content TEXT, '
            'type TEXT, '
            'sentAt int)',
          );
        },
        // Set the version. This executes the onCreate function and provides a
        // path to perform database upgrades and downgrades.
        version: 1,
      ),
    );
    return database;
  }

  /// Save a list of messages (Upsert: Insert or Update)
  Future<void> saveMessages(List<Message>? messages) async {
    if (messages == null || messages.isEmpty) {
      return;
    }

    var db = await _initDb();
    try {
      for (var message in messages) {
        await db.insert(
          'message',
          message.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    } finally {
      db.close();
    }
  }

  /// Get messages for a conversation from LOCAL storage
  Future<List<Message>> getMessages(
    String conversationId, {
    int offset = 0,
    int limit = 50,
  }) async {
    var db = await _initDb();
    try {
      final List<Map<String, Object?>> messages = await db.query(
        'message',
        where: 'conversationId = ?',
        whereArgs: [conversationId],
        orderBy: 'sentAt DESC',
        limit: 50,
        offset: offset,
      );
      return messages.map((e) => Message.fromMap(e)).toList();
    } finally {
      db.close();
    }
  }

  /// Get a specific message by external ID
  Future<Message?> getMessageById(String messageId) async {
    var db = await _initDb();
    try {
      final List<Map<String, Object?>> messages = await db.query(
        'message',
        where: 'externalId = ?',
        whereArgs: [messageId],
        orderBy: 'sentAt DESC',
        limit: 1,
      );
      return messages.map((e) => Message.fromMap(e)).first;
    } finally {
      db.close();
    }
  }

  /// Delete specific message locally
  Future<void> deleteMessage(String messageId) async {
    var db = await _initDb();
    try {
      await db.delete(
        'message',
        where: 'externalId = ?',
        whereArgs: [messageId],
      );
    } finally {
      db.close();
    }
  }
}
