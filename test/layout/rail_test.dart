// COMMIT 6: the navigation rail. Covers lib/core/layout/adaptive_shell.dart,
// lib/core/layout/nav_destinations.dart and lib/core/layout/current_module.dart.
//
// Everything here pumps the REAL BmaApp and the REAL appRouterProvider,
// because the three things that can go wrong with a rail installed above the
// Navigator — it appears where it must not, it re-parents the page, or it
// grows the back stack — are all properties of the whole app and of nothing
// smaller.
import 'package:bma_app/app.dart';
import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/forms/schema_form_controller.dart';
import 'package:bma_app/core/layout/adaptive_shell.dart';
import 'package:bma_app/core/layout/current_module.dart';
import 'package:bma_app/core/layout/nav_destinations.dart';
import 'package:bma_app/core/models/form_schema.dart';
import 'package:bma_app/core/models/user_profile.dart';
import 'package:bma_app/features/auth/login_screen.dart';
import 'package:bma_app/features/dashboard/dashboard_screen.dart';
import 'package:bma_app/features/home/home_shell.dart';
import 'package:bma_app/features/registrations/registration_list_screen.dart';
import 'package:bma_app/features/settings/settings_screen.dart';
import 'package:bma_app/features/setup/server_setup_screen.dart';
import 'package:bma_app/features/tips/tips_controller.dart';
import 'package:bma_app/features/tips/tips_wizard_screen.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:bma_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';
import '../support/viewport.dart';

const home = ValueKey('nav-dest-home');
const beneficiaries = ValueKey('nav-dest-beneficiaries');
const dashboard = ValueKey('nav-dest-dashboard');
const settings = ValueKey('nav-dest-settings');
const sync = ValueKey('nav-dest-sync');
const moduleSwitch = ValueKey('nav-module-switch');

UserProfile _profile({bool allModules = false}) => UserProfile(
      id: 42,
      username: 'u42',
      firstName: 'Rima',
      lastName: 'Haddad',
      groups: const [],
      modules: allModules
          ? {BmaModule.mscc: caps(), BmaModule.alp: caps()}
          : {BmaModule.mscc: caps()},
      partner: const NamedRef(id: 15, name: 'Test Partner'),
      center: const NamedRef(id: 1, name: 'NFE Centre'),
      school: const NamedRef(id: 7, name: 'Bar Elias Public School'),
    );

/// A container wired to an in-memory SQLite database and a signed-in account
/// that has already seen the tips, so the app opens on Home.
Future<ProviderContainer> fixture(
  WidgetTester tester, {
  bool allModules = false,
  bool signedOut = false,
  bool serverConfigured = true,
  bool tipsSeen = true,
  String lang = 'en',
}) async {
  final db = await tester.runAsync(AppDatabase.openInMemory);
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db!),
    ...tipsOverrides(
      auth: signedOut
          ? AuthState.signedOut
          : AuthState(
              status: AuthStatus.signedIn,
              token: 't',
              deviceId: 'd',
              profile: _profile(allModules: allModules),
            ),
      tips: tipsSeen ? TipsState(seen: {TipsState.seenKey(42)}) : const TipsState(),
      lang: lang,
      serverConfigured: serverConfigured,
    ),
  ]);
  addTearDown(container.dispose);
  addTearDown(() => db.close());
  return container;
}

/// Lets the real SQLite futures resolve.
Future<void> settle(WidgetTester tester, {int rounds = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> pumpApp(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const BmaApp()));
  await settle(tester);
}

/// Where the app actually is — `currentConfiguration.uri` ignores imperative
/// pushes and would read /home for the whole test.
String path(ProviderContainer c) => currentLocation(c.read(appRouterProvider));

int depth(ProviderContainer c) =>
    c.read(appRouterProvider).routerDelegate.currentConfiguration.matches.length;

/// The Android back button, delivered the way the platform delivers it — not
/// `router.pop()`, which would prove nothing about what back means.
Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
}

