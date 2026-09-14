import 'package:bma_app/app.dart';
import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/config/settings_controller.dart';
import 'package:bma_app/core/network/server_probe.dart';
import 'package:bma_app/features/auth/login_screen.dart';
import 'package:bma_app/features/home/home_shell.dart';
import 'package:bma_app/features/setup/server_setup_screen.dart';
import 'package:bma_app/features/tips/tips_controller.dart';
import 'package:bma_app/router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Signed out, so the router decides between /setup and /login.
AuthState get _signedOut => const AuthState(status: AuthStatus.signedOut, deviceId: 'd');

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(412 * 2.625, 915 * 2.625);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  required bool serverConfigured,
  ServerCheck probe = ServerCheck.ok,
  String lang = 'en',
}) async {
  final container = ProviderContainer(
    overrides: tipsOverrides(
      auth: _signedOut,
      lang: lang,
      serverConfigured: serverConfigured,
      probe: probe,
    ),
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const BmaApp()));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('AppSettings.serverConfigured', () {
    setUp(() => TestWidgetsFlutterBinding.ensureInitialized());

    test('a fresh install is not configured and falls back to the default URL', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = await SettingsController.load();
      final container = ProviderContainer(overrides: [settingsControllerProvider.overrideWith(() => controller)]);
      addTearDown(container.dispose);
      final settings = container.read(settingsControllerProvider);
      expect(settings.serverConfigured, isFalse);
      expect(settings.serverUrl, AppConfig.defaultServerUrl);
    });

    test('an install that already stored a URL is configured', () async {
      SharedPreferences.setMockInitialValues({'server_url': 'https://stored.example.org'});
      final controller = await SettingsController.load();
      final container = ProviderContainer(overrides: [settingsControllerProvider.overrideWith(() => controller)]);
      addTearDown(container.dispose);
      expect(container.read(settingsControllerProvider).serverConfigured, isTrue);
      expect(container.read(settingsControllerProvider).serverUrl, 'https://stored.example.org');
    });

    test('saving an address normalises it, marks the device configured and persists it', () async {
      SharedPreferences.setMockInitialValues({});
      final controller = await SettingsController.load();
      final container = ProviderContainer(overrides: [settingsControllerProvider.overrideWith(() => controller)]);
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.notifier).setServerUrl('  bma.example.org/  ');
      final settings = container.read(settingsControllerProvider);
      expect(settings.serverUrl, 'https://bma.example.org');
      expect(settings.serverConfigured, isTrue);
      expect((await SharedPreferences.getInstance()).getString('server_url'), 'https://bma.example.org');
    });
  });

  group('routing', () {
    testWidgets('a device that was never set up lands on the setup page', (tester) async {
      _phone(tester);
      await _pumpApp(tester, serverConfigured: false);
      expect(find.byType(ServerSetupScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('a configured device goes straight to sign in', (tester) async {
      _phone(tester);
      await _pumpApp(tester, serverConfigured: true);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ServerSetupScreen), findsNothing);
    });

    testWidgets('a deep link is gated until the server is set up', (tester) async {
      _phone(tester);
      final container = await _pumpApp(tester, serverConfigured: false);
      container.read(appRouterProvider).go(Routes.sync);
      await tester.pumpAndSettle();
      expect(find.byType(ServerSetupScreen), findsOneWidget);
    });

    testWidgets('a signed-in session never sees the setup page', (tester) async {
      _phone(tester);
      final container = ProviderContainer(
        overrides: tipsOverrides(
          auth: signedIn(),
          tips: TipsState(seen: {TipsState.seenKey(42)}),
          serverConfigured: false,
        ),
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const BmaApp()));
      await tester.pumpAndSettle();
      expect(find.byType(ServerSetupScreen), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
    });
  });

  group('ServerSetupScreen', () {
    testWidgets('continue saves the address and opens the sign-in screen', (tester) async {
      _phone(tester);
      final container = await _pumpApp(tester, serverConfigured: false);
      await tester.enterText(find.byKey(const ValueKey('setup-url')), 'bma-nfe.example.org');
      await tester.tap(find.byKey(const ValueKey('setup-continue')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      final settings = container.read(settingsControllerProvider);
      expect(settings.serverUrl, 'https://bma-nfe.example.org');
      expect(settings.serverConfigured, isTrue);
    });

    testWidgets('an empty address is rejected and nothing is saved', (tester) async {
      _phone(tester);
      final container = await _pumpApp(tester, serverConfigured: false);
      await tester.enterText(find.byKey(const ValueKey('setup-url')), '   ');
      await tester.tap(find.byKey(const ValueKey('setup-continue')));
      await tester.pumpAndSettle();
      expect(find.byType(ServerSetupScreen), findsOneWidget);
      expect(find.text('This field is required.'), findsOneWidget);
      expect(container.read(settingsControllerProvider).serverConfigured, isFalse);
    });

    testWidgets('an address without a host is rejected', (tester) async {
      _phone(tester);
      await _pumpApp(tester, serverConfigured: false);
      await tester.enterText(find.byKey(const ValueKey('setup-url')), 'https://');
      await tester.tap(find.byKey(const ValueKey('setup-continue')));
      await tester.pumpAndSettle();
      expect(find.byType(ServerSetupScreen), findsOneWidget);
      expect(find.textContaining('Enter a web address'), findsOneWidget);
    });

    testWidgets('a successful check reports the mobile API and probes the normalised URL', (tester) async {
      _phone(tester);
      final container = await _pumpApp(tester, serverConfigured: false, probe: ServerCheck.ok);
      await tester.enterText(find.byKey(const ValueKey('setup-url')), 'bma-nfe.example.org/');
      await tester.tap(find.byKey(const ValueKey('setup-test')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Connected'), findsOneWidget);
      final probe = container.read(serverProbeProvider) as FakeServerProbe;
      expect(probe.checked, ['https://bma-nfe.example.org']);
    });

    testWidgets('a server without the mobile API is called out', (tester) async {
      _phone(tester);
      await _pumpApp(tester, serverConfigured: false, probe: ServerCheck.notBmaServer);
      await tester.tap(find.byKey(const ValueKey('setup-test')));
      await tester.pumpAndSettle();
      expect(find.textContaining('mobile API is not installed'), findsOneWidget);
    });

    testWidgets('an unreachable server is reported and does not block continuing', (tester) async {
      _phone(tester);
      final container = await _pumpApp(tester, serverConfigured: false, probe: ServerCheck.unreachable);
      await tester.tap(find.byKey(const ValueKey('setup-test')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not reach'), findsOneWidget);

      // Setting up a device with no connectivity has to stay possible.
      await tester.tap(find.byKey(const ValueKey('setup-continue')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(container.read(settingsControllerProvider).serverConfigured, isTrue);
    });

    testWidgets('editing the address clears a stale check result', (tester) async {
      _phone(tester);
      await _pumpApp(tester, serverConfigured: false, probe: ServerCheck.ok);
      await tester.tap(find.byKey(const ValueKey('setup-test')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('setup-result')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('setup-url')), 'https://other.example.org');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('setup-result')), findsNothing);
    });

    testWidgets('the language can be switched before signing in', (tester) async {
      _phone(tester);
      final container = await _pumpApp(tester, serverConfigured: false);
      await tester.tap(find.text('Arabic'));
      await tester.pumpAndSettle();
      expect(container.read(settingsControllerProvider).locale.languageCode, 'ar');
      expect(find.text('إعداد الخادم'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(ServerSetupScreen))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in Arabic without overflowing at 1.3 text scale', (tester) async {
      _phone(tester);
      await _pumpApp(tester, serverConfigured: false, lang: 'ar');
      expect(find.text('إعداد الخادم'), findsOneWidget);
      tester.view.physicalSize = const Size(412 * 2.625, 700 * 2.625);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
