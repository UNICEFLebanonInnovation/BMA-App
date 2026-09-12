import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// User-editable settings persisted with shared preferences.
class AppSettings {
  const AppSettings({
    required this.serverUrl,
    required this.locale,
  });

  final String serverUrl;
  final Locale locale;

  AppSettings copyWith({String? serverUrl, Locale? locale}) => AppSettings(
        serverUrl: serverUrl ?? this.serverUrl,
        locale: locale ?? this.locale,
      );
}

class SettingsController extends Notifier<AppSettings> {
  SettingsController(this._initial, this._prefs);

  static const _keyServer = 'server_url';
  static const _keyLocale = 'locale';

  final AppSettings _initial;
  final SharedPreferences? _prefs;

  static Future<SettingsController> load() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString(_keyServer) ?? AppConfig.defaultServerUrl;
    final locale = Locale(prefs.getString(_keyLocale) ?? 'en');
    return SettingsController(
      AppSettings(serverUrl: server, locale: locale),
      prefs,
    );
  }

  @override
  AppSettings build() => _initial;

  Future<void> setServerUrl(String url) async {
    final cleaned = normaliseServerUrl(url);
    state = state.copyWith(serverUrl: cleaned);
    await _prefs?.setString(_keyServer, cleaned);
  }

  Future<void> setLocale(Locale locale) async {
    state = state.copyWith(locale: locale);
    await _prefs?.setString(_keyLocale, locale.languageCode);
  }

  /// Removes a trailing slash and guarantees a scheme so that `dio` builds
  /// valid URLs whatever the user typed.
  static String normaliseServerUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return AppConfig.defaultServerUrl;
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(
  () => throw UnimplementedError('Overridden in main()'),
);
