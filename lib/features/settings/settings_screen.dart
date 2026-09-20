import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/config/settings_controller.dart';
import '../../core/db/app_database.dart';
import '../../core/db/providers.dart';
import '../../core/forms/reference_cache.dart';
import '../../core/layout/adaptive.dart';
import '../../core/layout/app_layout.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../tips/tips_controller.dart';

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
    // Every button is built once here so the ValueKey, the callbacks and the
    // labels are literally the same widget in both branches; only the
    // arrangement below differs.
    final showTips = OutlinedButton.icon(
      key: const ValueKey('settings-show-tips'),
      icon: const Icon(Icons.tips_and_updates_outlined),
      label: Text(l10n.tipsShowAgain),
      onPressed: () async {
        // Restores this user's dismissed TipCards; never clears the seen flag.
        final id = auth.profile?.id;
        if (id != null) await ref.read(tipsControllerProvider.notifier).restoreTips(id);
        if (context.mounted) context.push(Routes.tips);
      },
    );
    final fullRefresh = OutlinedButton.icon(
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
    );
    final clearData = OutlinedButton.icon(
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
    );
    final logout = FilledButton.icon(
      icon: const Icon(Icons.logout),
      label: Text(l10n.logout),
      onPressed: () async {
        await ref.read(authControllerProvider.notifier).logout();
        if (context.mounted) context.go(Routes.login);
      },
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = AppLayout.forWidth(constraints.maxWidth);
          final wide = layout.width.atLeastMedium;
          // Settings gain nothing from width: a reading cap keeps the labels
          // next to their controls. gutter is OFF at compact because the
          // ListView below already carries the 12 px page padding it has
          // today — AdaptiveBody's compact gutter would add 16 more and move
          // the phone.
          return AdaptiveBody(
            maxWidth: layout.readingMaxWidth,
            gutter: wide,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(l10n.language, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                // Intrinsic width at medium+ only: a 700 px-wide two-segment
                // language switch is a target, not a control. At compact the
                // widget is the bare stretched SegmentedButton it is today,
                // with no Align wrapper around it.
                _startAligned(
                  wide,
                  SegmentedButton<String>(
                    key: const ValueKey('settings-language'),
                    segments: [
                      ButtonSegment(value: 'en', label: Text(l10n.english)),
                      ButtonSegment(value: 'ar', label: Text(l10n.arabic)),
                    ],
                    selected: {settings.locale.languageCode},
                    onSelectionChanged: (s) =>
                        ref.read(settingsControllerProvider.notifier).setLocale(Locale(s.first)),
                  ),
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
                if (!wide) ...[
                  showTips,
                  const SizedBox(height: 8),
                  fullRefresh,
                  const SizedBox(height: 8),
                  clearData,
                  const SizedBox(height: 8),
                  logout,
                ] else ...[
                  // Two intrinsic-width columns. A full-bleed "clear local
                  // data" bar on a shared centre tablet is an accidental-tap
                  // hazard, so the destructive pair is both smaller and fenced
                  // off behind a divider.
                  Wrap(
                    key: const ValueKey('settings-actions'),
                    spacing: 12,
                    runSpacing: 12,
                    children: [showTips, fullRefresh],
                  ),
                  const Divider(height: 32),
                  Wrap(
                    key: const ValueKey('settings-danger'),
                    spacing: 12,
                    runSpacing: 12,
                    children: [clearData, logout],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Returns [child] untouched unless [wide]; the compact tree must not gain a
/// wrapper it does not have today.
Widget _startAligned(bool wide, Widget child) => wide
    ? Align(alignment: AlignmentDirectional.centerStart, child: child)
    : child;
