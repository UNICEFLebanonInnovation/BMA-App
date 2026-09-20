// The four ALP dashboards at the three viewports the tablet work targets and
// in Arabic at 1.3x: every panel mounts, the figures read the seeded records,
// a filter change recomputes in place, and nothing overflows.
import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/db/entity_dao.dart';
import 'package:bma_app/core/db/reference_dao.dart';
import 'package:bma_app/core/layout/breakpoints.dart';
import 'package:bma_app/core/models/form_schema.dart';
import 'package:bma_app/core/models/reference_item.dart';
import 'package:bma_app/core/models/sync_models.dart';
import 'package:bma_app/core/models/user_profile.dart';
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:bma_app/core/widgets/common.dart';
import 'package:bma_app/features/analytics/alp/alp_attendance_dashboard_screen.dart';
import 'package:bma_app/features/analytics/alp/alp_registration_insights_screen.dart';
import 'package:bma_app/features/analytics/alp/alp_school_dashboard_screen.dart';
import 'package:bma_app/features/analytics/alp/alp_teacher_dashboard_screen.dart';
import 'package:bma_app/features/analytics/charts/heatmap_calendar.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';
import '../support/viewport.dart';

UserProfile _profile() => UserProfile(
      id: 42,
      username: 'u42',
      firstName: 'Rima',
      lastName: 'Haddad',
      groups: const [],
      modules: {BmaModule.alp: caps()},
      partner: const NamedRef(id: 10, name: 'Partner Ten'),
      school: const NamedRef(id: 7, name: 'Bar Elias School'),
    );

Map<String, dynamic> _registration(
  int id, {
  String gender = 'Male',
  String birthYear = '2015',
  int school = 7,
  int round = 2,
  int programme = 1,
  int? childId,
}) =>
    {
      'id': id,
      'school': school,
      'school_label': 'Bar Elias School',
      'round': round,
      'round_label': round == 2 ? '2025-2026' : '2024-2025',
      'programme': programme,
      'registration_date': '2026-09-01',
      'source_of_identification': 'Awareness Session',
      'cash_support_programmes': const ['Haddi'],
      'child': {
        'id': childId ?? 100 + id,
        'first_name': 'Child',
        'father_name': 'F',
        'last_name': 'L$id',
        'gender': gender,
        'nationality': 1,
        'nationality_label': 'سوري',
        'birthday_year': birthYear,
        'marital_status': 'Single',
        'disability': 1,
        'disability_label': 'لا',
      },
    };

Map<String, dynamic> _attendance(String date, int programme, List<String> attended) => {
      'school_id': 7,
      'round_id': 2,
      'programme': programme,
      'attendance_date': date,
      'children_attendance': [
        for (var i = 0; i < attended.length; i++) {'registration_id': i, 'attended': attended[i]},
      ],
    };

class Fixture {
  Fixture(this.container);

  final ProviderContainer container;
}

