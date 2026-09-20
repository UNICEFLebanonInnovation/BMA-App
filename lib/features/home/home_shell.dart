import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/db/providers.dart';
import '../../core/layout/adaptive.dart';
import '../../core/layout/app_layout.dart';
import '../../core/layout/breakpoints.dart';
import '../../core/models/user_profile.dart';
import '../../core/sync/connectivity_service.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../analytics/analytics_catalog.dart';
import '../tips/tip_card.dart';
import '../tips/tips_content.dart';

/// Narrowest card box that still fits the warning icon, a readable sentence
/// and the `fullRefresh` button side by side at a 1.0 text scale. Below it the
/// bootstrap card stacks. The 400 px summary pane (342 px of content) and the
/// phone (354 px) are both under it; tablet portrait's 694 px is not.
const double _bootstrapRowMin = 480;

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
    final modules = profile?.enabledModules ?? const <BmaModule>[];

    // Every block below is built once and placed differently per width class,
    // so the phone branch is the same widgets in the same order it has today.
    final header = HeroHeader(
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
    );

    // THE OUT-OF-BOX CARD, and the one sentence that tells a new user why the
    // app is empty — so it must survive the narrowest box it is placed in.
    //
    // `fullRefresh` is the longest button label in the app ("Full refresh
    // (reference data + records)", 320 px at the tablet density, 438 px in
    // Arabic at 1.3x) and a FilledButton does not shrink: as a non-flexible
    // Row child it takes that width first and the Expanded sentence is handed
    // whatever is left — 0 px inside the 400 px summary pane, with the Row
    // overflowing on top of it. Below the threshold the two stack instead, so
    // the button gets a line of its own at its natural width and the sentence
    // gets the whole box. The threshold follows the text scaler because the
    // button is what grows with it.
    final bootstrapCard = AppCard(
      color: AppColors.warning.withValues(alpha: 0.10),
      borderColor: AppColors.warning.withValues(alpha: 0.45),
      child: LayoutBuilder(
        builder: (context, box) {
          const icon = Icon(Icons.warning_amber, color: AppColors.warning);
          final message = Text(l10n.bootstrapRequired);
          final button = FilledButton(
            onPressed: sync.busy || !online ? null : () => _fullRefresh(context, ref),
            child: Text(l10n.fullRefresh),
          );
          final stacked = box.maxWidth < MediaQuery.textScalerOf(context).scale(_bootstrapRowMin);
          if (!stacked) {
            return Row(
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(child: message),
                const SizedBox(width: 8),
                button,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Expanded(child: message),
                ],
              ),
              const SizedBox(height: 12),
              Align(alignment: AlignmentDirectional.centerStart, child: button),
            ],
          );
        },
      ),
    );

    // Who you are, what still has to reach the server, and the tip about it.
    List<Widget> summary() => [
          header,
          if (!bootstrapReady) bootstrapCard,
          SectionHeader(l10n.quickActions),
          _SyncActions(sync: sync, online: online),
          TipCard(id: TipIds.homeSync, text: l10n.tipHomeSync),
        ];

    List<Widget> moduleCards() => [
          for (final module in modules)
            _ModuleCard(module: module, capabilities: profile!.capabilities(module), profile: profile),
        ];

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = AppLayout.forWidth(constraints.maxWidth);

          if (!layout.width.atLeastMedium) {
            // PHONE. No LayoutScope, no AdaptiveBody, no cap: this is the
            // list that ships today, child for child.
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const OfflineBanner(),
                ...summary(),
                if (profile != null && modules.isNotEmpty) SectionHeader(l10n.yourProgrammes),
                ...moduleCards(),
                if (profile != null && modules.isEmpty)
                  Padding(padding: const EdgeInsets.all(24), child: Text(l10n.moduleDisabled)),
              ],
            );
          }

          if (layout.width.isExpanded) {
            // TABLET LANDSCAPE. Identity and sync on the left, the programmes
            // — the reason the app is open — take the rest. A plain Row puts
            // the summary on the right under Directionality.rtl.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OfflineBanner(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: layout.listPaneWidth,
                        child: LayoutScope(
                          // A 400 px pane is compact, and that is the right
                          // answer: the hero, the two stat tiles and the
                          // Push/Pull pair render exactly as they do on the
                          // phone rather than being stretched.
                          layout: AppLayout.forWidth(layout.listPaneWidth),
                          child: ListView(
                            key: const ValueKey('home-summary-pane'),
                            padding: const EdgeInsets.only(bottom: 24),
                            children: summary(),
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, pane) => LayoutScope(
                            layout: AppLayout.forWidth(pane.maxWidth),
                            child: ListView(
                              key: const ValueKey('home-modules'),
                              padding: const EdgeInsets.only(bottom: 24),
                              children: [
                                if (profile != null && modules.isNotEmpty) SectionHeader(l10n.yourProgrammes),
                                if (profile != null && modules.isNotEmpty)
                                  _ModuleGrid(cards: moduleCards(), available: pane.maxWidth),
                                if (profile != null && modules.isEmpty)
                                  Padding(padding: const EdgeInsets.all(24), child: Text(l10n.moduleDisabled)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          // TABLET PORTRAIT / phone landscape. One column, capped, with the
          // gradient band still full bleed above it.
          return LayoutScope(
            layout: layout,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                const OfflineBanner(),
                header,
                AdaptiveBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!bootstrapReady) bootstrapCard,
                      SectionHeader(l10n.quickActions),
                      _SyncActions(sync: sync, online: online),
                      TipCard(id: TipIds.homeSync, text: l10n.tipHomeSync),
                      if (profile != null && modules.isNotEmpty) SectionHeader(l10n.yourProgrammes),
                      if (profile != null && modules.isNotEmpty)
                        // Stacked, not 2-up: a portrait tablet is 752 px wide
                        // inside the gutter, and two module cards there would
                        // squeeze the action tiles harder than the extra row
                        // of scrolling costs.
                        KeyedSubtree(key: const ValueKey('home-modules'), child: Column(children: moduleCards())),
                      if (profile != null && modules.isEmpty)
                        Padding(padding: const EdgeInsets.all(24), child: Text(l10n.moduleDisabled)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
          _PushPull(
            push: FilledButton.icon(
              onPressed: sync.busy || !online || sync.pendingCount == 0 ? null : () => _run(context, engine.push),
              icon: const Icon(Icons.upload),
              label: Text(l10n.pushNow),
            ),
            pull: OutlinedButton.icon(
              onPressed: sync.busy || !online ? null : () => _run(context, () => engine.pull()),
              icon: const Icon(Icons.download),
              label: Text(l10n.pullNow),
            ),
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
      if (hasAnalytics(module))
        _Action(l10n.analytics, Icons.query_stats_outlined, () => context.push(Routes.analytics(module))),
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
              final layout = LayoutScope.of(context);
              final tiles = [
                for (final action in actions)
                  ActionTile(icon: action.icon, label: action.label, onTap: action.onTap, color: accent),
              ];
              if (!layout.width.atLeastMedium) {
                // Verbatim: 3 or 4 square-ish tiles, exactly as today.
                final columns = constraints.maxWidth > 560 ? 4 : 3;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.95,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  children: tiles,
                );
              }
              // Extent-based: a 44 px glyph does not need a 300x316 slab.
              // The tile keeps a fixed size and the COUNT absorbs the width.
              return GridView(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: layout.actionTileExtent,
                  mainAxisExtent: _actionTileHeight(context, layout),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: tiles,
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

/// Push and Pull. Two Expandeds on the phone, where filling the row is the
/// point; content-sized from 600 px up, where a 600 px-wide "Pull" button is
/// just a bigger accident waiting to happen.
class _PushPull extends StatelessWidget {
  const _PushPull({required this.push, required this.pull});

  final Widget push;
  final Widget pull;

  @override
  Widget build(BuildContext context) {
    if (!LayoutScope.of(context).width.atLeastMedium) {
      return Row(
        children: [
          Expanded(child: push),
          const SizedBox(width: 8),
          Expanded(child: pull),
        ],
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(spacing: 12, runSpacing: 12, children: [push, pull]),
    );
  }
}

/// Lays the module cards out at up to [_maxCardExtent] each — 2-up on a 1280
/// px landscape tablet, one column anywhere narrower.
class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({required this.cards, required this.available});

  final List<Widget> cards;
  final double available;

  static const double _maxCardExtent = 620;
  static const double _gap = 16;

  @override
  Widget build(BuildContext context) {
    final columns = (available / _maxCardExtent).ceil().clamp(1, cards.length);
    if (columns == 1) return Column(children: cards);
    final width = (available - _gap * (columns - 1)) / columns;
    // Wrap, not GridView: module cards differ in height with the number of
    // actions the account may use, and a fixed cell would clip the tallest.
    return Wrap(
      spacing: _gap,
      children: [for (final card in cards) SizedBox(width: width, child: card)],
    );
  }
}

/// Height one [ActionTile] needs, with [AppLayout.actionTileHeight] as the
/// FLOOR rather than the answer.
///
/// A grid cell hands its child a TIGHT height, so anything the tile needs
/// beyond the cell is a RenderFlex overflow rather than a taller tile. The
/// token (116/124) is a pixel or six short of a two-line label even at scale
/// 1.0, and Arabic at 1.3x needs ~10 px more again, so the real height is
/// derived from ActionTile's own box model: a 1 px border top and bottom, 14
/// px of vertical padding each side, the icon circle, an 8 px gap and up to
/// two label lines at height 1.2. Kept next to the only grid that uses it;
/// test/layout/home_dash_layout_test.dart pins the no-overflow result at both
/// text scales.
double _actionTileHeight(BuildContext context, AppLayout layout) {
  final (circle, label) = switch (layout.width) {
    WidthClass.compact => (44.0, 12.5),
    WidthClass.medium => (52.0, 13.5),
    WidthClass.expanded => (56.0, 14.0),
  };
  final needed = 2 + 28 + circle + 8 + 2 * MediaQuery.textScalerOf(context).scale(label) * 1.2;
  return needed > layout.actionTileHeight ? needed : layout.actionTileHeight;
}
