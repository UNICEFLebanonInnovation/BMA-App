import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/db/entity_dao.dart';
import 'package:bma_app/core/models/entity_record.dart';
import 'package:bma_app/core/models/sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, dynamic> serverRegistration(int id, {String first = 'Mohamad', String modified = '2026-09-10T10:00:00'}) => {
      'id': id,
      'center': 41,
      'center_label': 'NFE',
      'round': 5,
      'registration_date': '2026-09-01',
      'have_labour': 'No',
      'modified': modified,
      'child': {
        'id': 100 + id,
        'first_name': first,
        'father_name': 'Ahmad',
        'last_name': 'Sayed',
        'mother_fullname': 'Fatima',
        'gender': 'Male',
        'nationality': 1,
        'nationality_label': 'Syrian',
        'birthday_year': '2015',
        'birthday_month': '3',
        'birthday_day': '5',
        'number': 'ABC123',
        'unicef_id': 'U-1',
      },
      'education_summary': [
        {'id': 1, 'round': 5, 'education_program': 'BLN Level 1', 'class_section': 'A', 'registration_date': '2026-09-01'}
      ],
    };

void main() {
  late AppDatabase db;
  late EntityDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await AppDatabase.openInMemory();
    dao = EntityDao(db);
  });

  tearDown(() => db.close());

  test('createLocal stores a pending create with label and search text', () async {
    final record = await dao.createLocal(entity: Entities.msccRegistration, data: {
      'child_first_name': 'Mohamad',
      'child_father_name': 'Ahmad',
      'child_last_name': 'Sayed',
      'child_gender': 'Male',
      'child_birthday_year': '2015',
    });
    expect(record.syncState, SyncState.pending);
    expect(record.op, 'create');
    expect(record.label, 'Mohamad Ahmad Sayed');
    expect(record.search, contains('mohamad'));

    final found = await dao.list(const RecordQuery(entity: Entities.msccRegistration, search: 'sayed moh'));
    expect(found.map((r) => r.uuid), [record.uuid]);
    expect((await dao.countsByState())[SyncState.pending], 1);
    expect(await dao.outbox(), hasLength(1));
  });

  test('applyPullChange inserts server records and links children to parents', () async {
    await dao.applyPullChange(PullChange(
        entity: Entities.msccRegistration, serverId: 8812, modified: '2026-09-10T10:00:00', data: serverRegistration(8812)));
    await dao.applyPullChange(const PullChange(
        entity: Entities.msccEducationService,
        serverId: 4401,
        parentId: 8812,
        modified: '2026-09-10T10:00:00',
        data: {'id': 4401, 'registration': 8812, 'education_program': 'BLN Level 1', 'class_section': 'A'}));
    final parent = await dao.byServerId(Entities.msccRegistration, 8812);
    expect(parent, isNotNull);
    expect(parent!.syncState, SyncState.synced);
    expect(parent.label, 'Mohamad Ahmad Sayed');
    final children = await dao.childrenOf(parent);
    expect(children, hasLength(1));
    expect(children.first.parentUuid, parent.uuid);

    // Deleted on the server → removed locally.
    await dao.applyPullChange(PullChange(
        entity: Entities.msccRegistration, serverId: 8812, deleted: true, data: serverRegistration(8812)));
    expect(await dao.byServerId(Entities.msccRegistration, 8812), isNull);
  });

  test('applyPullChange never overwrites unsent local edits', () async {
    await dao.applyPullChange(PullChange(
        entity: Entities.msccRegistration, serverId: 1, modified: '2026-09-10T10:00:00', data: serverRegistration(1)));
    final record = (await dao.byServerId(Entities.msccRegistration, 1))!;
    final edited = await dao.updateLocal(record, {...record.data, 'have_labour': 'Yes - Morning'});
    expect(edited.op, 'update');
    expect(edited.baseModified, '2026-09-10T10:00:00');

    await dao.applyPullChange(PullChange(
        entity: Entities.msccRegistration,
        serverId: 1,
        modified: '2026-09-11T10:00:00',
        data: serverRegistration(1, first: 'Changed', modified: '2026-09-11T10:00:00')));
    final after = (await dao.byServerId(Entities.msccRegistration, 1))!;
    expect(after.syncState, SyncState.pending);
    expect(after.data['have_labour'], 'Yes - Morning');
    expect(after.conflictData?['child']?['first_name'], 'Changed');
    expect(after.serverModified, '2026-09-11T10:00:00');
  });

  test('applyPushResult handles created, duplicate, conflict, error and discarded', () async {
    final reg = await dao.createLocal(entity: Entities.msccRegistration, data: {'child_first_name': 'A'});
    final svc = await dao.createLocal(
        entity: Entities.msccEducationService, data: {'education_program': 'BLN Level 1'}, parent: reg);
    expect(svc.parentUuid, reg.uuid);

    await dao.applyPushResult(
        reg,
        PushItemResult(
            clientUuid: reg.uuid, entity: reg.entity, status: 'created', serverId: 8812, dataAfter: serverRegistration(8812)));
    final created = (await dao.byUuid(reg.uuid))!;
    expect(created.syncState, SyncState.synced);
    expect(created.serverId, 8812);
    expect(created.data['child']['number'], 'ABC123');
    expect(created.op, isNull);
    final child = (await dao.byUuid(svc.uuid))!;
    expect(child.parentServerId, 8812, reason: 'children learn the parent server id');

    final dup = await dao.createLocal(entity: Entities.msccRegistration, data: {'child_first_name': 'B'});
    await dao.applyPushResult(
        dup,
        PushItemResult(clientUuid: dup.uuid, entity: dup.entity, status: 'duplicate', message: 'dup', duplicates: [
          {'registration_id': 8812, 'child_id': 8912, 'label': 'Mohamad Ahmad Sayed', 'match': {'reason': 'identity'}}
        ]));
    final flagged = (await dao.byUuid(dup.uuid))!;
    expect(flagged.syncState, SyncState.duplicate);
    expect(flagged.duplicates.first['registration_id'], 8812);
    expect(await dao.outbox(), isNotEmpty);

    final resolved = await dao.setResolution(flagged, {'action': 'discard', 'target_id': 8812});
    expect(resolved.syncState, SyncState.pending);
    await dao.applyPushResult(resolved, PushItemResult(clientUuid: dup.uuid, entity: dup.entity, status: 'discarded'));
    expect((await dao.byUuid(dup.uuid))!.syncState, SyncState.discarded);

    await dao.applyPushResult(
        created,
        PushItemResult(clientUuid: created.uuid, entity: created.entity, status: 'conflict', errors: {
          'server_data': {'id': 8812, 'have_labour': 'No'}
        }));
    expect((await dao.byUuid(created.uuid))!.syncState, SyncState.conflict);
    expect((await dao.byUuid(created.uuid))!.conflictData?['have_labour'], 'No');

    await dao.applyPushResult(
        child,
        PushItemResult(clientUuid: child.uuid, entity: child.entity, status: 'error', errors: {
          'education_program': ['Select a valid choice.']
        }));
    expect((await dao.byUuid(child.uuid))!.syncState, SyncState.error);
    expect((await dao.byUuid(child.uuid))!.lastError?['education_program'], ['Select a valid choice.']);
  });

  test('new round result creates the registration and removes the request', () async {
    final parent = await dao.createLocal(entity: Entities.msccRegistration, data: {'child_first_name': 'A'});
    final request = await dao.createLocal(entity: Entities.msccNewRoundKey, data: {'round': 6}, parent: parent);
    await dao.applyPushResult(
        request,
        PushItemResult(
            clientUuid: request.uuid,
            entity: request.entity,
            status: 'created',
            serverId: 9000,
            createdEntity: Entities.msccRegistration,
            dataAfter: serverRegistration(9000)));
    expect(await dao.byUuid(request.uuid), isNull);
    expect(await dao.byServerId(Entities.msccRegistration, 9000), isNotNull);
  });

  test('attendance documents are keyed by natural key and upsert', () async {
    final data = {
      'center_id': 41,
      'round_id': 5,
      'attendance_date': '2026-09-10',
      'education_program': 'BLN Level 1',
      'class_section': 'A',
      'attendance_day_off': 'No',
      'children_attendance': [
        {'registration_id': 8812, 'child_id': 8912, 'attended': 'No', 'absence_reason': 'Sick'}
      ],
    };
    final key = EntityDao.naturalKeyFor(Entities.msccAttendanceDay, data)!;
    final day = await dao.createLocal(entity: Entities.msccAttendanceDay, data: data, naturalKey: key);
    expect(day.op, 'upsert');
    expect(day.label, contains('BLN Level 1'));
    expect((await dao.byNaturalKey(Entities.msccAttendanceDay, key))!.uuid, day.uuid);

    // The same sheet pulled from the server after push merges into the local row.
    await dao.applyPullChange(PullChange(
        entity: Entities.msccAttendanceDay, serverId: 77, modified: '2026-09-10T12:00:00', data: {...data, 'id': 77}));
    final rows = await dao.list(const RecordQuery(entity: Entities.msccAttendanceDay));
    expect(rows, hasLength(1));
  });

  test('local duplicate pre-check matches normalised names, year and gender', () async {
    await dao.createLocal(entity: Entities.msccRegistration, data: {
      'child_first_name': 'Mohamad',
      'child_father_name': 'Ahmad',
      'child_last_name': 'Sayed',
      'child_gender': 'Male',
      'child_birthday_year': '2015',
    });
    final matches = await dao.findLocalDuplicates(Entities.msccRegistration, {
      'child_first_name': ' mohamad ',
      'child_father_name': 'AHMAD',
      'child_last_name': 'sayed',
      'child_gender': 'Male',
      'child_birthday_year': '2015',
    });
    expect(matches, hasLength(1));
    final none = await dao.findLocalDuplicates(Entities.msccRegistration, {
      'child_first_name': 'mohamad',
      'child_father_name': 'ahmad',
      'child_last_name': 'sayed',
      'child_gender': 'Female',
      'child_birthday_year': '2015',
    });
    expect(none, isEmpty);
  });
}
