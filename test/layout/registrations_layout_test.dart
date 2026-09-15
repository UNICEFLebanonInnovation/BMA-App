// LANE: registrations. Covers the spec's two_pane_registrations_test.dart plus
// the compact/tablet smoke cases for the three screens this lane owns:
// the beneficiaries list, the child profile (routed and embedded) and the
// teacher list.
//
// Everything runs against the REAL router and a REAL in-memory SQLite database,
// because the behaviour under test is `context.replace` reusing the page key —
// a stub router would prove nothing.
import 'package:bma_app/app.dart';
import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/config/settings_controller.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/db/entity_dao.dart';
import 'package:bma_app/core/models/entity_record.dart';
import 'package:bma_app/core/sync/connectivity_service.dart';
import 'package:bma_app/core/sync/sync_engine.dart';
import 'package:bma_app/core/widgets/ui.dart';
import 'package:bma_app/features/registrations/child_profile_screen.dart';
import 'package:bma_app/features/registrations/child_profile_view.dart';
import 'package:bma_app/features/registrations/registration_list_screen.dart';
import 'package:bma_app/features/teachers/teacher_list_screen.dart';
import 'package:bma_app/features/tips/tips_controller.dart';
import 'package:bma_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';
import '../support/viewport.dart';

const listPane = ValueKey('reg-list-pane');
const detailPane = ValueKey('reg-detail-pane');
const detailEmpty = ValueKey('reg-detail-empty');
const search = ValueKey('reg-search');
const filter = ValueKey('reg-filter');
const regAdd = ValueKey('reg-add');
const identity = ValueKey('profile-identity');
const actionDelete = ValueKey('profile-action-delete');
const teachersSearch = ValueKey('teachers-search');
const teachersAdd = ValueKey('teachers-add');

/// Never touches the network; `refreshCounts` would otherwise walk the DAO.
class _Engine extends SyncEngine {
  @override
  SyncStatus build() => const SyncStatus();

  @override
  Future<void> refreshCounts() async {}
}

Map<String, dynamic> _child(String first, {required String mother, required String day}) => {
      'center_label': 'Makani Centre',
      'registration_date': '2026-09-01',
      'child': {
        'first_name': first,
        'father_name': 'Ahmad',
        'last_name': 'Sayed',
        'mother_fullname': mother,
        'gender': 'Female',
        'nationality_label': 'Syrian',
        'birthday_year': '2015',
        'birthday_month': '3',
        'birthday_day': day,
        'number': 'ABC-$first',
      },
    };

class Fixture {
  Fixture(this.container, this.db, this.records, this.teachers);

  final ProviderContainer container;
  final AppDatabase db;
  final List<EntityRecord> records;
  final List<EntityRecord> teachers;

  GoRouterLike get router => GoRouterLike(container);
}

/// Thin accessor so the tests read `fx.router.uri` instead of repeating the
/// provider read.
class GoRouterLike {
  GoRouterLike(this.container);

  final ProviderContainer container;

  Uri get uri => container.read(appRouterProvider).routerDelegate.currentConfiguration.uri;

  void go(String location) => container.read(appRouterProvider).go(location);
}

Future<Fixture> fixture(WidgetTester tester, {String lang = 'en'}) async {
  final db = await tester.runAsync(AppDatabase.openInMemory);
  final dao = EntityDao(db!);
  final records = <EntityRecord>[];
  final teachers = <EntityRecord>[];
  await tester.runAsync(() async {
    records.add(await dao.createLocal(
        entity: Entities.msccRegistration, data: _child('Amal', mother: 'Fatima Nasr', day: '5')));
    records.add(await dao.createLocal(
        entity: Entities.msccRegistration, data: _child('Bilal', mother: 'Hanan Deeb', day: '9')));
    records.add(await dao.createLocal(
        entity: Entities.msccRegistration, data: _child('Carla', mother: 'Nour Saad', day: '12')));
    for (final name in ['Rania Khoury', 'Samir Aziz', 'Tarek Wehbe', 'Yara Fares']) {
      teachers.add(await dao.createLocal(entity: Entities.msccTeacher, data: {
        'first_name': name.split(' ').first,
        'last_name': name.split(' ').last,
        'primary_phone_number': '70 123 456',
        'teacher_assignment': 'Facilitator',
        'center_label': 'Makani Centre',
      }));
    }
  });
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db),
    authControllerProvider.overrideWith(() => FakeAuthController(signedIn())),
    syncEngineProvider.overrideWith(_Engine.new),
    connectivityProvider.overrideWith((ref) => Stream.value(true)),
    tipsControllerProvider.overrideWith(() => TipsController(TipsState(seen: {TipsState.seenKey(42)}), null)),
    settingsControllerProvider.overrideWith(() => SettingsController(
          AppSettings(serverUrl: 'https://x.invalid', locale: Locale(lang), serverConfigured: true),
          null,
        )),
  ]);
  addTearDown(container.dispose);
  addTearDown(() => db.close());
  return Fixture(container, db, records, teachers);
}

