// Layout contract for the attendance lane at the three sizes that matter:
// 1280x800 (the desk posture this work targets), 800x1280 (portrait) and
// 412x915 (the phone fallback that must not move).
//
// This is the first widget test in the repo that pumps a DB-backed screen: it
// opens a real in-memory SQLite database, seeds the reference data and twelve
// enrolled children, and then DRIVES the screen the way a teacher does —
// programme, section, Load children — rather than reaching into State. That is
// deliberate: the assertions below are about what a finger can reach, so a
// test that bypassed the controls would not be evidence of anything.
import 'dart:io';

import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/config/settings_controller.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/db/entity_dao.dart';
import 'package:bma_app/core/db/reference_dao.dart';
import 'package:bma_app/core/layout/breakpoints.dart';
import 'package:bma_app/core/models/reference_item.dart';
import 'package:bma_app/core/sync/connectivity_service.dart';
import 'package:bma_app/core/sync/sync_engine.dart';
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:bma_app/core/widgets/ui.dart';
import 'package:bma_app/features/attendance/attendance_screen.dart';
import 'package:bma_app/features/attendance/child_attendance_screen.dart';
import 'package:bma_app/features/attendance/teacher_attendance_screen.dart';
import 'package:bma_app/features/tips/tips_controller.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';
import '../support/viewport.dart';

const _programme = 'BLN Level 1';
const _section = 'A';
const _childCount = 12;

