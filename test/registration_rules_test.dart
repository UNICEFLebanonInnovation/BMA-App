// END TO END: the rule the server has always enforced, now met in the wizard.
//
// The child registration is the app's most-used form and the one whose rules
// went missing: thirteen of its fields are letters-only on the website via
// `only_letters_validator`, and the schema export dropped `validators=[...]`
// entirely. A name with a digit therefore saved happily on the device and
// failed on push, in a report the worker reads long after the family left.
//
// This runs the REAL wizard against the REAL bootstrap fixture, so it fails if
// the export, the schema model, the validator or the wizard stops carrying the
// rule -- not just if one unit of them does.
import 'dart:convert';
import 'dart:io';

import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/config/settings_controller.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/db/reference_dao.dart';
import 'package:bma_app/core/sync/connectivity_service.dart';
import 'package:bma_app/core/sync/sync_engine.dart';
import 'package:bma_app/features/registrations/registration_wizard_screen.dart';
import 'package:bma_app/features/tips/tips_controller.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<ProviderContainer> boot(WidgetTester tester) async {
    final db = await tester.runAsync(AppDatabase.openInMemory);
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db!),
      authControllerProvider.overrideWith(() => FakeAuthController(signedIn())),
      connectivityProvider.overrideWith((ref) => Stream.value(true)),
      tipsControllerProvider.overrideWith(() => TipsController(TipsState(seen: {TipsState.seenKey(42)}), null)),
      settingsControllerProvider.overrideWith(() => SettingsController(
            AppSettings(serverUrl: 'https://x.invalid', locale: const Locale('en'), serverConfigured: true),
            null,
          )),
    ]);
    addTearDown(container.dispose);
    addTearDown(() => db.close());
    final bootstrap = jsonDecode(File('test/screenshots/fixtures/bootstrap.json').readAsStringSync()) as Map;
    await tester.runAsync(() =>
        container.read(syncEngineProvider.notifier).storeBootstrap(Map<String, dynamic>.from(bootstrap)));
    return container;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the bootstrap the app stores carries the letters-only rule', (tester) async {
    final container = await boot(tester);
    final schema = await tester.runAsync(
      () => container.read(referenceDaoProvider).schema(Entities.msccRegistration),
    );
    final name = schema!.fields.firstWhere((f) => f.name == 'child_first_name');
    expect(name.effectivePatterns, isNotEmpty, reason: 'the rule must survive the round trip through SQLite');
    expect(name.effectivePatterns.first.message, 'Only alphabetic characters are allowed.');

    // Every one of the thirteen, so a partial export is caught here.
    const lettersOnly = {
      'child_first_name', 'child_father_name', 'child_last_name', 'child_mother_fullname',
      'child_nationality_other', 'main_caregiver_nationality_other', 'child_address',
      'source_of_identification_specify', 'main_caregiver_other', 'caregiver_first_name',
      'caregiver_middle_name', 'caregiver_last_name', 'caregiver_mother_name',
    };
    final carried = {
      for (final f in schema.fields)
        if (f.effectivePatterns.any((p) => p.pattern.contains('A-Za-z'))) f.name
    };
    expect(carried, lettersOnly);
  });

  testWidgets('the wizard refuses a name with a digit and says why', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = await boot(tester);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: RegistrationWizardScreen(module: BmaModule.mscc),
      ),
    ));
    await settle(tester);

    final field = find.byKey(const ValueKey('field-child_first_name'));
    expect(field, findsOneWidget, reason: 'step 0 shows the child name');

    await tester.enterText(field, 'Omar2');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wizard-next')));
    await settle(tester);

    expect(find.text('Only alphabetic characters are allowed.'), findsWidgets,
        reason: 'the server wording, shown under the field, offline');

    // And the rule accepts a real name, in either script.
    await tester.enterText(field, 'محمد');
    await tester.pump();
    expect(find.text('Only alphabetic characters are allowed.'), findsNothing);
  });
}
