import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/settings_controller.dart';
import 'core/db/app_database.dart';
import 'features/tips/tips_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Open (and migrate) the local SQLite database and load persisted settings
  // before the first frame so the UI never sees a half-initialised state.
  final database = await AppDatabase.open();
  final settings = await SettingsController.load();
  final tips = await TipsController.load();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        settingsControllerProvider.overrideWith(() => settings),
        // The app only overrides this here (tests and the screenshot harness do too);
        // without an override the tips flags are in-memory only.
        tipsControllerProvider.overrideWith(() => tips),
      ],
      child: const BmaApp(),
    ),
  );
}
