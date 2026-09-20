import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:bma_app/features/tips/tip_card.dart';
import 'package:bma_app/features/tips/tips_controller.dart';
import 'package:bma_app/features/tips/tips_wizard_screen.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:bma_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

const _next = ValueKey('tips-next');
const _back = ValueKey('tips-back');
const _skip = ValueKey('tips-skip');
const _wide = Key('tips-page-wide');

/// Router of the last [wizardApp] pumped; lets tests push/pop like Home and Settings do.
late GoRouter router;

Widget wizardApp(ProviderContainer c, {String lang = 'en', String initial = Routes.tips, TextScaler? textScaler}) {
  router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: Routes.tips, builder: (_, _) => const TipsWizardScreen()),
      GoRoute(path: Routes.home, builder: (_, _) => const Scaffold(body: Text('home-stub'))),
    ],
  );
  addTearDown(router.dispose);
  return UncontrolledProviderScope(
    container: c,
    child: MaterialApp.router(
      locale: Locale(lang),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      // Applied below the View's MediaQuery so the window size is kept and only the scale changes.
      builder: textScaler == null
          ? null
          : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
    ),
  );
}

ProviderContainer container({AuthState? auth, TipsState tips = const TipsState(), String lang = 'en'}) {
  final c = ProviderContainer(overrides: tipsOverrides(auth: auth ?? signedIn(id: 42), tips: tips, lang: lang));
  addTearDown(c.dispose);
  return c;
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 2.625, 915 * 2.625);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

void tablet(WidgetTester tester) {
  tester.view.physicalSize = const Size(800 * 2.0, 1280 * 2.0);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
}

