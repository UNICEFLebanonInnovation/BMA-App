// LANE: forms-screens. Covers the five screens this lane converts — the
// registration wizard, the service form, the teacher form, the login card and
// the server-setup card — at 1280x800 landscape, 800x1280 portrait and
// 412x915 phone, plus the Arabic 1.3x matrix.
//
// The three form screens run against a REAL in-memory SQLite database seeded
// with the REAL bootstrap fixture, so the schemas under test are the ones that
// ship: mscc.registration (identity 26 / caregivers 44 / labour 6 + Review),
// mscc.teacher (39 fields in one section) and mscc.health_nutrition (29).
// A synthetic schema would prove nothing about the packer's behaviour on the
// forms staff actually fill in.
import 'dart:convert';
import 'dart:io';

import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/config/settings_controller.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/db/entity_dao.dart';
import 'package:bma_app/core/layout/breakpoints.dart';
import 'package:bma_app/core/sync/connectivity_service.dart';
import 'package:bma_app/core/sync/sync_engine.dart';
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:bma_app/core/widgets/bma_logo.dart';
import 'package:bma_app/features/auth/login_screen.dart';
import 'package:bma_app/features/registrations/registration_wizard_screen.dart';
import 'package:bma_app/features/services/service_form_screen.dart';
import 'package:bma_app/features/setup/server_setup_screen.dart';
import 'package:bma_app/features/teachers/teacher_form_screen.dart';
import 'package:bma_app/features/tips/tips_controller.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fakes.dart';
import '../support/viewport.dart';

const stepRail = ValueKey('wizard-step-rail');
const wizardNext = ValueKey('wizard-next');
const serviceSave = ValueKey('service-save');
const serviceCancel = ValueKey('service-cancel');
const teacherSave = ValueKey('teacher-save');
const teacherCancel = ValueKey('teacher-cancel');

class Fixture {
  Fixture(this.container, this.parentUuid);

  final ProviderContainer container;
  final String parentUuid;
}

/// Seeds the real bootstrap payload (schemas, reference lists, choices) into an
/// in-memory database and creates one registration to hang a service form off.
Future<Fixture> fixture(WidgetTester tester, {String lang = 'en'}) async {
  final db = await tester.runAsync(AppDatabase.openInMemory);
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(db!),
    authControllerProvider.overrideWith(() => FakeAuthController(signedIn())),
    connectivityProvider.overrideWith((ref) => Stream.value(true)),
    tipsControllerProvider.overrideWith(() => TipsController(TipsState(seen: {TipsState.seenKey(42)}), null)),
    settingsControllerProvider.overrideWith(() => SettingsController(
          AppSettings(serverUrl: 'https://x.invalid', locale: Locale(lang), serverConfigured: true),
          null,
        )),
  ]);
  addTearDown(container.dispose);
  addTearDown(() => db.close());

  final bootstrap = jsonDecode(File('test/screenshots/fixtures/bootstrap.json').readAsStringSync()) as Map;
  var parentUuid = '';
  await tester.runAsync(() async {
    await container.read(syncEngineProvider.notifier).storeBootstrap(Map<String, dynamic>.from(bootstrap));
    final record = await container.read(entityDaoProvider).createLocal(
      entity: Entities.msccRegistration,
      data: {
        'center_label': 'NFE Centre',
        'registration_date': '2026-09-01',
        'child': {'first_name': 'Amal', 'last_name': 'Sayed', 'mother_fullname': 'Fatima Nasr'},
      },
    );
    parentUuid = record.uuid;
  });
  return Fixture(container, parentUuid);
}

/// Real SQLite work needs wall-clock time; pumpAndSettle alone starves it.
Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Mirrors lib/app.dart: the same density builder, so the tablet type scale is
/// under test here and not only in production.
Future<void> pumpScreen(
  WidgetTester tester,
  Fixture fx,
  Widget screen, {
  String lang = 'en',
  double scale = 1.0,
}) async {
  await tester.pumpWidget(UncontrolledProviderScope(
    container: fx.container,
    child: MaterialApp(
      locale: Locale(lang),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Theme(
          data: AppTheme.cached(
            tablet: MediaQuery.sizeOf(context).shortestSide >= Breakpoints.tabletShortestSide,
          ),
          child: child!,
        ),
      ),
      home: screen,
    ),
  ));
  await settle(tester);
}

