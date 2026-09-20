import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/settings_controller.dart';
import 'core/layout/adaptive_shell.dart';
import 'core/theme/app_theme.dart';
import 'l10n/app_localizations.dart';
import 'router.dart';

/// Root widget: wires theme, localisation (English / Arabic with RTL) and the
/// router that is guarded by the authentication state.
class BmaApp extends ConsumerWidget {
  const BmaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'BMA Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      // The rail lives ABOVE the Navigator, so it is painted once and stays
      // put while pages push and pop underneath it. On any window too small
      // for a rail — every phone — AdaptiveShell returns the page child with
      // only the theme around it, exactly as this builder did before.
      builder: (context, child) => AdaptiveShell(child: child!),
    );
  }
}
