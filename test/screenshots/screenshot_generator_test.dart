// Renders the application's screens with real fonts and realistic data and
// writes PNG screenshots to `screenshots/`.
//
// It is skipped by default; run it with:
//
//     BMA_SCREENSHOTS=1 flutter test test/screenshots/screenshot_generator_test.dart
//
// The data comes from `test/screenshots/fixtures/*.json`, generated from the
// real BMA-NFE API with `student_registration/mobile_api/tests/make_fixtures.py`.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bma_app/app.dart';
import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/config/settings_controller.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/db/entity_dao.dart';
import 'package:bma_app/core/db/reference_dao.dart';
import 'package:bma_app/core/db/sync_dao.dart';
import 'package:bma_app/core/models/entity_record.dart';
import 'package:bma_app/core/models/sync_models.dart';
import 'package:bma_app/core/models/user_profile.dart';
import 'package:bma_app/core/network/api_client.dart';
import 'package:bma_app/core/network/bma_api.dart';
import 'package:bma_app/core/sync/connectivity_service.dart';
import 'package:bma_app/core/sync/sync_engine.dart';
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:bma_app/features/tips/tips_controller.dart';
import 'package:bma_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final bool _enabled = Platform.environment['BMA_SCREENSHOTS'] == '1';
const _fixtures = 'test/screenshots/fixtures';
// The two push batches the seed writes, named so they can be routed to.
const _batchUuid = 'batch-0001';
const _dupBatchUuid = 'batch-0002';
const _outDir = 'screenshots';
final GlobalKey _shotKey = GlobalKey();

/// A capture target. The dpr belongs to the record, not to the call site:
/// see [_shootFor].
typedef Device = ({double width, double height, double dpr});

// THE APP IS TABLET-FIRST FOR A 9-INCH ANDROID TABLET, so the two tablet
// records below are the primary set and the phone is the documented fallback.
// 1280x800 and 800x1280 at dpr 2.0 is ~168 logical px per inch.
const Device _phone = (width: 412.0, height: 915.0, dpr: 2.625);
const Device _tablet = (width: 800.0, height: 1280.0, dpr: 2.0);
const Device _tabletLandscape = (width: 1280.0, height: 800.0, dpr: 2.0);

Map<String, dynamic> _json(String name) =>
    Map<String, dynamic>.from(jsonDecode(File('$_fixtures/$name').readAsStringSync()) as Map);

class FakeSessionStore extends SessionStore {
  final Map<String, String> _memory = {};

  @override
  Future<String?> read(String key) async => _memory[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _memory.remove(key);
    } else {
      _memory[key] = value;
    }
  }

  @override
  Future<String> deviceId() async => 'screenshot-device';
}

class FakeAuthController extends AuthController {
  FakeAuthController(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;

  @override
  Future<void> restore() async {}
}

class FixtureApi extends BmaApi {
  FixtureApi() : super(ApiClient(baseUrl: 'https://bma-nfe.example.org'));

  @override
  Future<Map<String, dynamic>> bootstrap({required String deviceId}) async => _json('bootstrap.json');

  @override
  Future<({List<PullChange> changes, String serverTime, String? nextCursor, bool hasMore})> pull({
    String? since,
    String? cursor,
    int limit = AppConfig.pullPageSize,
    List<String>? entities,
    required String deviceId,
  }) async {
    final json = _json('pull.json');
    return (
      changes: ((json['changes'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => PullChange.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      serverTime: (json['server_time'] ?? '').toString(),
      nextCursor: null,
      hasMore: false,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> duplicateCheck(String entity, Map<String, dynamic> data) async => const [];

  @override
  Future<PushReport> push({required String batchUuid, required String deviceId, required List<Map<String, dynamic>> items}) async =>
      PushReport.fromJson(_json('push_report.json'));
}

Future<ByteData> _fontBytes(String path) async {
  final bytes = await File(path).readAsBytes();
  return ByteData.view(bytes.buffer);
}

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final material = '$root/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final file in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf', 'Roboto-Light.ttf']) {
    roboto.addFont(_fontBytes('$material/$file'));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(_fontBytes('$material/MaterialIcons-Regular.otf'));
  await icons.load();
  final arabic = FontLoader('NotoSansArabic')
    ..addFont(_fontBytes('test/screenshots/fonts/NotoSansArabic-Regular.ttf'))
    ..addFont(_fontBytes('test/screenshots/fonts/NotoSansArabic-Bold.ttf'));
  await arabic.load();
  AppTheme.fontFamilyFallback = const ['NotoSansArabic'];
}

/// Let real async work (SQLite, providers) progress, then pump frames.
Future<void> _settle(WidgetTester tester, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 120));
  }
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
  } catch (_) {
    // Progress indicators keep animating; the frame is still complete.
  }
}

/// Writes `screenshots/<name>.png` for [device], at [device]'s OWN pixel ratio.
///
/// This replaces a helper that took the ratio as an argument entirely separate
/// from `_setSize(tester, device)`. Pairing `_setSize(tester, _tablet)` with
/// `_phone.dpr` produced a wrongly scaled PNG and no error whatsoever — a
/// silent defect, and precisely the sort that a third device record invites.
/// Here the ratio comes from the record, and the two assertions make a
/// mismatched pair fail instead of writing a bad file.
Future<void> _shootFor(WidgetTester tester, String name, Device device) async {
  expect(
    tester.view.devicePixelRatio,
    device.dpr,
    reason: 'shooting "$name" without _setSize(tester, <the same device>) first',
  );
  expect(
    tester.view.physicalSize,
    Size(device.width * device.dpr, device.height * device.dpr),
    reason: 'shooting "$name" at a size that is not ${device.width}x${device.height}',
  );
  await _settle(tester);
  final boundary = tester.renderObject(find.byKey(_shotKey)) as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: device.dpr));
  final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  final file = File('$_outDir/$name.png');
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('screenshot: ${file.path}');
}