final _fields = find.byWidgetPredicate(
    (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('field-'));

/// How many form fields share a top edge — i.e. the number of columns the
/// packer actually rendered, measured rather than recomputed from the tokens.
int renderedColumns(WidgetTester tester) {
  final tops = <int, int>{};
  for (final element in _fields.evaluate()) {
    final box = element.renderObject;
    if (box is! RenderBox || !box.hasSize) continue;
    final dy = box.localToGlobal(Offset.zero).dy.round();
    tops[dy] = (tops[dy] ?? 0) + 1;
  }
  return tops.values.fold(0, (m, v) => v > m ? v : m);
}

/// The maxWidth of the ConstrainedBox the login / setup card sits in.
double cardCap(WidgetTester tester) {
  final caps = tester
      .widgetList<ConstrainedBox>(find.ancestor(of: find.byType(Card), matching: find.byType(ConstrainedBox)))
      .map((b) => b.constraints.maxWidth)
      .where((w) => w.isFinite)
      .toList();
  return caps.reduce((a, b) => a < b ? a : b);
}

/// The brand lockup's box. It is deliberately NOT text-scaled: it is what
/// tells the worker they opened the right app.
double logoWidth(WidgetTester tester) =>
    tester.getSize(find.descendant(of: find.byType(BmaLogo), matching: find.byType(Image))).width;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  // -------------------------------------------------------------- the wizard
  group('registration wizard', () {
    testWidgets('1280x800: a 240 px step rail replaces the 1/4 line', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, const RegistrationWizardScreen(module: BmaModule.mscc));

      expect(find.byKey(stepRail), findsOneWidget);
      expect(tester.getSize(find.byKey(stepRail)).width, 240);
      // identity / caregivers / labour + Review.
      expect(find.byKey(const ValueKey('wizard-step-identity')), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard-step-caregivers')), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard-step-labour')), findsOneWidget);
      expect(find.byKey(const ValueKey('wizard-step-review')), findsOneWidget);
      // The rail carries the position, so the numeric line is gone.
      expect(find.text('1/4'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1280x800: the rail is orientation and a way BACK, never a way forward', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, const RegistrationWizardScreen(module: BmaModule.mscc));

      // Nothing ahead of the current step is tappable: _next() stays the only
      // path forward, so the step-0 duplicate check cannot be jumped over.
      for (final key in ['wizard-step-caregivers', 'wizard-step-labour', 'wizard-step-review']) {
        expect(tester.widget<ListTile>(find.byKey(ValueKey(key))).onTap, isNull, reason: key);
      }
      // The current step is not a tap target either.
      expect(tester.widget<ListTile>(find.byKey(const ValueKey('wizard-step-identity'))).onTap, isNull);
      // Tapping ahead does nothing: still the identity section.
      await tester.tap(find.byKey(const ValueKey('wizard-step-labour')), warnIfMissed: false);
      await tester.pump();
      expect(find.byKey(const ValueKey('field-child_first_name')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('1280x800: the footer is trailing-aligned inside the cap, not at the window corner',
        (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, const RegistrationWizardScreen(module: BmaModule.mscc));

      // The Spacer is the compact-only mechanism; at medium+ the row is
      // MainAxisAlignment.end with a 12 px gap.
      expect(find.byType(Spacer), findsNothing);
      final next = tester.getRect(find.byKey(wizardNext));
      // Inside the form area (right of the 240 px rail) and trailing-aligned.
      expect(next.left, greaterThan(241));
      expect(next.right, greaterThan(1100));
      expect(next.right, lessThanOrEqualTo(1280));
    });

    testWidgets('1280x800: the identity section packs two columns', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, const RegistrationWizardScreen(module: BmaModule.mscc));

      // 1280 - 240 rail - 1 divider = 1039, capped at formMaxWidth 1040, less
      // the screen's own 16 px padding on each side.
      expect(renderedColumns(tester), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280: no rail, the 1/4 line stays, the form packs two columns', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, const RegistrationWizardScreen(module: BmaModule.mscc));

      expect(find.byKey(stepRail), findsNothing);
      expect(find.text('1/4'), findsOneWidget);
      expect(find.byType(Spacer), findsNothing);
      expect(renderedColumns(tester), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('412x915: today\'s phone tree — one column, the Spacer, the 1/4 line', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, const RegistrationWizardScreen(module: BmaModule.mscc));

      expect(find.byKey(stepRail), findsNothing);
      expect(find.text('1/4'), findsOneWidget);
      // The phone footer keeps the Spacer verbatim.
      expect(find.byType(Spacer), findsOneWidget);
      expect(renderedColumns(tester), 1);
      // The cap must not add a second inset: a field still spans 16..396.
      final first = tester.getRect(find.byKey(const ValueKey('field-child_first_name')));
      expect(first.left, 16);
      expect(first.width, 412 - 32);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic mirrors the rail to the RIGHT of the window', (tester) async {
      // takeException() is null on a rail that rendered on the wrong side, so
      // this has to be measured.
      tabletLandscape(tester);
      final fx = await fixture(tester, lang: 'ar');
      await pumpScreen(tester, fx, const RegistrationWizardScreen(module: BmaModule.mscc), lang: 'ar');

      final rail = tester.getRect(find.byKey(stepRail));
      expect(rail.right, 1280);
      expect(rail.left, 1040);
      // ...and the form sits to its start side, i.e. the left half.
      expect(tester.getRect(find.byKey(wizardNext)).left, lessThan(1040));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic at 1.3x raises nothing at any of the three sizes', (tester) async {
      for (final size in [tabletLandscape, tabletPortrait, phone]) {
        size(tester);
        final fx = await fixture(tester, lang: 'ar');
        await pumpScreen(tester, fx, const RegistrationWizardScreen(module: BmaModule.mscc),
            lang: 'ar', scale: 1.3);
        expect(find.byKey(wizardNext), findsOneWidget);
        expect(tester.takeException(), isNull);
        // 1.3x spends a column: the safety valve in formColumns.
        expect(renderedColumns(tester), 1);
      }
    });
  });

  // --------------------------------------------------------- the service form
  group('service form (mscc.health_nutrition, 29 fields)', () {
    Widget screen(Fixture fx) => ServiceFormScreen(parentUuid: fx.parentUuid, entity: 'mscc.health_nutrition');

    testWidgets('1280x800: capped, trailing-aligned footer, three columns', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, screen(fx));

      expect(find.byKey(serviceSave), findsOneWidget);
      expect(find.byKey(serviceCancel), findsOneWidget);
      expect(find.byType(Spacer), findsNothing);
      final save = tester.getRect(find.byKey(serviceSave));
      final cancel = tester.getRect(find.byKey(serviceCancel));
      // Both buttons inside the 1040 cap centred in 1280 → 120..1160.
      expect(cancel.left, greaterThan(100));
      expect(save.right, lessThan(1180));
      // The two-handed reach is gone: ~12 px, not ~1200.
      expect(save.left - cancel.right, lessThan(40));
      expect(renderedColumns(tester), 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280: two columns, footer still trailing-aligned', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, screen(fx));

      expect(find.byType(Spacer), findsNothing);
      expect(renderedColumns(tester), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('412x915: one column and the Spacer, unchanged', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, screen(fx));

      expect(find.byType(Spacer), findsOneWidget);
      expect(renderedColumns(tester), 1);
      // The white parent-label band is still full-bleed on the phone, and its
      // text is still on the start edge rather than centred by the cap.
      expect(tester.getSize(find.byType(Container).first).width, 412);
      expect(tester.getTopLeft(find.text('Amal Sayed')).dx, 16);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic at 1.3x raises nothing at any of the three sizes', (tester) async {
      for (final size in [tabletLandscape, tabletPortrait, phone]) {
        size(tester);
        final fx = await fixture(tester, lang: 'ar');
        await pumpScreen(tester, fx, screen(fx), lang: 'ar', scale: 1.3);
        expect(find.byKey(serviceSave), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  // --------------------------------------------------------- the teacher form
  group('teacher form (mscc.teacher, 39 fields in one section)', () {
    testWidgets('1280x800: three columns and a trailing-aligned footer', (tester) async {
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, const TeacherFormScreen(module: BmaModule.mscc));

      expect(find.byKey(teacherSave), findsOneWidget);
      expect(find.byKey(teacherCancel), findsOneWidget);
      expect(find.byType(Spacer), findsNothing);
      expect(renderedColumns(tester), 3);
      final save = tester.getRect(find.byKey(teacherSave));
      final cancel = tester.getRect(find.byKey(teacherCancel));
      expect(save.left - cancel.right, lessThan(40));
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280: two columns', (tester) async {
      tabletPortrait(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, const TeacherFormScreen(module: BmaModule.mscc));

      expect(renderedColumns(tester), 2);
      expect(find.byType(Spacer), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('412x915: one column, the Spacer, and the scroll body still 16 px from the edge',
        (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, const TeacherFormScreen(module: BmaModule.mscc));

      expect(renderedColumns(tester), 1);
      expect(find.byType(Spacer), findsOneWidget);
      // AdaptiveBody(gutter: false) must not add a second inset on the phone.
      final first = tester.getRect(find.byKey(const ValueKey('field-round')));
      expect(first.left, 16);
      expect(first.width, 412 - 32);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic at 1.3x raises nothing at any of the three sizes', (tester) async {
      for (final size in [tabletLandscape, tabletPortrait, phone]) {
        size(tester);
        final fx = await fixture(tester, lang: 'ar');
        await pumpScreen(tester, fx, const TeacherFormScreen(module: BmaModule.mscc), lang: 'ar', scale: 1.3);
        expect(find.byKey(teacherSave), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  // ------------------------------------------------------- login + setup cards
  group('login card', () {
    testWidgets('412x915 keeps the 440 cap and the phone lockup', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, const LoginScreen());

      expect(cardCap(tester), 440);
      expect(logoWidth(tester), 200, reason: 'the phone lockup');
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280 and 1280x800 raise the cap to 520 and the lockup to 260', (tester) async {
      for (final size in [tabletPortrait, tabletLandscape]) {
        size(tester);
        final fx = await fixture(tester);
        await pumpScreen(tester, fx, const LoginScreen());

        expect(cardCap(tester), 520);
        expect(logoWidth(tester), 260, reason: 'the tablet lockup');
        // The card stays centred, not stretched across the tablet.
        expect(tester.getSize(find.byType(Card)).width, 520);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the three TextFormFields keep their positional order', (tester) async {
      // screenshot_generator_test.dart addresses them with .at(1) / .at(2).
      tabletLandscape(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, const LoginScreen());

      expect(find.byType(TextFormField), findsNWidgets(3));
      final tops = [
        for (var i = 0; i < 3; i++) tester.getTopLeft(find.byType(TextFormField).at(i)).dy,
      ];
      expect(tops[0] < tops[1] && tops[1] < tops[2], isTrue);
    });

    testWidgets('Arabic at 1.3x raises nothing', (tester) async {
      for (final size in [tabletLandscape, phone]) {
        size(tester);
        final fx = await fixture(tester, lang: 'ar');
        await pumpScreen(tester, fx, const LoginScreen(), lang: 'ar', scale: 1.3);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('server setup card', () {
    const keys = ['setup-url', 'setup-test', 'setup-continue', 'setup-language'];

    testWidgets('412x915 keeps the 440 cap, the phone lockup and every protected key', (tester) async {
      phone(tester);
      final fx = await fixture(tester);
      await pumpScreen(tester, fx, const ServerSetupScreen());

      expect(cardCap(tester), 440);
      expect(tester.widget<Icon>(find.byIcon(Icons.settings_ethernet)).size, 32);
      expect(logoWidth(tester), 200);
      for (final k in keys) {
        expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('800x1280 and 1280x800: 520 cap, bigger lockup, still ONE centred card', (tester) async {
      for (final size in [tabletPortrait, tabletLandscape]) {
        size(tester);
        final fx = await fixture(tester);
        await pumpScreen(tester, fx, const ServerSetupScreen());

        expect(cardCap(tester), 520);
        expect(tester.widget<Icon>(find.byIcon(Icons.settings_ethernet)).size, 40);
        expect(logoWidth(tester), 260);
        expect(find.byType(Card), findsOneWidget);
        for (final k in keys) {
          expect(find.byKey(ValueKey(k)), findsOneWidget, reason: k);
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('412x700 at 1.3x Arabic still fits — the server_setup_test case', (tester) async {
      tester.view.physicalSize = const Size(412 * 2.625, 700 * 2.625);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final fx = await fixture(tester, lang: 'ar');
      await pumpScreen(tester, fx, const ServerSetupScreen(), lang: 'ar', scale: 1.3);

      expect(cardCap(tester), 440);
      expect(tester.widget<Icon>(find.byIcon(Icons.settings_ethernet)).size, 32);
      expect(logoWidth(tester), 200);
      expect(tester.takeException(), isNull);
    });
  });
}
