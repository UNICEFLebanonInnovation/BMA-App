import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../auth/auth_controller.dart';
import '../config/app_config.dart';
import '../db/entity_dao.dart';
import '../db/providers.dart';
import '../db/reference_dao.dart';
import '../db/sync_dao.dart';
import '../models/entity_record.dart';
import '../models/form_schema.dart';
import '../models/reference_item.dart';
import '../models/sync_models.dart';
import '../network/api_exception.dart';
import '../network/bma_api.dart';

enum SyncPhase { idle, bootstrapping, pulling, pushing }

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.progress,
    this.message,
    this.error,
    this.lastReport,
    this.lastPull,
    this.bootstrapAt,
    this.counts = const {},
  });

  final SyncPhase phase;
  final double? progress;
  final String? message;
  final String? error;
  final PushReport? lastReport;
  final String? lastPull;
  final String? bootstrapAt;
  final Map<SyncState, int> counts;

  bool get busy => phase != SyncPhase.idle;
  int get pendingCount => (counts[SyncState.pending] ?? 0) + (counts[SyncState.pushing] ?? 0);
  int get attentionCount =>
      (counts[SyncState.duplicate] ?? 0) + (counts[SyncState.conflict] ?? 0) + (counts[SyncState.error] ?? 0);

  SyncStatus copyWith({
    SyncPhase? phase,
    double? progress,
    bool clearProgress = false,
    String? message,
    String? error,
    bool clearError = false,
    PushReport? lastReport,
    String? lastPull,
    String? bootstrapAt,
    Map<SyncState, int>? counts,
  }) =>
      SyncStatus(
        phase: phase ?? this.phase,
        progress: clearProgress ? null : (progress ?? this.progress),
        message: message ?? this.message,
        error: clearError ? null : (error ?? this.error),
        lastReport: lastReport ?? this.lastReport,
        lastPull: lastPull ?? this.lastPull,
        bootstrapAt: bootstrapAt ?? this.bootstrapAt,
        counts: counts ?? this.counts,
      );
}

/// Orchestrates bootstrap, pull and push against the BMA-NFE server.
class SyncEngine extends Notifier<SyncStatus> {
  late BmaApi _api;
  late EntityDao _records;
  late ReferenceDao _reference;
  late SyncDao _batches;

  @override
  SyncStatus build() {
    _api = ref.watch(bmaApiProvider);
    _records = ref.watch(entityDaoProvider);
    _reference = ref.watch(referenceDaoProvider);
    _batches = ref.watch(syncDaoProvider);
    Future.microtask(refreshCounts);
    return const SyncStatus();
  }

  String get _deviceId => ref.read(authControllerProvider).deviceId ?? 'unknown-device';

  Future<void> refreshCounts() async {
    final counts = await _records.countsByState();
    final lastPull = await _reference.getMeta(ReferenceDao.metaLastPull);
    final bootstrapAt = await _reference.getMeta(ReferenceDao.metaBootstrapAt);
    state = state.copyWith(counts: counts, lastPull: lastPull, bootstrapAt: bootstrapAt);
    bumpDataVersion(ref);
  }

  // ------------------------------------------------------------- bootstrap
  Future<void> bootstrap() async {
    if (state.busy) return;
    state = state.copyWith(phase: SyncPhase.bootstrapping, clearError: true, message: 'bootstrap');
    try {
      final json = await _api.bootstrap(deviceId: _deviceId);
      await storeBootstrap(json);
      state = state.copyWith(phase: SyncPhase.idle, clearProgress: true);
      await refreshCounts();
    } catch (e) {
      state = state.copyWith(phase: SyncPhase.idle, error: _describe(e), clearProgress: true);
      rethrow;
    }
  }

  /// Persist a bootstrap payload (public for tests).
  Future<void> storeBootstrap(Map<String, dynamic> json) async {
    final reference = Map<String, dynamic>.from((json['reference'] as Map?) ?? const {});
    for (final entry in reference.entries) {
      if (entry.key == 'rounds' && entry.value is Map) {
        for (final round in Map<String, dynamic>.from(entry.value as Map).entries) {
          await _reference.replaceKind('rounds.${round.key}', _items('rounds.${round.key}', round.value));
        }
        continue;
      }
      await _reference.replaceKind(entry.key, _items(entry.key, entry.value));
    }
    final choices = <String, List<ChoiceRow>>{};
    final choicesJson = Map<String, dynamic>.from((json['choices'] as Map?) ?? const {});
    for (final entry in choicesJson.entries) {
      var position = 0;
      choices[entry.key] = ((entry.value as List?) ?? const [])
          .whereType<Map>()
          .map((c) => ChoiceRow(
                key: entry.key,
                value: (c['value'] ?? '').toString(),
                label: (c['label'] ?? '').toString(),
                labelAr: c['label_ar']?.toString(),
                position: position++,
              ))
          .toList();
    }
    await _reference.replaceChoices(choices);
    final schemasJson = Map<String, dynamic>.from((json['schemas'] as Map?) ?? const {});
    final schemas = <String, EntitySchema>{
      for (final entry in schemasJson.entries)
        entry.key: EntitySchema.fromJson(Map<String, dynamic>.from(entry.value as Map)),
    };
    await _reference.replaceSchemas(schemas);
    await _reference.setMeta(ReferenceDao.metaEntities,
        ((json['entities'] as List?) ?? const []).map((e) => e.toString()).join(','));
    await _reference.setMeta(ReferenceDao.metaBootstrapAt, (json['server_time'] ?? DateTime.now().toIso8601String()).toString());
  }