void _setSize(WidgetTester tester, Device device) {
  tester.view.physicalSize = Size(device.width * device.dpr, device.height * device.dpr);
  tester.view.devicePixelRatio = device.dpr;
}

Future<ProviderContainer> _container({
  required bool signedIn,
  String language = 'en',
  bool tipsSeen = true,
  bool serverConfigured = true,
}) async {
  final db = await AppDatabase.openInMemory();
  final profile = UserProfile.fromJson(Map<String, dynamic>.from(_json('bootstrap.json')['user'] as Map));
  final auth = signedIn
      ? AuthState(status: AuthStatus.signedIn, profile: profile, token: 'token', deviceId: 'screenshot-device')
      : const AuthState(status: AuthStatus.signedOut, deviceId: 'screenshot-device');
  return ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    bmaApiProvider.overrideWithValue(FixtureApi()),
    sessionStoreProvider.overrideWithValue(FakeSessionStore()),
    authControllerProvider.overrideWith(() => FakeAuthController(auth)),
    // Keeps the existing captures on their routes; the first-run wizard would otherwise replace 02_home.
    tipsControllerProvider.overrideWith(
        () => TipsController(TipsState(seen: tipsSeen ? {TipsState.seenKey(profile.id)} : const {}), null)),
    settingsControllerProvider.overrideWith(() => SettingsController(
        AppSettings(
          serverUrl: 'https://bma-nfe.example.org',
          locale: Locale(language),
          serverConfigured: serverConfigured,
        ),
        null)),
    connectivityProvider.overrideWith((ref) => Stream.value(true)),
  ]);
}

