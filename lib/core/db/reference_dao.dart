import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../models/form_schema.dart';
import '../models/reference_item.dart';
import 'app_database.dart';

/// Reference lists, choice lists and form schemas downloaded at bootstrap.
class ReferenceDao {
  ReferenceDao(this._db);

  final AppDatabase _db;

  Database get db => _db.db;

  static const String metaBootstrapAt = 'bootstrap_at';
  static const String metaLastPull = 'last_pull';
  static const String metaProfile = 'profile';
  static const String metaEntities = 'entities';

  // ------------------------------------------------------------ reference
  Future<void> replaceKind(String kind, Iterable<ReferenceItem> items) async {
    await db.transaction((txn) async {
      await txn.delete('ref_items', where: 'kind = ?', whereArgs: [kind]);
      final batch = txn.batch();
      for (final item in items) {
        batch.insert('ref_items', item.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<ReferenceItem>> items(String kind, {int? parentId, String? search, int? limit}) async {
    final where = <String>['kind = ?'];
    final args = <Object?>[kind];
    if (parentId != null) {
      where.add('parent_id = ?');
      args.add(parentId);
    }
    if (search != null && search.trim().isNotEmpty) {
      where.add('(name LIKE ? OR name_en LIKE ?)');
      args.addAll(['%${search.trim()}%', '%${search.trim()}%']);
    }
    final rows = await db.query('ref_items',
        where: where.join(' AND '), whereArgs: args, orderBy: 'name COLLATE NOCASE', limit: limit);
    return rows.map(ReferenceItem.fromRow).toList();
  }

  Future<ReferenceItem?> item(String kind, int id) async {
    final rows = await db.query('ref_items', where: 'kind = ? AND id = ?', whereArgs: [kind, id], limit: 1);
    return rows.isEmpty ? null : ReferenceItem.fromRow(rows.first);
  }

  Future<Map<int, ReferenceItem>> mapOf(String kind) async {
    final list = await items(kind);
    return {for (final i in list) i.id: i};
  }

  Future<int> countKind(String kind) async {
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM ref_items WHERE kind = ?', [kind]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // --------------------------------------------------------------- choices
  Future<void> replaceChoices(Map<String, List<ChoiceRow>> choices) async {
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in choices.entries) {
        batch.delete('choices', where: 'key = ?', whereArgs: [entry.key]);
        for (final row in entry.value) {
          batch.insert('choices', row.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<ChoiceRow>> choices(String key) async {
    final rows = await db.query('choices', where: 'key = ?', whereArgs: [key], orderBy: 'position');
    return rows.map(ChoiceRow.fromRow).toList();
  }

  // --------------------------------------------------------------- schemas
  Future<void> replaceSchemas(Map<String, EntitySchema> schemas) async {
    await db.transaction((txn) async {
      await txn.delete('schemas');
      final batch = txn.batch();
      for (final entry in schemas.entries) {
        batch.insert('schemas', {'entity': entry.key, 'data': jsonEncode(entry.value.toJson())},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<EntitySchema?> schema(String entity) async {
    final rows = await db.query('schemas', where: 'entity = ?', whereArgs: [entity], limit: 1);
    if (rows.isEmpty) return null;
    return EntitySchema.fromJson(Map<String, dynamic>.from(jsonDecode(rows.first['data'] as String) as Map));
  }

  Future<Map<String, EntitySchema>> allSchemas() async {
    final rows = await db.query('schemas');
    return {
      for (final row in rows)
        row['entity'] as String:
            EntitySchema.fromJson(Map<String, dynamic>.from(jsonDecode(row['data'] as String) as Map)),
    };
  }

  // ------------------------------------------------------------------ meta
  Future<String?> getMeta(String key) => _db.getMeta(key);

  Future<void> setMeta(String key, String? value) => _db.setMeta(key, value);

  Future<bool> get hasBootstrap async => (await getMeta(metaBootstrapAt)) != null;
}

final referenceDaoProvider = Provider<ReferenceDao>((ref) => ReferenceDao(ref.watch(appDatabaseProvider)));
