import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/config/settings_controller.dart';
import '../../core/db/app_database.dart';
import '../../core/db/providers.dart';
import '../../core/forms/reference_cache.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _server;

  @override
  void initState() {
    super.initState();
    _server = TextEditingController(text: ref.read(settingsControllerProvider).serverUrl);
  }

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final sync = ref.watch(syncEngineProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text(l10n.language, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'en', label: Text(l10n.english)),
              ButtonSegment(value: 'ar', label: Text(l10n.arabic)),
            ],
            selected: {settings.locale.languageCode},
            onSelectionChanged: (s) => ref.read(settingsControllerProvider.notifier).setLocale(Locale(s.first)),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _server,
            decoration: InputDecoration(
              labelText: l10n.serverUrl,
              suffixIcon: IconButton(
                icon: const Icon(Icons.save),
                onPressed: () async {
                  await ref.read(settingsControllerProvider.notifier).setServerUrl(_server.text);
                  if (context.mounted) showMessage(context, l10n.save);
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Column(children: [
              ListTile(title: Text(l10n.username), subtitle: Text(auth.profile?.username ?? '—')),
              ListTile(title: Text(l10n.deviceInfo), subtitle: Text(auth.deviceId ?? '—')),
              ListTile(title: Text(l10n.version), subtitle: const Text(AppConfig.appVersion)),
              ListTile(
                title: Text(l10n.lastPull(sync.lastPull ?? l10n.never)),
                subtitle: Text(sync.bootstrapAt == null ? l10n.bootstrapRequired : sync.bootstrapAt!),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: Text(l10n.fullRefresh),
            onPressed: sync.busy
                ? null
                : () async {
                    try {
                      final engine = ref.read(syncEngineProvider.notifier);
                      await engine.bootstrap();
                      ref.read(referenceCacheProvider).invalidate();
                      await engine.pull(full: true);
                      if (context.mounted) showMessage(context, l10n.synced);
                    } catch (e) {
                      if (context.mounted) showMessage(context, e.toString(), error: true);
                    }
                  },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_forever, color: AppColors.danger),
            label: Text(l10n.clearLocalData, style: const TextStyle(color: AppColors.danger)),
            onPressed: () async {
              if (!await confirmDialog(context, l10n.clearLocalDataWarning, title: l10n.clearLocalData)) return;
              await ref.read(appDatabaseProvider).clearAll();
              ref.read(referenceCacheProvider).invalidate();
              bumpDataVersion(ref);
              await ref.read(syncEngineProvider.notifier).refreshCounts();
              if (context.mounted) showMessage(context, l10n.clearLocalData);
            },
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.logout),
            label: Text(l10n.logout),
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go(Routes.login);
            },
          ),
        ],
      ),
    );
  }
}