/// Download everything and add offline work so every state is visible.
Future<
    ({
      String pulledUuid,
      String pendingUuid,
      String duplicateUuid,
      String batchUuid,
      String dupBatchUuid,
      List<EntityRecord> pulled,
    })> _seed(ProviderContainer container) async {
  final engine = container.read(syncEngineProvider.notifier);
  await engine.bootstrap();
  await engine.pull(full: true);
  final dao = container.read(entityDaoProvider);
  final profile = container.read(currentProfileProvider)!;
  final all = await dao.list(const RecordQuery(entity: Entities.msccRegistration, orderBy: 'server_id ASC'));
  // ONLY the records that came from the server. A local record has no
  // server_id, and `server_id ASC` sorts NULL FIRST in SQLite, so before this
  // filter `pulled.first` silently became a locally created child as soon as
  // one existed — which is why the child-profile capture was of an unsynced
  // record rather than of the synced one it names.
  final pulled = all.where((r) => r.serverId != null).toList();

  // EVERY container in this file shares one `:memory:` database (see
  // _alreadySeeded), and `pull` upserts by server id while `createLocal`
  // does not. Seeding twice therefore appended a SECOND pending child, a
  // second duplicate and a second failed service, so by the last test in the
  // file the beneficiaries list showed the same child seven times and the
  // "waiting to push" counter read 54. Seed once; hand back the same records
  // afterwards.
  final seededLocals = all.where((r) => r.serverId == null).toList();
  final previousPending = seededLocals.where((r) => r.data['child_last_name'] == 'العلي').toList();
  final previousDuplicate = seededLocals.where((r) => r.data['child_last_name'] == 'السيد').toList();
  if (previousPending.isNotEmpty && previousDuplicate.isNotEmpty) {
    await engine.refreshCounts();
    return (
      pulledUuid: pulled.isNotEmpty ? pulled.first.uuid : previousPending.first.uuid,
      pendingUuid: previousPending.first.uuid,
      duplicateUuid: previousDuplicate.first.uuid,
      batchUuid: _batchUuid,
      dupBatchUuid: _dupBatchUuid,
      pulled: pulled,
    );
  }

  final pending = await dao.createLocal(entity: Entities.msccRegistration, data: {
    'child_first_name': 'حسن',
    'child_father_name': 'محمود',
    'child_last_name': 'العلي',
    'child_mother_fullname': 'رنا خليل',
    'child_gender': 'Male',
    'child_nationality': 1,
    'child_birthday_year': '2016',
    'child_birthday_month': '8',
    'child_birthday_day': '12',
    'child_address': 'Bar Elias, informal settlement 021',
    'child_disability': 1,
    'child_living_arrangement': 'Living with caregivers',
    'source_of_identification': 'Awareness Session',
    'cash_support_programmes': ['None'],
    'first_phone_owner': 'Phone Main Caregiver',
    'first_phone_number': '03-778899',
    'first_phone_number_confirm': '03-778899',
    'main_caregiver': 'Mother',
    'have_labour': 'No',
    'id_type': 3,
    'registration_date': DateTime.now().toIso8601String().split('T').first,
  });

  final dupReport = PushReport.fromJson(_json('duplicate_report.json'));
  final dupResult = dupReport.results.first;
  final duplicate = await dao.createLocal(entity: Entities.msccRegistration, data: {
    'child_first_name': 'محمد',
    'child_father_name': 'أحمد',
    'child_last_name': 'السيد',
    'child_mother_fullname': 'فاطمة علي',
    'child_gender': 'Male',
    'child_nationality': 1,
    'child_birthday_year': '2015',
    'child_birthday_month': '3',
    'child_birthday_day': '5',
    'first_phone_number': '03-123456',
    'have_labour': 'No',
  });
  await dao.applyPushResult(
      duplicate,
      PushItemResult(
        clientUuid: duplicate.uuid,
        entity: dupResult.entity,
        status: dupResult.status,
        message: dupResult.message,
        duplicates: dupResult.duplicates,
      ));

  if (pulled.isNotEmpty) {
    final service = await dao.createLocal(
        entity: Entities.msccEducationService,
        data: {'education_program': 'BLN Level 4', 'class_section': 'B', 'round': 1},
        parent: pulled.first);
    await dao.applyPushResult(
        service,
        PushItemResult(clientUuid: service.uuid, entity: service.entity, status: 'error', message: 'Validation failed.', errors: {
          'education_program': ['Select a valid choice. BLN Level 4 is not one of the available choices.'],
          'registration_date': ['This field is required.'],
        }));
    await dao.createLocal(entity: Entities.msccFollowUp, data: {
      'follow_up_type': 'Phone call',
      'follow_up_number': '1',
      'follow_up_result': 'Child returned to program',
      'parent_attended_meeting': 'Yes',
      'meeting_type': 'PSS Session',
      'meeting_number': '2',
      'meeting_modality': 'Offline (F2F)',
      'caregiver_attended': 'Mother Only',
    }, parent: pulled.first);
  }

  // Today's attendance sheet, saved offline (one child absent).
  final today = DateTime.now();
  final iso = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  final rounds = await container.read(referenceDaoProvider).items('rounds.mscc');
  final round = rounds.firstWhere((r) => r.extra['current_year'] == true, orElse: () => rounds.first);
  final enrolled = <EntityRecord>[];
  for (final r in pulled) {
    final summary = (r.data['education_summary'] as List?) ?? const [];
    if (summary.any((e) => e['education_program'] == 'BLN Level 1' && e['class_section'] == 'A')) enrolled.add(r);
  }
  final attendance = {
    'round_id': round.id,
    'center_id': profile.center!.id,
    'attendance_date': iso,
    'education_program': 'BLN Level 1',
    'class_section': 'A',
    'attendance_day_off': 'No',
    'close_reason': '',
    'children_attendance': [
      for (var i = 0; i < enrolled.length; i++)
        {
          'registration_id': enrolled[i].serverId,
          'child_id': (enrolled[i].data['child'] as Map)['id'],
          'child_label': enrolled[i].label,
          'attended': i == 1 ? 'No' : 'Yes',
          'absence_reason': i == 1 ? 'Sick' : '',
          'absence_reason_other': '',
        },
    ],
  };
  await dao.createLocal(
      entity: Entities.msccAttendanceDay,
      data: attendance,
      naturalKey: EntityDao.naturalKeyFor(Entities.msccAttendanceDay, attendance));

  final batches = container.read(syncDaoProvider);
  final report = PushReport.fromJson(_json('push_report.json'));
  await batches.put(SyncBatch(
      uuid: _batchUuid,
      serverBatchId: report.batchId,
      startedAt: today.subtract(const Duration(hours: 3)).toIso8601String(),
      finishedAt: today.subtract(const Duration(hours: 3)).toIso8601String(),
      status: 'completed',
      summary: report.summary,
      itemCount: report.results.length,
      report: report));
  final dupResults = [
    PushItemResult(
        clientUuid: duplicate.uuid,
        entity: dupResult.entity,
        status: dupResult.status,
        message: dupResult.message,
        duplicates: dupResult.duplicates),
  ];
  await batches.put(SyncBatch(
      uuid: _dupBatchUuid,
      serverBatchId: dupReport.batchId,
      startedAt: today.subtract(const Duration(minutes: 20)).toIso8601String(),
      finishedAt: today.subtract(const Duration(minutes: 19)).toIso8601String(),
      status: 'completed',
      summary: {'total': 1, 'duplicate': 1},
      itemCount: 1,
      report: PushReport(
          batchId: dupReport.batchId, batchUuid: _dupBatchUuid, status: 'completed',
          summary: const {'total': 1, 'duplicate': 1}, results: dupResults)));
  await engine.refreshCounts();
  return (
    pulledUuid: pulled.isNotEmpty ? pulled.first.uuid : pending.uuid,
    pendingUuid: pending.uuid,
    duplicateUuid: duplicate.uuid,
    batchUuid: _batchUuid,
    dupBatchUuid: _dupBatchUuid,
    // The pulled children themselves, so a capture can pick one BY NAME
    // instead of by list position. The two-pane beneficiaries shot needs the
    // one child that the search box it also types into still matches.
    pulled: pulled,
  );
}

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(key: _shotKey, child: const BmaApp()),
    );

Future<void> _go(WidgetTester tester, ProviderContainer container, String location) async {
  container.read(appRouterProvider).go(location);
  await _settle(tester);
}

Future<void> _tapText(WidgetTester tester, String text, {bool last = false}) async {
  final finder = find.text(text);
  await tester.tap(last ? finder.last : finder.first, warnIfMissed: false);
  await _settle(tester, rounds: 4);
}

/// Taps a control by its stable ValueKey. Preferred over [_tapText] for the
/// app's own controls: a label change or a layout redesign must not silently
/// turn a capture into a screenshot of an empty screen.
Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget, reason: 'no widget with key "$key" to tap');
  await tester.tap(finder, warnIfMissed: false);
  await _settle(tester, rounds: 4);
}

