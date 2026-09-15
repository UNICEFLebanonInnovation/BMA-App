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
const _outDir = 'screenshots';
final GlobalKey _shotKey = GlobalKey();

// Pixel 7 class phone and a 10" tablet.
const _phone = (width: 412.0, height: 915.0, dpr: 2.625);
const _tablet = (width: 800.0, height: 1280.0, dpr: 2.0);

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

Future<void> _shoot(WidgetTester tester, String name, double dpr) async {
  await _settle(tester);
  final boundary = tester.renderObject(find.byKey(_shotKey)) as RenderRepaintBoundary;
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: dpr));
  final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
  final file = File('$_outDir/$name.png');
  file.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('screenshot: ${file.path}');
}

void _setSize(WidgetTester tester, ({double width, double height, double dpr}) device) {
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
Future<({String pulledUuid, String pendingUuid, String duplicateUuid, String batchUuid, String dupBatchUuid})> _seed(
    ProviderContainer container) async {
  final engine = container.read(syncEngineProvider.notifier);
  await engine.bootstrap();
  await engine.pull(full: true);
  final dao = container.read(entityDaoProvider);
  final profile = container.read(currentProfileProvider)!;
  final pulled = await dao.list(const RecordQuery(entity: Entities.msccRegistration, orderBy: 'server_id ASC'));

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
  const batchUuid = 'batch-0001';
  const dupBatchUuid = 'batch-0002';
  await batches.put(SyncBatch(
      uuid: batchUuid,
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
      uuid: dupBatchUuid,
      serverBatchId: dupReport.batchId,
      startedAt: today.subtract(const Duration(minutes: 20)).toIso8601String(),
      finishedAt: today.subtract(const Duration(minutes: 19)).toIso8601String(),
      status: 'completed',
      summary: {'total': 1, 'duplicate': 1},
      itemCount: 1,
      report: PushReport(
          batchId: dupReport.batchId, batchUuid: dupBatchUuid, status: 'completed',
          summary: const {'total': 1, 'duplicate': 1}, results: dupResults)));
  await engine.refreshCounts();
  return (
    pulledUuid: pulled.isNotEmpty ? pulled.first.uuid : pending.uuid,
    pendingUuid: pending.uuid,
    duplicateUuid: duplicate.uuid,
    batchUuid: batchUuid,
    dupBatchUuid: dupBatchUuid,
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
    await _shoot(tester, '28_server_setup', _phone.dpr);

    final arabic =
        await tester.runAsync(() => _container(signedIn: false, language: 'ar', serverConfigured: false));
    addTearDown(arabic!.dispose);
    await tester.pumpWidget(_app(arabic));
    await _settle(tester);
    await _shoot(tester, '29_server_setup_arabic', _phone.dpr);
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
    await _shoot(tester, '01_login', _phone.dpr);
  }, skip: !_enabled);

  testWidgets('phone screens (English)', (tester) async {
    _setSize(tester, _phone);
    addTearDown(tester.view.reset);
    final container = await tester.runAsync(() => _container(signedIn: true));
    addTearDown(container!.dispose);
    final ids = await tester.runAsync(() => _seed(container));
    await tester.pumpWidget(_app(container));
    await _settle(tester);
    await _shoot(tester, '02_home', _phone.dpr);

    await _go(tester, container, Routes.registrations(BmaModule.mscc));
    await _shoot(tester, '03_beneficiaries', _phone.dpr);

    await _go(tester, container, Routes.profile(ids!.pulledUuid));
    await _shoot(tester, '04_child_profile', _phone.dpr);
    await _tapText(tester, 'Services');
    await _shoot(tester, '05_child_services', _phone.dpr);

    await _go(tester, container, Routes.editRegistration(ids.pulledUuid));
    await _shoot(tester, '06_registration_wizard_identity', _phone.dpr);
    await _tapText(tester, 'Next');
    await _shoot(tester, '07_registration_wizard_caregivers', _phone.dpr);

    await _go(tester, container, Routes.newService(ids.pulledUuid, 'mscc.pss'));
    await _shoot(tester, '08_service_form_pss', _phone.dpr);

    await _go(tester, container, Routes.teachers(BmaModule.mscc));
    await _shoot(tester, '09_teachers', _phone.dpr);

    await _go(tester, container, Routes.dashboard(BmaModule.mscc));
    await _shoot(tester, '10_dashboard', _phone.dpr);

    await _go(tester, container, Routes.sync);
    await _shoot(tester, '11_sync_center', _phone.dpr);

    await _go(tester, container, Routes.pushReport(ids.batchUuid));
    await _shoot(tester, '12_push_report', _phone.dpr);

    await _go(tester, container, Routes.resolveDuplicate(ids.duplicateUuid));
    await _shoot(tester, '13_duplicate_resolution', _phone.dpr);

    await _go(tester, container, Routes.syncHistory);
    await _shoot(tester, '14_sync_history', _phone.dpr);

    await _go(tester, container, Routes.settings);
    await _shoot(tester, '15_settings', _phone.dpr);
  }, skip: !_enabled);

  testWidgets('tablet attendance sheet', (tester) async {
    _setSize(tester, _tablet);
    addTearDown(tester.view.reset);
    final container = await tester.runAsync(() => _container(signedIn: true));
    addTearDown(container!.dispose);
    await tester.runAsync(() => _seed(container));
    await tester.pumpWidget(_app(container));
    await _settle(tester);

    await _go(tester, container, Routes.attendance(BmaModule.mscc));
    await _tapKey(tester, 'att-programme');
    await _tapText(tester, 'BLN Level 1', last: true);
    await _tapKey(tester, 'att-section');
    await _tapText(tester, 'A', last: true);
    await _tapKey(tester, 'att-load');
    await _settle(tester);
    // The capture is only worth keeping if the roster actually loaded.
    expect(find.byKey(const ValueKey('att-save')), findsOneWidget);
    expect(find.byKey(const ValueKey('att-mark-all')), findsOneWidget);
    await _shoot(tester, '16_attendance_tablet', _tablet.dpr);

    await _go(tester, container, Routes.registrations(BmaModule.mscc));
    await _shoot(tester, '17_beneficiaries_tablet', _tablet.dpr);
  }, skip: !_enabled);

  testWidgets('phone screens (Arabic)', (tester) async {
    _setSize(tester, _phone);
    addTearDown(tester.view.reset);
    final container = await tester.runAsync(() => _container(signedIn: true, language: 'ar'));
    addTearDown(container!.dispose);
    final ids = await tester.runAsync(() => _seed(container));
    await tester.pumpWidget(_app(container));
    await _settle(tester);
    await _shoot(tester, '18_home_arabic', _phone.dpr);

    await _go(tester, container, Routes.registrations(BmaModule.mscc));
    await _shoot(tester, '19_beneficiaries_arabic', _phone.dpr);

    await _go(tester, container, Routes.editRegistration(ids!.pendingUuid));
    await _shoot(tester, '20_registration_wizard_arabic', _phone.dpr);

    await _go(tester, container, Routes.sync);
    await _shoot(tester, '21_sync_center_arabic', _phone.dpr);
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
    await _shoot(tester, '30_center_profile', _phone.dpr);

    final arabic = await tester.runAsync(() => _container(signedIn: true, language: 'ar'));
    addTearDown(arabic!.dispose);
    await tester.runAsync(() => _seed(arabic));
    await tester.pumpWidget(_app(arabic));
    await _settle(tester);
    await _go(tester, arabic, Routes.centerProfile);
    await _shoot(tester, '31_center_profile_arabic', _phone.dpr);
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
    await _shoot(tester, '22_tips_welcome', _phone.dpr);

    await _tapText(tester, 'Next');
    await _tapText(tester, 'Next');
    await _shoot(tester, '23_tips_register', _phone.dpr);

    await _tapText(tester, 'Next');
    await _tapText(tester, 'Next');
    await _shoot(tester, '24_tips_push', _phone.dpr);

    final arabic = await tester.runAsync(() => _container(signedIn: true, language: 'ar', tipsSeen: false));
    addTearDown(arabic!.dispose);
    await tester.runAsync(() => _seed(arabic));
    await tester.pumpWidget(_app(arabic));
    await _settle(tester);
    await _shoot(tester, '25_tips_welcome_arabic', _phone.dpr);

    for (var i = 0; i < 4; i++) {
      await _tapText(tester, 'التالي');
    }
    await _shoot(tester, '26_tips_push_arabic', _phone.dpr);

    _setSize(tester, _tablet);
    final tablet = await tester.runAsync(() => _container(signedIn: true, tipsSeen: false));
    addTearDown(tablet!.dispose);
    await tester.runAsync(() => _seed(tablet));
    await tester.pumpWidget(_app(tablet));
    await _settle(tester);
    await _shoot(tester, '27_tips_welcome_tablet', _tablet.dpr);
  }, skip: !_enabled);
}
