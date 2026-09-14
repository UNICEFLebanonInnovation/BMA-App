import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../models/sync_models.dart';
import 'app_database.dart';

/// Local history of push batches (`sync_batches` table).
class SyncDao {
  SyncDao(this._db);

  final AppDatabase _db;

  Future<void> put(SyncBatch batch) async {
    await _db.db.insert('sync_batches', batch.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SyncBatch>> history({int limit = 50}) async {
    final rows = await _db.db.query('sync_batches', orderBy: 'started_at DESC', limit: limit);
    return rows.map(SyncBatch.fromRow).toList();
  }

  Future<SyncBatch?> byUuid(String uuid) async {
    final rows = await _db.db.query('sync_batches', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : SyncBatch.fromRow(rows.first);
  }

  Future<SyncBatch?> latest() async {
    final rows = await _db.db.query('sync_batches', orderBy: 'started_at DESC', limit: 1);
    return rows.isEmpty ? null : SyncBatch.fromRow(rows.first);
  }
}

final syncDaoProvider = Provider<SyncDao>((ref) => SyncDao(ref.watch(appDatabaseProvider)));
