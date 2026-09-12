import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/entity_record.dart';
import '../models/sync_models.dart';
import '../utils/names.dart';
import 'app_database.dart';

/// Filters for [EntityDao.list].
class RecordQuery {
  const RecordQuery({
    this.entity,
    this.entities,
    this.module,
    this.search,
    this.parentUuid,
    this.parentServerId,
    this.states,
    this.includeDeleted = false,
    this.limit,
    this.offset = 0,
    this.orderBy = 'label COLLATE NOCASE ASC',
  });

  final String? entity;
  final List<String>? entities;
  final String? module;
  final String? search;
  final String? parentUuid;
  final int? parentServerId;
  final List<SyncState>? states;
  final bool includeDeleted;
  final int? limit;
  final int offset;
  final String orderBy;
}

/// Data access for the generic `records` table.
class EntityDao {
  EntityDao(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  Database get db => _db.db;

  String newUuid() => _uuid.v4();

  static String now() => DateTime.now().toIso8601String();

  // ---------------------------------------------------------------- queries
  Future<EntityRecord?> byUuid(String uuid) async {
    final rows = await db.query('records', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return rows.isEmpty ? null : EntityRecord.fromRow(rows.first);
  }

  Future<EntityRecord?> byServerId(String entity, int serverId) async {
    final rows = await db.query('records',
        where: 'entity = ? AND server_id = ?', whereArgs: [entity, serverId], limit: 1);
    return rows.isEmpty ? null : EntityRecord.fromRow(rows.first);
  }

  Future<EntityRecord?> byNaturalKey(String entity, String naturalKey) async {
    final rows = await db.query('records',
        where: 'entity = ? AND natural_key = ?', whereArgs: [entity, naturalKey], limit: 1);
    return rows.isEmpty ? null : EntityRecord.fromRow(rows.first);
  }

  Future<List<EntityRecord>> list(RecordQuery q) async {
    final where = <String>[];
    final args = <Object?>[];
    if (q.entity != null) {
      where.add('entity = ?');
      args.add(q.entity);
    }
    if (q.entities != null && q.entities!.isNotEmpty) {
      where.add('entity IN (${List.filled(q.entities!.length, '?').join(',')})');
      args.addAll(q.entities!);
    }
    if (q.module != null) {
      where.add('module = ?');
      args.add(q.module);
    }
    if (q.parentUuid != null) {
      where.add('parent_uuid = ?');
      args.add(q.parentUuid);
    }
    if (q.parentServerId != null) {
      where.add('parent_server_id = ?');
      args.add(q.parentServerId);
    }
    if (q.states != null && q.states!.isNotEmpty) {
      where.add('sync_state IN (${List.filled(q.states!.length, '?').join(',')})');
      args.addAll(q.states!.map((s) => s.name));
    }
    if (!q.includeDeleted) {
      where.add('deleted = 0');
    }
    final search = normalizeSearch(q.search ?? '');
    if (search.isNotEmpty) {
      for (final token in search.split(' ')) {
        if (token.isEmpty) continue;
        where.add('search LIKE ?');
        args.add('%$token%');
      }
    }
    final rows = await db.query(
      'records',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: q.orderBy,
      limit: q.limit,
      offset: q.limit == null ? null : q.offset,
    );
    return rows.map(EntityRecord.fromRow).toList();
  }

  /// Children of a record: matches on the local uuid *or* the server id so
  /// that services pulled from the server and services created offline both
  /// appear under the same parent.
  Future<List<EntityRecord>> childrenOf(EntityRecord parent, {String? entity}) async {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (entity != null) {
      where.add('entity = ?');
      args.add(entity);
    }
    final clauses = <String>['parent_uuid = ?'];
    args.add(parent.uuid);
    if (parent.serverId != null) {
      clauses.add('parent_server_id = ?');
      args.add(parent.serverId);
    }
    where.add('(${clauses.join(' OR ')})');
    final rows = await db.query('records',
        where: where.join(' AND '), whereArgs: args, orderBy: 'created_at DESC, rowid DESC');
    return rows.map(EntityRecord.fromRow).toList();
  }

  Future<int> count({String? entity, String? module, List<SyncState>? states, bool includeDeleted = false}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (entity != null) {
      where.add('entity = ?');
      args.add(entity);
    }
    if (module != null) {
      where.add('module = ?');
      args.add(module);
    }
    if (states != null && states.isNotEmpty) {
      where.add('sync_state IN (${List.filled(states.length, '?').join(',')})');
      args.addAll(states.map((s) => s.name));
    }
    if (!includeDeleted) where.add('deleted = 0');
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM records${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}',
      args,
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<SyncState, int>> countsByState() async {
    final rows = await db.rawQuery(
        'SELECT sync_state, COUNT(*) AS c FROM records WHERE deleted = 0 OR sync_state != ? GROUP BY sync_state',
        ['synced']);
    final result = {for (final s in SyncState.values) s: 0};
    for (final row in rows) {
      result[SyncState.fromKey(row['sync_state'] as String?)] = (row['c'] as int?) ?? 0;
    }
    return result;
  }

  /// Records waiting to be pushed, parents before children.
  Future<List<EntityRecord>> outbox() async {
    final rows = await db.query(
      'records',
      where: 'sync_state IN (?, ?, ?, ?)',
      whereArgs: [SyncState.pending.name, SyncState.duplicate.name, SyncState.conflict.name, SyncState.error.name],
      orderBy: 'client_modified ASC, rowid ASC',
    );
    final records = rows.map(EntityRecord.fromRow).toList();
    records.sort((a, b) => _pushOrder(a).compareTo(_pushOrder(b)));
    return records;
  }

  static int _pushOrder(EntityRecord r) {
    if (Entities.identityEntities.contains(r.entity)) return 10;
    if (r.entity.endsWith('.teacher')) return 10;
    if (r.entity == 'mscc.new_round') return 20;
    if (Entities.attendanceEntities.contains(r.entity)) return 40;
    return 30;
  }

  // ---------------------------------------------------------------- writes
  Future<void> put(EntityRecord record) async {
    await db.insert('records', record.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> putAll(Iterable<EntityRecord> records) async {
    final batch = db.batch();
    for (final r in records) {
      batch.insert('records', r.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> delete(String uuid) => db.delete('records', where: 'uuid = ?', whereArgs: [uuid]);

  /// Create a new local record (pending push).
  Future<EntityRecord> createLocal({
    required String entity,
    required Map<String, dynamic> data,
    EntityRecord? parent,
    String? naturalKey,
    String? op,
  }) async {
    final record = EntityRecord(
      uuid: newUuid(),
      entity: entity,
      module: Entities.moduleOf(entity).key,
      data: data,
      parentUuid: parent?.uuid,
      parentServerId: parent?.serverId,
      naturalKey: naturalKey,
      label: labelFor(entity, data),
      search: searchTextFor(entity, data),
      syncState: SyncState.pending,
      op: op ?? (Entities.attendanceEntities.contains(entity) ? 'upsert' : 'create'),
      clientModified: now(),
      createdAt: now(),
    );
    await put(record);
    return record;
  }

  /// Edit an existing record; keeps `create` when the row never reached the
  /// server, otherwise marks an `update`.
  Future<EntityRecord> updateLocal(EntityRecord record, Map<String, dynamic> data) async {
    final isNew = record.serverId == null && (record.op == 'create' || record.op == null);
    final updated = record.copyWith(
      data: data,
      label: labelFor(record.entity, data),
      search: searchTextFor(record.entity, data),
      syncState: SyncState.pending,
      op: Entities.attendanceEntities.contains(record.entity) ? 'upsert' : (isNew ? 'create' : 'update'),
      baseModified: record.serverModified ?? record.baseModified,
      clientModified: now(),
      clearError: true,
      clearConflict: true,
      duplicates: const [],
      clearResolution: true,
    );
    await put(updated);
    return updated;
  }

  Future<void> markDeleted(EntityRecord record) async {
    if (record.serverId == null) {
      await delete(record.uuid);
      return;
    }
    await put(record.copyWith(
      deleted: true,
      syncState: SyncState.pending,
      op: 'delete',
      clientModified: now(),
    ));
  }

  Future<EntityRecord> setResolution(EntityRecord record, Map<String, dynamic>? resolution) async {
    final updated = record.copyWith(
      resolution: resolution,
      clearResolution: resolution == null,
      syncState: resolution == null ? record.syncState : SyncState.pending,
      clientModified: now(),
    );
    await put(updated);
    return updated;
  }

  Future<EntityRecord> markDiscarded(EntityRecord record, {int? targetServerId}) async {
    final updated = record.copyWith(
      syncState: SyncState.discarded,
      clearOp: true,
      clearResolution: true,
      serverMessage: targetServerId == null ? null : 'Mapped to server record #$targetServerId',
    );
    await put(updated);
    return updated;
  }

  // ---------------------------------------------------------------- server merges
  /// Apply a change downloaded from the server.
  ///
  /// Local rows with unsent work are never overwritten; the server copy is
  /// kept in `conflict_data` so the user can compare, and the push engine
  /// will decide (via `base_modified`) whether it is a real conflict.
  Future<void> applyPullChange(PullChange change) async {
    final entity = change.entity;
    EntityRecord? existing;
    if (change.serverId != null) {
      existing = await byServerId(entity, change.serverId!);
    } else if (change.key != null) {
      existing = await byNaturalKey(entity, change.key!);
    }
    existing ??= await _matchLocalByNaturalKey(entity, change);

    if (existing != null && existing.syncState.isOutbound) {
      await put(existing.copyWith(
        serverId: change.serverId ?? existing.serverId,
        serverModified: change.modified,
        conflictData: change.deleted ? null : change.data,
      ));
      return;
    }
    if (change.deleted) {
      if (existing != null) await delete(existing.uuid);
      return;
    }
    final record = EntityRecord(
      uuid: existing?.uuid ?? newUuid(),
      entity: entity,
      module: Entities.moduleOf(entity).key,
      data: change.data,
      serverId: change.serverId ?? existing?.serverId,
      parentUuid: existing?.parentUuid,
      parentServerId: change.parentId ?? existing?.parentServerId,
      naturalKey: change.key ?? naturalKeyFor(entity, change.data) ?? existing?.naturalKey,
      label: labelFor(entity, change.data),
      search: searchTextFor(entity, change.data),
      syncState: SyncState.synced,
      serverModified: change.modified,
      createdAt: existing?.createdAt ?? change.data['created']?.toString() ?? now(),
    );
    await put(record);
    if (record.parentServerId != null && record.parentUuid == null) {
      await _linkParent(record);
    }
  }

  Future<EntityRecord?> _matchLocalByNaturalKey(String entity, PullChange change) async {
    final key = naturalKeyFor(entity, change.data);
    if (key == null) return null;
    return byNaturalKey(entity, key);
  }

  Future<void> _linkParent(EntityRecord record) async {
    final parentEntity = _parentEntityOf(record.entity);
    if (parentEntity == null || record.parentServerId == null) return;
    final parent = await byServerId(parentEntity, record.parentServerId!);
    if (parent != null) {
      await put(record.copyWith(parentUuid: parent.uuid));
    }
  }

  static String? _parentEntityOf(String entity) {
    final module = Entities.moduleOf(entity);
    if (Entities.identityEntities.contains(entity) ||
        Entities.attendanceEntities.contains(entity) ||
        entity.endsWith('.teacher') ||
        entity == Entities.alpSchoolProfile ||
        entity == Entities.clmTeacher) {
      return null;
    }
    return Entities.registrationFor(module);
  }

  /// Update the parent server id of children once a parent has been pushed.
  Future<void> propagateParentServerId(String parentUuid, int parentServerId) async {
    await db.update('records', {'parent_server_id': parentServerId},
        where: 'parent_uuid = ?', whereArgs: [parentUuid]);
  }

  /// Apply the outcome of a push for [record].
  Future<void> applyPushResult(EntityRecord record, PushItemResult result) async {
    switch (result.status) {
      case 'created':
      case 'updated':
      case 'merged':
      case 'linked':
        if (result.updatedEntity != null && result.updatedEntity != record.entity && result.dataAfter != null) {
          // A sub-form (e.g. bridging assessment) updated its parent registration.
          await applyPullChange(PullChange(
            entity: result.updatedEntity!,
            serverId: result.serverId,
            modified: result.dataAfter!['modified']?.toString(),
            data: result.dataAfter!,
          ));
          await delete(record.uuid);
          return;
        }
        if (result.createdEntity != null && result.createdEntity != record.entity && result.dataAfter != null) {
          // e.g. mscc.new_round produced a new registration: store it and drop the request.
          await applyPullChange(PullChange(
            entity: result.createdEntity!,
            serverId: result.serverId,
            modified: result.dataAfter!['modified']?.toString(),
            data: result.dataAfter!,
          ));
          await delete(record.uuid);
          return;
        }
        final data = result.dataAfter != null && result.dataAfter!.isNotEmpty
            ? _mergeDataAfter(record, result.dataAfter!)
            : record.data;
        final updated = record.copyWith(
          data: data,
          serverId: result.serverId ?? record.serverId,
          parentServerId: result.parentId ?? record.parentServerId,
          label: labelFor(record.entity, data),
          search: searchTextFor(record.entity, data),
          syncState: SyncState.synced,
          clearOp: true,
          clearError: true,
          clearConflict: true,
          clearResolution: true,
          duplicates: const [],
          serverModified: data['modified']?.toString() ?? now(),
          serverMessage: result.message,
          naturalKey: result.key ?? record.naturalKey,
        );
        await put(updated);
        if (result.serverId != null) {
          await propagateParentServerId(record.uuid, result.serverId!);
        }
        return;
      case 'deleted':
        await delete(record.uuid);
        return;
      case 'duplicate':
        await put(record.copyWith(
          syncState: SyncState.duplicate,
          duplicates: result.duplicates,
          serverMessage: result.message,
          clearResolution: true,
        ));
        return;
      case 'conflict':
        final serverData = result.errors['server_data'];
        await put(record.copyWith(
          syncState: SyncState.conflict,
          conflictData: serverData is Map ? Map<String, dynamic>.from(serverData) : null,
          serverMessage: result.message,
          clearResolution: true,
        ));
        return;
      case 'discarded':
        final target = (record.resolution?['target_id'] as num?)?.toInt();
        await markDiscarded(record, targetServerId: target);
        if (target != null) await propagateParentServerId(record.uuid, target);
        return;
      case 'skipped':
        await put(record.copyWith(
          syncState: SyncState.pending,
          serverMessage: result.message,
        ));
        return;
      default:
        await put(record.copyWith(
          syncState: SyncState.error,
          lastError: result.errors.isEmpty ? {'__all__': [result.message]} : result.errors,
          serverMessage: result.message,
          clearResolution: true,
        ));
    }
  }

  Map<String, dynamic> _mergeDataAfter(EntityRecord record, Map<String, dynamic> after) {
    if (Entities.identityEntities.contains(record.entity) ||
        Entities.attendanceEntities.contains(record.entity)) {
      // The server representation is authoritative (ids, generated numbers).
      return after;
    }
    return {...record.data, ...after};
  }

  Future<void> markPushing(Iterable<EntityRecord> records) async {
    final batch = db.batch();
    for (final r in records) {
      batch.update('records', {'sync_state': SyncState.pushing.name}, where: 'uuid = ?', whereArgs: [r.uuid]);
    }
    await batch.commit(noResult: true);
  }

  /// Anything left in `pushing` after a failed request goes back to pending.
  Future<void> resetPushing() async {
    await db.update('records', {'sync_state': SyncState.pending.name},
        where: 'sync_state = ?', whereArgs: [SyncState.pushing.name]);
  }

  // ---------------------------------------------------------------- labels
  static String labelFor(String entity, Map<String, dynamic> data) {
    if (Entities.identityEntities.contains(entity)) {
      final person = data['child'] ?? data['student'];
      if (person is Map) {
        final p = Map<String, dynamic>.from(person);
        return joinNames([p['first_name'], p['father_name'], p['last_name']]);
      }
      final prefix = entity == Entities.clmBridging ? 'student_' : 'child_';
      return joinNames([data['${prefix}first_name'], data['${prefix}father_name'], data['${prefix}last_name']]);
    }
    if (entity.endsWith('.teacher')) {
      return joinNames([data['first_name'], data['father_name'], data['last_name']]);
    }
    if (Entities.attendanceEntities.contains(entity)) {
      final date = data['attendance_date'] ?? '';
      final programme = data['education_program'] ?? data['registration_level'] ?? data['programme'] ?? '';
      final section = data['class_section'] ?? '';
      return [date, programme, section].where((e) => e.toString().isNotEmpty).join(' · ');
    }
    final date = data['registration_date'] ?? data['date'] ?? data['created'] ?? '';
    return date.toString().split('T').first;
  }

  static String searchTextFor(String entity, Map<String, dynamic> data) {
    final parts = <Object?>[];
    void addPerson(Map<String, dynamic> p) {
      parts.addAll([
        p['first_name'], p['father_name'], p['last_name'], p['mother_fullname'], p['number'],
        p['unicef_id'], p['id_number'], p['national_number'], p['individual_case_number'],
        p['case_number'], p['recorded_number'], p['syrian_national_number'], p['sop_national_number'],
        p['other_number'], p['first_phone_number'],
      ]);
    }

    final person = data['child'] ?? data['student'];
    if (person is Map) {
      addPerson(Map<String, dynamic>.from(person));
    } else {
      final prefix = entity == Entities.clmBridging ? 'student_' : 'child_';
      addPerson({
        'first_name': data['${prefix}first_name'],
        'father_name': data['${prefix}father_name'],
        'last_name': data['${prefix}last_name'],
        'mother_fullname': data['${prefix}mother_fullname'],
        'national_number': data['national_number'],
        'individual_case_number': data['individual_case_number'],
        'first_phone_number': data['first_phone_number'] ?? data['phone_number'],
      });
    }
    parts.addAll([data['first_name'], data['father_name'], data['last_name'], data['partner_unique_number'],
      data['internal_number'], data['attendance_date'], data['education_program'], data['class_section']]);
    return normalizeSearch(parts.where((e) => e != null && e.toString().isNotEmpty).join(' '));
  }

  /// Natural key of idempotent documents (attendance days).
  static String? naturalKeyFor(String entity, Map<String, dynamic> data) {
    switch (entity) {
      case Entities.msccAttendanceDay:
        return [data['center_id'], data['round_id'], data['attendance_date'], data['education_program'],
          data['class_section']].join('|');
      case Entities.alpAttendanceDay:
        return [data['school_id'], data['round_id'], data['programme'], data['attendance_date']].join('|');
      case Entities.clmAttendanceDay:
        return [data['school_id'], data['round_id'], data['registration_level'], data['attendance_date']].join('|');
      case Entities.alpTeacherAttendanceDay:
        return data['attendance_date']?.toString();
    }
    return null;
  }

  /// Local duplicate pre-check used by the registration wizard while offline.
  Future<List<EntityRecord>> findLocalDuplicates(String entity, Map<String, dynamic> values) async {
    final prefix = entity == Entities.clmBridging ? 'student_' : 'child_';
    final genderKey = entity == Entities.clmBridging ? 'student_sex' : 'child_gender';
    final wanted = normalizeNameKey([
      values['${prefix}first_name'], values['${prefix}father_name'], values['${prefix}last_name'],
    ]);
    if (wanted.isEmpty) return const [];
    final year = values['${prefix}birthday_year']?.toString() ?? '';
    final gender = values[genderKey]?.toString() ?? '';
    final rows = await list(RecordQuery(entity: entity, includeDeleted: false));
    final matches = <EntityRecord>[];
    for (final r in rows) {
      final person = r.data['child'] ?? r.data['student'];
      final p = person is Map ? Map<String, dynamic>.from(person) : r.data;
      final first = p['first_name'] ?? r.data['${prefix}first_name'];
      final father = p['father_name'] ?? r.data['${prefix}father_name'];
      final last = p['last_name'] ?? r.data['${prefix}last_name'];
      final key = normalizeNameKey([first, father, last]);
      if (key != wanted) continue;
      final rYear = (p['birthday_year'] ?? r.data['${prefix}birthday_year'] ?? '').toString();
      final rGender = (p['gender'] ?? p['sex'] ?? r.data[genderKey] ?? '').toString();
      if (rYear == year && rGender == gender) matches.add(r);
    }
    return matches;
  }

  /// Export a record (and its children) as a JSON string, handy for support.
  Future<String> dump(EntityRecord record) async {
    final children = await childrenOf(record);
    return jsonEncode({
      'record': record.toRow(),
      'children': children.map((c) => c.toRow()).toList(),
    });
  }
}

final entityDaoProvider = Provider<EntityDao>((ref) => EntityDao(ref.watch(appDatabaseProvider)));