/// Taps a DATA label — a programme name, a section letter — which has no key
/// of its own because it comes from the server's reference lists.
///
/// Unlike [_tapText] it fails when the label is not on screen. That matters on
/// the attendance flow: the reference picker is a bottom sheet on the phone and
/// a dialog on the tablet, and a tap that quietly missed used to leave the
/// harness writing a screenshot of an unloaded screen.
Future<void> _tapLabel(WidgetTester tester, String text, {bool last = false}) async {
  final finder = find.text(text);
  expect(finder, findsWidgets, reason: 'no "$text" on screen to tap');
  await tester.tap(last ? finder.last : finder.first, warnIfMissed: false);
  await _settle(tester, rounds: 4);
}

Future<void> _type(WidgetTester tester, String key, String text) async {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget, reason: 'no field with key "$key"');
  await tester.enterText(finder, text);
  await _settle(tester, rounds: 4);
}

/// Opens the attendance sheet the seed saved for today, by key throughout.
Future<void> _loadRoster(WidgetTester tester, ProviderContainer container) async {
  await _go(tester, container, Routes.attendance(BmaModule.mscc));
  await _tapKey(tester, 'att-programme');
  await _tapLabel(tester, 'BLN Level 1', last: true);
  await _tapKey(tester, 'att-section');
  await _tapLabel(tester, 'A', last: true);
  await _tapKey(tester, 'att-load');
  await _settle(tester);
  // A capture of this screen is only worth keeping if the roster really loaded.
  expect(find.byKey(const ValueKey('att-save')), findsOneWidget, reason: 'the roster did not load');
  expect(find.byKey(const ValueKey('att-mark-all')), findsOneWidget);
}

bool _isAttendanceToggle(Widget widget) {
  final key = widget.key;
  return key is ValueKey<String> && key.value.startsWith('att-toggle-');
}

/// Marks the child in roster position [index] absent by tapping the Absent
/// segment of that row's toggle. The point of the capture it feeds is that the
/// rows BELOW do not move, so it must act on a row with rows under it.
Future<void> _markAbsent(WidgetTester tester, int index, String absentLabel) async {
  final toggles = find.byWidgetPredicate(_isAttendanceToggle);
  expect(toggles, findsWidgets, reason: 'no attendance toggles on screen');
  expect(tester.widgetList(toggles).length, greaterThan(index), reason: 'roster shorter than ${index + 1} rows');
  final segment = find.descendant(of: toggles.at(index), matching: find.text(absentLabel));
  expect(segment, findsOneWidget, reason: 'row $index has no "$absentLabel" segment');
  await tester.tap(segment, warnIfMissed: false);
  await _settle(tester, rounds: 4);
}

/// The uuid of the pulled child whose label contains [fragment].
String _childNamed(List<EntityRecord> pulled, String fragment) => pulled
    .firstWhere((r) => r.label.contains(fragment), orElse: () => pulled.first)
    .uuid;

/// True when a previous test in this file already wrote these fixtures.
///
/// Every `_container()` in this file opens the SAME `:memory:` database, so a
/// second call would duplicate every row rather than replace it.
Future<bool> _alreadySeeded(EntityDao dao, String entity, String marker) async =>
    (await dao.list(RecordQuery(entity: entity, search: marker))).isNotEmpty;

/// Eight more children enrolled in BLN Level 1 section A, created LOCALLY and
/// only for the tablet captures.
///
/// The pull fixture has six children and three of them are in that class, which
/// is a fair sheet on a 412 px phone and a nearly empty table on a 1280x800
/// tablet — the one thing a tablet capture must not show. A real Makani section
/// is twenty to thirty children, so this is what the screen is actually for.
/// Deliberately NOT part of [_seed], and deliberately called only from the
/// three tablet tests, which run LAST: `AppDatabase.openInMemory()` opens
/// `:memory:` with sqflite's default `singleInstance: true`, so EVERY container
/// in this file shares one database and anything seeded here would show up in
/// the phone captures shot afterwards. For the same reason this is idempotent —
/// three tablet tests calling it against one database would otherwise list
/// every child three times.
Future<void> _seedClassmates(ProviderContainer container) async {
  final dao = container.read(entityDaoProvider);
  if (await _alreadySeeded(dao, Entities.msccRegistration, 'Sarkis')) return;
  final rounds = await container.read(referenceDaoProvider).items('rounds.mscc');
  final round = rounds.firstWhere((r) => r.extra['current_year'] == true, orElse: () => rounds.first);
  final today = DateTime.now();
  final enrolledOn = today.subtract(const Duration(days: 40)).toIso8601String().split('T').first;
  const children = [
    (first: 'يارا', father: 'باسل', last: 'الحاج', mother: 'سعاد الحاج', gender: 'Female', year: '2015'),
    (first: 'كريم', father: 'زياد', last: 'الخطيب', mother: 'أمل الخطيب', gender: 'Male', year: '2016'),
    (first: 'Tala', father: 'Ziad', last: 'Fares', mother: 'Hiba Fares', gender: 'Female', year: '2015'),
    (first: 'نور', father: 'عماد', last: 'شعبان', mother: 'دلال شعبان', gender: 'Female', year: '2014'),
    (first: 'Elias', father: 'Tony', last: 'Sarkis', mother: 'Maya Sarkis', gender: 'Male', year: '2016'),
    (first: 'رامي', father: 'فادي', last: 'العبد', mother: 'نجوى العبد', gender: 'Male', year: '2015'),
    (first: 'جنى', father: 'مازن', last: 'دياب', mother: 'وفاء دياب', gender: 'Female', year: '2016'),
    (first: 'Ziad', father: 'Wissam', last: 'Daher', mother: 'Lina Daher', gender: 'Male', year: '2014'),
  ];
  for (var i = 0; i < children.length; i++) {
    final c = children[i];
    final registration = await dao.createLocal(entity: Entities.msccRegistration, data: {
      'child_first_name': c.first,
      'child_father_name': c.father,
      'child_last_name': c.last,
      'child_mother_fullname': c.mother,
      'child_gender': c.gender,
      'child_nationality': i.isEven ? 1 : 2,
      'child_birthday_year': c.year,
      'child_birthday_month': '${(i % 12) + 1}',
      'child_birthday_day': '${(i % 27) + 1}',
      'child_disability': 1,
      'child_living_arrangement': 'Living with caregivers',
      'have_labour': 'No',
      'registration_date': enrolledOn,
    });
    // Eligibility for the sheet comes from the education service, exactly as it
    // does in the field: programme, section, round and a date on or before the
    // attendance date.
    await dao.createLocal(
      entity: Entities.msccEducationService,
      data: {
        'education_program': 'BLN Level 1',
        'class_section': 'A',
        'round': round.id,
        'registration_date': enrolledOn,
      },
      parent: registration,
    );
  }
}

