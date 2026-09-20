// The NFE Advanced Analytics screen at the three viewports the tablet work
// targets, in English and in Arabic at 1.3x: every panel is mounted, the wide
// panels span the page, the KPI band reads the seeded records, and a filter
// change recomputes in place.
import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/db/entity_dao.dart';
import 'package:bma_app/core/db/reference_dao.dart';
import 'package:bma_app/core/layout/breakpoints.dart';
import 'package:bma_app/core/models/reference_item.dart';
import 'package:bma_app/core/models/sync_models.dart';
import 'package:bma_app/core/models/user_profile.dart';
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:bma_app/core/widgets/common.dart';
import 'package:bma_app/features/analytics/analytics_hub_screen.dart';
import 'package:bma_app/features/analytics/charts/crosstab_table.dart';
import 'package:bma_app/features/analytics/charts/trend_line_chart.dart';
import 'package:bma_app/features/analytics/nfe/nfe_advanced_analytics_screen.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';
import '../support/viewport.dart';

const kpis = ValueKey('nfe-kpis');
const list = ValueKey('nfe-analytics-list');
const trend = ValueKey('chart-trend');
const center = ValueKey('chart-center');
const gender = ValueKey('chart-gender');
const nationality = ValueKey('chart-nationality');
const teacherGender = ValueKey('chart-teacher-gender');
const teacherNationality = ValueKey('chart-teacher-nationality');
const teacherCenter = ValueKey('chart-teacher-center');
const crosstab = ValueKey('chart-crosstab');
const moreFilters = ValueKey('nfe-more-filters');

UserProfile _profile() => UserProfile(
      id: 42,
      username: 'u42',
      firstName: 'Rima',
      lastName: 'Haddad',
      groups: const [],
      modules: {BmaModule.mscc: caps(), BmaModule.alp: caps()},
      partner: const NamedRef(id: 10, name: 'Partner Ten'),
      center: const NamedRef(id: 1, name: 'Centre One'),
    );

Map<String, dynamic> _server(int id, String gender, String birthYear, String created) => {
      'id': id,
      'created': created,
      'center': 1,
      'center_label': 'Centre One',
      'partner': 10,
      'partner_label': 'Partner Ten',
      'child': {
        'id': 100 + id,
        'first_name': 'Child',
        'father_name': 'F',
        'last_name': 'L$id',
        'gender': gender,
        'nationality': 1,
        'nationality_label': 'سوري',
        'birthday_year': birthYear,
        'birthday_month': '3',
        'birthday_day': '5',
      },
      'education_summary': [
        {'id': id, 'education_program': id.isEven ? 'BLN Level 1' : 'BLN Level 2'},
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
    await reference.replaceKind('partners', const [
      ReferenceItem(kind: 'partners', id: 10, name: 'Partner Ten'),
      ReferenceItem(kind: 'partners', id: 11, name: 'Partner Eleven'),
    ]);
    await reference.replaceKind('centers', const [
      ReferenceItem(kind: 'centers', id: 1, name: 'مركز واحد', nameEn: 'Centre One', extra: {'partner_id': 10}),
      ReferenceItem(kind: 'centers', id: 2, name: 'مركز اثنان', nameEn: 'Centre Two', extra: {'partner_id': 11}),
    ]);
    await reference.replaceKind('nationalities', const [
      ReferenceItem(kind: 'nationalities', id: 1, name: 'سوري', nameEn: 'Syrian'),
      ReferenceItem(kind: 'nationalities', id: 2, name: 'لبناني', nameEn: 'Lebanese'),
    ]);
    await reference.replaceChoices({
      'mscc.education_service.education_program': const [
        ChoiceRow(key: 'mscc.education_service.education_program', value: 'BLN Level 1', label: 'BLN Level 1'),
        ChoiceRow(key: 'mscc.education_service.education_program', value: 'BLN Level 2', label: 'BLN Level 2'),
      ],
      'child.gender': const [
        ChoiceRow(key: 'child.gender', value: '', label: '----------'),
        ChoiceRow(key: 'child.gender', value: 'Male', label: 'Male', labelAr: 'ذكر'),
        ChoiceRow(key: 'child.gender', value: 'Female', label: 'Female', labelAr: 'أنثى'),
      ],
    });
    final dao = EntityDao(db);
    final now = DateTime.now();
    String daysAgo(int n) => now.subtract(Duration(days: n)).toIso8601String();
    await dao.applyPullChange(PullChange(
        entity: Entities.msccRegistration, serverId: 1, data: _server(1, 'Male', '2015', daysAgo(1))));
    await dao.applyPullChange(PullChange(
        entity: Entities.msccRegistration, serverId: 2, data: _server(2, 'Female', '2016', daysAgo(3))));
    await dao.applyPullChange(PullChange(
        entity: Entities.msccRegistration, serverId: 3, data: _server(3, 'Female', '2008', daysAgo(3))));
    // One typed offline: no partner/centre ids, counted at the account's.
    await dao.createLocal(entity: Entities.msccRegistration, data: {
      'child_first_name': 'Hasan',
      'child_father_name': 'M',
      'child_last_name': 'Ali',
      'child_gender': 'Male',
      'child_nationality': 2,
      'child_birthday_year': '2019',
    });
    await dao.applyPullChange(PullChange(entity: Entities.msccTeacher, serverId: 1, data: {
      'id': 1,
      'created': daysAgo(10),
      'first_name': 'Hala',
      'sex': 'Female',
      'nationality': 2,
      'center': 1,
    }));
  });
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db!),
    ...tipsOverrides(auth: AuthState(status: AuthStatus.signedIn, token: 't', deviceId: 'd', profile: _profile())),
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