  static List<ReferenceItem> _items(String kind, Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map((e) => ReferenceItem.fromJson(kind, Map<String, dynamic>.from(e))).toList();
  }

  // ------------------------------------------------------------------ pull
  Future<int> pull({bool full = false}) async {
    if (state.busy) return 0;
    state = state.copyWith(phase: SyncPhase.pulling, clearError: true, message: 'pull');
    var applied = 0;
    try {
      final since = full ? null : await _reference.getMeta(ReferenceDao.metaLastPull);
      String? cursor;
      String serverTime = DateTime.now().toIso8601String();
      while (true) {
        final page = await _api.pull(since: since, cursor: cursor, deviceId: _deviceId);
        serverTime = page.serverTime.isEmpty ? serverTime : page.serverTime;
        for (final change in page.changes) {
          await _records.applyPullChange(change);
          applied++;
        }
        state = state.copyWith(message: 'pull:$applied');
        if (!page.hasMore || page.nextCursor == null) break;
        cursor = page.nextCursor;
      }
      await _reference.setMeta(ReferenceDao.metaLastPull, serverTime);
      state = state.copyWith(phase: SyncPhase.idle, clearProgress: true);
      await refreshCounts();
      return applied;
    } catch (e) {
      state = state.copyWith(phase: SyncPhase.idle, error: _describe(e), clearProgress: true);
      await _handleAuth(e);
      rethrow;
    }
  }

  // ------------------------------------------------------------------ push
  /// Push every pending record. Returns the reports of all batches sent.
  Future<List<PushReport>> push() async {
    if (state.busy) return const [];
    state = state.copyWith(phase: SyncPhase.pushing, clearError: true, message: 'push');
    final reports = <PushReport>[];
    try {
      final outbox = await _records.outbox();
      final ready = outbox.where(_readyToPush).toList();
      if (ready.isEmpty) {
        state = state.copyWith(phase: SyncPhase.idle, clearProgress: true);
        await refreshCounts();
        return reports;
      }
      final batches = _chunk(ready, AppConfig.pushBatchSize);
      var done = 0;
      for (final batch in batches) {
        final report = await _pushBatch(batch);
        reports.add(report);
        done += batch.length;
        state = state.copyWith(progress: done / ready.length, lastReport: report, message: 'push:$done/${ready.length}');
      }
      state = state.copyWith(phase: SyncPhase.idle, clearProgress: true);
      await refreshCounts();
      return reports;
    } catch (e) {
      await _records.resetPushing();
      state = state.copyWith(phase: SyncPhase.idle, error: _describe(e), clearProgress: true);
      await refreshCounts();
      await _handleAuth(e);
      rethrow;
    }
  }

  /// Duplicates/conflicts/errors are only re-sent once the user resolved or
  /// edited them (which puts them back to `pending`).
  bool _readyToPush(EntityRecord r) =>
      r.syncState == SyncState.pending || (r.resolution != null && r.syncState != SyncState.discarded);

  Future<PushReport> _pushBatch(List<EntityRecord> batch) async {
    final batchUuid = const Uuid().v4();
    final startedAt = DateTime.now().toIso8601String();
    await _batches.put(SyncBatch(uuid: batchUuid, startedAt: startedAt, status: 'pushing', itemCount: batch.length));
    await _records.markPushing(batch);
    final byUuid = {for (final r in batch) r.uuid: r};
    final uuids = byUuid.keys.toSet();
    final items = <Map<String, dynamic>>[];
    for (final record in batch) {
      items.add(await buildItem(record, uuidsInBatch: uuids));
    }
    PushReport report;
    try {
      report = await _api.push(batchUuid: batchUuid, deviceId: _deviceId, items: items);
    } catch (e) {
      await _batches.put(SyncBatch(
          uuid: batchUuid, startedAt: startedAt, finishedAt: DateTime.now().toIso8601String(),
          status: 'failed', itemCount: batch.length, error: _describe(e)));
      rethrow;
    }
    for (final result in report.results) {
      final record = byUuid[result.clientUuid];
      if (record == null) continue;
      await _records.applyPushResult(record, result);
    }
    // Anything the server did not answer for goes back to pending.
    final answered = report.results.map((r) => r.clientUuid).toSet();
    for (final record in batch) {
      if (!answered.contains(record.uuid)) {
        await _records.put(record.copyWith(syncState: SyncState.pending));
      }
    }
    await _batches.put(SyncBatch(
      uuid: batchUuid,
      serverBatchId: report.batchId,
      startedAt: startedAt,
      finishedAt: DateTime.now().toIso8601String(),
      status: 'completed',
      itemCount: batch.length,
      summary: report.summary,
      report: report,
    ));
    return report;
  }