/// One registration with EVERY required field of all three wizard sections
/// filled, created locally and only for the tablet captures.
///
/// The review step is reachable only by walking `_next()` — the step rail is
/// deliberately backward-only so the step-0 duplicate check cannot be jumped
/// over — and `_next()` runs that section's `validate()`. The pull fixture's
/// children have no caregiver block at all, so no record already in the
/// database can reach Review. This one can, which is what makes the review
/// capture a picture of the real screen rather than of a blocked wizard.
///
/// Values are chosen to leave every `reveal` closed except the phone-number
/// confirm pair, which the caregivers capture is there to show.
Future<EntityRecord> _seedCompleteRegistration(ProviderContainer container) async {
  final dao = container.read(entityDaoProvider);
  final existing = await dao.list(const RecordQuery(entity: Entities.msccRegistration, search: 'Merhi'));
  if (existing.isNotEmpty) return existing.first;
  return dao.createLocal(entity: Entities.msccRegistration, data: {
    'child_first_name': 'Lara',
    'child_father_name': 'Georges',
    'child_last_name': 'Merhi',
    'child_mother_fullname': 'Nadine Merhi',
    'child_gender': 'Female',
    'child_birthday_year': '2014',
    'child_birthday_month': '4',
    'child_birthday_day': '19',
    'child_nationality': 2,
    'child_disability': 1,
    'child_marital_status': 'Single',
    'child_have_children': 'No',
    'child_have_sibling': 'Yes',
    'child_mother_pregnant_expecting': 'No',
    'child_living_arrangement': 'Living with caregivers',
    'child_address': 'Bar Elias, Main Road, building 14',
    'source_of_identification': 'Awareness Session',
    'cash_support_programmes': ['None'],
    'main_caregiver': 'Mother',
    'caregiver_first_name': 'Nadine',
    'caregiver_middle_name': 'Elias',
    'caregiver_last_name': 'Merhi',
    'caregiver_mother_name': 'Therese Aoun',
    'father_educational_level': 3,
    'mother_educational_level': 4,
    'children_number_under18': 3,
    'first_phone_owner': 'Phone Main Caregiver',
    'first_phone_number': '03-661234',
    'first_phone_number_confirm': '03-661234',
    'id_type': 5,
    'have_labour': 'No',
    'registration_date': DateTime.now().toIso8601String().split('T').first,
  });
}

