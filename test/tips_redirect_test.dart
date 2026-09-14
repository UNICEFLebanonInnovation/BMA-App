// Gating tests against the real BmaApp and the real appRouterProvider. The
// fakes keep every screen off SQLite and the network.
import 'package:bma_app/app.dart';
import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/features/auth/login_screen.dart';
import 'package:bma_app/features/home/home_shell.dart';
import 'package:bma_app/features/settings/settings_screen.dart';
import 'package:bma_app/features/sync/sync_center_screen.dart';
import 'package:bma_app/features/tips/tips_controller.dart';
import 'package:bma_app/features/tips/tips_wizard_screen.dart';
import 'package:bma_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

const _next = ValueKey('tips-next');
const _skip = ValueKey('tips-skip');
const _homeTip = ValueKey('tip-home.sync');

ProviderContainer _container({AuthState? auth, TipsState tips = const TipsState()}) {
  final c = ProviderContainer(overrides: tipsOverrides(auth: auth ?? signedIn(id: 42), tips: tips));
  addTearDown(c.dispose);
  return c;
}

Future<void> _pumpApp(WidgetTester tester, ProviderContainer c) async {
  tester.view.physicalSize = const Size(412 * 2.625, 915 * 2.625);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const BmaApp()));
  await tester.pumpAndSettle();
}

GoRouter _router(ProviderContainer c) => c.read(appRouterProvider);

/// Taps Next until the last page, then Done.
Future<void> _walkToDone(WidgetTester tester, {int pages = 7}) async {
  for (var i = 1; i < pages; i++) {
    await tester.tap(find.byKey(_next));
    await tester.pumpAndSettle();
  }
  expect(find.text('Done'), findsOneWidget);
  await tester.tap(find.byKey(_next));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('(1) unseen signed-in account is gated to the wizard; Skip lands on Home with its tip',
      (tester) async {
    final c = _container();
    await _pumpApp(tester, c);

    expect(find.byType(TipsWizardScreen), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);
    expect(_router(c).routerDelegate.currentConfiguration.uri.path, Routes.tips);

    await tester.tap(find.byKey(_skip));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(TipsWizardScreen), findsNothing);
    expect(_router(c).routerDelegate.currentConfiguration.uri.path, Routes.home);
    expect(c.read(tipsControllerProvider).hasSeen(42), isTrue);

    expect(find.byKey(_homeTip), findsOneWidget);
    await tester.ensureVisible(find.text('Got it'));
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.byKey(_homeTip), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(c.read(tipsControllerProvider).isDismissed(42, 'home.sync'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('(2) a seen account can push /tips without being bounced and pop back', (tester) async {
    final c = _container();
    await _pumpApp(tester, c);
    await tester.tap(find.byKey(_skip));
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);

    _router(c).push(Routes.tips);
    await tester.pumpAndSettle();
    expect(find.byType(TipsWizardScreen), findsOneWidget);
    expect(find.byKey(_skip), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.takeException(), isNull);

    _router(c).pop();
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(TipsWizardScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('(3) deep links are gated while the tips are pending', (tester) async {
    final c = _container();
    await _pumpApp(tester, c);
    expect(find.byType(TipsWizardScreen), findsOneWidget);

    _router(c).go(Routes.sync);
    await tester.pumpAndSettle();
    expect(find.byType(TipsWizardScreen), findsOneWidget);
    expect(find.byType(SyncCenterScreen), findsNothing);
    expect(_router(c).routerDelegate.currentConfiguration.uri.path, Routes.tips);
    expect(tester.takeException(), isNull);
  });

  testWidgets('(4) a pre-seeded account goes straight to Home; the help icon re-opens the wizard',
      (tester) async {
    final c = _container(tips: TipsState(seen: {TipsState.seenKey(42)}));
    await _pumpApp(tester, c);

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(TipsWizardScreen), findsNothing);
    expect(find.byKey(_homeTip), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-help')));
    await tester.pumpAndSettle();
    expect(find.byType(TipsWizardScreen), findsOneWidget);
    expect(find.byKey(_skip), findsNothing);

    await _walkToDone(tester);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(TipsWizardScreen), findsNothing);
    expect(c.read(tipsControllerProvider).seen, {TipsState.seenKey(42)});
    expect(tester.takeException(), isNull);
  });

  testWidgets('(5) a signed-out device shows the login screen and never the wizard', (tester) async {
    final c = _container(auth: AuthState.signedOut);
    await _pumpApp(tester, c);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(TipsWizardScreen), findsNothing);
    expect(find.byType(HomeShell), findsNothing);
    expect(c.read(tipsPendingProvider), isFalse);

    _router(c).go(Routes.tips);
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget, reason: 'the auth branch wins over /tips');
    expect(find.byType(TipsWizardScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('(6) Settings "Show tips again" re-opens the wizard, keeps the seen flag and pops back',
      (tester) async {
    final c = _container(
      tips: TipsState(seen: {TipsState.seenKey(42)}, dismissed: const {'42:home.sync', '7:home.sync'}),
    );
    await _pumpApp(tester, c);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(_homeTip), findsNothing);

    _router(c).push(Routes.settings);
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('settings-show-tips')));
    await tester.tap(find.byKey(const ValueKey('settings-show-tips')));
    await tester.pumpAndSettle();
    expect(find.byType(TipsWizardScreen), findsOneWidget);
    expect(find.byKey(_skip), findsNothing);
    final state = c.read(tipsControllerProvider);
    expect(state.hasSeen(42), isTrue);
    expect(state.isDismissed(42, 'home.sync'), isFalse, reason: 'this user\'s tips are restored');
    expect(state.isDismissed(7, 'home.sync'), isTrue, reason: 'other users are untouched');

    await _walkToDone(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(TipsWizardScreen), findsNothing);
    expect(c.read(tipsControllerProvider).hasSeen(42), isTrue);

    _router(c).pop();
    await tester.pumpAndSettle();
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(_homeTip), findsOneWidget, reason: 'the restored Home tip is back');
    expect(tester.takeException(), isNull);
  });
}