  /// Build the wire representation of a record (public for tests).
  Future<Map<String, dynamic>> buildItem(EntityRecord record, {Set<String> uuidsInBatch = const {}}) async {
    final item = <String, dynamic>{
      'client_uuid': record.uuid,
      'entity': record.entity,
      'op': record.op ?? (record.serverId == null ? 'create' : 'update'),
      'server_id': record.serverId,
      'client_modified': record.clientModified,
      'base_modified': record.baseModified ?? record.serverModified,
      'data': _payloadFor(record),
      if (record.resolution != null) 'resolution': record.resolution,
    };
    if (record.parentServerId != null) {
      item['parent_id'] = record.parentServerId;
    } else if (record.parentUuid != null) {
      final parent = await _records.byUuid(record.parentUuid!);
      if (parent?.serverId != null) {
        item['parent_id'] = parent!.serverId;
      } else if (uuidsInBatch.contains(record.parentUuid)) {
        item['parent_uuid'] = record.parentUuid;
      } else {
        item['parent_uuid'] = record.parentUuid;
      }
    }
    return item;
  }

  Map<String, dynamic> _payloadFor(EntityRecord record) {
    final data = Map<String, dynamic>.from(record.data);
    if (Entities.identityEntities.contains(record.entity)) {
      return flattenIdentityPayload(record.entity, data);
    }
    data.removeWhere((key, _) => key.endsWith('_label') || _serverOnlyGeneric.contains(key));
    return data;
  }

  static const _serverOnlyGeneric = {'id', 'created', 'modified', 'owner', 'modified_by', 'label'};

  /// Registrations are stored locally in the server shape (nested child)
  /// but posted in the web-form shape (`child_*` prefixed fields).
  static Map<String, dynamic> flattenIdentityPayload(String entity, Map<String, dynamic> data) {
    final prefix = entity == Entities.clmBridging ? 'student_' : 'child_';
    final personKey = entity == Entities.clmBridging ? 'student' : 'child';
    final result = <String, dynamic>{};
    final person = data[personKey];
    if (person is Map) {
      final p = Map<String, dynamic>.from(person);
      for (final entry in p.entries) {
        if (entry.key == 'id') {
          result['${personKey}_id'] = entry.value;
          continue;
        }
        if (entry.key.endsWith('_label') || _serverOnly.contains(entry.key)) continue;
        result[_personFieldName(entity, prefix, entry.key)] = entry.value;
      }
    }
    for (final entry in data.entries) {
      if (entry.key == personKey || entry.key.endsWith('_label') || _serverOnly.contains(entry.key)) continue;
      result[entry.key] = entry.value;
    }
    return result;
  }

  static const _serverOnly = {
    'id', 'created', 'modified', 'owner', 'modified_by', 'deleted', 'deleted_by', 'number', 'unicef_id', 'full_name',
    'birthday', 'birthdate', 'age', 'photo', 'cash_programmes', 'education_summary', 'dropout_date', 'label',
  };

  /// Child fields that the web form exposes with a `child_` prefix versus the
  /// ones it keeps unprefixed (ids, caregiver, phones, labour…).
  static String _personFieldName(String entity, String prefix, String field) {
    if (entity == Entities.clmBridging) {
      return '$prefix$field';
    }
    const prefixed = {
      'first_name', 'father_name', 'last_name', 'mother_fullname', 'gender', 'nationality', 'nationality_other',
      'birthday_year', 'birthday_month', 'birthday_day', 'p_code', 'address', 'living_arrangement', 'disability',
      'disability_other', 'marital_status', 'have_children', 'children_number', 'have_sibling',
      'siblings_have_disability', 'mother_pregnant_expecting', 'fe_unique_id',
    };
    return prefixed.contains(field) ? '$prefix$field' : field;
  }

  // ------------------------------------------------------------------ misc
  Future<void> syncAll({bool fullPull = false}) async {
    await push();
    await pull(full: fullPull);
  }

  static List<List<T>> _chunk<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      chunks.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return chunks;
  }

  Future<void> _handleAuth(Object error) async {
    if (error is ApiException && error.isUnauthorized) {
      await ref.read(authControllerProvider.notifier).sessionExpired();
    }
  }

  static String _describe(Object error) {
    if (error is ApiException) return error.message;
    return error.toString();
  }
}

final syncEngineProvider = NotifierProvider<SyncEngine, SyncStatus>(SyncEngine.new);
