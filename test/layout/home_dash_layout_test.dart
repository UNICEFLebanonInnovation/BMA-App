// LANE: home-dash. Covers lib/features/home/home_shell.dart,
// lib/features/dashboard/dashboard_screen.dart,
// lib/features/profiles/facility_profile_screen.dart and
// lib/features/settings/settings_screen.dart at the three viewports the
// tablet work targets — 1280x800 landscape, 800x1280 portrait and the
// 412x915 phone that must not move — plus Arabic RTL at 1.3x.
//
// The screens are pumped directly rather than through the router: none of
// them reads route state to lay itself out. The MaterialApp mirrors app.dart's
// builder exactly, so a test at 800 px shortest side sees the production
// density theme.
//
// NAMING: the lane is "home-dash" but the file is home_dash_layout_test.dart —
// a hyphen in a Dart file name trips the `file_names` lint and would fail the
// clean-analyze gate.
import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/db/entity_dao.dart';
import 'package:bma_app/core/db/reference_dao.dart';
import 'package:bma_app/core/layout/breakpoints.dart';
import 'package:bma_app/core/models/reference_item.dart';
import 'package:bma_app/core/models/user_profile.dart';
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:bma_app/core/widgets/common.dart';
import 'package:bma_app/core/widgets/ui.dart';
import 'package:bma_app/features/dashboard/dashboard_screen.dart';
import 'package:bma_app/features/home/home_shell.dart';
import 'package:bma_app/features/profiles/facility_profile_screen.dart';
import 'package:bma_app/features/settings/settings_screen.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';
import '../support/viewport.dart';

const summaryPane = ValueKey('home-summary-pane');
const modulesPane = ValueKey('home-modules');
const homeHelp = ValueKey('home-help');
const kpis = ValueKey('dash-kpis');
const breakGender = ValueKey('dash-breakdown-gender');
const breakNationality = ValueKey('dash-breakdown-nationality');
const breakAge = ValueKey('dash-breakdown-age');
const factsPane = ValueKey('profile-facts-pane');
const statsPane = ValueKey('profile-stats-pane');
const profileStatus = ValueKey('profile-status');
const profileEdit = ValueKey('profile-edit');
const showTips = ValueKey('settings-show-tips');
const settingsActions = ValueKey('settings-actions');
const settingsDanger = ValueKey('settings-danger');

// Reference data the centre/school profiles resolve their facts from. The ids
// line up with the NamedRefs on the profile below.
final _bekaa = ReferenceItem(kind: 'locations', id: 1, name: 'البقاع', nameEn: 'Bekaa');
final _zahle = ReferenceItem(kind: 'locations', id: 2, name: 'زحلة', nameEn: 'Zahle', parentId: 1);
final _barElias = ReferenceItem(kind: 'locations', id: 3, name: 'بر الياس', nameEn: 'Bar Elias', parentId: 2);
final _partner = ReferenceItem(kind: 'partners', id: 15, name: 'Test Partner');

final _center = ReferenceItem(
  kind: 'centers',
  id: 1,
  name: 'Makani Centre',
  extra: const {
    'partner_id': 15,
    'governorate_id': 1,
    'caza_id': 2,
    'cadaster_id': 3,
    'type': 'Community Hub',
    'programs': ['BLN', 'CBECE'],
    'provided_packages': ['YBLN'],
    'is_active': true,
    'latitude': 33.7654321,
    'longitude': 35.9123456,
  },
);

final _school = ReferenceItem(
  kind: 'schools',
  id: 7,
  name: 'Bar Elias Public School',
  extra: const {
    'number': '1234',
    'partner_id': 15,
    'governorate_id': 1,
    'district_id': 2,
    'cadaster_id': 3,
    'type': 'Public School',
    'is_bma': true,
    'is_closed': false,
    'working_days': ['Monday', 'Tuesday'],
    'weekend': ['Sunday'],
  },
);

/// Three modules so the module grid has something to go 2-up with, and a
/// school so the ALP profile renders its edit card.
UserProfile _profile({bool allModules = true}) => UserProfile(
      id: 42,
      username: 'u42',
      firstName: 'Rima',
      lastName: 'Haddad',
      groups: const [],
      modules: allModules
          ? {BmaModule.mscc: caps(), BmaModule.alp: caps(), BmaModule.clm: caps()}
          : {BmaModule.mscc: caps()},
      partner: const NamedRef(id: 15, name: 'Test Partner'),
      center: const NamedRef(id: 1, name: 'Makani Centre'),
      school: const NamedRef(id: 7, name: 'Bar Elias Public School'),
    );

Map<String, dynamic> _registration(String first, String gender) => {
      'center_label': 'Makani Centre',
      'registration_date': '2026-09-01',
      'child': {
        'first_name': first,
        'father_name': 'Ahmad',
        'last_name': 'Sayed',
        'gender': gender,
        'nationality_label': 'Syrian',
        'birthday_year': '2015',
        'birthday_month': '3',
        'birthday_day': '5',
      },
    };