/// Scrolls the page until [key] is mounted, then returns its rect.
Future<Rect> reveal(WidgetTester tester, Key key) async {
  // `.first`: the page's own Scrollable, not the KPI grid's or a table's.
  await tester.scrollUntilVisible(
    find.byKey(key),
    300,
    scrollable: find.descendant(of: find.byKey(list), matching: find.byType(Scrollable)).first,
  );
  await tester.pump();
  return rectOf(tester, key);
}

/// The value text of the KPI tile whose label is [label].
String kpiValue(WidgetTester tester, String label) {
  final tile = find.ancestor(of: find.text(label), matching: find.byType(StatTile));
  final texts = tester.widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text))).toList();
  return texts.first.data ?? '';
}

/// What the age box actually displays.
String _ageText(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextField)))
        .controller!
        .text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('NFE advanced analytics', () {
    testWidgets('412x915: every panel mounts in one column, KPIs read the records', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const NfeAdvancedAnalyticsScreen());

      expect(find.byKey(kpis), findsOneWidget);
      expect(kpiValue(tester, 'Registrations'), '4');
      expect(kpiValue(tester, 'Teachers'), '1');
      expect(kpiValue(tester, 'Partners'), '1');
      expect(kpiValue(tester, 'Centres'), '1');
      expect(kpiValue(tester, 'Programmes'), '3');
      expect(find.byKey(trend), findsOneWidget);
      expect(find.byType(TrendLineChart), findsOneWidget);

      final width = rectOf(tester, trend).width;
      for (final key in [center, gender, nationality, teacherGender, teacherNationality, teacherCenter, crosstab]) {
        final rect = await reveal(tester, key);
        expect(rect.width, closeTo(width, 0.5), reason: '$key is one column wide on the phone');
      }
      expect(find.byType(CrosstabTable), findsOneWidget);
      expectClean(tester);
    });

    testWidgets('1280x800: the trend and the cross-tab span the page, the rest sit three abreast', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const NfeAdvancedAnalyticsScreen());

      final page = rectOf(tester, list);
      expect(rectOf(tester, trend).width, closeTo(page.width - 16, 1));
      final c = rectOf(tester, center);
      final g = rectOf(tester, gender);
      final n = rectOf(tester, nationality);
      expect(c.top, g.top);
      expect(g.top, n.top);
      expect(c.left, lessThan(g.left));
      expect(g.left, lessThan(n.left));
      expect(c.width, closeTo((page.width - 16) / 3, 1));
      final ct = await reveal(tester, crosstab);
      expect(ct.width, closeTo(page.width - 16, 1));
      expectClean(tester);
    });

    testWidgets('800x1280: charts two abreast under a full-width trend', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const NfeAdvancedAnalyticsScreen());

      final c = rectOf(tester, center);
      final g = rectOf(tester, gender);
      expect(c.top, g.top);
      expect(c.left, lessThan(g.left));
      expect(c.width, closeTo(g.width, 0.5));
      // The third card wraps to a second row, beside the fourth.
      final n = await reveal(tester, nationality);
      final tg = rectOf(tester, teacherGender);
      expect(n.top, tg.top);
      expect(n.left, lessThan(tg.left));
      expect(n.left, closeTo(c.left, 0.5));
      expectClean(tester);
    });

    testWidgets('1280x800 Arabic at 1.3x mirrors and stays clean', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const NfeAdvancedAnalyticsScreen(), lang: 'ar', scale: 1.3);

      expect(find.byKey(kpis), findsOneWidget);
      // Wrap lays out in reading order: the first card is on the right.
      expect(rectOf(tester, center).left, greaterThan(rectOf(tester, nationality).left));
      await reveal(tester, crosstab);
      expectClean(tester);
    });

    testWidgets('a gender filter recomputes the KPIs in place, Reset restores them', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const NfeAdvancedAnalyticsScreen());

      expect(find.byKey(const ValueKey('nfe-filter-gender')), findsNothing);
      await tester.tap(find.byKey(moreFilters));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nfe-filter-gender')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Female').last);
      await tester.pumpAndSettle();
      expect(kpiValue(tester, 'Registrations'), '2');
      // Teachers ignore the gender filter, as on the server.
      expect(kpiValue(tester, 'Teachers'), '1');

      await tester.tap(find.byKey(const ValueKey('nfe-filters-reset')));
      await tester.pumpAndSettle();
      expect(kpiValue(tester, 'Registrations'), '4');
      expectClean(tester);
    });

    testWidgets('Reset clears the age boxes, not just the figures behind them', (tester) async {
      // A TextFormField reads `initialValue` once, so Reset used to recompute
      // every figure over all registrations while the box still showed the age
      // the worker had typed: a page claiming a filter it was not applying.
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const NfeAdvancedAnalyticsScreen());

      await tester.tap(find.byKey(moreFilters));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('nfe-filter-age-min')), '9');
      await tester.pumpAndSettle();
      // Two children are 11 (born 2015) and one is 18 (born 2008); the 10- and
      // 7-year-olds drop out.
      expect(kpiValue(tester, 'Registrations'), '3');
      expect(_ageText(tester, 'nfe-filter-age-min'), '9');

      await tester.tap(find.byKey(const ValueKey('nfe-filters-reset')));
      await tester.pumpAndSettle();
      expect(kpiValue(tester, 'Registrations'), '4');
      expect(_ageText(tester, 'nfe-filter-age-min'), isEmpty, reason: 'the control must agree with the figures');
      expectClean(tester);
    });

    testWidgets('the cross-tab re-pairs its axes without re-reading the records', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const NfeAdvancedAnalyticsScreen());

      await reveal(tester, crosstab);
      // It opens on the pairing the website draws.
      expect(find.text('Programme ↓ · Age group →'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('crosstab-y')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gender').last);
      await tester.pumpAndSettle();
      expect(find.text('Programme ↓ · Gender →'), findsOneWidget);
      expect(find.text('Female'), findsWidgets);

      // Choosing the dimension that is already on the other axis swaps them
      // rather than crossing a table with itself.
      await tester.tap(find.byKey(const ValueKey('crosstab-x')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gender').last);
      await tester.pumpAndSettle();
      expect(find.text('Gender ↓ · Programme →'), findsOneWidget);
      expectClean(tester);
    });

    testWidgets('tapping the trend plot prints the day under it', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const NfeAdvancedAnalyticsScreen());

      final plot = find.descendant(of: find.byType(TrendLineChart), matching: find.byType(CustomPaint)).first;
      final rect = tester.getRect(plot);
      await tester.tapAt(rect.centerRight - const Offset(2, 0));
      await tester.pump();
      final detail = tester.widget<Text>(find.byKey(const ValueKey('trend-detail')));
      expect(detail.data!.trim(), isNotEmpty);
      expect(detail.data, contains('registration'));
      expectClean(tester);
    });
  });

  group('analytics hub', () {
    testWidgets('lists the NFE dashboard and opens it', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AnalyticsHubScreen(module: BmaModule.mscc));
      expect(find.byKey(const ValueKey('analytics-entry-nfe-advanced')), findsOneWidget);
      expect(find.byKey(const ValueKey('analytics-entry-alp-registration')), findsNothing);
      expectClean(tester);
    });

    testWidgets('lists the four ALP dashboards, and none for CLM', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const AnalyticsHubScreen(module: BmaModule.alp));
      for (final key in ['alp-registration', 'alp-teachers', 'alp-attendance', 'alp-schools']) {
        expect(find.byKey(ValueKey('analytics-entry-$key')), findsOneWidget, reason: key);
      }
      expectClean(tester);

      await open(tester, fx, const AnalyticsHubScreen(module: BmaModule.clm));
      expect(find.byType(EmptyState), findsOneWidget);
      expectClean(tester);
    });
  });
}