Future<void> tapKey(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  group('TipsWizardScreen', () {
    testWidgets('(a) first run in English: step text, welcome header, next/back, skip', (tester) async {
      phone(tester);
      final c = container();
      await tester.pumpWidget(wizardApp(c));
      await tester.pumpAndSettle();

      expect(find.byType(TipsWizardScreen), findsOneWidget);
      expect(find.text('Getting started'), findsOneWidget);
      expect(find.text('Step 1 of 7'), findsOneWidget);
      expect(find.text('Welcome, Rima Haddad'), findsOneWidget);
      expect(find.text('Partner NGO · NFE Centre'), findsOneWidget);
      expect(find.text('Works without internet'), findsOneWidget);
      expect(find.byKey(_skip), findsOneWidget);
      expect(find.byKey(_back), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tapKey(tester, _next);
      expect(find.text('Step 2 of 7'), findsOneWidget);
      expect(find.text('Your data on this device'), findsOneWidget);
      expect(find.text('Reference data is on this device.'), findsOneWidget);
      expect(find.byKey(_back), findsOneWidget);

      await tapKey(tester, _back);
      expect(find.text('Step 1 of 7'), findsOneWidget);
      expect(find.byKey(_back), findsNothing);

      expect(c.read(tipsControllerProvider).hasSeen(42), isFalse);
      await tapKey(tester, _skip);
      expect(find.text('home-stub'), findsOneWidget);
      expect(find.byType(TipsWizardScreen), findsNothing);
      expect(c.read(tipsControllerProvider).hasSeen(42), isTrue);
      expect(c.read(tipsControllerProvider).hasSeen(7), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('(b) Done on the last page marks seen and goes home', (tester) async {
      phone(tester);
      final c = container();
      await tester.pumpWidget(wizardApp(c));
      await tester.pumpAndSettle();

      for (var i = 0; i < 6; i++) {
        expect(find.text('Next'), findsOneWidget);
        await tapKey(tester, _next);
      }
      expect(find.text('Step 7 of 7'), findsOneWidget);
      expect(find.text('Keep your data safe'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Next'), findsNothing);
      expect(find.text('Skip'), findsNothing);
      expect(find.byKey(_skip), findsNothing);
      expect(find.byIcon(Icons.check), findsOneWidget);

      await tapKey(tester, _next);
      expect(find.text('home-stub'), findsOneWidget);
      expect(c.read(tipsControllerProvider).hasSeen(42), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('(c) role gating: attendance-only account walks 5 pages without the register page',
        (tester) async {
      phone(tester);
      final c = container(auth: signedIn(modules: {BmaModule.mscc: caps(register: false, edit: false)}));
      await tester.pumpWidget(wizardApp(c));
      await tester.pumpAndSettle();

      expect(find.text('Step 1 of 5'), findsOneWidget);
      for (var i = 1; i <= 5; i++) {
        expect(find.text('Step $i of 5'), findsOneWidget);
        expect(find.text('Registering a child'), findsNothing);
        expect(find.text('Duplicates and conflicts'), findsNothing);
        if (i < 5) await tapKey(tester, _next);
      }
      expect(find.text('Done'), findsOneWidget);
      await tapKey(tester, _next);
      expect(find.text('home-stub'), findsOneWidget);
    });

    testWidgets('(d) system back: previous page, then a no-op on first-run page 1', (tester) async {
      phone(tester);
      final c = container();
      await tester.pumpWidget(wizardApp(c));
      await tester.pumpAndSettle();

      await tapKey(tester, _next);
      expect(find.text('Step 2 of 7'), findsOneWidget);

      await systemBack(tester);
      expect(find.text('Step 1 of 7'), findsOneWidget);
      expect(find.byType(TipsWizardScreen), findsOneWidget);

      await systemBack(tester);
      expect(find.byType(TipsWizardScreen), findsOneWidget);
      expect(find.text('Step 1 of 7'), findsOneWidget);
      expect(find.text('home-stub'), findsNothing);
      expect(c.read(tipsControllerProvider).hasSeen(42), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('(e) re-open mode: pushed wizard has no Skip, Done pops, back on page 1 pops', (tester) async {
      phone(tester);
      final c = container(tips: TipsState(seen: {TipsState.seenKey(42)}));
      await tester.pumpWidget(wizardApp(c, initial: Routes.home));
      await tester.pumpAndSettle();
      expect(find.text('home-stub'), findsOneWidget);

      router.push(Routes.tips);
      await tester.pumpAndSettle();
      expect(find.byType(TipsWizardScreen), findsOneWidget);
      expect(find.byKey(_skip), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);

      for (var i = 0; i < 6; i++) {
        await tapKey(tester, _next);
      }
      expect(find.text('Done'), findsOneWidget);
      await tapKey(tester, _next);
      expect(find.text('home-stub'), findsOneWidget);
      expect(find.byType(TipsWizardScreen), findsNothing);
      expect(c.read(tipsControllerProvider).seen, {TipsState.seenKey(42)});

      router.push(Routes.tips);
      await tester.pumpAndSettle();
      expect(find.byType(TipsWizardScreen), findsOneWidget);
      await tapKey(tester, _next);
      expect(find.text('Step 2 of 7'), findsOneWidget);
      await systemBack(tester);
      expect(find.text('Step 1 of 7'), findsOneWidget);
      await systemBack(tester);
      expect(find.byType(TipsWizardScreen), findsNothing);
      expect(find.text('home-stub'), findsOneWidget);
      expect(c.read(tipsControllerProvider).seen, {TipsState.seenKey(42)});
      expect(tester.takeException(), isNull);
    });

    testWidgets('(f) Arabic: RTL page view, localised step text and Next', (tester) async {
      phone(tester);
      final c = container(lang: 'ar');
      await tester.pumpWidget(wizardApp(c, lang: 'ar'));
      await tester.pumpAndSettle();

      expect(Directionality.of(tester.element(find.byType(PageView))), TextDirection.rtl);
      expect(find.text('دليل البدء'), findsOneWidget);
      expect(find.text('الخطوة 1 من 7'), findsOneWidget);
      expect(find.text('مرحباً، Rima Haddad'), findsOneWidget);
      expect(find.text('يعمل دون إنترنت'), findsOneWidget);
      expect(find.text('تخطي'), findsOneWidget);

      await tester.tap(find.text('التالي'));
      await tester.pumpAndSettle();
      expect(find.text('الخطوة 2 من 7'), findsOneWidget);
      expect(find.text('رجوع'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('(g) Arabic at text scale 1.3 never overflows on any page', (tester) async {
      phone(tester);
      final c = container(lang: 'ar');
      await tester.pumpWidget(wizardApp(c, lang: 'ar', textScaler: const TextScaler.linear(1.3)));
      await tester.pumpAndSettle();
      expect(MediaQuery.textScalerOf(tester.element(find.byType(PageView))).scale(10), closeTo(13, 0.01));
      expect(tester.takeException(), isNull);

      for (var i = 1; i <= 7; i++) {
        expect(find.text('الخطوة $i من 7'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'page $i overflowed');
        if (i < 7) await tapKey(tester, _next);
      }
      expect(find.text('تم'), findsOneWidget);
      await tapKey(tester, _next);
      expect(find.text('home-stub'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('(h) tablet uses the wide side-by-side layout inside a 720 px column', (tester) async {
      tablet(tester);
      final c = container();
      await tester.pumpWidget(wizardApp(c));
      await tester.pumpAndSettle();

      expect(find.byKey(_wide), findsOneWidget);
      final column = find.byWidgetPredicate((w) => w is ConstrainedBox && w.constraints.maxWidth == 720);
      expect(column, findsOneWidget);
      expect(tester.getSize(column).width, lessThanOrEqualTo(720));
      expect(tester.getSize(find.byType(PageView)).width, lessThanOrEqualTo(720));

      for (var i = 1; i <= 7; i++) {
        expect(find.text('Step $i of 7'), findsOneWidget);
        expect(find.byKey(_wide), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'page $i raised');
        if (i < 7) await tapKey(tester, _next);
      }
    });

    testWidgets('(h) phone keeps the stacked layout', (tester) async {
      phone(tester);
      final c = container();
      await tester.pumpWidget(wizardApp(c));
      await tester.pumpAndSettle();
      expect(find.byKey(_wide), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('(i) the step text is exposed to assistive technology', (tester) async {
      phone(tester);
      final handle = tester.ensureSemantics();
      final c = container();
      await tester.pumpWidget(wizardApp(c));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Step 1 of 7')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Works without internet')), findsOneWidget);
      handle.dispose();
    });
  });

  group('TipCard', () {
    Widget cardApp(List<Override> overrides) => ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: ListView(children: const [TipCard(id: 'x', text: 'hello')])),
          ),
        );

    testWidgets('(j) shows for the signed-in user and hides for that user only after Got it', (tester) async {
      final c = container();
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ListView(children: const [TipCard(id: 'x', text: 'hello')])),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tip-x')), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tip-x')), findsNothing);
      expect(find.text('hello'), findsNothing);
      final state = c.read(tipsControllerProvider);
      expect(state.isDismissed(42, 'x'), isTrue);
      expect(state.isDismissed(7, 'x'), isFalse);
      expect(state.hasSeen(42), isFalse, reason: 'Got it never marks the wizard as seen');

      await c.read(tipsControllerProvider.notifier).restoreTips(42);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tip-x')), findsOneWidget);
    });

    testWidgets('(j) renders nothing while signed out', (tester) async {
      await tester.pumpWidget(cardApp(tipsOverrides(auth: AuthState.signedOut)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tip-x')), findsNothing);
      expect(find.text('hello'), findsNothing);
      expect(find.text('Got it'), findsNothing);
      // A zero-size list child counts as offstage for the default finder.
      expect(find.byType(TipCard, skipOffstage: false), findsOneWidget);
      expect(find.byType(Card, skipOffstage: false), findsNothing);
    });

    testWidgets('(j) renders nothing when already dismissed for this user', (tester) async {
      await tester.pumpWidget(cardApp(
        tipsOverrides(auth: signedIn(), tips: const TipsState(dismissed: {'42:x'})),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tip-x')), findsNothing);
    });
  });
}