Future<void> tapRail(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('railModeFor', () {
    const wide = Size(1280, 800);

    test('window width picks the mode', () {
      expect(railModeFor(const Size(999, 800), Routes.home), RailMode.hidden);
      expect(railModeFor(const Size(1000, 800), Routes.home), RailMode.collapsed);
      expect(railModeFor(const Size(1199, 800), Routes.home), RailMode.collapsed);
      expect(railModeFor(const Size(1200, 800), Routes.home), RailMode.extended);
      expect(railModeFor(wide, Routes.home), RailMode.extended);
    });

    test('the two target orientations and the phone', () {
      // 800x1280 portrait: no rail, deliberately — 800 − 212 is too little for
      // a two-column form, and portrait is the registration posture.
      expect(railModeFor(const Size(800, 1280), Routes.home), RailMode.hidden);
      expect(railModeFor(const Size(412, 915), Routes.home), RailMode.hidden);
      // Phone landscape is wide enough and far too short.
      expect(railModeFor(const Size(915, 412), Routes.home), RailMode.hidden);
      expect(railFitsWindow(const Size(915, 412)), isFalse);
      expect(railFitsWindow(wide), isTrue);
    });

    test('every gate route hides the rail even on the target hardware', () {
      for (final gate in [Routes.splash, Routes.login, Routes.setup, Routes.tips]) {
        expect(railModeFor(wide, gate), RailMode.hidden, reason: gate);
      }
      // A query string must not smuggle a gate route past the check.
      expect(railModeFor(wide, '${Routes.tips}?from=settings'), RailMode.hidden);
      expect(railModeFor(wide, Routes.settings), RailMode.extended);
    });
  });

  group('destinations', () {
    late AppLocalizations l10n;

    setUpAll(() async => l10n = await AppLocalizations.delegate.load(const Locale('en')));

    test('mirror home_shell capability gating', () {
      final full = destinationsFor(_profile(), BmaModule.mscc, l10n);
      expect(full.map((d) => d.key).toList(),
          ['home', 'facility', 'beneficiaries', 'attendance', 'teachers', 'dashboard']);

      // ALP adds teacher attendance and swaps the facility profile.
      final alp = destinationsFor(_profile(allModules: true), BmaModule.alp, l10n);
      expect(alp.map((d) => d.key).toList(), [
        'home',
        'facility',
        'beneficiaries',
        'attendance',
        'teacher-attendance',
        'teachers',
        'dashboard',
      ]);
      expect(alp[1].location, Routes.schoolProfile);

      // No capabilities: only the two ungated places, and no facility card.
      final none = destinationsFor(null, BmaModule.mscc, l10n);
      expect(none.map((d) => d.key).toList(), ['home', 'beneficiaries', 'dashboard']);

      // "Register new" is an action, not a destination.
      expect(full.any((d) => d.location.endsWith('/new')), isFalse);
    });

    test('selection is a longest-prefix match, and null when nothing matches', () {
      final alp = destinationsFor(_profile(allModules: true), BmaModule.alp, l10n);
      int? index(String location) => destinationIndexFor(alp, location);
      final keys = alp.map((d) => d.key).toList();

      expect(keys[index(Routes.home)!], 'home');
      expect(keys[index('/registrations/alp')!], 'beneficiaries');
      expect(keys[index('/registrations/alp?sel=abc')!], 'beneficiaries');
      expect(keys[index('/registrations/alp/new')!], 'beneficiaries');
      // Drill-downs live on their own paths and still highlight their parent.
      expect(keys[index('/record/abc')!], 'beneficiaries');
      expect(keys[index('/record/abc/edit')!], 'beneficiaries');
      expect(keys[index('/service/abc')!], 'beneficiaries');
      expect(keys[index('/teachers/alp')!], 'teachers');
      expect(keys[index('/teacher/abc')!], 'teachers');
      // THE LONGEST-PREFIX CASE: /attendance/alp/teachers extends /attendance/alp.
      expect(keys[index('/attendance/alp')!], 'attendance');
      expect(keys[index('/attendance/alp/teachers')!], 'teacher-attendance');
      // A child's attendance sheet is reached from the profile, not the module
      // attendance screen.
      expect(keys[index('/record/abc/attendance')!], 'beneficiaries');
      // Unmatched: the rail highlights nothing rather than lying.
      expect(index(Routes.settings), isNull);
      expect(index(Routes.sync), isNull);

      final trailing = trailingDestinationsFor(l10n);
      expect(destinationIndexFor([trailing.first], '/sync/history'), 0);
      expect(destinationIndexFor([trailing.first], Routes.settings), isNull);
    });

    test('moduleOfLocation reads the :module segment and nothing else', () {
      expect(moduleOfLocation('/registrations/alp'), BmaModule.alp);
      expect(moduleOfLocation('/attendance/clm'), BmaModule.clm);
      expect(moduleOfLocation('/attendance/alp/teachers'), BmaModule.alp);
      expect(moduleOfLocation('/dashboard/mscc'), BmaModule.mscc);
      expect(moduleOfLocation('/teachers/alp/new'), BmaModule.alp);
      expect(moduleOfLocation(Routes.home), isNull);
      expect(moduleOfLocation(Routes.sync), isNull);
      expect(moduleOfLocation('/record/abc'), isNull);
      expect(moduleOfLocation('/profile/center'), isNull);
    });
  });

  group('where the rail appears', () {
    testWidgets('never on the phone, and Home is mounted exactly once', (tester) async {
      phone(tester);
      final c = await fixture(tester);
      await pumpApp(tester, c);

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never in phone landscape — 915 wide but only 412 tall', (tester) async {
      phoneLandscape(tester);
      final c = await fixture(tester);
      await pumpApp(tester, c);

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never in tablet portrait', (tester) async {
      tabletPortrait(tester);
      final c = await fixture(tester);
      await pumpApp(tester, c);

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('extended in tablet landscape, 212 px, Home still mounted once', (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester);
      await pumpApp(tester, c);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-rail')), findsOneWidget);
      expect(find.byType(HomeShell), findsOneWidget);
      final rail = tester.getRect(find.byType(NavigationRail));
      expect(rail.width, railExtendedWidth);
      expect(rail.left, 0);
      // Every destination and both trailing actions resolve.
      for (final key in [home, beneficiaries, dashboard, sync, settings]) {
        expect(find.byKey(key), findsOneWidget, reason: '$key');
      }
      // One enabled module: the switcher would be dead chrome.
      expect(find.byKey(moduleSwitch), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the module switcher appears only with more than one programme', (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester, allModules: true);
      await pumpApp(tester, c);

      expect(find.byKey(moduleSwitch), findsOneWidget);
      // Switching moves the module-scoped destinations without navigating.
      expect(c.read(currentModuleProvider), BmaModule.mscc);
      c.read(currentModuleProvider.notifier).select(BmaModule.alp);
      await tester.pump();
      expect(path(c), Routes.home);
      await tapRail(tester, beneficiaries);
      expect(path(c), '/registrations/alp');
      expect(tester.takeException(), isNull);
    });

    testWidgets('gate route: the tips wizard gets no rail at 1280x800', (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester, tipsSeen: false);
      await pumpApp(tester, c);

      expect(find.byType(TipsWizardScreen), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tips-skip')));
      await settle(tester);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget,
          reason: 'leaving the gate route brings the rail back');
      expect(tester.takeException(), isNull);
    });

    testWidgets('gate routes: login and setup get no rail at 1280x800', (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester, signedOut: true);
      await pumpApp(tester, c);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);

      final setup = await fixture(tester, signedOut: true, serverConfigured: false);
      await pumpApp(tester, setup);
      expect(find.byType(ServerSetupScreen), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  // TAB-001 / TAB-002. The rail's own height budget is a GUESS
  // (`_chromeHeight + destinations * _labelledDestination`) and the guess is
  // wrong: a collapsed rail is 72 px wide, so `Teacher attendance` wraps to
  // three lines and a labelled destination measures 64-112 px, not 76 — and
  // the guess never consulted the text scaler. What makes a wrong guess
  // harmless is `scrollable: true` (the destination group scrolls) plus
  // `trailingAtBottom: true` (Sync and Settings live OUTSIDE that group, in
  // the rail's outer Column). Before those two flags the trailing block was
  // appended to a `mainAxisSize.min` Column inside one Flexible and the last
  // children were laid out PAST the bottom edge: unreachable, with overflow
  // stripes painted on every screen in the app.
  group('the collapsed rail degrades instead of hiding its actions', () {
    /// The whole point: an action that is not inside the rail cannot be tapped.
    void expectOnTheRail(WidgetTester tester, Key key) {
      expect(find.byKey(key), findsOneWidget, reason: '$key must be in the tree');
      final rail = tester.getRect(find.byType(NavigationRail));
      final action = tester.getRect(find.byKey(key));
      expect(rail.contains(action.topLeft), isTrue, reason: '$key top $action is off the rail $rail');
      expect(rail.contains(action.bottomRight - const Offset(0.01, 0.01)), isTrue,
          reason: '$key bottom $action is off the rail $rail');
    }

    testWidgets('1100x636 — the exact height where the label gate flips on', (tester) async {
      // 180 + 6 * 76 = 636: one pixel lower the rail lays out icons only, here
      // it turns labels on. It used to overflow by 78 px and render Settings
      // entirely below the rail's bottom edge.
      freeformWindow(tester, 1100, 636);
      final c = await fixture(tester);
      await pumpApp(tester, c);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(tester.getRect(find.byType(NavigationRail)).width, railCollapsedWidth);
      expectOnTheRail(tester, sync);
      expectOnTheRail(tester, settings);
      expect(tester.takeException(), isNull);
    });

    for (final lang in ['en', 'ar']) {
      testWidgets('1100x800 at textScaler 1.3, $lang — every route, not just Home', (tester) async {
        freeformWindow(tester, 1100, 800);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final c = await fixture(tester, lang: lang);
        await pumpApp(tester, c);

        // The fault was in the persistent shell, so it showed on every screen.
        for (final key in [beneficiaries, dashboard, settings]) {
          await tapRail(tester, key);
          expectOnTheRail(tester, sync);
          expectOnTheRail(tester, settings);
          expect(tester.takeException(), isNull, reason: 'after opening $key');
        }
      });
    }

    testWidgets('Sync and Settings sit at the BOTTOM of the extended rail', (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester);
      await pumpApp(tester, c);

      final rail = tester.getRect(find.byType(NavigationRail));
      final settingsRect = tester.getRect(find.byKey(settings));
      // They used to float at y 320..408 of an 800 px rail, directly under the
      // last destination, with 392 px of empty rail beneath them.
      expect(settingsRect.bottom, closeTo(rail.bottom, 20));
      expect(settingsRect.top, greaterThan(rail.top + rail.height / 2));
      // Sync is immediately above Settings, still in reading order.
      expect(tester.getRect(find.byKey(sync)).bottom, lessThanOrEqualTo(settingsRect.top + 1));
      // And the destinations are still at the top, not pushed down with them.
      expect(tester.getRect(find.byKey(home)).bottom, lessThan(rail.height / 2));
      expect(tester.takeException(), isNull);
    });
  });

  // THE RAIL TAKES 212 PX OUT OF THE WINDOW, so every screen it opens is laid
  // out in a 1067 px pane rather than in the full 1280 — and nothing else in
  // the suite pumps a screen with the rail above it (the per-screen layout
  // files pump each screen on its own, at the full window width). This group is
  // the only place that combination is exercised, which makes it the guard
  // against a screen that only overflows once the rail has taken its width.
  group('every destination beside the rail', () {
    const walkKeys = ['facility', 'beneficiaries', 'attendance', 'teachers', 'dashboard', 'sync', 'settings'];

    Future<void> walk(WidgetTester tester, ProviderContainer c) async {
      for (final key in walkKeys) {
        await tapRail(tester, ValueKey('nav-dest-$key'));
        expect(tester.takeException(), isNull, reason: 'opening $key raised');
        expect(depth(c), 2, reason: '$key must not grow the stack');
      }
      await tapRail(tester, home);
      expect(path(c), Routes.home);
      expect(depth(c), 1);
      expect(tester.takeException(), isNull);
    }

    testWidgets('every destination opens in a 1067 px pane without an exception', (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester, allModules: true);
      await pumpApp(tester, c);
      await walk(tester, c);

      // Teacher attendance exists only for ALP, so it is reached by moving the
      // module rather than by another tap on the same rail.
      c.read(currentModuleProvider.notifier).select(BmaModule.alp);
      await tester.pump();
      await tapRail(tester, const ValueKey('nav-dest-teacher-attendance'));
      expect(path(c), '/attendance/alp/teachers');
      expect(depth(c), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the same walk in Arabic at a 1.3x text scale', (tester) async {
      tabletLandscape(tester);
      // The harshest case for a pane narrowed by the rail: mirrored, and with
      // every label a third wider.
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await fixture(tester, allModules: true, lang: 'ar');
      await pumpApp(tester, c);
      await walk(tester, c);
    });
  });

  group('stack discipline', () {
    testWidgets('three rail taps leave the stack at depth 2 and back returns to Home',
        (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester);
      await pumpApp(tester, c);
      expect(path(c), Routes.home);
      expect(depth(c), 1);
      expect(c.read(appRouterProvider).canPop(), isFalse);

      // 1. First hop off Home is a push: depth 2.
      await tapRail(tester, beneficiaries);
      expect(path(c), '/registrations/mscc');
      expect(find.byType(RegistrationListScreen), findsOneWidget);
      expect(depth(c), 2);

      // 2. and 3. Rail-to-rail hops are replaces: the depth does not grow.
      await tapRail(tester, dashboard);
      expect(path(c), '/dashboard/mscc');
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(depth(c), 2);

      await tapRail(tester, settings);
      expect(path(c), Routes.settings);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(depth(c), 2);

      // Android back means "back to Home", exactly as it does today.
      expect(c.read(appRouterProvider).canPop(), isTrue);
      await systemBack(tester);
      await settle(tester);
      expect(path(c), Routes.home);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(c.read(appRouterProvider).canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping Home pops instead of pushing, and tapping the current place is a no-op',
        (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester);
      await pumpApp(tester, c);

      await tapRail(tester, beneficiaries);
      expect(depth(c), 2);
      await tapRail(tester, beneficiaries);
      expect(depth(c), 2, reason: 'already there: nothing happens');
      expect(path(c), '/registrations/mscc');

      await tapRail(tester, home);
      expect(path(c), Routes.home);
      expect(depth(c), 1);
      expect(c.read(appRouterProvider).canPop(), isFalse);

      // Home from Home does nothing rather than pushing a second Home.
      await tapRail(tester, home);
      expect(path(c), Routes.home);
      expect(depth(c), 1);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // THE CASE THE ORIGINAL THREE NEVER REACHED. Every assertion above only
    // ever taps the rail, and no rail destination pushes — so the stack never
    // got deeper than 2 and both bugs below stayed invisible. Six of the app's
    // screens push a page of their own ("Register new", a child profile below
    // `expanded`, a sync queue item, a teacher form), and from there the old
    // `canPop() ? pop() : go()` landed on the MIDDLE route and the old
    // `replace` swapped that middle route while the stale destination stayed
    // underneath forever.
    testWidgets('rail Home returns to Home from a three-deep stack, not to the middle route',
        (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester);
      await pumpApp(tester, c);

      await tapRail(tester, beneficiaries);
      expect(depth(c), 2);
      // The beneficiaries pane pushes the registration wizard.
      await tester.tap(find.byKey(const ValueKey('reg-add')));
      await settle(tester);
      expect(path(c), '/registrations/mscc/new');
      expect(depth(c), 3);

      await tapRail(tester, home);
      // Used to land on /registrations/mscc at depth 2 with HomeShell unmounted,
      // so the user had to tap Home twice.
      expect(path(c), Routes.home);
      expect(depth(c), 1);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(c.read(appRouterProvider).canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a rail hop after a drill-down does not leave the old destination underneath',
        (tester) async {
      // 1040x800: rail collapsed (72), body 967 px — `medium`, so there is no
      // master-detail and the list pushes instead of selecting in place. This
      // is the 1000-1072 band the finding names, and 1280x800 at density 1.25.
      freeformWindow(tester, 1040, 800);
      final c = await fixture(tester);
      await pumpApp(tester, c);
      expect(tester.getRect(find.byType(NavigationRail)).width, railCollapsedWidth);

      await tapRail(tester, beneficiaries);
      expect(depth(c), 2);
      await tester.tap(find.byKey(const ValueKey('reg-add')));
      await settle(tester);
      expect(depth(c), 3);

      await tapRail(tester, dashboard);
      expect(path(c), '/dashboard/mscc');
      // Used to stay at depth 3: the wizard was replaced but the beneficiaries
      // entry stayed under it, and every further drill-down added another.
      expect(depth(c), 2);

      // And the documented contract holds: back is ONE step, to Home.
      await systemBack(tester);
      await settle(tester);
      expect(path(c), Routes.home);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(c.read(appRouterProvider).canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping the destination you drilled down FROM just unwinds to it', (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester);
      await pumpApp(tester, c);

      await tapRail(tester, beneficiaries);
      await tester.tap(find.byKey(const ValueKey('reg-add')));
      await settle(tester);
      expect(depth(c), 3);

      await tapRail(tester, beneficiaries);
      expect(path(c), '/registrations/mscc');
      expect(depth(c), 2, reason: 'unwound to it, not re-pushed on top of it');
      expect(find.byType(RegistrationListScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the rail is not rebuilt into the page: the page keeps its state across a hop',
        (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester);
      await pumpApp(tester, c);
      final railElement = find.byType(NavigationRail).evaluate().isEmpty
          ? null
          : find.byType(NavigationRail).evaluate().first;
      expect(railElement, isNotNull);

      await tapRail(tester, beneficiaries);
      // Same Element: the rail was not torn down and rebuilt by the page
      // transition, which is the entire point of installing it above the
      // Navigator.
      expect(find.byType(NavigationRail).evaluate().first, same(railElement));
      expect(tester.takeException(), isNull);
    });
  });

  // The rail is installed ABOVE the Navigator, so the app's only Overlay
  // belongs to the page and starts AFTER the rail and its divider
  // (Offset(213,0), 1067x800 here). An anchored `showMenu` cannot reach back
  // over the rail and cannot even be told to try: `_PopupMenuRouteLayout`
  // clamps the menu 8 px inside the overlay, which put the first item at
  // Rect(221,56) in English however the anchor was expressed. The switcher
  // therefore asks in a dialog — the same modality `AppLayout.dialogPickers`
  // already gives every other picker from `medium` up.
  group('the programme switcher', () {
    const menu = ValueKey('nav-module-menu');
    const optionAlp = ValueKey('nav-module-option-alp');

    testWidgets('opens a chooser inside the content area and switches programme', (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester, allModules: true);
      await pumpApp(tester, c);
      expect(c.read(currentModuleProvider), BmaModule.mscc);

      await tester.tap(find.byKey(moduleSwitch));
      await tester.pumpAndSettle();
      expect(find.byKey(menu), findsOneWidget);
      // Whatever the chooser is, it has to be ON SCREEN and clear of the rail
      // rather than positioned in a coordinate space nothing renders in.
      final option = tester.getRect(find.byKey(optionAlp));
      expect(option.left, greaterThanOrEqualTo(railExtendedWidth));
      expect(option.right, lessThanOrEqualTo(1280));
      expect(option.top, greaterThanOrEqualTo(0));
      expect(option.bottom, lessThanOrEqualTo(800));

      await tester.tap(find.byKey(optionAlp));
      await tester.pumpAndSettle();
      expect(find.byKey(menu), findsNothing);
      expect(c.read(currentModuleProvider), BmaModule.alp);
      await tapRail(tester, beneficiaries);
      expect(path(c), '/registrations/alp');
      expect(tester.takeException(), isNull);
    });

    testWidgets('mirrors under ar and raises nothing (the anchored menu overflowed here)',
        (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester, allModules: true, lang: 'ar');
      await pumpApp(tester, c);

      await tester.tap(find.byKey(moduleSwitch));
      await tester.pumpAndSettle();
      expect(find.byKey(menu), findsOneWidget);
      final option = tester.getRect(find.byKey(optionAlp));
      // The rail is on the trailing side, so the chooser is clear of it on the
      // other one.
      expect(option.right, lessThanOrEqualTo(1280 - railExtendedWidth));
      expect(option.left, greaterThanOrEqualTo(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('Arabic', () {
    testWidgets('THE MIRROR ASSERTION: the rail is on the trailing side under ar', (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester, lang: 'ar');
      await pumpApp(tester, c);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(Directionality.of(tester.element(find.byType(NavigationRail))), TextDirection.rtl);
      // A takeException()-is-null assertion passes happily on a rail rendered
      // on the wrong side. This does not.
      final left = tester.getTopLeft(find.byType(NavigationRail)).dx;
      expect(left, greaterThan(1280 / 2));
      expect(left, 1280 - railExtendedWidth);
      expect(tester.takeException(), isNull);
    });

    testWidgets('navigation works the same way in Arabic', (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester, lang: 'ar');
      await pumpApp(tester, c);

      await tapRail(tester, beneficiaries);
      expect(path(c), '/registrations/mscc');
      expect(depth(c), 2);
      await tapRail(tester, home);
      expect(path(c), Routes.home);
      expect(tester.takeException(), isNull);
    });
  });

  group('unsaved work', () {
    testWidgets('a rail tap over a dirty form asks first and stays put on cancel', (tester) async {
      tabletLandscape(tester);
      final c = await fixture(tester);
      await pumpApp(tester, c);
      await tapRail(tester, beneficiaries);
      expect(path(c), '/registrations/mscc');

      c.read(unsavedWorkProvider.notifier).state = 'Leave this form?';
      await tester.pump();

      await tester.tap(find.byKey(dashboard));
      await settle(tester);
      expect(find.text('Leave this form?'), findsOneWidget,
          reason: 'push/replace do NOT trigger PopScope, so this guard is the only one');
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(path(c), '/registrations/mscc', reason: 'cancel must not navigate');

      await tester.tap(find.byKey(dashboard));
      await settle(tester);
      await tester.tap(find.text('Confirm'));
      await settle(tester);
      expect(path(c), '/dashboard/mscc');
      expect(depth(c), 2);
      expect(tester.takeException(), isNull);
    });

    test('UnsavedWorkWatch publishes on a real edit and clears on save', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const schema = EntitySchema(
        key: 'test.thing',
        module: 'mscc',
        label: 'Thing',
        kind: 'service',
        fields: [
          FieldSpec(name: 'name', label: 'Name', type: 'text'),
          FieldSpec(name: 'note', label: 'Note', type: 'text'),
        ],
        sections: [
          FormSection(key: 'main', label: 'Main', fields: ['name', 'note']),
        ],
      );
      final controller = SchemaFormController(schema: schema, initial: {'name': 'Amal'});
      final watch = UnsavedWorkWatch(
        container: container,
        controller: controller,
        message: 'Leave this form?',
      );
      addTearDown(watch.dispose);

      expect(container.read(unsavedWorkProvider), isNull);

      // Validation notifies without changing a value: still clean.
      controller.validate();
      expect(container.read(unsavedWorkProvider), isNull);
      // Setting a field to what it already holds is not an edit.
      controller.setValue('name', 'Amal');
      expect(container.read(unsavedWorkProvider), isNull);

      controller.setValue('note', 'Called the caregiver');
      expect(container.read(unsavedWorkProvider), 'Leave this form?');
      expect(watch.isDirty, isTrue);

      watch.clear();
      expect(container.read(unsavedWorkProvider), isNull);
      expect(watch.isDirty, isFalse);
      // The saved values are the new baseline.
      controller.setValue('note', 'Called the caregiver');
      expect(container.read(unsavedWorkProvider), isNull);
      controller.setValue('note', 'Called twice');
      expect(container.read(unsavedWorkProvider), 'Leave this form?');
    });

    test('UnsavedWorkWatch clears when the form goes away', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const schema = EntitySchema(
        key: 'test.thing',
        module: 'mscc',
        label: 'Thing',
        kind: 'service',
        fields: [FieldSpec(name: 'name', label: 'Name', type: 'text')],
        sections: [FormSection(key: 'main', label: 'Main', fields: ['name'])],
      );
      final controller = SchemaFormController(schema: schema);
      final watch = UnsavedWorkWatch(
        container: container,
        controller: controller,
        message: 'Leave this form?',
      );
      controller.setValue('name', 'Omar');
      expect(container.read(unsavedWorkProvider), 'Leave this form?');

      watch.dispose();
      // Deferred by one microtask so the write never lands during the frame
      // that is disposing the element tree.
      await Future<void>.delayed(Duration.zero);
      expect(container.read(unsavedWorkProvider), isNull);
      // The listener is gone: a late notification cannot resurrect the flag.
      controller.setValue('name', 'Nour');
      expect(container.read(unsavedWorkProvider), isNull);
    });
  });
}
