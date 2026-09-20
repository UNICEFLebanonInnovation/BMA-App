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
import 'package:bma_app/core/forms/schema_form_controller.dart';
import 'package:bma_app/core/forms/script_input.dart';
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

  testWidgets('the bootstrap carries BOTH tiers of the name rules', (tester) async {
    final container = await boot(tester);
    final schema = await tester.runAsync(
      () => container.read(referenceDaoProvider).schema(Entities.msccRegistration),
    );

    // Tier 1: bio data must be ARABIC. checkArabicOnly() in the website's
    // validator.js, which is JavaScript and reached the app through nothing
    // until the schema started saying so.
    const arabic = {
      'child_first_name', 'child_father_name', 'child_last_name', 'child_mother_fullname',
      'caregiver_first_name', 'caregiver_middle_name', 'caregiver_last_name', 'caregiver_mother_name',
    };
    expect({for (final f in schema!.fields) if (f.isArabicOnly) f.name}, arabic);

    // Tier 2: the remaining only_letters_validator fields, which accept Latin
    // OR Arabic. Arabic-only is the stricter statement of the same idea, so a
    // field is in one tier or the other and never both.
    const lettersOnly = {
      'child_nationality_other', 'main_caregiver_nationality_other', 'child_address',
      'source_of_identification_specify', 'main_caregiver_other',
    };
    final latin = {
      for (final f in schema.fields)
        if (f.effectivePatterns.any((p) => p.pattern.contains('A-Za-z'))) f.name
    };
    expect(latin, lettersOnly);
    expect(latin.intersection(arabic), isEmpty, reason: 'one complaint per character, not two');

    // And the rule survives the round trip through SQLite with its message.
    final name = schema.fields.firstWhere((f) => f.name == 'child_first_name');
    expect(name.effectivePatterns.single.pattern, arabicOnlyPattern);
    expect(name.effectivePatterns.single.message, 'Please write this in Arabic.');
  });

  testWidgets('the wizard will not let a Latin name be typed into a bio field', (tester) async {
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

    final host = find.byKey(const ValueKey('field-child_first_name'));
    expect(host, findsOneWidget, reason: 'step 0 shows the child name');
    // The key sits on the schema field wrapper; the editable is inside it.
    final field = find.descendant(of: host, matching: find.byType(TextField));
    String typed() => tester.widget<TextField>(field).controller!.text;

    // The website would accept these keystrokes and delete them on blur. Here
    // they never land, so nothing the worker can see is taken away from them.
    await tester.enterText(field, 'Omar');
    await tester.pump();
    expect(typed(), '',
        reason: 'a Latin name never appears in an Arabic-only field');

    await tester.enterText(field, 'محمد');
    await tester.pump();
    expect(typed(), 'محمد');

    await tester.enterText(field, 'محمد2');
    await tester.pump();
    expect(typed(), 'محمد',
        reason: 'the digit is dropped, the name is kept');

    // A blocked keystroke is silent, so the field says why it refuses.
    expect(find.text('Arabic only'), findsWidgets);
  });

  testWidgets('a Latin name already on a pulled record does not block an edit', (tester) async {
    // Twelve of the twenty-eight names in this very fixture are Latin, and the
    // website lets them through: Django's validator accepts Latin, and the
    // Arabic rule is on-blur JavaScript that only fires on a field the worker
    // focused. Rejecting them here would stop someone correcting a birth date
    // on a record whose name they never touched.
    final container = await boot(tester);
    final schema = await tester.runAsync(
      () => container.read(referenceDaoProvider).schema(Entities.msccRegistration),
    );
    final opened = SchemaFormController(schema: schema!, initial: const {'child_first_name': 'Omar'});
    expect(opened.validate(fields: const ['child_first_name']), isTrue);
    expect(opened.errorsFor('child_first_name'), isEmpty);

    // Touch it, and the rule applies from then on.
    opened.setValue('child_first_name', 'Omar Kassem');
    expect(opened.validate(fields: const ['child_first_name']), isFalse);
    expect(opened.errorsFor('child_first_name'), ['Please write this in Arabic.']);
  });
}
