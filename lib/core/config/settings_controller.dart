import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// User-editable settings persisted with shared preferences.
class AppSettings {
  const AppSettings({
    required this.serverUrl,
    required this.locale,
    this.serverConfigured = true,
  });

  final String serverUrl;
  final Locale locale;

  /// False until someone confirms the server address on this device, which is
  /// what sends a fresh install to the first-run setup screen. Installs that
  /// already stored a URL keep going straight to the sign-in screen.
  final bool serverConfigured;

  AppSettings copyWith({String? serverUrl, Locale? locale, bool? serverConfigured}) => AppSettings(
        serverUrl: serverUrl ?? this.serverUrl,
        locale: locale ?? this.locale,
        serverConfigured: serverConfigured ?? this.serverConfigured,
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
    final stored = prefs.getString(_keyServer);
    final locale = Locale(prefs.getString(_keyLocale) ?? 'en');
    return SettingsController(
      AppSettings(
        serverUrl: stored ?? AppConfig.defaultServerUrl,
        locale: locale,
        serverConfigured: stored != null,
      ),
      prefs,
    );
  }

  @override
  AppSettings build() => _initial;

  /// Saves the address and marks the device as set up. State is assigned
  /// before persisting so the next router redirect already sees it.
  Future<void> setServerUrl(String url) async {
    final cleaned = normaliseServerUrl(url);
    state = state.copyWith(serverUrl: cleaned, serverConfigured: true);
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
