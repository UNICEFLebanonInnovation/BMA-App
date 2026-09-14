import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// SQLite schema for the offline store.
///
/// Every synchronised record lives in the generic `records` table as a JSON
/// document with indexed bookkeeping columns; reference lists, choice lists
/// and form schemas downloaded from the server live in their own tables.
class AppDatabase {
  AppDatabase(this.db);

  final Database db;

  static const int schemaVersion = 1;
  static const String fileName = 'bma_mobile.db';

  static const List<String> _createStatements = [
    '''
    CREATE TABLE IF NOT EXISTS records (
      uuid TEXT PRIMARY KEY,
      entity TEXT NOT NULL,
      module TEXT NOT NULL,
      server_id INTEGER,
      parent_uuid TEXT,
      parent_server_id INTEGER,
      natural_key TEXT,
      label TEXT NOT NULL DEFAULT '',
      search TEXT NOT NULL DEFAULT '',
      data TEXT NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'synced',
      op TEXT,
      server_modified TEXT,
      base_modified TEXT,
      client_modified TEXT,
      created_at TEXT,
      deleted INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      duplicates TEXT,
      conflict_data TEXT,
      resolution TEXT,
      server_message TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_records_entity ON records(entity, deleted)',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_records_server ON records(entity, server_id) WHERE server_id IS NOT NULL',
    'CREATE INDEX IF NOT EXISTS idx_records_parent_uuid ON records(parent_uuid)',
    'CREATE INDEX IF NOT EXISTS idx_records_parent_server ON records(entity, parent_server_id)',
    'CREATE INDEX IF NOT EXISTS idx_records_state ON records(sync_state)',
    'CREATE INDEX IF NOT EXISTS idx_records_natural ON records(entity, natural_key)',
    'CREATE INDEX IF NOT EXISTS idx_records_search ON records(entity, search)',
    '''
    CREATE TABLE IF NOT EXISTS ref_items (
      kind TEXT NOT NULL,
      id INTEGER NOT NULL,
      name TEXT NOT NULL,
      name_en TEXT,
      parent_id INTEGER,
      data TEXT,
      PRIMARY KEY (kind, id)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_ref_parent ON ref_items(kind, parent_id)',
    '''
    CREATE TABLE IF NOT EXISTS choices (
      key TEXT NOT NULL,
      value TEXT NOT NULL,
      label TEXT NOT NULL,
      label_ar TEXT,
      position INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (key, value)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS schemas (
      entity TEXT PRIMARY KEY,
      data TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS sync_batches (
      uuid TEXT PRIMARY KEY,
      server_batch_id INTEGER,
      started_at TEXT NOT NULL,
      finished_at TEXT,
      status TEXT NOT NULL,
      summary TEXT,
      item_count INTEGER NOT NULL DEFAULT 0,
      report TEXT,
      error TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS meta (
      key TEXT PRIMARY KEY,
      value TEXT
    )
    ''',
  ];

  /// Open the on-device database (call once at start-up).
  static Future<AppDatabase> open({String? directory}) async {
    final dir = directory ?? await getDatabasesPath();
    final path = p.join(dir, fileName);
    final db = await openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => _createSchema(db),
      onUpgrade: (db, oldVersion, newVersion) => _createSchema(db),
    );
    return AppDatabase(db);
  }

  /// Open an in-memory database (unit tests, previews).
  static Future<AppDatabase> openInMemory({DatabaseFactory? factory}) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: (db, version) => _createSchema(db),
      ),
    );
    return AppDatabase(db);
  }

  static Future<void> _createSchema(DatabaseExecutor db) async {
    for (final statement in _createStatements) {
      await db.execute(statement);
    }
  }

  /// Remove every locally stored row (settings and credentials are kept).
  Future<void> clearAll() async {
    await db.transaction((txn) async {
      for (final table in ['records', 'ref_items', 'choices', 'schemas', 'sync_batches', 'meta']) {
        await txn.delete(table);
      }
    });
  }

  Future<void> close() => db.close();

  // ------------------------------------------------------------------ meta
  Future<String?> getMeta(String key) async {
    final rows = await db.query('meta', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String? value) async {
    await db.insert(
      'meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

/// Provided by `main()` after the database has been opened.
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('AppDatabase must be overridden in main()'),
);