class Fixture {
  Fixture(this.container);

  final ProviderContainer container;
}

Future<Fixture> fixture(WidgetTester tester, {bool allModules = true}) async {
  final db = await tester.runAsync(AppDatabase.openInMemory);
  await tester.runAsync(() async {
    final reference = ReferenceDao(db!);
    await reference.replaceKind('locations', [_bekaa, _zahle, _barElias]);
    await reference.replaceKind('partners', [_partner]);
    await reference.replaceKind('centers', [_center]);
    await reference.replaceKind('schools', [_school]);
    final dao = EntityDao(db);
    // Enough rows for the dashboard breakdowns to have bars to draw.
    await dao.createLocal(entity: Entities.msccRegistration, data: _registration('Amal', 'Female'));
    await dao.createLocal(entity: Entities.msccRegistration, data: _registration('Omar', 'Male'));
    await dao.createLocal(entity: Entities.msccRegistration, data: _registration('Nour', 'Female'));
  });
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db!),
    ...tipsOverrides(
      auth: AuthState(
        status: AuthStatus.signedIn,
        token: 't',
        deviceId: 'd',
        profile: _profile(allModules: allModules),
      ),
    ),
  ]);
  addTearDown(container.dispose);
  addTearDown(() => db.close());
  return Fixture(container);
}