Future<Fixture> fixture(WidgetTester tester) async {
  final db = await tester.runAsync(AppDatabase.openInMemory);
  await tester.runAsync(() async {
    final reference = ReferenceDao(db!);
    await reference.replaceKind('schools', const [
      ReferenceItem(kind: 'schools', id: 7, name: 'مدرسة بر الياس', nameEn: 'Bar Elias School', extra: {
        'number': '1234',
        'type': 'Public School',
        'governorate_id': 1,
        'district_id': 2,
        'cadaster_id': 3,
        'is_bma': true,
        'is_closed': false,
        'latitude': 33.75,
        'longitude': 35.9,
      }),
      ReferenceItem(kind: 'schools', id: 8, name: 'مدرسة زحلة', nameEn: 'Zahle School', extra: {
        'number': '5678',
        'latitude': '33.85',
        'longitude': '35.92',
      }),
      ReferenceItem(kind: 'schools', id: 9, name: 'Unmapped School', extra: {}),
    ]);
    await reference.replaceKind('locations', const [
      ReferenceItem(kind: 'locations', id: 1, name: 'البقاع', nameEn: 'Bekaa'),
      ReferenceItem(kind: 'locations', id: 2, name: 'زحلة', nameEn: 'Zahle'),
      ReferenceItem(kind: 'locations', id: 3, name: 'بر الياس', nameEn: 'Bar Elias'),
    ]);
    await reference.replaceKind('rounds.alp', const [
      ReferenceItem(kind: 'rounds.alp', id: 1, name: '2024-2025'),
      ReferenceItem(kind: 'rounds.alp', id: 2, name: '2025-2026', extra: {'current_year': true}),
    ]);
    await reference.replaceKind('alp_programs', const [
      ReferenceItem(kind: 'alp_programs', id: 1, name: 'ALP'),
      ReferenceItem(kind: 'alp_programs', id: 2, name: 'Bridging'),
    ]);
    await reference.replaceKind('nationalities', const [
      ReferenceItem(kind: 'nationalities', id: 1, name: 'سوري', nameEn: 'Syrian'),
      ReferenceItem(kind: 'nationalities', id: 2, name: 'لبناني', nameEn: 'Lebanese'),
    ]);
    await reference.replaceKind('disabilities', const [
      ReferenceItem(kind: 'disabilities', id: 1, name: 'لا', nameEn: 'None'),
    ]);
    await reference.replaceKind('alp_grading_definitions', const [
      ReferenceItem(kind: 'alp_grading_definitions', id: 1, name: 'Arabic', extra: {'min_grade': 0, 'max_grade': 20}),
      ReferenceItem(kind: 'alp_grading_definitions', id: 2, name: 'Math', extra: {'min_grade': 0, 'max_grade': 10}),
    ]);
    await reference.replaceKind('trainings', const [
      ReferenceItem(kind: 'trainings', id: 1, name: 'Child protection'),
      ReferenceItem(kind: 'trainings', id: 2, name: 'Arabic literacy'),
    ]);
    await reference.replaceSchemas({
      Entities.alpRegistration: const EntitySchema(
        key: Entities.alpRegistration,
        module: 'alp',
        label: 'ALP registration',
        kind: 'identity',
        sections: [],
        fields: [
          FieldSpec(
            name: 'cash_support_programmes',
            label: 'Cash support',
            type: 'multiselect',
            choices: [
              ChoiceOption(value: 'None', label: 'None'),
              ChoiceOption(value: 'Haddi', label: 'Haddi'),
            ],
          ),
        ],
      ),
      Entities.alpTeacher: const EntitySchema(
        key: Entities.alpTeacher,
        module: 'alp',
        label: 'ALP teacher',
        kind: 'modelform',
        sections: [],
        fields: [
          FieldSpec(
            name: 'subjects_provided',
            label: 'Subjects',
            type: 'multiselect',
            choices: [
              ChoiceOption(value: 'arabic', label: 'Arabic'),
              ChoiceOption(value: 'math', label: 'Mathematics'),
            ],
          ),
          FieldSpec(
            name: 'registration_level',
            label: 'Levels',
            type: 'multiselect',
            choices: [ChoiceOption(value: 'Level one', label: 'Level one')],
          ),
          FieldSpec(
            name: 'teacher_assignment',
            label: 'Assignment',
            type: 'select',
            choices: [
              ChoiceOption(value: 'ALP only', label: 'ALP only'),
              ChoiceOption(value: 'ALP and FE', label: 'ALP and FE'),
            ],
          ),
          FieldSpec(
            name: 'extra_coaching',
            label: 'Extra coaching',
            type: 'select',
            choices: [ChoiceOption(value: 'yes', label: 'Yes'), ChoiceOption(value: 'no', label: 'No')],
          ),
        ],
      ),
    });

    final dao = EntityDao(db);
    // Four registrations: child 500 sits in both rounds, so "moved between
    // rounds" has something to split.
    await dao.applyPullChange(PullChange(
        entity: Entities.alpRegistration, serverId: 1, data: _registration(1, round: 1, childId: 500)));
    await dao.applyPullChange(PullChange(
        entity: Entities.alpRegistration, serverId: 2, data: _registration(2, round: 2, childId: 500)));
    await dao.applyPullChange(PullChange(
        entity: Entities.alpRegistration,
        serverId: 3,
        data: _registration(3, gender: 'Female', birthYear: '2019', school: 8, programme: 2)));
    await dao.applyPullChange(PullChange(
        entity: Entities.alpRegistration, serverId: 4, data: _registration(4, gender: 'Female')));
    // One typed offline: no school, so it counts at the account's.
    await dao.createLocal(entity: Entities.alpRegistration, data: const {
      'child_first_name': 'Hasan',
      'child_father_name': 'M',
      'child_last_name': 'Ali',
      'child_gender': 'Male',
      'child_nationality': 2,
      'child_birthday_year': '2018',
      'round': 2,
      'programme': 1,
    });
    // Two assessments for child 1: 50% then 90%, so the outcomes have a
    // follow-up and an improvement to report.
    await dao.applyPullChange(PullChange(entity: Entities.alpGrading, serverId: 1, parentId: 1, data: {
      'id': 1,
      'registration': 1,
      'grading_data': {'1': 10},
      'created': '2026-01-01T00:00:00',
    }));
    await dao.applyPullChange(PullChange(entity: Entities.alpGrading, serverId: 2, parentId: 1, data: {
      'id': 2,
      'registration': 1,
      'grading_data': {'1': 18, '2': 9},
      'created': '2026-06-01T00:00:00',
    }));

    await dao.applyPullChange(PullChange(entity: Entities.alpTeacher, serverId: 1, data: {
      'id': 1,
      'first_name': 'Hala',
      'sex': 'Female',
      'nationality': 2,
      'school': 7,
      'round': 2,
      'teacher_assignment': 'ALP only',
      'extra_coaching': 'no',
      'subjects_provided': ['arabic', 'math'],
      'registration_level': ['Level one'],
      'trainings': [1],
      'training_sessions_attended': 3,
      'years_of_experience': 5,
      'teaching_hours_mscc': 20,
      'teaching_hours_private_school': 4,
      'phone_number': '03-111222',
    }));
    await dao.applyPullChange(PullChange(entity: Entities.alpTeacher, serverId: 2, data: {
      'id': 2,
      'first_name': 'Sami',
      'sex': 'Male',
      'nationality': 1,
      'school': 8,
      'round': 1,
      'teacher_assignment': 'ALP and FE',
      'extra_coaching': 'yes',
      'subjects_provided': ['arabic'],
      'registration_level': [],
      'trainings': [],
      'training_sessions_attended': null,
      'years_of_experience': null,
      'teaching_hours_mscc': 10,
      'phone_number': '',
    }));
    // One typed offline, at the account school.
    await dao.createLocal(entity: Entities.alpTeacher, data: const {
      'first_name': 'Nour',
      'sex': 'Female',
      'round': 2,
      'subjects_provided': ['math'],
      'trainings': [2],
      'training_sessions_attended': 1,
      'years_of_experience': 7,
      'phone_number': '03-333444',
    });

    // Attendance across two years and two programmes.
    for (final (date, programme, rows) in [
      ('2026-03-10', 1, ['Yes', 'Yes', 'No']),
      ('2026-03-11', 1, ['Yes', 'Yes']),
      ('2026-03-11', 2, ['No', 'Yes']),
      ('2025-05-06', 1, ['Yes']),
    ]) {
      final data = _attendance(date, programme, rows);
      await dao.createLocal(
        entity: Entities.alpAttendanceDay,
        data: data,
        naturalKey: EntityDao.naturalKeyFor(Entities.alpAttendanceDay, data),
      );
    }
  });
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db!),
    ...tipsOverrides(auth: AuthState(status: AuthStatus.signedIn, token: 't', deviceId: 'd', profile: _profile())),
    // No network in a widget test: the markers are placed from the stored
    // coordinates and no tile is ever requested.
    mapTilesEnabledProvider.overrideWithValue(false),
  ]);
  addTearDown(container.dispose);
  addTearDown(() => db.close());
  return Fixture(container);
}

Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> open(WidgetTester tester, Fixture fx, Widget screen, {String lang = 'en', double scale = 1.0}) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: fx.container,
    child: MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(lang),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Theme(
        data: AppTheme.cached(tablet: MediaQuery.sizeOf(context).shortestSide >= Breakpoints.tabletShortestSide),
        child: MediaQuery.withNoTextScaling(
          child: scale == 1.0
              ? child!
              : MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
        ),
      ),
      home: screen,
    ),
  ));
  await settle(tester);
}

