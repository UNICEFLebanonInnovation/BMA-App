import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/db/entity_dao.dart';
import 'package:bma_app/core/db/reference_dao.dart';
import 'package:bma_app/core/db/sync_dao.dart';
import 'package:bma_app/core/models/entity_record.dart';
import 'package:bma_app/core/models/sync_models.dart';
import 'package:bma_app/core/network/api_client.dart';
import 'package:bma_app/core/network/bma_api.dart';
import 'package:bma_app/core/sync/sync_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// In-memory stand-in for the server implementing the sync protocol.
class FakeBmaApi extends BmaApi {
  FakeBmaApi() : super(ApiClient(baseUrl: 'https://example.invalid'));

  final List<Map<String, dynamic>> pushedItems = [];
  List<PullChange> pullChanges = [];
  int pullCalls = 0;
  String? lastSince;

  @override
  Future<Map<String, dynamic>> bootstrap({required String deviceId}) async => {
        'server_time': '2026-09-12T08:00:00',
        'reference': {
          'nationalities': [
            {'id': 1, 'name': 'سوري', 'name_en': 'Syrian', 'code': 'SY'}
          ],
          'centers': [
            {'id': 41, 'name': 'Makani', 'partner_id': 3}
          ],
          'rounds': {
            'mscc': [
              {'id': 5, 'name': '2025-2026', 'current_year': true}
            ],
            'alp': [],
            'clm': [],
          },
        },
        'choices': {
          'mscc.attendance.class_section': [
            {'value': '', 'label': '---'},
            {'value': 'A', 'label': 'A'}
          ]
        },
        'schemas': {
          'mscc.registration': {
            'key': 'mscc.registration',
            'module': 'mscc',
            'label': 'Registration',
            'kind': 'identity',
            'identity': true,
            'fields': [
              {'name': 'child_first_name', 'label': 'First name', 'type': 'text', 'required': true}
            ],
            'sections': [],
          }
        },
        'entities': ['mscc.registration'],
      };

  @override
  Future<({List<PullChange> changes, String serverTime, String? nextCursor, bool hasMore})> pull({
    String? since,
    String? cursor,
    int limit = AppConfig.pullPageSize,
    List<String>? entities,
    required String deviceId,
  }) async {
    pullCalls++;
    lastSince = since;
    return (changes: pullChanges, serverTime: '2026-09-12T09:00:00', nextCursor: null, hasMore: false);
  }

  @override
  Future<PushReport> push({required String batchUuid, required String deviceId, required List<Map<String, dynamic>> items}) async {
    pushedItems.addAll(items);
    final results = <PushItemResult>[];
    var nextId = 500;
    final created = <String, int>{};
    for (final item in items) {
      final uuid = item['client_uuid'] as String;
      final data = Map<String, dynamic>.from(item['data'] as Map);
      if (item['entity'] == 'mscc.registration') {
        if (data['child_first_name'] == 'Duplicate' && item['resolution'] == null) {
          results.add(PushItemResult(clientUuid: uuid, entity: 'mscc.registration', status: 'duplicate', message: 'dup', duplicates: [
            {'registration_id': 1, 'child_id': 2, 'label': 'Existing', 'match': {'reason': 'identity'}}
          ]));
          continue;
        }
        final merge = item['resolution']?['action'] == 'merge';
        final id = merge ? item['resolution']['target_id'] as int : nextId++;
        created[uuid] = id;
        results.add(PushItemResult(
          clientUuid: uuid,
          entity: 'mscc.registration',
          status: merge ? 'merged' : 'created',
          serverId: id,
          dataAfter: {
            'id': id,
            'modified': '2026-09-12T09:00:00',
            'child': {'id': id + 1000, 'first_name': data['child_first_name'], 'father_name': 'X', 'last_name': 'Y'},
          },
        ));
      } else if (item['entity'] == 'mscc.attendance_day') {
        final rows = (data['children_attendance'] as List).cast<Map>();
        final unresolved = rows.where((r) => r['registration_id'] == null && r['registration_uuid'] == null);
        results.add(PushItemResult(
            clientUuid: uuid, entity: 'mscc.attendance_day', status: unresolved.isEmpty ? 'created' : 'error', serverId: 77));
      } else {
        final parentOk = item['parent_id'] != null || created.containsKey(item['parent_uuid']);
        results.add(PushItemResult(
            clientUuid: uuid,
            entity: item['entity'] as String,
            status: parentOk ? 'created' : 'skipped',
            serverId: parentOk ? nextId++ : null,
            parentId: item['parent_id'] as int? ?? created[item['parent_uuid']]));
      }
    }
    final summary = <String, int>{'total': results.length};
    for (final r in results) {
      summary[r.status] = (summary[r.status] ?? 0) + 1;
    }
    return PushReport(batchId: 1, batchUuid: batchUuid, status: 'completed', summary: summary, results: results);
  }
}