/// Eight more teachers, created LOCALLY and only for the tablet captures.
///
/// The pull fixture holds exactly one teacher, which says nothing about a
/// three-across grid or a no-scroll teacher-attendance sheet; nine is the size
/// of a real Makani teaching team. This is
/// deliberately NOT part of [_seed]: adding it there would change the phone
/// captures too, and those are the evidence that the phone fallback did not
/// move.
Future<void> _seedTeachers(ProviderContainer container) async {
  final dao = container.read(entityDaoProvider);
  if (await _alreadySeeded(dao, Entities.msccTeacher, 'Chidiac')) return;
  final profile = container.read(currentProfileProvider)!;
  const people = [
    (first: 'Rana', father: 'Samir', last: 'Haddad', mother: 'Leila Haddad', sex: 'Female', phone: '03-441122'),
    (first: 'Karim', father: 'Fouad', last: 'Chidiac', mother: 'Mona Chidiac', sex: 'Male', phone: '03-552233'),
    (first: 'ندى', father: 'وليد', last: 'شرف', mother: 'سميرة شرف', sex: 'Female', phone: '03-663344'),
    (first: 'Joelle', father: 'Antoine', last: 'Rizk', mother: 'Carla Rizk', sex: 'Female', phone: '03-774455'),
    (first: 'مها', father: 'سليم', last: 'الزين', mother: 'هناء الزين', sex: 'Female', phone: '03-885566'),
    (first: 'Georges', father: 'Michel', last: 'Abou Khalil', mother: 'Nada Abou Khalil', sex: 'Male', phone: '03-996677'),
    (first: 'سلمى', father: 'رامي', last: 'قاسم', mother: 'ليلى قاسم', sex: 'Female', phone: '03-117788'),
    (first: 'Maher', father: 'Nabil', last: 'Younes', mother: 'Salwa Younes', sex: 'Male', phone: '03-228899'),
  ];
  for (var i = 0; i < people.length; i++) {
    final p = people[i];
    await dao.createLocal(entity: Entities.msccTeacher, data: {
      'first_name': p.first,
      'father_name': p.father,
      'last_name': p.last,
      'mother_fullname': p.mother,
      'sex': p.sex,
      'birthdate': '19${80 + i}-0${(i % 9) + 1}-1${i % 10}',
      'nationality': 2,
      'center': profile.center?.id,
      'primary_phone_number': p.phone,
      'teacher_assignment': 'Makani only',
      'teaching_hours_mscc': 18 + i,
      'years_of_experience': 2 + i,
      'training_sessions_attended': i,
      'extra_coaching': 'no',
      'subjects_provided': const ['arabic'],
      'registration_level': const ['Level one'],
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    if (!_enabled) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Directory(_outDir).createSync(recursive: true);
    await _loadFonts();
  });

  testWidgets('first-run server setup', (tester) async {
    // serverConfigured: false, so the signed-out redirect opens the setup page.
    _setSize(tester, _phone);
    addTearDown(tester.view.reset);
    final english = await tester.runAsync(() => _container(signedIn: false, serverConfigured: false));
    addTearDown(english!.dispose);
    await tester.pumpWidget(_app(english));
    await _settle(tester);
    await _shootFor(tester, '28_server_setup', _phone);

    final arabic =
        await tester.runAsync(() => _container(signedIn: false, language: 'ar', serverConfigured: false));
    addTearDown(arabic!.dispose);
    await tester.pumpWidget(_app(arabic));
    await _settle(tester);
    await _shootFor(tester, '29_server_setup_arabic', _phone);
  }, skip: !_enabled);

  testWidgets('login screen', (tester) async {
    _setSize(tester, _phone);
    addTearDown(tester.view.reset);
    final container = await tester.runAsync(() => _container(signedIn: false));
    addTearDown(container!.dispose);
    await tester.pumpWidget(_app(container));
    await _settle(tester);
    await tester.enterText(find.byType(TextFormField).at(1), 'rima.center');
    await tester.enterText(find.byType(TextFormField).at(2), '••••••••');
    await _shootFor(tester, '01_login', _phone);
  }, skip: !_enabled);

  testWidgets('phone screens (English)', (tester) async {
    _setSize(tester, _phone);
    addTearDown(tester.view.reset);
    final container = await tester.runAsync(() => _container(signedIn: true));
    addTearDown(container!.dispose);
    final ids = await tester.runAsync(() => _seed(container));
    await tester.pumpWidget(_app(container));
    await _settle(tester);
    await _shootFor(tester, '02_home', _phone);

    await _go(tester, container, Routes.registrations(BmaModule.mscc));
    await _shootFor(tester, '03_beneficiaries', _phone);

    await _go(tester, container, Routes.profile(ids!.pulledUuid));
    await _shootFor(tester, '04_child_profile', _phone);
    await _tapText(tester, 'Services');
    await _shootFor(tester, '05_child_services', _phone);

    await _go(tester, container, Routes.editRegistration(ids.pulledUuid));
    await _shootFor(tester, '06_registration_wizard_identity', _phone);
    await _tapText(tester, 'Next');
    await _shootFor(tester, '07_registration_wizard_caregivers', _phone);

    await _go(tester, container, Routes.newService(ids.pulledUuid, 'mscc.pss'));
    await _shootFor(tester, '08_service_form_pss', _phone);

    await _go(tester, container, Routes.teachers(BmaModule.mscc));
    await _shootFor(tester, '09_teachers', _phone);

    await _go(tester, container, Routes.dashboard(BmaModule.mscc));
    await _shootFor(tester, '10_dashboard', _phone);

    await _go(tester, container, Routes.sync);
    await _shootFor(tester, '11_sync_center', _phone);

    await _go(tester, container, Routes.pushReport(ids.batchUuid));
    await _shootFor(tester, '12_push_report', _phone);

    await _go(tester, container, Routes.resolveDuplicate(ids.duplicateUuid));
    await _shootFor(tester, '13_duplicate_resolution', _phone);

    await _go(tester, container, Routes.syncHistory);
    await _shootFor(tester, '14_sync_history', _phone);

    await _go(tester, container, Routes.settings);
    await _shootFor(tester, '15_settings', _phone);
  }, skip: !_enabled);

  testWidgets('phone screens (Arabic)', (tester) async {
    _setSize(tester, _phone);
    addTearDown(tester.view.reset);
    final container = await tester.runAsync(() => _container(signedIn: true, language: 'ar'));
    addTearDown(container!.dispose);
    final ids = await tester.runAsync(() => _seed(container));
    await tester.pumpWidget(_app(container));
    await _settle(tester);
    await _shootFor(tester, '18_home_arabic', _phone);

    await _go(tester, container, Routes.registrations(BmaModule.mscc));
    await _shootFor(tester, '19_beneficiaries_arabic', _phone);

    await _go(tester, container, Routes.editRegistration(ids!.pendingUuid));
    await _shootFor(tester, '20_registration_wizard_arabic', _phone);

    await _go(tester, container, Routes.sync);
    await _shootFor(tester, '21_sync_center_arabic', _phone);
  }, skip: !_enabled);

  testWidgets('NFE centre profile', (tester) async {
    _setSize(tester, _phone);
    addTearDown(tester.view.reset);
    final container = await tester.runAsync(() => _container(signedIn: true));
    addTearDown(container!.dispose);
    await tester.runAsync(() => _seed(container));
    await tester.pumpWidget(_app(container));
    await _settle(tester);
    await _go(tester, container, Routes.centerProfile);
    await _shootFor(tester, '30_center_profile', _phone);

    final arabic = await tester.runAsync(() => _container(signedIn: true, language: 'ar'));
    addTearDown(arabic!.dispose);
    await tester.runAsync(() => _seed(arabic));
    await tester.pumpWidget(_app(arabic));
    await _settle(tester);
    await _go(tester, arabic, Routes.centerProfile);
    await _shootFor(tester, '31_center_profile_arabic', _phone);
  }, skip: !_enabled);

  testWidgets('tips wizard', (tester) async {
    // tipsSeen: false, so the first settled frame is the first-run wizard the
    // router redirects to; seeding first makes the data page report ready.
    _setSize(tester, _phone);
    addTearDown(tester.view.reset);
    final english = await tester.runAsync(() => _container(signedIn: true, tipsSeen: false));
    addTearDown(english!.dispose);
    await tester.runAsync(() => _seed(english));
    await tester.pumpWidget(_app(english));
    await _settle(tester);
    await _shootFor(tester, '22_tips_welcome', _phone);

    await _tapText(tester, 'Next');
    await _tapText(tester, 'Next');
    await _shootFor(tester, '23_tips_register', _phone);

    await _tapText(tester, 'Next');
    await _tapText(tester, 'Next');
    await _shootFor(tester, '24_tips_push', _phone);

    final arabic = await tester.runAsync(() => _container(signedIn: true, language: 'ar', tipsSeen: false));
    addTearDown(arabic!.dispose);
    await tester.runAsync(() => _seed(arabic));
    await tester.pumpWidget(_app(arabic));
    await _settle(tester);
    await _shootFor(tester, '25_tips_welcome_arabic', _phone);

    for (var i = 0; i < 4; i++) {
      await _tapText(tester, 'التالي');
    }
    await _shootFor(tester, '26_tips_push_arabic', _phone);

    _setSize(tester, _tablet);
    final tablet = await tester.runAsync(() => _container(signedIn: true, tipsSeen: false));
    addTearDown(tablet!.dispose);
    await tester.runAsync(() => _seed(tablet));
    await tester.pumpWidget(_app(tablet));
    await _settle(tester);
    await _shootFor(tester, '27_tips_welcome_tablet', _tablet);
  }, skip: !_enabled);

  // =====================================================================
  // PRIMARY SET — 9" tablet, 1280x800 landscape. The desk posture the whole
  // tablet-first layout exists for: extended navigation rail, two-pane
  // screens, multi-column forms.
  // =====================================================================
  testWidgets('tablet landscape screens (English)', (tester) async {
    _setSize(tester, _tabletLandscape);
    addTearDown(tester.view.reset);
    final container = await tester.runAsync(() => _container(signedIn: true));
    addTearDown(container!.dispose);
    final ids = await tester.runAsync(() => _seed(container));
    await tester.runAsync(() => _seedTeachers(container));
    await tester.runAsync(() => _seedClassmates(container));
    final complete = await tester.runAsync(() => _seedCompleteRegistration(container));
    await tester.pumpWidget(_app(container));
    await _settle(tester);
    await _shootFor(tester, '32_home_tablet_landscape', _tabletLandscape);

    // The search box stays filled across the selection: the visible proof that
    // selecting a child `replace`s the query parameter instead of pushing a
    // new page, so the list's State (search text, scroll offset) survives.
    await _go(tester, container, Routes.registrations(BmaModule.mscc));
    await _type(tester, 'reg-search', 'a');
    await _tapKey(tester, 'reg-row-${_childNamed(ids!.pulled, 'Omar')}');
    expect(find.byKey(const ValueKey('reg-detail-pane')), findsOneWidget, reason: 'no detail pane at 1280');
    await _shootFor(tester, '33_beneficiaries_two_pane_tablet_landscape', _tabletLandscape);

    await _go(tester, container, Routes.profile(ids.pulledUuid));
    await _shootFor(tester, '34_child_profile_tablet_landscape', _tabletLandscape);

    await _loadRoster(tester, container);
    expect(find.byKey(const ValueKey('att-session-pane')), findsOneWidget, reason: 'no session pane at 1280');
    expect(find.byKey(const ValueKey('att-roster')), findsOneWidget);
    await _shootFor(tester, '35_attendance_tablet_landscape', _tabletLandscape);

    // Marking a child absent must reveal the reason on the SAME line and leave
    // every row below exactly where it was.
    await _markAbsent(tester, 2, 'Absent');
    await _shootFor(tester, '36_attendance_absent_tablet_landscape', _tabletLandscape);

    await _go(tester, container, Routes.editRegistration(complete!.uuid));
    expect(find.byKey(const ValueKey('wizard-step-rail')), findsOneWidget, reason: 'no step rail at 1280');
    await _tapKey(tester, 'wizard-next');
    await _shootFor(tester, '37_registration_wizard_caregivers_tablet_landscape', _tabletLandscape);
    await _tapKey(tester, 'wizard-next');
    await _tapKey(tester, 'wizard-next');
    // The step rail is backward-only, so reaching Review means every section
    // actually validated — if one did not, this fails instead of capturing the
    // wrong step under the right name.
    expect(
      find.descendant(of: find.byKey(const ValueKey('wizard-next')), matching: find.text('Submit')),
      findsOneWidget,
      reason: 'the wizard never reached the review step',
    );
    await _shootFor(tester, '38_registration_wizard_review_tablet_landscape', _tabletLandscape);

    await _go(tester, container, Routes.newService(ids.pulledUuid, 'mscc.health_nutrition'));
    await _shootFor(tester, '39_service_form_health_tablet_landscape', _tabletLandscape);

    await _go(tester, container, Routes.newTeacher(BmaModule.mscc));
    await _shootFor(tester, '40_teacher_form_tablet_landscape', _tabletLandscape);

    await _go(tester, container, Routes.teacherAttendance(BmaModule.mscc));
    await _shootFor(tester, '41_teacher_attendance_tablet_landscape', _tabletLandscape);

    await _go(tester, container, Routes.teachers(BmaModule.mscc));
    await _shootFor(tester, '42_teachers_grid_tablet_landscape', _tabletLandscape);

    await _go(tester, container, Routes.dashboard(BmaModule.mscc));
    await _shootFor(tester, '43_dashboard_tablet_landscape', _tabletLandscape);

    await _go(tester, container, Routes.sync);
    await _shootFor(tester, '44_sync_center_two_pane_tablet_landscape', _tabletLandscape);

    await _go(tester, container, Routes.resolveDuplicate(ids.duplicateUuid));
    await _shootFor(tester, '45_duplicate_resolution_two_pane_tablet_landscape', _tabletLandscape);
  }, skip: !_enabled);

  // =====================================================================
  // PRIMARY SET — Arabic at 1280x800. The rail moves to the trailing (right)
  // edge and every pane mirrors; these are the captures that expose an
  // EdgeInsets.fromLTRB that should have been EdgeInsetsDirectional.
  // =====================================================================
  testWidgets('tablet landscape screens (Arabic)', (tester) async {
    _setSize(tester, _tabletLandscape);
    addTearDown(tester.view.reset);
    final container = await tester.runAsync(() => _container(signedIn: true, language: 'ar'));
    addTearDown(container!.dispose);
    final ids = await tester.runAsync(() => _seed(container));
    await tester.runAsync(() => _seedClassmates(container));
    await tester.pumpWidget(_app(container));
    await _settle(tester);
    await _shootFor(tester, '46_home_ar_tablet_landscape', _tabletLandscape);

    // Addressed by the `?sel=` query parameter rather than by a tap: the list
    // is long enough here that the target row is not built yet, and this is the
    // same URL the tap produces — the shareable, rotation-proof one.
    await _go(tester, container, Routes.registrationsSelected(BmaModule.mscc, ids!.pulledUuid));
    expect(find.byKey(const ValueKey('reg-detail-pane')), findsOneWidget, reason: 'no detail pane at 1280');
    await _shootFor(tester, '47_beneficiaries_two_pane_ar_tablet_landscape', _tabletLandscape);

    await _loadRoster(tester, container);
    await _markAbsent(tester, 2, 'غائب');
    await _shootFor(tester, '48_attendance_ar_tablet_landscape', _tabletLandscape);

    await _go(tester, container, Routes.editRegistration(ids.pendingUuid));
    await _shootFor(tester, '49_registration_wizard_ar_tablet_landscape', _tabletLandscape);

    await _go(tester, container, Routes.sync);
    await _shootFor(tester, '50_sync_center_ar_tablet_landscape', _tabletLandscape);
  }, skip: !_enabled);

  // =====================================================================
  // PRIMARY SET — 9" tablet, 800x1280 portrait. No rail (the window is below
  // the 1000 px rail threshold), no panes; this is the registration posture,
  // where the win is two-column forms and a 2-across filter grid.
  // =====================================================================
  testWidgets('tablet portrait screens (English)', (tester) async {
    _setSize(tester, _tablet);
    addTearDown(tester.view.reset);
    final container = await tester.runAsync(() => _container(signedIn: true));
    addTearDown(container!.dispose);
    final ids = await tester.runAsync(() => _seed(container));
    await tester.runAsync(() => _seedClassmates(container));
    await tester.pumpWidget(_app(container));
    await _settle(tester);
    await _shootFor(tester, '51_home_tablet', _tablet);

    // Deliberately single-pane: 800 px split two ways gives a 400 px list and
    // a 400 px profile, and neither is usable. This capture documents that
    // decision rather than hiding it.
    await _go(tester, container, Routes.registrations(BmaModule.mscc));
    expect(find.byKey(const ValueKey('reg-detail-pane')), findsNothing, reason: 'portrait must stay single-pane');
    await _shootFor(tester, '17_beneficiaries_tablet', _tablet);

    await _go(tester, container, Routes.editRegistration(ids!.pulledUuid));
    await _shootFor(tester, '53_registration_wizard_identity_tablet', _tablet);

    await _go(tester, container, Routes.newService(ids.pulledUuid, 'mscc.pss'));
    await _shootFor(tester, '54_service_form_tablet', _tablet);

    await _loadRoster(tester, container);
    expect(find.byKey(const ValueKey('att-session-pane')), findsNothing, reason: 'portrait must stay single-pane');
    await _shootFor(tester, '16_attendance_tablet', _tablet);

    await _go(tester, container, Routes.centerProfile);
    await _shootFor(tester, '56_center_profile_tablet', _tablet);
  }, skip: !_enabled);
}