/// Lets the real SQLite work finish and any route transition run out.
Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Navigates BEFORE the first frame, so no test ever renders Home: this lane
/// does not own home_shell.dart and must not fail on it.
Future<void> open(WidgetTester tester, Fixture fx, String location) async {
  fx.router.go(location);
  await tester.pumpWidget(UncontrolledProviderScope(container: fx.container, child: const BmaApp()));
  await settle(tester);
}

void bigText(WidgetTester tester) {
  tester.platformDispatcher.textScaleFactorTestValue = 1.3;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

String textIn(WidgetTester tester, Key key) =>
    tester.widget<TextField>(find.descendant(of: find.byKey(key), matching: find.byType(TextField))).controller?.text ??
    // SearchField uses an uncontrolled TextField, so read the rendered value.
    (tester.widget<EditableText>(
      find.descendant(of: find.byKey(key), matching: find.byType(EditableText)),
    )).controller.text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('beneficiaries, 1280x800 landscape', () {
    testWidgets('no selection: a 400 px list pane beside the placeholder', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, Routes.registrations(BmaModule.mscc));

      expect(find.byType(RegistrationListScreen), findsOneWidget);
      expect(find.byKey(detailEmpty), findsOneWidget);
      expect(find.byKey(detailPane), findsNothing);
      expect(tester.getSize(find.byKey(listPane)).width, 400);
      // The toolbar replaces the FAB, so there is exactly one add control.
      expect(find.byKey(regAdd), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a row tap selects in place: ?sel= in the URL, profile in the pane, search text kept',
        (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, Routes.registrations(BmaModule.mscc));

      await tester.enterText(find.descendant(of: find.byKey(search), matching: find.byType(TextField)), 'sayed');
      await settle(tester);
      expect(find.byKey(ValueKey('reg-row-${fx.records[1].uuid}')), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('reg-row-${fx.records[1].uuid}')));
      await settle(tester);

      expect(fx.router.uri.queryParameters['sel'], fx.records[1].uuid);
      expect(fx.router.uri.path, '/registrations/mscc');
      expect(find.byKey(detailPane), findsOneWidget);
      expect(find.byKey(detailEmpty), findsNothing);
      expect(find.byType(ChildProfileView), findsOneWidget);
      expect(find.byKey(identity), findsOneWidget);
      // THE REPLACE PROOF: a pushReplacement would have rebuilt the page and
      // emptied this field.
      expect(textIn(tester, search), 'sayed');
      // The stack never grew: the list is still the only page.
      expect(find.byType(RegistrationListScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Selecting another child swaps the pane rather than stacking one.
      await tester.tap(find.byKey(ValueKey('reg-row-${fx.records[2].uuid}')));
      await settle(tester);
      expect(fx.router.uri.queryParameters['sel'], fx.records[2].uuid);
      expect(find.byType(ChildProfileView), findsOneWidget);
    });

    testWidgets('a ?sel= that resolves to nothing shows the placeholder and heals the URL', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, '/registrations/mscc?sel=not-a-record');

      expect(find.byKey(detailEmpty), findsOneWidget);
      expect(find.byKey(detailPane), findsNothing);
      expect(fx.router.uri.queryParameters['sel'], isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mark deleted in the pane closes the pane and leaves the list mounted', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, Routes.registrationsSelected(BmaModule.mscc, fx.records[0].uuid));
      expect(find.byKey(detailPane), findsOneWidget);

      await tester.tap(find.byKey(actionDelete));
      await settle(tester);
      // confirmDialog: Cancel / Confirm.
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await settle(tester);

      // THE HIGHEST-SEVERITY LINE: a context.pop() here would have dismissed
      // the whole list screen.
      expect(find.byType(RegistrationListScreen), findsOneWidget);
      expect(find.byKey(detailPane), findsNothing);
      expect(find.byKey(detailEmpty), findsOneWidget);
      expect(fx.router.uri.queryParameters['sel'], isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('system back clears the selection instead of leaving the screen', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, Routes.registrationsSelected(BmaModule.mscc, fx.records[0].uuid));
      expect(find.byKey(detailPane), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);

      expect(find.byType(RegistrationListScreen), findsOneWidget);
      expect(find.byKey(detailEmpty), findsOneWidget);
      expect(fx.router.uri.queryParameters['sel'], isNull);
    });

    testWidgets('Arabic at 1.3x: the list pane is on the RIGHT and nothing overflows', (tester) async {
      tabletLandscape(tester);
      bigText(tester);
      final fx = await fixture(tester, lang: 'ar');
      await open(tester, fx, Routes.registrationsSelected(BmaModule.mscc, fx.records[0].uuid));

      // A takeException-is-null assertion passes happily on a pane that
      // rendered on the wrong side, so the side is asserted mechanically.
      expect(tester.getTopLeft(find.byKey(listPane)).dx, greaterThan(640));
      expect(tester.getSize(find.byKey(listPane)).width, 400);
      expect(find.byKey(detailPane), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('beneficiaries, 800x1280 portrait', () {
    testWidgets('no pane; a row tap pushes the profile and back keeps the search text', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await open(tester, fx, Routes.registrations(BmaModule.mscc));

      expect(find.byKey(detailEmpty), findsNothing);
      expect(find.byKey(detailPane), findsNothing);
      // Single column: the pane fills the window.
      expect(tester.getSize(find.byKey(listPane)).width, 800);
      // The multi-column row spreads the facts out: the mother's name is its
      // own cell rather than part of a joined subtitle.
      expect(find.text('Fatima Nasr'), findsOneWidget);
      expect(find.byKey(regAdd), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      // The sync state is a labelled chip from `medium` up, not an 18 px glyph.
      expect(find.descendant(of: find.byKey(listPane), matching: find.byType(Chip)), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.descendant(of: find.byKey(search), matching: find.byType(TextField)), 'sayed');
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('reg-row-${fx.records[0].uuid}')));
      await settle(tester);

      // An imperative push leaves `currentConfiguration.uri` on the list, so
      // the pushed page is asserted by what is on screen.
      expect(find.byType(ChildProfileScreen), findsOneWidget);
      expect(find.byType(RegistrationListScreen), findsNothing);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(ChildProfileScreen), findsNothing);
      expect(find.byType(RegistrationListScreen), findsOneWidget);
      expect(textIn(tester, search), 'sayed');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic at 1.3x does not overflow', (tester) async {
      tabletPortrait(tester);
      bigText(tester);
      final fx = await fixture(tester, lang: 'ar');
      await open(tester, fx, Routes.registrations(BmaModule.mscc));
      expect(find.byKey(listPane), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('beneficiaries, 412x915 phone (the fallback that must not move)', () {
    testWidgets('extended FAB, no pane, icon-only sync state, and a pushed profile', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, Routes.registrations(BmaModule.mscc));

      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byKey(regAdd), findsOneWidget);
      expect(find.byKey(detailEmpty), findsNothing);
      expect(find.byKey(filter), findsOneWidget);
      // Compact chips stay 18 px glyphs with a tooltip.
      expect(find.descendant(of: find.byKey(listPane), matching: find.byType(Chip)), findsNothing);
      // The joined subtitle, not the column row.
      expect(find.text('Fatima Nasr'), findsNothing);
      expect(find.textContaining('Fatima Nasr · '), findsOneWidget);

      await tester.tap(find.byKey(ValueKey('reg-row-${fx.records[0].uuid}')));
      await settle(tester);
      expect(find.byType(ChildProfileScreen), findsOneWidget);
      expect(find.byKey(identity), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the row geometry is byte-for-byte today\'s: avatar at 16, name at 70', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, Routes.registrations(BmaModule.mscc));

      final row = find.byKey(ValueKey('reg-row-${fx.records[0].uuid}'));
      final avatar = find.descendant(of: row, matching: find.byType(InitialsAvatar));
      // EdgeInsets.symmetric(horizontal: 16) + a 40 px avatar + SizedBox(14).
      expect(tester.getTopLeft(avatar).dx, 16);
      expect(tester.getSize(avatar).width, 40);
      expect(tester.getTopLeft(find.descendant(of: row, matching: find.text('Amal Ahmad Sayed'))).dx, 70);
      // No selection tint wrapper is added when nothing is selected.
      expect(find.descendant(of: row, matching: find.byType(Material)), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a ?sel= on a phone is ignored: no pane, no URL rewrite fight', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, Routes.registrationsSelected(BmaModule.mscc, fx.records[0].uuid));

      expect(find.byKey(detailPane), findsNothing);
      expect(find.byType(ChildProfileView), findsNothing);
      expect(find.byType(RegistrationListScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('child profile as its own route', () {
    testWidgets('1280x800: the identity panel replaces the header band, tabs are kept', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, Routes.profile(fx.records[0].uuid));

      expect(find.byKey(identity), findsOneWidget);
      expect(tester.getSize(find.byKey(identity)).width, 340);
      expect(find.byType(Tab), findsNWidgets(3));
      // The route owns the app bar, so the panel shows no duplicate buttons.
      expect(find.byKey(actionDelete), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('412x915: unchanged — header band, no identity panel', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, Routes.profile(fx.records[0].uuid));

      expect(find.byKey(identity), findsNothing);
      expect(find.byType(Tab), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280 in Arabic at 1.3x does not overflow', (tester) async {
      tabletPortrait(tester);
      bigText(tester);
      final fx = await fixture(tester, lang: 'ar');
      await open(tester, fx, Routes.profile(fx.records[0].uuid));
      expect(find.byType(ChildProfileView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('teachers', () {
    testWidgets('412x915: the list and the circular FAB are unchanged', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await open(tester, fx, Routes.teachers(BmaModule.mscc));

      expect(find.byType(TeacherListScreen), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.byKey(teachersSearch), findsOneWidget);
      expect(find.byKey(ValueKey('teacher-card-${fx.teachers[0].uuid}')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1280x800: a three-across card grid with a labelled add button', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await open(tester, fx, Routes.teachers(BmaModule.mscc));

      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.widgetWithIcon(FilledButton, Icons.add), findsOneWidget);
      expect(find.byKey(teachersAdd), findsOneWidget);

      final tops = [
        for (final t in fx.teachers) tester.getTopLeft(find.byKey(ValueKey('teacher-card-${t.uuid}'))),
      ];
      // Three on the first row, the fourth wrapping to the second.
      expect(tops[1].dy, tops[0].dy);
      expect(tops[2].dy, tops[0].dy);
      expect(tops[3].dy, greaterThan(tops[0].dy));
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280: two across, and Arabic at 1.3x does not overflow', (tester) async {
      tabletPortrait(tester);
      bigText(tester);
      final fx = await fixture(tester, lang: 'ar');
      await open(tester, fx, Routes.teachers(BmaModule.mscc));

      expect(find.byType(GridView), findsOneWidget);
      final tops = [
        for (final t in fx.teachers) tester.getTopLeft(find.byKey(ValueKey('teacher-card-${t.uuid}'))),
      ];
      expect(tops[1].dy, tops[0].dy);
      expect(tops[2].dy, greaterThan(tops[0].dy));
      // RTL: the first card starts on the right.
      expect(tops[0].dx, greaterThan(tops[1].dx));
      expect(tester.takeException(), isNull);
    });
  });
}
