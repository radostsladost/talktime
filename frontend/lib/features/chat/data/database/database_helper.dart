import 'dart:async';
import 'dart:io';

import 'package:logger/web.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Database? _db;

  Future<Database> _initDb() async {
    if (_db != null && _db!.isOpen) return _db!;

    sqfliteFfiInit();
    var factory = !kIsWeb ? databaseFactoryFfi : databaseFactoryFfiWeb;
    var dbPath = !kIsWeb
        ? join(await factory.getDatabasesPath(), 'msg_database.db')
        : 'msg_database.db';

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final Directory documentsDirectory =
          await getApplicationDocumentsDirectory();
      await documentsDirectory.create(recursive: true);
      dbPath = join(documentsDirectory.path, 'msg_database.db');
    }

    Logger().i('Db path: $dbPath');

    final database = await factory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        onCreate: (db, version) async {
          await _createTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _migrateDatabase(db, oldVersion, newVersion);
        },
        version: 7,
      ),
    );

    _db = database;
    return database;
  }

  Future<void> _createTables(Database db) async {
    // Create tables for messages, accounts, users, conversations, and conversation participants
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

    await db.execute(
      'CREATE TABLE IF NOT EXISTS user(id INTEGER PRIMARY KEY, '
      'externalId TEXT NOT NULL, '
      'username TEXT, '
      'avatarUrl TEXT, '
      'isOnline bool, '
      'email TEXT)',
    );

    await db.execute(
      'CREATE TABLE IF NOT EXISTS conversation(id INTEGER PRIMARY KEY, '
      'createdAt INTEGER NOT NULL, '
      'externalId TEXT NOT NULL, '
      'lastMessageAt INTEGER, '
      'status TEXT DEFAULT \'active\','
      'name TEXT,'
      'type TEXT DEFAULT \'direct\''
      ')',
    );

    await db.execute(
      'CREATE TABLE IF NOT EXISTS conversation_participant(id INTEGER PRIMARY KEY, '
      'conversationId INTEGER, '
      'userExternalId TEXT NOT NULL)',
    );
  }

  Future<void> _migrateDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await _createTables(db);

    if (oldVersion <= 4) {
      await db.execute(
        'ALTER TABLE message ADD COLUMN readAt INTEGER DEFAULT null;',
      );
    }
    if (oldVersion < 6) {
      await db.execute('DROP TABLE IF EXISTS conversation_participant_old');
      await db.execute(
        'ALTER TABLE conversation_participant RENAME TO conversation_participant_old',
      );
      await db.execute(
        'CREATE TABLE IF NOT EXISTS conversation_participant(id INTEGER PRIMARY KEY, '
        'conversationId INTEGER, '
        'userExternalId TEXT NOT NULL)',
      );
    }

    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE conversation ADD COLUMN name TEXT DEFAULT null;',
      );
      await db.execute(
        'ALTER TABLE conversation ADD COLUMN type TEXT DEFAULT \'direct\';',
      );
      await db.execute(
        'UPDATE conversation SET type = \'group\' WHERE (SELECT COUNT(*) FROM conversation_participant WHERE conversationId = conversation.id) > 2;',
      );
    }
  }

  Future<Database> getDb() async {
    return await _initDb();
  }
}