void main() {
  late AppDatabase db;
  late FakeBmaApi api;
  late ProviderContainer container;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await AppDatabase.openInMemory();
    api = FakeBmaApi();
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      bmaApiProvider.overrideWithValue(api),
    ]);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('bootstrap stores reference lists, choices and schemas', () async {
    final engine = container.read(syncEngineProvider.notifier);
    await engine.bootstrap();
    final reference = container.read(referenceDaoProvider);
    expect((await reference.items('nationalities')).single.nameEn, 'Syrian');
    expect((await reference.items('rounds.mscc')).single.extra['current_year'], true);
    expect((await reference.choices('mscc.attendance.class_section')).last.value, 'A');
    expect((await reference.schema('mscc.registration'))!.fields.single.name, 'child_first_name');
    expect(await reference.hasBootstrap, isTrue);
  });

  test('pull applies changes and remembers the server time as next since', () async {
    api.pullChanges = [
      const PullChange(entity: 'mscc.registration', serverId: 8812, modified: '2026-09-10T10:00:00', data: {
        'id': 8812,
        'child': {'id': 1, 'first_name': 'Sara', 'father_name': 'Ali', 'last_name': 'Omar'}
      }),
    ];
    final engine = container.read(syncEngineProvider.notifier);
    expect(await engine.pull(), 1);
    expect(api.lastSince, isNull);
    final dao = container.read(entityDaoProvider);
    expect((await dao.byServerId('mscc.registration', 8812))!.label, 'Sara Ali Omar');
    await engine.pull();
    expect(api.lastSince, '2026-09-12T09:00:00');
  });

  test('push sends parents before children, flattens identity payloads and applies results', () async {
    final dao = container.read(entityDaoProvider);
    final reg = await dao.createLocal(entity: Entities.msccRegistration, data: {
      'child_first_name': 'Nour',
      'child_father_name': 'Hassan',
      'child_last_name': 'Ali',
      'cash_support_programmes': ['None'],
    });
    final svc = await dao.createLocal(entity: Entities.msccEducationService, data: {'education_program': 'BLN Level 1'}, parent: reg);
    final day = await dao.createLocal(entity: Entities.msccAttendanceDay, naturalKey: 'k', data: {
      'round_id': 5,
      'attendance_date': '2026-09-10',
      'children_attendance': [
        {'registration_uuid': reg.uuid, 'attended': 'Yes'}
      ],
    });

    final engine = container.read(syncEngineProvider.notifier);
    final reports = await engine.push();
    expect(reports, hasLength(1));
    expect(api.pushedItems.map((i) => i['entity']),
        [Entities.msccRegistration, Entities.msccEducationService, Entities.msccAttendanceDay]);
    final regItem = api.pushedItems.first;
    expect(regItem['op'], 'create');
    expect(regItem['data']['child_first_name'], 'Nour');
    expect(regItem['data']['cash_support_programmes'], ['None']);
    final svcItem = api.pushedItems[1];
    expect(svcItem['parent_uuid'], reg.uuid);

    final savedReg = (await dao.byUuid(reg.uuid))!;
    expect(savedReg.syncState, SyncState.synced);
    expect(savedReg.serverId, 500);
    expect(savedReg.data['child']['id'], 1500);
    final savedSvc = (await dao.byUuid(svc.uuid))!;
    expect(savedSvc.syncState, SyncState.synced);
    expect(savedSvc.parentServerId, 500);
    expect((await dao.byUuid(day.uuid))!.syncState, SyncState.synced);
    expect(container.read(syncEngineProvider).counts[SyncState.pending], 0);
    final history = await container.read(syncDaoProvider).history();
    expect(history.single.status, 'completed');
    expect(history.single.report!.results, hasLength(3));
  });

  test('duplicates stay on the device until resolved, then merge on the next push', () async {
    final dao = container.read(entityDaoProvider);
    final reg = await dao.createLocal(entity: Entities.msccRegistration, data: {'child_first_name': 'Duplicate'});
    final svc = await dao.createLocal(entity: Entities.msccPss, data: {'child_registered': 'Yes'}, parent: reg);
    final engine = container.read(syncEngineProvider.notifier);
    await engine.push();

    final flagged = (await dao.byUuid(reg.uuid))!;
    expect(flagged.syncState, SyncState.duplicate);
    expect(flagged.duplicates.single['registration_id'], 1);
    expect((await dao.byUuid(svc.uuid))!.syncState, SyncState.pending, reason: 'skipped children wait');
    expect(container.read(syncEngineProvider).attentionCount, 1);

    // Nothing is re-sent while the duplicate is unresolved.
    api.pushedItems.clear();
    await engine.push();
    expect(api.pushedItems.map((i) => i['entity']), [Entities.msccPss]);

    await dao.setResolution(flagged, {'action': 'merge', 'target_id': 1, 'overwrite': true});
    api.pushedItems.clear();
    await engine.push();
    expect(api.pushedItems.first['resolution'], {'action': 'merge', 'target_id': 1, 'overwrite': true});
    final merged = (await dao.byUuid(reg.uuid))!;
    expect(merged.syncState, SyncState.synced);
    expect(merged.serverId, 1);
    expect((await dao.byUuid(svc.uuid))!.parentServerId, 1);
  });

  test('flattenIdentityPayload converts the nested server shape to web-form fields', () {
    final flat = SyncEngine.flattenIdentityPayload(Entities.msccRegistration, {
      'id': 1,
      'have_labour': 'No',
      'center_label': 'X',
      'child': {
        'id': 9,
        'first_name': 'A',
        'nationality': 1,
        'nationality_label': 'Syrian',
        'national_number': '123',
        'first_phone_owner': 'Mother',
        'number': 'hash',
      },
    });
    expect(flat['child_first_name'], 'A');
    expect(flat['child_nationality'], 1);
    expect(flat['national_number'], '123');
    expect(flat['first_phone_owner'], 'Mother');
    expect(flat['child_id'], 9);
    expect(flat.containsKey('number'), isFalse);
    expect(flat.containsKey('center_label'), isFalse);
    expect(flat.containsKey('id'), isFalse);
    expect(flat['have_labour'], 'No');
  });
}