Rect rectOf(WidgetTester tester, Key key) => tester.getRect(find.byKey(key));

void expectClean(WidgetTester tester) => expect(tester.takeException(), isNull);

/// Scrolls the page until [key] is mounted, then returns its rect. A
/// negative [delta] scrolls back up, for a control the page has passed.
Future<Rect> reveal(WidgetTester tester, Key listKey, Key key, {double delta = 300}) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    delta,
    scrollable: find.descendant(of: find.byKey(listKey), matching: find.byType(Scrollable)).first,
  );
  await tester.pump();
  return rectOf(tester, key);
}

/// The value text of the KPI tile whose label starts with [label].
String kpiValue(WidgetTester tester, String label) {
  final tile = find.ancestor(
    of: find.textContaining(label).first,
    matching: find.byType(StatTile),
  );
  final texts = tester.widgetList<Text>(find.descendant(of: tile.first, matching: find.byType(Text))).toList();
  return texts.first.data ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ALP registration insights', () {
    const list = ValueKey('alp-reg-list');
    const panels = [
      ValueKey('chart-learning-outcomes'),
      ValueKey('chart-gender'),
      ValueKey('chart-gender-age'),
      ValueKey('chart-nationality'),
      ValueKey('chart-source'),
      ValueKey('chart-round'),
      ValueKey('chart-family-status'),
      ValueKey('chart-disability'),
      ValueKey('chart-cash-support'),
      ValueKey('chart-referred'),
      ValueKey('chart-moved-rounds'),
    ];

    testWidgets('412x915: every panel mounts and the KPIs read the records', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpRegistrationInsightsScreen());

      expect(kpiValue(tester, 'Registrations'), '5');
      expect(kpiValue(tester, 'Active schools'), '2');
      expect(kpiValue(tester, 'Partners'), '1');
      expect(kpiValue(tester, 'Programme rounds'), '2');
      for (final key in panels) {
        await reveal(tester, list, key);
      }
      expectClean(tester);
    });

    testWidgets('the learning-outcome figures follow the assessments', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpRegistrationInsightsScreen());

      expect(kpiValue(tester, 'Children assessed'), '1');
      expect(kpiValue(tester, 'Average achievement'), '90%');
      expect(kpiValue(tester, 'Follow-up assessments'), '1');
      expect(kpiValue(tester, 'Children improving'), '1');
      expectClean(tester);
    });

    testWidgets('1280x800: the wide panels span the page, the rest sit three abreast', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpRegistrationInsightsScreen());

      final page = rectOf(tester, list);
      expect(rectOf(tester, const ValueKey('chart-learning-outcomes')).width, closeTo(page.width - 16, 1));
      final gender = await reveal(tester, list, const ValueKey('chart-gender'));
      final age = rectOf(tester, const ValueKey('chart-gender-age'));
      final nationality = rectOf(tester, const ValueKey('chart-nationality'));
      expect(gender.top, age.top);
      expect(age.top, nationality.top);
      expect(gender.left, lessThan(age.left));
      final source = await reveal(tester, list, const ValueKey('chart-source'));
      expect(source.width, closeTo(page.width - 16, 1));
      expectClean(tester);
    });

    testWidgets('800x1280 and Arabic at 1.3x stay clean', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpRegistrationInsightsScreen());
      final gender = rectOf(tester, const ValueKey('chart-gender'));
      final age = rectOf(tester, const ValueKey('chart-gender-age'));
      expect(gender.top, age.top);
      expect(gender.left, lessThan(age.left));
      expectClean(tester);

      tabletLandscape(tester);
      await open(tester, fx, const AlpRegistrationInsightsScreen(), lang: 'ar', scale: 1.3);
      expect(find.byKey(const ValueKey('alp-reg-kpis')), findsOneWidget);
      // Wrap lays out in reading order: the first card is rightmost in Arabic.
      final genderAr = await reveal(tester, list, const ValueKey('chart-gender'));
      expect(genderAr.left, greaterThan(rectOf(tester, const ValueKey('chart-nationality')).left));
      expectClean(tester);
    });

    testWidgets('a round filter recomputes in place and Reset restores', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpRegistrationInsightsScreen());

      await tester.tap(find.byKey(const ValueKey('alp-reg-filter-round')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2024-2025').last);
      await tester.pumpAndSettle();
      expect(kpiValue(tester, 'Registrations'), '1');
      expect(kpiValue(tester, 'Programme rounds'), '2', reason: 'the round count is not filtered');

      await tester.tap(find.byKey(const ValueKey('alp-reg-filters-reset')));
      await tester.pumpAndSettle();
      expect(kpiValue(tester, 'Registrations'), '5');
      expectClean(tester);
    });
  });

  group('ALP teacher dashboard', () {
    const list = ValueKey('alp-teacher-list');

    testWidgets('412x915: six KPIs and ten panels', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpTeacherDashboardScreen());

      expect(kpiValue(tester, 'Total teachers'), '3');
      expect(kpiValue(tester, 'Active schools'), '2');
      expect(kpiValue(tester, 'Teachers trained'), '2');
      // Experience over the two teachers that recorded one: (5 + 7) / 2.
      expect(kpiValue(tester, 'Average experience'), '6');
      expect(kpiValue(tester, 'Average training'), '2');
      expect(kpiValue(tester, 'Contact coverage'), '66.7%');

      for (final key in const [
        ValueKey('chart-gender'),
        ValueKey('chart-nationality'),
        ValueKey('chart-assignment'),
        ValueKey('chart-school'),
        ValueKey('chart-round'),
        ValueKey('chart-subjects'),
        ValueKey('chart-levels'),
        ValueKey('chart-trainings'),
        ValueKey('chart-hours'),
        ValueKey('chart-coaching'),
      ]) {
        await reveal(tester, list, key);
      }
      expectClean(tester);
    });

    testWidgets('1280x800 and Arabic at 1.3x stay clean', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpTeacherDashboardScreen());
      final gender = rectOf(tester, const ValueKey('chart-gender'));
      final nationality = rectOf(tester, const ValueKey('chart-nationality'));
      expect(gender.top, nationality.top);
      expect(gender.left, lessThan(nationality.left));
      expectClean(tester);

      await open(tester, fx, const AlpTeacherDashboardScreen(), lang: 'ar', scale: 1.3);
      expect(find.byKey(const ValueKey('alp-teacher-kpis')), findsOneWidget);
      expectClean(tester);
    });

    testWidgets('800x1280: a school filter recomputes, and an empty filter says so', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpTeacherDashboardScreen());

      await tester.tap(find.byKey(const ValueKey('alp-teacher-filter-school')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zahle School').last);
      await tester.pumpAndSettle();
      expect(kpiValue(tester, 'Total teachers'), '1');
      expect(kpiValue(tester, 'Contact coverage'), '0%');

      await tester.tap(find.byKey(const ValueKey('alp-teacher-filter-school')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unmapped School').last);
      await tester.pumpAndSettle();
      expect(kpiValue(tester, 'Total teachers'), '0');
      expect(find.byKey(const ValueKey('alp-teacher-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('chart-gender')), findsNothing);
      expectClean(tester);
    });
  });

  group('ALP attendance dashboard', () {
    const list = ValueKey('alp-attendance-list');

    testWidgets('412x915: the overall map, one per programme, and the figures', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpAttendanceDashboardScreen());

      expect(find.byKey(const ValueKey('chart-attendance-overall')), findsOneWidget);
      // 2026: three sheets over two days, 7 rows of which 5 present.
      expect(kpiValue(tester, 'Attendance days'), '2');
      expect(kpiValue(tester, 'Attendance rate'), '71.4%');
      await reveal(tester, list, const ValueKey('chart-attendance-programme-0'));
      await reveal(tester, list, const ValueKey('chart-attendance-programme-1'));
      expectClean(tester);
    });

    testWidgets('the year selector switches the year and the maps follow', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpAttendanceDashboardScreen());

      expect(find.text('Overall attendance (2026)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('alp-attendance-year')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2025').last);
      await tester.pumpAndSettle();
      expect(find.text('Overall attendance (2025)'), findsOneWidget);
      expect(kpiValue(tester, 'Attendance days'), '1');
      expect(kpiValue(tester, 'Attendance rate'), '100%');
      // Only the ALP programme recorded anything in 2025.
      expect(find.byKey(const ValueKey('chart-attendance-programme-1')), findsNothing);
      expectClean(tester);
    });

    testWidgets('tapping a cell with data prints its figures', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpAttendanceDashboardScreen());

      final heatmap = find.descendant(
        of: find.byKey(const ValueKey('chart-attendance-overall')),
        matching: find.byType(AttendanceHeatmap),
      );
      final paint = find.descendant(of: heatmap, matching: find.byType(CustomPaint)).first;
      final rect = tester.getRect(paint);
      // Row 3 (March), column 10 — the 44 px label gutter plus ten cells.
      const cell = 24.0;
      await tester.tapAt(rect.topLeft + const Offset(44 + 9.5 * cell, 18 + 2.5 * cell));
      await tester.pump();
      final detail = tester.widget<Text>(
        find.descendant(of: heatmap, matching: find.byKey(const ValueKey('heatmap-detail'))),
      );
      expect(detail.data!.trim(), isNotEmpty);
      expect(detail.data, contains('present of'));
      expectClean(tester);
    });

    testWidgets('800x1280 and Arabic at 1.3x stay clean', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpAttendanceDashboardScreen());
      expectClean(tester);

      tabletLandscape(tester);
      await open(tester, fx, const AlpAttendanceDashboardScreen(), lang: 'ar', scale: 1.3);
      expect(find.byKey(const ValueKey('chart-attendance-overall')), findsOneWidget);
      expectClean(tester);
    });
  });

  group('ALP school dashboard', () {
    const list = ValueKey('alp-school-list');

    testWidgets('412x915: KPIs, the map and a row per mapped school', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpSchoolDashboardScreen());

      expect(kpiValue(tester, 'Accessible schools'), '3');
      expect(kpiValue(tester, 'Mapped schools'), '2');
      // Four registrations at the two mapped schools (one offline at 7).
      expect(kpiValue(tester, 'ALP students'), '5');
      expect(kpiValue(tester, 'ALP teachers'), '3');
      expect(find.byKey(const ValueKey('alp-school-map')), findsOneWidget);
      expect(find.byType(TileLayer), findsNothing, reason: 'tiles are disabled in tests');
      await reveal(tester, list, const ValueKey('school-row-7'));
      await reveal(tester, list, const ValueKey('school-row-8'));
      expect(find.byKey(const ValueKey('school-row-9')), findsNothing);
      expectClean(tester);
    });

    testWidgets('a school row opens the details as a sheet on the phone', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpSchoolDashboardScreen());

      await reveal(tester, list, const ValueKey('school-row-7'));
      await tester.tap(find.byKey(const ValueKey('school-row-7')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('school-details')), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('33.75000, 35.90000'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('school-details')), findsNothing);
      expectClean(tester);
    });

    testWidgets('1280x800: an unmapped school empties the map, and the details are a dialog', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpSchoolDashboardScreen());

      // The filter first, while the page is still at the top.
      await tester.tap(find.byKey(const ValueKey('alp-school-filter-school')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unmapped School').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('alp-school-map')), findsNothing);
      expect(find.textContaining('No schools with GPS coordinates'), findsOneWidget);
      expect(kpiValue(tester, 'Accessible schools'), '3', reason: 'the scope figure is not filtered');
      expect(kpiValue(tester, 'Mapped schools'), '0');
      expect(find.byKey(const ValueKey('school-row-7')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('alp-school-filters-reset')));
      await tester.pumpAndSettle();
      expect(kpiValue(tester, 'Mapped schools'), '2');

      // From 600 px up a picker is a centred dialog, not a bottom sheet.
      await reveal(tester, list, const ValueKey('school-row-8'));
      await tester.tap(find.byKey(const ValueKey('school-row-8')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byKey(const ValueKey('school-details')), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('school-details')), findsNothing);
      expectClean(tester);
    });

    testWidgets('800x1280 and Arabic at 1.3x stay clean', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AlpSchoolDashboardScreen());
      expect(find.byKey(const ValueKey('alp-school-map')), findsOneWidget);
      expectClean(tester);

      tabletLandscape(tester);
      await open(tester, fx, const AlpSchoolDashboardScreen(), lang: 'ar', scale: 1.3);
      expect(find.byKey(const ValueKey('alp-school-kpis')), findsOneWidget);
      expectClean(tester);
    });
  });
}