/// Lets the real SQLite futures resolve.
Future<void> settle(WidgetTester tester, {int rounds = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

/// Mirrors app.dart: same delegates, same density builder.
Future<void> open(
  WidgetTester tester,
  Fixture fx,
  Widget screen, {
  String lang = 'en',
  double scale = 1.0,
}) async {
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
        data: AppTheme.cached(
          tablet: MediaQuery.sizeOf(context).shortestSide >= Breakpoints.tabletShortestSide,
        ),
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

/// The single assertion every case in this file shares: no RenderFlex, no
/// unbounded-height and no grid-cell overflow at this size.
void expectClean(WidgetTester tester) => expect(tester.takeException(), isNull);

/// Rows of widgets that share a top edge, largest row first in document order.
List<List<Rect>> rowsOf(WidgetTester tester, Finder finder) {
  final rects = [for (final e in finder.evaluate()) tester.getRect(find.byWidget(e.widget))];
  final rows = <List<Rect>>[];
  for (final r in rects) {
    final row = rows.where((row) => (row.first.top - r.top).abs() < 1).firstOrNull;
    if (row == null) {
      rows.add([r]);
    } else {
      row.add(r);
    }
  }
  return rows;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('home shell', () {
    testWidgets('412x915: the phone list, unchanged', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const HomeShell());

      // No panes, no module grid container: the phone takes the branch that
      // installs no LayoutScope at all.
      expect(find.byKey(summaryPane), findsNothing);
      expect(find.byKey(modulesPane), findsNothing);
      expect(find.byKey(homeHelp), findsOneWidget);

      // GridView.count(3, childAspectRatio: 0.95) geometry, verbatim. The
      // first module card is 412 - 24 of AppCard margin - 32 of padding wide.
      final tiles = rowsOf(tester, find.byType(ActionTile));
      expect(tiles.first, hasLength(3));
      final tile = tiles.first.first;
      // 412 - 24 of AppCard margin - 32 of padding - 2 of border - 16 of
      // crossAxisSpacing, over three columns.
      expect(tile.width, closeTo((412 - 24 - 32 - 2 - 16) / 3, 0.5));
      expect(tile.width / tile.height, closeTo(0.95, 0.01));
      expectClean(tester);
    });

    testWidgets('1280x800: a 400 px summary pane beside a 2-up module grid', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const HomeShell());

      final summary = rectOf(tester, summaryPane);
      final modules = rectOf(tester, modulesPane);
      expect(summary.width, 400);
      expect(summary.left, 0);
      expect(modules.left, greaterThanOrEqualTo(400));
      expect(modules.width, greaterThan(summary.width));
      expect(find.byKey(homeHelp), findsOneWidget);

      // Three module cards, 2-up: one GridView of action tiles per card.
      final cards = rowsOf(tester, find.byType(GridView));
      expect(cards.first, hasLength(2));
      expect(cards, hasLength(2));

      // The point of the commit: an extent-based delegate. Tiles stay small
      // instead of ballooning to ~300x316 for a 44 px glyph.
      final tile = rowsOf(tester, find.byType(ActionTile)).first.first;
      // maxCrossAxisExtent is a target, not a hard cap: the delegate rounds
      // the column count up and shares the remainder, so a tile may exceed
      // the 132 token by up to one crossAxisSpacing.
      expect(tile.width, lessThanOrEqualTo(132 + 8));
      // 2 px border + 28 px padding + a 52 px circle + an 8 px gap + two
      // 13.5 px label lines at height 1.2. Nowhere near the ~300x316 the
      // childAspectRatio grid produced at this width.
      expect(tile.height, closeTo(122.4, 0.5));
      expectClean(tester);
    });

    testWidgets('800x1280: one capped column, no panes', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const HomeShell());

      expect(find.byKey(summaryPane), findsNothing);
      expect(find.byKey(modulesPane), findsOneWidget);
      // The gradient band stays full bleed; only its content is capped.
      expect(tester.getSize(find.byType(HeroHeader)).width, 800);
      // contentMaxWidth 840 > 800, so the cap is the window and the gutter is
      // what shows: 24 each side.
      expect(rectOf(tester, modulesPane).left, 24);
      expect(rectOf(tester, modulesPane).width, 800 - 48);

      final tile = rowsOf(tester, find.byType(ActionTile)).first.first;
      // maxCrossAxisExtent is a target, not a hard cap: the delegate rounds
      // the column count up and shares the remainder, so a tile may exceed
      // the 132 token by up to one crossAxisSpacing.
      expect(tile.width, lessThanOrEqualTo(132 + 8));
      expect(tile.height, closeTo(122.4, 0.5));
      expectClean(tester);
    });

    testWidgets('1280x800 ar at 1.3x: the summary pane mirrors to the right', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const HomeShell(), lang: 'ar', scale: 1.3);

      final summary = rectOf(tester, summaryPane);
      // A takeException-is-null assertion passes happily on a pane that
      // rendered on the wrong side, so assert the side explicitly.
      expect(summary.left, greaterThan(640));
      expect(summary.right, 1280);
      expect(rectOf(tester, modulesPane).left, 0);
      expectClean(tester);
    });

    testWidgets('800x1280 ar at 1.3x stays clean', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const HomeShell(), lang: 'ar', scale: 1.3);
      expect(find.byKey(modulesPane), findsOneWidget);
      expectClean(tester);
    });
  });

  group('dashboard', () {
    testWidgets('412x915: the two-column KPI grid the phone has today', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const DashboardScreen(module: BmaModule.mscc));

      final rows = rowsOf(tester, find.descendant(of: find.byKey(kpis), matching: find.byType(StatTile)));
      expect(rows.first, hasLength(2));
      // GridView.count(2, childAspectRatio: 1.6) over 412 - 16 of padding.
      expect(rows.first.first.width, closeTo(198, 0.5));
      expect(rows.first.first.height, closeTo(198 / 1.6, 0.5));
      // One breakdown card per row.
      expect(rectOf(tester, breakGender).top, lessThan(rectOf(tester, breakNationality).top));
      expectClean(tester);
    });

    testWidgets('1280x800: six KPIs in one band and three breakdowns abreast', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const DashboardScreen(module: BmaModule.mscc));

      final rows = rowsOf(tester, find.descendant(of: find.byKey(kpis), matching: find.byType(StatTile)));
      expect(rows, hasLength(1));
      expect(rows.single, hasLength(6));
      // Capped at contentMaxWidth and centred.
      expect(rectOf(tester, kpis).width, closeTo(1120 - 16, 0.5));

      final gender = rectOf(tester, breakGender);
      final nationality = rectOf(tester, breakNationality);
      final age = rectOf(tester, breakAge);
      expect(gender.top, nationality.top);
      expect(nationality.top, age.top);
      expect(gender.left, lessThan(nationality.left));
      expect(nationality.left, lessThan(age.left));
      expectClean(tester);
    });

    testWidgets('800x1280: breakdowns 2-up', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const DashboardScreen(module: BmaModule.mscc));

      final gender = rectOf(tester, breakGender);
      final nationality = rectOf(tester, breakNationality);
      final age = rectOf(tester, breakAge);
      expect(gender.top, nationality.top);
      expect(gender.left, lessThan(nationality.left));
      expect(age.top, greaterThan(gender.top));
      expectClean(tester);
    });

    testWidgets('1280x800 ar at 1.3x stays clean and mirrors', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const DashboardScreen(module: BmaModule.mscc), lang: 'ar', scale: 1.3);
      // Wrap lays out in reading order, so the first breakdown is rightmost.
      expect(rectOf(tester, breakGender).left, greaterThan(rectOf(tester, breakAge).left));
      expectClean(tester);
    });
  });

  group('facility profile', () {
    testWidgets('412x915: stats above the facts, single column', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const CenterProfileScreen());

      expect(find.byKey(profileStatus), findsOneWidget);
      expect(find.byKey(factsPane), findsNothing);
      expect(find.byKey(statsPane), findsNothing);
      // Three tiles sharing the row, as StatRow does at compact.
      final tiles = rowsOf(tester, find.byType(StatTile));
      expect(tiles.single, hasLength(3));
      // Facts stacked one per row.
      final facts = rowsOf(tester, find.byType(FactRow));
      expect(facts.every((row) => row.length == 1), isTrue);
      expectClean(tester);
    });

    testWidgets('1280x800: facts lead, figures follow in a 400 px column', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const CenterProfileScreen());

      final facts = rectOf(tester, factsPane);
      final stats = rectOf(tester, statsPane);
      expect(stats.width, 400);
      expect(stats.left, greaterThanOrEqualTo(facts.right));
      expect(facts.width, greaterThan(stats.width));
      // The gradient band is still full bleed above both.
      expect(tester.getSize(find.byType(HeroHeader)).width, 1280);
      expect(find.byKey(profileStatus), findsOneWidget);
      // Facts split 2-up: the six facts land in three rows of two.
      final rows = rowsOf(tester, find.byType(FactRow));
      expect(rows.first, hasLength(2));
      expectClean(tester);
    });

    testWidgets('800x1280: one column and three tiles that still fit', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const CenterProfileScreen());

      final facts = rectOf(tester, factsPane);
      final stats = rectOf(tester, statsPane);
      expect(stats.top, lessThan(facts.top));
      expect(stats.left, facts.left);
      // THE REGRESSION THIS CASE EXISTS FOR: StatRow pins each tile to 260 at
      // medium, and three of those plus the gaps need 796 px — more than an
      // 800 px tablet has once the gutter is paid. _StatBand takes the token
      // as a ceiling instead, so the row fits.
      final tiles = rowsOf(tester, find.byType(StatTile));
      expect(tiles.single, hasLength(3));
      expect(tiles.single.last.right, lessThanOrEqualTo(800));
      expectClean(tester);
    });

    testWidgets('1280x800: the ALP school profile keeps its edit card', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SchoolProfileScreen());

      expect(find.byKey(profileStatus), findsOneWidget);
      expect(find.byKey(profileEdit), findsOneWidget);
      // The edit card belongs to the figures column, not the facts column.
      expect(rectOf(tester, profileEdit).left, greaterThanOrEqualTo(rectOf(tester, factsPane).right));
      expectClean(tester);
    });

    testWidgets('1280x800 ar at 1.3x: the figures column mirrors', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const CenterProfileScreen(), lang: 'ar', scale: 1.3);
      expect(rectOf(tester, statsPane).right, lessThanOrEqualTo(rectOf(tester, factsPane).left));
      expectClean(tester);
    });

    testWidgets('800x1280 ar at 1.3x stays clean', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const CenterProfileScreen(), lang: 'ar', scale: 1.3);
      expect(find.byKey(profileStatus), findsOneWidget);
      expectClean(tester);
    });
  });

  group('settings', () {
    testWidgets('412x915: four stretched buttons, no divider block', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SettingsScreen());

      expect(find.byKey(showTips), findsOneWidget);
      expect(find.byKey(settingsActions), findsNothing);
      expect(find.byKey(settingsDanger), findsNothing);
      // 412 - 24 of ListView padding: the full-bleed bar it is today.
      expect(rectOf(tester, showTips).width, 412 - 24);
      expectClean(tester);
    });

    testWidgets('800x1280: intrinsic-width actions with the destructive pair fenced off', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SettingsScreen());

      expect(find.byKey(settingsActions), findsOneWidget);
      expect(find.byKey(settingsDanger), findsOneWidget);
      expect(rectOf(tester, showTips).width, lessThan(400));
      // The safe pair sits above the divider, the destructive pair below it.
      final divider = tester.getRect(find.byType(Divider).last);
      expect(rectOf(tester, settingsActions).bottom, lessThanOrEqualTo(divider.top));
      expect(rectOf(tester, settingsDanger).top, greaterThanOrEqualTo(divider.bottom));
      expectClean(tester);
    });

    testWidgets('1280x800: the page is capped at the reading width', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SettingsScreen());

      // readingMaxWidth at expanded is 760; settings gain nothing from width.
      // readingMaxWidth 760 minus the 32 px gutter AdaptiveBody pays inside
      // the cap.
      final list = tester.getRect(find.byType(ListView));
      expect(list.width, 760 - 64);
      expect(list.center.dx, closeTo(640, 0.5));
      expect(find.byKey(showTips), findsOneWidget);
      expectClean(tester);
    });

    testWidgets('1280x800 ar at 1.3x stays clean', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, const SettingsScreen(), lang: 'ar', scale: 1.3);
      expect(find.byKey(showTips), findsOneWidget);
      // The action block hugs the start edge, which is the right in Arabic.
      expect(rectOf(tester, showTips).right, greaterThan(640));
      expectClean(tester);
    });
  });
}
