import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/features/tips/tips_content.dart';
import 'package:bma_app/features/tips/tips_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

ProviderContainer _inMemory({TipsState initial = const TipsState(), List<Override> extra = const []}) {
  final container = ProviderContainer(overrides: [
    tipsControllerProvider.overrideWith(() => TipsController(initial, null)),
    ...extra,
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TipsState', () {
    test('default state has nothing seen or dismissed', () {
      const state = TipsState();
      expect(state.hasSeen(42), isFalse);
      expect(state.hasSeen(null), isFalse);
      expect(state.isDismissed(42, 'x'), isFalse);
      expect(state.isDismissed(null, 'x'), isFalse);
    });

    test('seenKey embeds the current tips version', () {
      expect(TipsState.seenKey(42), '42:${AppConfig.tipsVersion}');
      expect(TipsState.seenKey(42), '42:1');
    });

    test('an entry for another tips version does not count as seen', () {
      expect(const TipsState(seen: {'42:0'}).hasSeen(42), isFalse);
      expect(const TipsState(seen: {'42:1'}).hasSeen(42), isTrue);
    });
  });

  group('TipsController (in-memory)', () {
    test('markSeen flags only that user for the current version', () async {
      final container = _inMemory();
      await container.read(tipsControllerProvider.notifier).markSeen(42);
      final state = container.read(tipsControllerProvider);
      expect(state.hasSeen(42), isTrue);
      expect(state.hasSeen(7), isFalse);
      expect(state.seen, {'42:1'});
      expect(state.seen, {TipsState.seenKey(42)});
    });

    test('dismissTip and restoreTips are per user and never touch seen', () async {
      final container = _inMemory(initial: const TipsState(seen: {'42:1', '7:1'}));
      final notifier = container.read(tipsControllerProvider.notifier);
      await notifier.dismissTip(42, TipIds.homeSync);
      await notifier.dismissTip(7, TipIds.homeSync);
      var state = container.read(tipsControllerProvider);
      expect(state.isDismissed(42, 'home.sync'), isTrue);
      expect(state.isDismissed(7, 'home.sync'), isTrue);
      expect(state.isDismissed(42, TipIds.syncCenter), isFalse);

      await notifier.restoreTips(42);
      state = container.read(tipsControllerProvider);
      expect(state.isDismissed(42, 'home.sync'), isFalse);
      expect(state.isDismissed(7, 'home.sync'), isTrue, reason: 'other users keep their dismissals');
      expect(state.dismissed, {'7:home.sync'});
      expect(state.seen, {'42:1', '7:1'}, reason: 'restoreTips must never clear the seen flag');
      expect(state.hasSeen(42), isTrue);
    });

    test('the default provider (null prefs) never throws on writes', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(tipsControllerProvider.notifier);
      await expectLater(notifier.markSeen(1), completes);
      await expectLater(notifier.dismissTip(1, TipIds.attendanceFlow), completes);
      await expectLater(notifier.restoreTips(1), completes);
      expect(container.read(tipsControllerProvider).hasSeen(1), isTrue);
      expect(container.read(tipsControllerProvider).isDismissed(1, TipIds.attendanceFlow), isFalse);
    });

    test('state is updated synchronously before the write completes', () {
      final container = _inMemory();
      final future = container.read(tipsControllerProvider.notifier).markSeen(42);
      expect(container.read(tipsControllerProvider).hasSeen(42), isTrue);
      return future;
    });
  });

  group('TipsController (shared_preferences round trip)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('markSeen and dismissTip persist and reload', () async {
      final loaded = await TipsController.load();
      expect(loaded.build().hasSeen(42), isFalse);

      final container = ProviderContainer(overrides: [tipsControllerProvider.overrideWith(() => loaded)]);
      addTearDown(container.dispose);
      final notifier = container.read(tipsControllerProvider.notifier);
      await notifier.markSeen(42);
      await notifier.dismissTip(42, 'home.sync');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(TipsController.keySeen), ['42:1']);
      expect(prefs.getStringList('tips_seen'), ['42:1']);
      expect(prefs.getStringList(TipsController.keyDismissed), ['42:home.sync']);
      expect(prefs.getStringList('tips_dismissed'), ['42:home.sync']);

      final reloaded = await TipsController.load();
      final second = ProviderContainer(overrides: [tipsControllerProvider.overrideWith(() => reloaded)]);
      addTearDown(second.dispose);
      final state = second.read(tipsControllerProvider);
      expect(state.hasSeen(42), isTrue);
      expect(state.hasSeen(7), isFalse);
      expect(state.isDismissed(42, 'home.sync'), isTrue);
    });

    test('restoreTips rewrites the persisted list', () async {
      SharedPreferences.setMockInitialValues({
        'tips_seen': ['42:1'],
        'tips_dismissed': ['42:home.sync', '7:home.sync'],
      });
      final loaded = await TipsController.load();
      final container = ProviderContainer(overrides: [tipsControllerProvider.overrideWith(() => loaded)]);
      addTearDown(container.dispose);
      await container.read(tipsControllerProvider.notifier).restoreTips(42);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('tips_dismissed'), ['7:home.sync']);
      expect(prefs.getStringList('tips_seen'), ['42:1']);
    });
  });

  group('tipsPendingProvider', () {
    test('true for an unseen signed-in account, false after markSeen', () async {
      final container = _inMemory(extra: [
        authControllerProvider.overrideWith(() => FakeAuthController(signedIn(id: 42))),
      ]);
      expect(container.read(tipsPendingProvider), isTrue);
      await container.read(tipsControllerProvider.notifier).markSeen(42);
      expect(container.read(tipsPendingProvider), isFalse);
    });

    test('false while signed out', () {
      final container = _inMemory(extra: [
        authControllerProvider.overrideWith(() => FakeAuthController(AuthState.signedOut)),
      ]);
      expect(container.read(tipsPendingProvider), isFalse);
    });

    test('false while the auth state is unknown', () {
      final container = _inMemory(extra: [
        authControllerProvider.overrideWith(() => FakeAuthController(AuthState.unknown)),
      ]);
      expect(container.read(tipsPendingProvider), isFalse);
    });

    test('a different account on the same device has its own first run', () {
      final container = _inMemory(
        initial: TipsState(seen: {TipsState.seenKey(42)}),
        extra: [authControllerProvider.overrideWith(() => FakeAuthController(signedIn(id: 7)))],
      );
      expect(container.read(tipsPendingProvider), isTrue);
    });

    test('an old tips version entry still counts as pending', () {
      final container = _inMemory(
        initial: const TipsState(seen: {'42:0'}),
        extra: [authControllerProvider.overrideWith(() => FakeAuthController(signedIn(id: 42)))],
      );
      expect(container.read(tipsPendingProvider), isTrue);
    });
  });
}