/// Every roster row, in tree order, whatever renders it (a [Card] at compact,
/// a table row at expanded).
final _rows = find.byWidgetPredicate(
    (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('att-row-'));

Finder _key(String value) => find.byKey(ValueKey(value));

/// REAL FONTS, not Ahem. The default test font draws every glyph as a 1 em
/// square, so 'Mark all present' measures ~2.3x its real width and a phone row
/// that is fine on a device overflows in the test. Measuring a LAYOUT against
/// a font the app never ships would make every assertion below meaningless,
/// so this loads the same faces the screenshot harness does.
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;
  final material = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> bytes(String path) async => ByteData.view((await File(path).readAsBytes()).buffer);
  final roboto = FontLoader('Roboto');
  for (final file in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    roboto.addFont(bytes('$material/$file'));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')..addFont(bytes('$material/MaterialIcons-Regular.otf'));
  await icons.load();
  final arabic = FontLoader('NotoSansArabic')
    ..addFont(bytes('test/screenshots/fonts/NotoSansArabic-Regular.ttf'))
    ..addFont(bytes('test/screenshots/fonts/NotoSansArabic-Bold.ttf'));
  await arabic.load();
  AppTheme.fontFamilyFallback = const ['NotoSansArabic'];
}

/// sqflite_common_ffi hands out ONE shared ':memory:' database per process, so
/// a second `openInMemory()` in the same test file sees the first test's rows.
/// Every seed therefore starts from empty.
Future<AppDatabase> _reset(AppDatabase db) async {
  for (final table in ['records', 'ref_items', 'choices']) {
    await db.db.delete(table);
  }
  return db;
}

Future<AppDatabase> _seedDatabase() async {
  final db = await _reset(await AppDatabase.openInMemory());
  final reference = ReferenceDao(db);
  await reference.replaceKind('rounds.mscc', const [
    ReferenceItem(kind: 'rounds.mscc', id: 7, name: '2025-2026', extra: {'current_year': true}),
  ]);
  await reference.replaceKind('centers', const [
    ReferenceItem(kind: 'centers', id: 1, name: 'Makani Centre'),
  ]);
  await reference.replaceChoices(const {
    'mscc.attendance.education_program': [
      ChoiceRow(key: 'mscc.attendance.education_program', value: _programme, label: _programme),
      ChoiceRow(key: 'mscc.attendance.education_program', value: 'BLN Level 2', label: 'BLN Level 2', position: 1),
    ],
    'mscc.attendance.class_section': [
      ChoiceRow(key: 'mscc.attendance.class_section', value: _section, label: _section),
      ChoiceRow(key: 'mscc.attendance.class_section', value: 'B', label: 'B', position: 1),
    ],
    'mscc.attendance.absence_reason': [
      ChoiceRow(key: 'mscc.attendance.absence_reason', value: 'Sick', label: 'Sick'),
      ChoiceRow(key: 'mscc.attendance.absence_reason', value: 'Other', label: 'Other', position: 1),
    ],
    'mscc.attendance.close_reason': [
      ChoiceRow(key: 'mscc.attendance.close_reason', value: 'Holiday', label: 'Holiday'),
    ],
  });
  final dao = EntityDao(db);
  for (var i = 1; i <= _childCount; i++) {
    final n = i.toString().padLeft(2, '0');
    await dao.createLocal(entity: Entities.msccRegistration, data: {
      'child_first_name': 'Child',
      'child_father_name': 'Number',
      'child_last_name': 'P$n',
      'child_mother_fullname': 'Mother P$n',
      'child_birthday_year': '2015',
      'child_birthday_month': '3',
      'child_birthday_day': '$i',
      'center': 1,
      'round': 7,
      'registration_date': '2020-01-01',
      'education_summary': [
        {'education_program': _programme, 'class_section': _section, 'round': 7, 'registration_date': '2020-01-01'},
      ],
    });
  }
  return db;
}

/// SQLite work is genuinely asynchronous here, so pumping alone is not enough.
Future<void> _settle(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Settles until [until] matches. A fixed number of real-time rounds is a
/// flake waiting for a loaded machine — the whole suite runs four isolates at
/// once — so wait for the condition and only then give up.
Future<void> _settleUntil(WidgetTester tester, Finder until, {int maxRounds = 150}) async {
  for (var i = 0; i < maxRounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
    if (until.evaluate().isNotEmpty) return;
  }
  fail('timed out waiting for $until');
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  String language = 'en',
  double textScale = 1.0,
  String scope = 'center',
}) async {
  // SQLite is REAL async: inside testWidgets the fake-async zone never
  // completes an I/O future, so every database call goes through runAsync.
  final db = (await tester.runAsync(_seedDatabase))!;
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    authControllerProvider.overrideWith(
        () => FakeAuthController(signedIn(modules: {BmaModule.mscc: caps(scope: scope)}))),
    syncEngineProvider.overrideWith(FakeSyncEngine.new),
    connectivityProvider.overrideWith((ref) => Stream.value(true)),
    tipsControllerProvider.overrideWith(() => TipsController(const TipsState(), null)),
    settingsControllerProvider.overrideWith(() => SettingsController(
          AppSettings(serverUrl: 'https://x.invalid', locale: Locale(language), serverConfigured: true),
          null,
        )),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      // Mirrors app.dart: density follows the DEVICE, and the text scale is
      // applied above the screen so the window size is untouched.
      builder: (context, child) => Theme(
        data: AppTheme.cached(
            tablet: MediaQuery.sizeOf(context).shortestSide >= Breakpoints.tabletShortestSide),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: const AttendanceScreen(module: BmaModule.mscc),
    ),
  ));
  await _settleUntil(tester, _key('att-load'));
  await _settle(tester);
}

/// Programme -> section -> Load children, by key, exactly as the operator does.
Future<void> _loadRoster(WidgetTester tester) async {
  await tester.tap(_key('att-programme'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_programme).last);
  await tester.pumpAndSettle();
  await tester.tap(_key('att-section'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_section).last);
  await tester.pumpAndSettle();
  await tester.tap(_key('att-load'));
  await _settleUntil(tester, _rows);
}

/// True when two boxes sit side by side on the same line.
bool _sideBySide(Rect a, Rect b) {
  final overlap = (a.bottom < b.bottom ? a.bottom : b.bottom) - (a.top > b.top ? a.top : b.top);
  return overlap > 8 && (a.right <= b.left + 1 || b.right <= a.left + 1);
}

