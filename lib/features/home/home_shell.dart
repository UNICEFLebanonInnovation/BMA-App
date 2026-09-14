import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/db/providers.dart';
import '../../core/models/user_profile.dart';
import '../../core/sync/connectivity_service.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../tips/tip_card.dart';
import '../tips/tips_content.dart';

/// Landing page: sync status, quick actions and one card per module.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(currentProfileProvider);
    final sync = ref.watch(syncEngineProvider);
    final online = ref.watch(isOnlineProvider);
    final bootstrapReady = ref.watch(bootstrapReadyProvider).value ?? true;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            tooltip: l10n.syncCenter,
            onPressed: () => context.push(Routes.sync),
            icon: Badge(
              isLabelVisible: sync.pendingCount + sync.attentionCount > 0,
              label: Text('${sync.pendingCount + sync.attentionCount}'),
              child: Icon(online ? Icons.cloud_sync : Icons.cloud_off),
            ),
          ),
          IconButton(
            key: const ValueKey('home-help'),
            tooltip: l10n.tipsTitle,
            onPressed: () => context.push(Routes.tips),
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            tooltip: l10n.settings,
            onPressed: () => context.push(Routes.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const OfflineBanner(),
          if (profile != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(l10n.welcome(profile.displayName), style: Theme.of(context).textTheme.titleLarge),
            ),
          if (profile != null) _ScopeLine(profile: profile),
          if (!bootstrapReady)
            Card(
              color: AppColors.warning.withValues(alpha: 0.15),
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: AppColors.warning),
                title: Text(l10n.bootstrapRequired),
                trailing: FilledButton(
                  onPressed: sync.busy || !online ? null : () => _fullRefresh(context, ref),
                  child: Text(l10n.fullRefresh),
                ),
              ),
            ),
          _SyncCard(sync: sync, online: online),
          TipCard(id: TipIds.homeSync, text: l10n.tipHomeSync),
          if (profile != null)
            for (final module in profile.enabledModules)
              _ModuleCard(module: module, capabilities: profile.capabilities(module)),
          if (profile != null && profile.enabledModules.isEmpty)
            Padding(padding: const EdgeInsets.all(24), child: Text(l10n.moduleDisabled)),
        ],
      ),
    );
  }

  Future<void> _fullRefresh(BuildContext context, WidgetRef ref) async {
    final engine = ref.read(syncEngineProvider.notifier);
    try {
      await engine.bootstrap();
      await engine.pull(full: true);
    } catch (e) {
      if (context.mounted) showMessage(context, e.toString(), error: true);
    }
  }
}

class _ScopeLine extends StatelessWidget {
  const _ScopeLine({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (profile.partner != null) profile.partner!.name,
      if (profile.center != null) profile.center!.name,
      if (profile.school != null) profile.school!.name,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(parts.join(' · '), style: const TextStyle(color: AppColors.muted)),
    );
  }
}

class _SyncCard extends ConsumerWidget {
  const _SyncCard({required this.sync, required this.online});

  final SyncStatus sync;
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final engine = ref.read(syncEngineProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(online ? Icons.wifi : Icons.wifi_off, color: online ? AppColors.success : AppColors.warning),
              const SizedBox(width: 8),
              Text(online ? l10n.online : l10n.offline, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(l10n.lastPull(_shortTime(sync.lastPull) ?? l10n.never),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(
                avatar: const Icon(Icons.cloud_upload, size: 16),
                label: Text(l10n.pendingChanges(sync.pendingCount)),
              ),
              if (sync.attentionCount > 0)
                ActionChip(
                  avatar: const Icon(Icons.warning_amber, size: 16, color: AppColors.danger),
                  label: Text('${l10n.kpiDuplicates}: ${sync.attentionCount}'),
                  onPressed: () => context.push(Routes.sync),
                ),
            ]),
            if (sync.busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            if (sync.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(sync.error!, style: const TextStyle(color: AppColors.danger)),
              ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: sync.busy || !online || sync.pendingCount == 0 ? null : () => _run(context, engine.push),
                  icon: const Icon(Icons.upload),
                  label: Text(l10n.pushNow),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: sync.busy || !online ? null : () => _run(context, () => engine.pull()),
                  icon: const Icon(Icons.download),
                  label: Text(l10n.pullNow),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) showMessage(context, e.toString(), error: true);
    }
  }

  static String? _shortTime(String? iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, required this.capabilities});

  final BmaModule module;
  final ModuleCapabilities capabilities;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = switch (module) {
      BmaModule.mscc => l10n.mscc,
      BmaModule.alp => l10n.alp,
      BmaModule.clm => l10n.clm,
    };
    final actions = <_Action>[
      _Action(l10n.beneficiaries, Icons.people, () => context.push(Routes.registrations(module))),
      if (capabilities.canRegister)
        _Action(l10n.registerNew, Icons.person_add, () => context.push(Routes.newRegistration(module))),
      if (capabilities.canAttend)
        _Action(l10n.attendance, Icons.fact_check, () => context.push(Routes.attendance(module))),
      if (module == BmaModule.alp && capabilities.canAttend)
        _Action(l10n.teacherAttendance, Icons.co_present, () => context.push(Routes.teacherAttendance(module))),
      if (capabilities.canManageTeachers)
        _Action(l10n.teachers, Icons.badge, () => context.push(Routes.teachers(module))),
      _Action(l10n.dashboard, Icons.insights, () => context.push(Routes.dashboard(module))),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth > 560 ? 4 : 3;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.4,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: actions.map((a) => _ActionTile(action: a)).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Action {
  const _Action(this.label, this.icon, this.onTap);

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});

  final _Action action;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, color: AppColors.primary),
            const SizedBox(height: 6),
            Text(action.label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
