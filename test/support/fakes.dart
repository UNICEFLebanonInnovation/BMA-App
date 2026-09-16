// Shared test doubles for the tips wizard and server setup tests. Nothing here
// touches SQLite or the network; the screenshot harness keeps its own copies.
import 'package:bma_app/core/auth/auth_controller.dart';
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/config/settings_controller.dart';
import 'package:bma_app/core/db/providers.dart';
import 'package:bma_app/core/models/user_profile.dart';
import 'package:bma_app/core/network/server_probe.dart';
import 'package:bma_app/core/sync/connectivity_service.dart';
import 'package:bma_app/core/sync/sync_engine.dart';
import 'package:bma_app/features/tips/tips_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FakeAuthController extends AuthController {
  FakeAuthController(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;

  @override
  Future<void> restore() async {}
}

/// Never touches DAOs/SQLite (the real build() schedules a refreshCounts microtask).
class FakeSyncEngine extends SyncEngine {
  @override
  SyncStatus build() => const SyncStatus();
}

ModuleCapabilities caps({
  bool register = true,
  bool edit = true,
  bool attend = true,
  bool teachers = true,
  String scope = 'center',
}) =>
    ModuleCapabilities(
      enabled: true,
      canRegister: register,
      canEdit: edit,
      canAttend: attend,
      canManageTeachers: teachers,
      scope: scope,
    );

UserProfile profileWith({int id = 42, Map<BmaModule, ModuleCapabilities>? modules}) => UserProfile(
      id: id,
      username: 'u$id',
      firstName: 'Rima',
      lastName: 'Haddad',
      groups: const [],
      modules: modules ?? {BmaModule.mscc: caps()},
      partner: const NamedRef(id: 1, name: 'Partner NGO'),
      center: const NamedRef(id: 1, name: 'NFE Centre'),
    );

AuthState signedIn({int id = 42, Map<BmaModule, ModuleCapabilities>? modules}) => AuthState(
      status: AuthStatus.signedIn,
      token: 't',
      deviceId: 'd',
      profile: profileWith(id: id, modules: modules),
    );

/// Answers the setup screen's connection check without any network access.
class FakeServerProbe extends ServerProbe {
  FakeServerProbe(this.result);

  final ServerCheck result;
  final List<String> checked = [];

  @override
  Future<ServerCheck> check(String baseUrl, {Dio? dio}) async {
    checked.add(baseUrl);
    return result;
  }
}

/// Overrides every provider the wizard, Home and the router touch, without SQLite.
List<Override> tipsOverrides({
  required AuthState auth,
  TipsState tips = const TipsState(),
  String lang = 'en',
  bool serverConfigured = true,
  ServerCheck probe = ServerCheck.ok,
}) =>
    [
      authControllerProvider.overrideWith(() => FakeAuthController(auth)),
      tipsControllerProvider.overrideWith(() => TipsController(tips, null)),
      syncEngineProvider.overrideWith(FakeSyncEngine.new),
      connectivityProvider.overrideWith((ref) => Stream.value(true)),
      bootstrapReadyProvider.overrideWith((ref) async => true),
      settingsControllerProvider.overrideWith(
        () => SettingsController(
          AppSettings(
            serverUrl: 'https://x.invalid',
            locale: Locale(lang),
            serverConfigured: serverConfigured,
          ),
          null,
        ),
      ),
      serverProbeProvider.overrideWithValue(FakeServerProbe(probe)),
    ];
