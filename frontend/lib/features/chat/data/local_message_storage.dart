import 'dart:async';

import 'package:logger/web.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

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
  Database? _db;

  Future<Database> _initDb() async {
    if (_db != null && _db!.isOpen) return _db!;

    sqfliteFfiInit();
    var factory = !kIsWeb ? databaseFactoryFfi : databaseFactoryFfiWeb;
    var dbPath = !kIsWeb
        ? join(await factory.getDatabasesPath(), 'msg_database.db')
        : 'msg_database.db';

    Logger().i('Db path: $dbPath');

    final database = await factory.openDatabase(
      // Set the path to the database. Note: Using the `join` function from the
      // `path` package is best practice to ensure the path is correctly
      // constructed for each platform.
      dbPath,
      options: OpenDatabaseOptions(
        onCreate: (db, version) async {
          // Run the CREATE TABLE statement on the database.
          await db.execute(
            'CREATE TABLE IF NOT EXISTS message(id INTEGER PRIMARY KEY,'
            'externalId TEXT, '
            'conversationId TEXT, '
            'senderId TEXT, '
            'content TEXT, '
            'type TEXT, '
            'sentAt int, '
            'readAt int)',
          );
          // my accounts
          await db.execute(
            'CREATE TABLE IF NOT EXISTS account(id INTEGER PRIMARY KEY, '
            'externalId TEXT NOT NULL, '
            'username TEXT, '
            'avatarUrl TEXT, '
            'email TEXT, '
            'isOnline bool, '
            'accessToken TEXT,'
            'accessTokenExpiration INTEGER,'
            'refreshToken TEXT,'
            'refreshTokenExpiration INTEGER'
            ')',
          );
          // contacts
          await db.execute(
            'CREATE TABLE IF NOT EXISTS user(id INTEGER PRIMARY KEY, '
            'externalId TEXT NOT NULL, '
            'username TEXT, '
            'avatarUrl TEXT, '
            'isOnline bool, '
            'email TEXT)',
          );
          // conversations
          await db.execute(
            'CREATE TABLE IF NOT EXISTS conversation(id INTEGER PRIMARY KEY, '
            'createdAt INTEGER NOT NULL, '
            'externalId TEXT NOT NULL, '
            'lastMessageAt INTEGER, '
            'status TEXT DEFAULT \'active\')',
          );

          // convo participants
          await db.execute(
            'CREATE TABLE IF NOT EXISTS conversation_participant(id INTEGER PRIMARY KEY, '
            'conversationId INTEGER, '
            'userExternalId TEXT NOT NULL)',
          );
        },
        onUpgrade: (Database db, int oldVersion, int newVersion) async {
          if (oldVersion <= 4) {
            await db.execute(
              'ALTER TABLE message ADD COLUMN readAt INTEGER DEFAULT null;',
            );
          }
          if (oldVersion < 5) {
            // my accounts
            await db.execute(
              'CREATE TABLE IF NOT EXISTS account(id INTEGER PRIMARY KEY, '
              'externalId TEXT NOT NULL, '
              'username TEXT, '
              'avatarUrl TEXT, '
              'email TEXT, '
              'isOnline bool, '
              'accessToken TEXT,'
              'accessTokenExpiration INTEGER,'
              'refreshToken TEXT,'
              'refreshTokenExpiration INTEGER'
              ')',
            );
            // contacts
            await db.execute(
              'CREATE TABLE IF NOT EXISTS user(id INTEGER PRIMARY KEY, '
              'externalId TEXT NOT NULL, '
              'username TEXT, '
              'avatarUrl TEXT, '
              'isOnline bool, '
              'email TEXT)',
            );
            // conversations
            await db.execute(
              'CREATE TABLE IF NOT EXISTS conversation(id INTEGER PRIMARY KEY, '
              'createdAt INTEGER NOT NULL, '
              'externalId TEXT NOT NULL, '
              'lastMessageAt INTEGER, '
              'status TEXT DEFAULT \'active\')',
            );

            // convo participants
            await db.execute(
              'CREATE TABLE IF NOT EXISTS conversation_participant(id INTEGER PRIMARY KEY, '
              'conversationId INTEGER, '
              'userExternalId TEXT NOT NULL)',
            );
          }
          if (oldVersion < 6) {
            // Migrate conversation_participant table from userId INTEGER to userExternalId TEXT
            await db.execute(
              'DROP TABLE IF EXISTS conversation_participant_old',
            );
            await db.execute(
              'ALTER TABLE conversation_participant RENAME TO conversation_participant_old',
            );
            await db.execute(
              'CREATE TABLE IF NOT EXISTS conversation_participant(id INTEGER PRIMARY KEY, '
              'conversationId INTEGER, '
              'userExternalId TEXT NOT NULL)',
            );
            // Note: We can't easily migrate data from old table since we don't have the mapping,
            // but this is acceptable since the app will repopulate conversations from API
          }
        },
        // Set the version. This executes the onCreate function and provides a
        // path to perform database upgrades and downgrades.
        version: 6,
      ),
    );

    _db = database;
    return database;
  }

  /// Save a list of messages (Upsert: Insert or Update)
  Future<void> saveMessages(List<Message>? messages) async {
    if (messages == null || messages.isEmpty) {
      return;
    }

    var db = await _initDb();
    for (var message in messages) {
      await db.insert(
        'message',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
    var db = await _initDb();
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
    var db = await _initDb();
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

  /// Mark a specific message as read in local storage
  Future<void> markAsRead(String messageExternalId) async {
    var db = await _initDb();
    await db.update(
      'message',
      {'readAt': DateTime.now().millisecondsSinceEpoch},
      where: 'externalId = ?',
      whereArgs: [messageExternalId],
    );
  }
}
