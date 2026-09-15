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
import '../../core/widgets/ui.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../tips/tip_card.dart';
import '../tips/tips_content.dart';

/// Landing page: who you are and where you work, what still has to reach the
/// server, then one card per programme the account may use.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(currentProfileProvider);
    final sync = ref.watch(syncEngineProvider);
    final online = ref.watch(isOnlineProvider);
    final bootstrapReady = ref.watch(bootstrapReadyProvider).value ?? true;
    final attention = sync.pendingCount + sync.attentionCount;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const OfflineBanner(),
          HeroHeader(
            title: profile == null ? l10n.appTitle : l10n.welcome(profile.displayName),
            subtitle: profile == null ? null : _scope(profile),
            leading: profile == null
                ? null
                : CircleAvatar(
                    radius: 22,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    child: Text(
                      InitialsAvatar.initialsOf(profile.displayName),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeaderAction(
                  tooltip: l10n.syncCenter,
                  icon: online ? Icons.cloud_sync : Icons.cloud_off,
                  badge: attention > 0 ? '$attention' : null,
                  onPressed: () => context.push(Routes.sync),
                ),
                _HeaderAction(
                  key: const ValueKey('home-help'),
                  tooltip: l10n.tipsTitle,
                  icon: Icons.help_outline,
                  onPressed: () => context.push(Routes.tips),
                ),
                _HeaderAction(
                  tooltip: l10n.settings,
                  icon: Icons.settings_outlined,
                  onPressed: () => context.push(Routes.settings),
                ),
              ],
            ),
            footer: _SyncStrip(sync: sync, online: online),
          ),
          if (!bootstrapReady)
            AppCard(
              color: AppColors.warning.withValues(alpha: 0.10),
              borderColor: AppColors.warning.withValues(alpha: 0.45),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: AppColors.warning),
                  const SizedBox(width: 12),
                  Expanded(child: Text(l10n.bootstrapRequired)),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: sync.busy || !online ? null : () => _fullRefresh(context, ref),
                    child: Text(l10n.fullRefresh),
                  ),
                ],
              ),
            ),
          SectionHeader(l10n.quickActions),
          _SyncActions(sync: sync, online: online),
          TipCard(id: TipIds.homeSync, text: l10n.tipHomeSync),
          if (profile != null && profile.enabledModules.isNotEmpty) SectionHeader(l10n.yourProgrammes),
          if (profile != null)
            for (final module in profile.enabledModules)
              _ModuleCard(module: module, capabilities: profile.capabilities(module), profile: profile),
          if (profile != null && profile.enabledModules.isEmpty)
            Padding(padding: const EdgeInsets.all(24), child: Text(l10n.moduleDisabled)),
        ],
      ),
    );
  }

  static String _scope(UserProfile profile) => [
        if (profile.partner != null) profile.partner!.name,
        if (profile.center != null) profile.center!.name,
        if (profile.school != null) profile.school!.name,
      ].join(' · ');

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

/// Icon button that reads correctly on the coloured header.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({super.key, required this.tooltip, required this.icon, required this.onPressed, this.badge});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      color: Colors.white,
      icon: Badge(
        isLabelVisible: badge != null,
        label: Text(badge ?? ''),
        child: Icon(icon),
      ),
    );
  }
}

/// One glanceable line inside the header: connection, outbox, last download.
class _SyncStrip extends StatelessWidget {
  const _SyncStrip({required this.sync, required this.online});

  final SyncStatus sync;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: AppRadius.controlRadius,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(online ? Icons.wifi : Icons.wifi_off, size: 18, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                online ? l10n.online : l10n.offline,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  l10n.lastPull(shortTime(sync.lastPull) ?? l10n.never),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                ),
              ),
            ],
          ),
          if (sync.busy)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LinearProgressIndicator(color: Colors.white, backgroundColor: Colors.white24),
            ),
          if (sync.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(sync.error!, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  static String? shortTime(String? iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

/// Push, download and the outbox figures, directly under the header.
class _SyncActions extends ConsumerWidget {
  const _SyncActions({required this.sync, required this.online});

  final SyncStatus sync;
  final bool online;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final engine = ref.read(syncEngineProvider.notifier);
    return AppCard(
      child: Column(
        children: [
          // StatRow gives each tile an equal share; a bare Row would overflow.
          StatRow(
            padding: EdgeInsets.zero,
            tiles: [
              StatTile(
                label: l10n.kpiPendingPush,
                value: '${sync.pendingCount}',
                icon: Icons.cloud_upload_outlined,
                color: sync.pendingCount > 0 ? AppColors.warning : AppColors.success,
                onTap: () => context.push(Routes.sync),
              ),
              StatTile(
                label: l10n.needsResolution,
                value: '${sync.attentionCount}',
                icon: Icons.error_outline,
                color: sync.attentionCount > 0 ? AppColors.danger : AppColors.success,
                onTap: () => context.push(Routes.sync),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
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
            ],
          ),
        ],
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
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.module, required this.capabilities, required this.profile});

  final BmaModule module;
  final ModuleCapabilities capabilities;
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (title, accent) = switch (module) {
      BmaModule.mscc => (l10n.mscc, AppColors.primary),
      BmaModule.alp => (l10n.alp, AppColors.secondary),
      BmaModule.clm => (l10n.clm, AppColors.success),
    };
    // The facility profile comes first: it is the "where am I" of the module.
    final actions = <_Action>[
      if (module == BmaModule.mscc && profile.center != null)
        _Action(l10n.centerProfile, Icons.apartment_outlined, () => context.push(Routes.centerProfile)),
      if (module == BmaModule.alp && profile.school != null)
        _Action(l10n.schoolProfile, Icons.school_outlined, () => context.push(Routes.schoolProfile)),
      _Action(l10n.beneficiaries, Icons.people_outline, () => context.push(Routes.registrations(module))),
      if (capabilities.canRegister)
        _Action(l10n.registerNew, Icons.person_add_alt, () => context.push(Routes.newRegistration(module))),
      if (capabilities.canAttend)
        _Action(l10n.attendance, Icons.fact_check_outlined, () => context.push(Routes.attendance(module))),
      if (module == BmaModule.alp && capabilities.canAttend)
        _Action(l10n.teacherAttendance, Icons.co_present_outlined,
            () => context.push(Routes.teacherAttendance(module))),
      if (capabilities.canManageTeachers)
        _Action(l10n.teachers, Icons.badge_outlined, () => context.push(Routes.teachers(module))),
      _Action(l10n.dashboard, Icons.insights_outlined, () => context.push(Routes.dashboard(module))),
    ];

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleMedium),
              ),
              StatusPill(label: capabilities.scope, color: AppColors.muted),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 560 ? 4 : 3;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.95,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final action in actions)
                    ActionTile(icon: action.icon, label: action.label, onTap: action.onTap, color: accent),
                ],
              );
            },
          ),
        ],
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