// --------------------------------------------------------------------------
// Teacher attendance and child attendance share the plumbing above; only the
// seed data and the widget under test differ.

Finder _keysStartingWith(String prefix) => find.byWidgetPredicate(
    (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith(prefix));

/// How many of [finder]'s boxes share the topmost line — i.e. the column count.
int _perLine(WidgetTester tester, Finder finder) {
  final tops = <double>[for (var i = 0; i < finder.evaluate().length; i++) tester.getTopLeft(finder.at(i)).dy];
  if (tops.isEmpty) return 0;
  final first = tops.reduce((a, b) => a < b ? a : b);
  return tops.where((t) => (t - first).abs() < 1).length;
}

Future<AppDatabase> _seedTeachers() async {
  final db = await _reset(await AppDatabase.openInMemory());
  final dao = EntityDao(db);
  for (var i = 1; i <= 12; i++) {
    await dao.createLocal(entity: Entities.teacherFor(BmaModule.alp), data: {
      'first_name': 'Teacher',
      'father_name': 'Number',
      'last_name': 'T${i.toString().padLeft(2, '0')}',
      'teacher_assignment': 'Grade $i',
      'school_label': 'Bar Elias School',
    });
  }
  return db;
}

/// One registration plus three months of attendance documents referencing it.
Future<({AppDatabase db, String uuid})> _seedHistory() async {
  final db = await _reset(await AppDatabase.openInMemory());
  final dao = EntityDao(db);
  final child = await dao.createLocal(entity: Entities.msccRegistration, data: {
    'child_first_name': 'Child',
    'child_father_name': 'Number',
    'child_last_name': 'P01',
    'child_birthday_year': '2015',
    'child_birthday_month': '3',
    'child_birthday_day': '4',
  });
  for (final month in ['2025-09', '2025-10', '2025-11']) {
    for (final day in ['03', '04', '05', '10', '11']) {
      final date = '$month-$day';
      final data = {
        'attendance_date': date,
        'education_program': _programme,
        'class_section': _section,
        'children_attendance': [
          {
            'registration_uuid': child.uuid,
            'child_label': child.label,
            'attended': day == '04' ? 'No' : 'Yes',
            'absence_reason': day == '04' ? 'Sick' : '',
          },
        ],
      };
      await dao.createLocal(entity: Entities.msccAttendanceDay, data: data, naturalKey: date);
    }
  }
  return (db: db, uuid: child.uuid);
}

Future<void> _pumpWidget(WidgetTester tester, AppDatabase db, Widget home,
    {String language = 'en', double textScale = 1.0, Finder? until}) async {
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    authControllerProvider.overrideWith(() => FakeAuthController(signedIn())),
    syncEngineProvider.overrideWith(FakeSyncEngine.new),
    connectivityProvider.overrideWith((ref) => Stream.value(true)),
    tipsControllerProvider.overrideWith(() => TipsController(const TipsState(), null)),
    settingsControllerProvider.overrideWith(() => SettingsController(
          AppSettings(serverUrl: 'https://x.invalid', locale: Locale(language), serverConfigured: true),
          null,
        )),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.light(),
      builder: (context, child) => Theme(
        data: AppTheme.cached(
            tablet: MediaQuery.sizeOf(context).shortestSide >= Breakpoints.tabletShortestSide),
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
      home: home,
    ),
  ));
  if (until != null) await _settleUntil(tester, until);
  await _settle(tester);
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await _loadFonts();
  });

  // The fallback list is a mutable static and the theme cache keys on it.
  tearDownAll(() => AppTheme.fontFamilyFallback = const []);

  group('9-inch landscape, 1280x800', () {
    testWidgets('session pane beside a roster table with at least 10 children visible', (tester) async {
      tabletLandscape(tester);
      await _pumpScreen(tester);
      await _loadRoster(tester);

      expect(_key('att-session-pane'), findsOneWidget);
      expect(_key('att-roster'), findsOneWidget);
      // 12 children seeded; at least 10 laid out at once (the phone card list
      // shows five in the same 800 px).
      expect(_rows, findsAtLeast(10));
      expect(_rows.evaluate().length, lessThanOrEqualTo(12));
      // The pane is fixed; the table gets everything else.
      expect(tester.getSize(_key('att-session-pane')).width, 360);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Save is pinned inside the session pane and needs no scrolling', (tester) async {
      tabletLandscape(tester);
      await _pumpScreen(tester);
      await _loadRoster(tester);

      expect(find.descendant(of: _key('att-session-pane'), matching: _key('att-save')), findsOneWidget);
      final save = tester.getRect(_key('att-save'));
      expect(save.bottom, lessThanOrEqualTo(800));
      expect(save.top, greaterThan(0));
      // Below the roster's first row: it is pinned at the bottom, not floating
      // after the filters.
      expect(save.top, greaterThan(tester.getRect(_rows.first).top));
      expect(tester.takeException(), isNull);
    });

    testWidgets('marking a child absent moves nothing below it', (tester) async {
      tabletLandscape(tester);
      await _pumpScreen(tester);
      await _loadRoster(tester);

      // The reason control exists BEFORE the child is marked absent — that is
      // the whole no-reflow mechanism.
      final reasons = find.byWidgetPredicate(
          (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('att-reason-'));
      expect(reasons, findsAtLeast(10));

      final third = tester.getTopLeft(_rows.at(2));
      final height = tester.getSize(_rows.at(1)).height;
      await tester.tap(find.descendant(of: _rows.at(1), matching: find.text('Absent')));
      await tester.pump();

      expect(tester.getTopLeft(_rows.at(2)), third);
      expect(tester.getSize(_rows.at(1)).height, height);
      expect(tester.takeException(), isNull);
    });

    testWidgets('60 px rows, and no icons in the segments at tablet width', (tester) async {
      tabletLandscape(tester);
      await _pumpScreen(tester);
      await _loadRoster(tester);

      expect(tester.getSize(_rows.first).height, 60);
      // The success/danger tint carries the meaning; the icons are what make
      // Arabic overflow a 240 px column.
      expect(find.descendant(of: _rows.first, matching: find.byIcon(Icons.check)), findsNothing);
      expect(find.descendant(of: _rows.first, matching: find.byIcon(Icons.close)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a centre-scoped user sees a fact, not a control that does nothing', (tester) async {
      tabletLandscape(tester);
      await _pumpScreen(tester);

      expect(find.descendant(of: _key('att-center'), matching: find.byType(FactRow)), findsOneWidget);
      expect(find.descendant(of: _key('att-center'), matching: find.byType(InputDecorator)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a partner-scoped user keeps the centre picker', (tester) async {
      tabletLandscape(tester);
      await _pumpScreen(tester, scope: 'partner');

      expect(find.descendant(of: _key('att-center'), matching: find.byType(InputDecorator)), findsOneWidget);
      expect(find.descendant(of: _key('att-center'), matching: find.byType(FactRow)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic at 1.3x mirrors the panes and overflows nothing', (tester) async {
      tabletLandscape(tester);
      await _pumpScreen(tester, language: 'ar', textScale: 1.3);
      await _loadRoster(tester);

      // A takeException-is-null assertion passes happily on a pane that
      // rendered on the wrong side, so check the side mechanically.
      expect(tester.getTopLeft(_key('att-session-pane')).dx, greaterThan(640));
      expect(_rows, findsAtLeast(8));
      expect(tester.takeException(), isNull);
    });
  });

  group('9-inch portrait, 800x1280', () {
    testWidgets('filters pack two across and Save sits in a bottom bar', (tester) async {
      tabletPortrait(tester);
      await _pumpScreen(tester, scope: 'partner');

      final centre = tester.getRect(_key('att-center'));
      final round = tester.getRect(_key('att-round'));
      final programme = tester.getRect(_key('att-programme'));
      expect(_sideBySide(centre, round), isTrue, reason: 'centre and round share a line');
      expect(programme.top, greaterThan(centre.bottom - 1), reason: 'programme starts the next line');

      await _loadRoster(tester);
      expect(_key('att-session-pane'), findsNothing);
      expect(_key('att-roster'), findsNothing);
      final save = tester.getRect(_key('att-save'));
      expect(save.bottom, greaterThan(1280 - 120));
      expect(tester.takeException(), isNull);
    });

    testWidgets('children keep their cards, with the toggle beside the name', (tester) async {
      tabletPortrait(tester);
      await _pumpScreen(tester);
      await _loadRoster(tester);

      expect(_rows, findsAtLeast(5));
      expect(tester.widget(_rows.first), isA<Card>());
      final row = tester.getRect(_rows.first);
      final toggle = tester.getRect(find.descendant(
          of: _rows.first,
          matching: find.byWidgetPredicate(
              (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('att-toggle-'))));
      // Bounded name column: the toggle is not pushed to the far edge.
      expect(toggle.top, lessThan(row.top + 60));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic at 1.3x overflows nothing', (tester) async {
      tabletPortrait(tester);
      await _pumpScreen(tester, language: 'ar', textScale: 1.3);
      await _loadRoster(tester);

      expect(_rows, findsAtLeast(3));
      expect(tester.takeException(), isNull);
    });
  });

  group('phone fallback, 412x915', () {
    testWidgets('is today\'s sheet: one card per child, one filter column, bottom Save', (tester) async {
      phone(tester);
      await _pumpScreen(tester, scope: 'partner');

      final centre = tester.getRect(_key('att-center'));
      final round = tester.getRect(_key('att-round'));
      expect(_sideBySide(centre, round), isFalse, reason: 'the phone stacks its filters');
      // The phone keeps the control, dead or not: the fact row is a tablet
      // affordance and must not leak down.
      expect(find.descendant(of: _key('att-center'), matching: find.byType(InputDecorator)), findsOneWidget);

      await _loadRoster(tester);
      expect(_key('att-session-pane'), findsNothing);
      expect(_key('att-roster'), findsNothing);
      expect(tester.widget(_rows.first), isA<Card>());
      expect(find.descendant(of: _rows.first, matching: find.byIcon(Icons.check)), findsOneWidget);
      final save = tester.getRect(_key('att-save'));
      expect(save.bottom, greaterThan(915 - 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a scope-locked centre stays an InputDecorator at compact', (tester) async {
      phone(tester);
      await _pumpScreen(tester);

      expect(find.descendant(of: _key('att-center'), matching: find.byType(InputDecorator)), findsOneWidget);
      expect(find.descendant(of: _key('att-center'), matching: find.byType(FactRow)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic at 1.3x overflows nothing', (tester) async {
      phone(tester);
      await _pumpScreen(tester, language: 'ar', textScale: 1.3);
      await _loadRoster(tester);

      expect(_rows, findsAtLeast(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('teacher attendance', () {
    testWidgets('1280x800: one grid, one toolbar, nothing to scroll', (tester) async {
      tabletLandscape(tester);
      final db = (await tester.runAsync(_seedTeachers))!;
      await _pumpWidget(tester, db, const TeacherAttendanceScreen(module: BmaModule.alp),
          until: _keysStartingWith('tatt-row-'));

      final rows = _keysStartingWith('tatt-row-');
      expect(rows, findsNWidgets(12));
      expect(_perLine(tester, rows), greaterThanOrEqualTo(3));
      expect(_key('tatt-mark-all'), findsOneWidget);
      // Date, Save and Mark all are in the toolbar ABOVE the grid, and the
      // last teacher is on screen: a school's staff needs no scrolling.
      expect(tester.getRect(_key('tatt-save')).top, lessThan(tester.getRect(rows.first).top));
      expect(tester.getRect(rows.last).bottom, lessThanOrEqualTo(800));
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280: two across', (tester) async {
      tabletPortrait(tester);
      final db = (await tester.runAsync(_seedTeachers))!;
      await _pumpWidget(tester, db, const TeacherAttendanceScreen(module: BmaModule.alp),
          until: _keysStartingWith('tatt-row-'));

      expect(_perLine(tester, _keysStartingWith('tatt-row-')), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('412x915: today\'s list and bottom Save bar', (tester) async {
      phone(tester);
      final db = (await tester.runAsync(_seedTeachers))!;
      await _pumpWidget(tester, db, const TeacherAttendanceScreen(module: BmaModule.alp),
          until: _keysStartingWith('tatt-row-'));

      final rows = _keysStartingWith('tatt-row-');
      expect(_perLine(tester, rows), 1);
      expect(tester.widget(rows.first), isA<ListTile>());
      expect(_key('tatt-mark-all'), findsNothing);
      expect(tester.getRect(_key('tatt-save')).bottom, greaterThan(915 - 100));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic at 1.3x overflows nothing in either orientation', (tester) async {
      tabletLandscape(tester);
      final db = (await tester.runAsync(_seedTeachers))!;
      await _pumpWidget(tester, db, const TeacherAttendanceScreen(module: BmaModule.alp),
          language: 'ar', textScale: 1.3, until: _keysStartingWith('tatt-row-'));
      expect(tester.takeException(), isNull);

      tabletPortrait(tester);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('child attendance history', () {
    testWidgets('1280x800: three month grids across, with colour-coded days', (tester) async {
      tabletLandscape(tester);
      final seed = (await tester.runAsync(_seedHistory))!;
      await _pumpWidget(tester, seed.db, ChildAttendanceScreen(uuid: seed.uuid),
          until: _keysStartingWith('month-2'));

      final months = _keysStartingWith('month-2');
      expect(months, findsNWidgets(3));
      expect(_perLine(tester, months), 3);
      // A 7-column grid of real days, not a list of rows.
      expect(_key('month-day-2025-09-04'), findsOneWidget);
      expect(_key('month-day-2025-09-30'), findsOneWidget);
      expect(_perLine(tester, _keysStartingWith('month-day-2025-09')), lessThanOrEqualTo(7));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a day explains it', (tester) async {
      tabletLandscape(tester);
      final seed = (await tester.runAsync(_seedHistory))!;
      await _pumpWidget(tester, seed.db, ChildAttendanceScreen(uuid: seed.uuid),
          until: _keysStartingWith('month-2'));

      await tester.tap(_key('month-day-2025-09-04'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Sick'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280: two across', (tester) async {
      tabletPortrait(tester);
      final seed = (await tester.runAsync(_seedHistory))!;
      await _pumpWidget(tester, seed.db, ChildAttendanceScreen(uuid: seed.uuid),
          until: _keysStartingWith('month-2'));

      expect(_perLine(tester, _keysStartingWith('month-2')), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('412x915: today\'s dense day list, no grid', (tester) async {
      phone(tester);
      final seed = (await tester.runAsync(_seedHistory))!;
      await _pumpWidget(tester, seed.db, ChildAttendanceScreen(uuid: seed.uuid),
          until: _keysStartingWith('month-2'));

      expect(_keysStartingWith('month-day-'), findsNothing);
      expect(_keysStartingWith('month-2'), findsNWidgets(3));
      expect(find.text('2025-09-04'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic at 1.3x overflows nothing', (tester) async {
      tabletLandscape(tester);
      final seed = (await tester.runAsync(_seedHistory))!;
      await _pumpWidget(tester, seed.db, ChildAttendanceScreen(uuid: seed.uuid),
          language: 'ar', textScale: 1.3, until: _keysStartingWith('month-2'));
      expect(tester.takeException(), isNull);
    });
  });
}
