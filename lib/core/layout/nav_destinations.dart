// What the navigation rail offers, how it decides what is selected, and the
// stack discipline it navigates with.
//
// The destination list MIRRORS `home_shell.dart`'s `_ModuleCard` action list
// (the same capability gates in the same order) so the rail and Home can never
// disagree about what an account may open. "Register new" is deliberately NOT
// here: it is an action on a list, not a place, and it lives as a labelled
// button in the Beneficiaries pane header.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../auth/auth_controller.dart';
import '../config/app_config.dart';
import '../models/user_profile.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'current_module.dart';

/// Width of the rail in each of its two visible modes.
///
/// The rail is given these widths explicitly by [BmaNavigationRail] rather
/// than letting it size itself: a [Row] hands its non-flexible children an
/// UNBOUNDED width, and the extended rail's leading and trailing rows need a
/// finite box to lay a label out in.
const double railCollapsedWidth = 72;
const double railExtendedWidth = 212;

/// One place the rail can take you.
@immutable
class NavDestinationSpec {
  const NavDestinationSpec({
    required this.key,
    required this.label,
    required this.icon,
    required this.location,
    this.alsoMatches = const <String>[],
  });

  /// Suffix of the destination's `ValueKey`: `nav-dest-<key>`.
  final String key;
  final String label;
  final IconData icon;

  /// Where a tap goes.
  final String location;

  /// Extra location prefixes that keep this destination highlighted, for the
  /// drill-downs that live on a different path than their parent list
  /// (`/record/<uuid>` belongs to Beneficiaries, `/teacher/<uuid>` to Teachers).
  final List<String> alsoMatches;

  List<String> get prefixes => [location, ...alsoMatches];
}

/// The main destinations, module-scoped and capability-gated.
///
/// Mirrors `home_shell.dart:293-309`: facility profile first (the "where am I"
/// of a programme), then beneficiaries, attendance, teacher attendance,
/// teachers, dashboard.
List<NavDestinationSpec> destinationsFor(
  UserProfile? profile,
  BmaModule module,
  AppLocalizations l10n,
) {
  final caps = profile?.capabilities(module) ?? ModuleCapabilities.none;
  return [
    NavDestinationSpec(
      key: 'home',
      label: l10n.home,
      icon: Icons.home_outlined,
      location: Routes.home,
    ),
    if (module == BmaModule.mscc && profile?.center != null)
      NavDestinationSpec(
        key: 'facility',
        label: l10n.centerProfile,
        icon: Icons.apartment_outlined,
        location: Routes.centerProfile,
      ),
    if (module == BmaModule.alp && profile?.school != null)
      NavDestinationSpec(
        key: 'facility',
        label: l10n.schoolProfile,
        icon: Icons.school_outlined,
        location: Routes.schoolProfile,
      ),
    NavDestinationSpec(
      key: 'beneficiaries',
      label: l10n.beneficiaries,
      icon: Icons.people_outline,
      location: Routes.registrations(module),
      // A child profile, a registration edit and a service form are all
      // "inside" the beneficiaries list as far as the rail is concerned.
      alsoMatches: const ['/record', '/service'],
    ),
    if (caps.canAttend)
      NavDestinationSpec(
        key: 'attendance',
        label: l10n.attendance,
        icon: Icons.fact_check_outlined,
        location: Routes.attendance(module),
      ),
    if (module == BmaModule.alp && caps.canAttend)
      NavDestinationSpec(
        key: 'teacher-attendance',
        label: l10n.teacherAttendance,
        icon: Icons.co_present_outlined,
        location: Routes.teacherAttendance(module),
      ),
    if (caps.canManageTeachers)
      NavDestinationSpec(
        key: 'teachers',
        label: l10n.teachers,
        icon: Icons.badge_outlined,
        location: Routes.teachers(module),
        alsoMatches: const ['/teacher'],
      ),
    NavDestinationSpec(
      key: 'dashboard',
      label: l10n.dashboard,
      icon: Icons.insights_outlined,
      location: Routes.dashboard(module),
    ),
  ];
}

/// Sync centre and Settings: app-wide, not programme-wide, so they sit at the
/// bottom of the rail instead of among the destinations.
List<NavDestinationSpec> trailingDestinationsFor(AppLocalizations l10n) => [
      NavDestinationSpec(
        key: 'sync',
        label: l10n.syncCenter,
        icon: Icons.cloud_sync_outlined,
        location: Routes.sync,
      ),
      NavDestinationSpec(
        key: 'settings',
        label: l10n.settings,
        icon: Icons.settings_outlined,
        location: Routes.settings,
      ),
    ];

/// The location the app is actually showing.
///
/// NOT `routerDelegate.currentConfiguration.uri`: that uri deliberately ignores
/// `ImperativeRouteMatch`es, so after `push('/registrations/mscc')` it still
/// reads `/home` — and a rail that believed it would push a second copy of the
/// page it is already standing on, growing the back stack on every tap. The
/// delegate's own `state` unwraps the imperative match and reports the leaf.
String currentLocation(GoRouter router) {
  final delegate = router.routerDelegate;
  // Before the first route is parsed there is no state to ask for.
  if (delegate.currentConfiguration.isEmpty) return Routes.splash;
  return delegate.state.matchedLocation;
}

/// Index of the destination [location] belongs to, by LONGEST-PREFIX match, or
/// null when nothing matches.
///
/// Longest-prefix, not first-match, because `/attendance/alp/teachers` is a
/// prefix-extension of `/attendance/alp` and teacher attendance has to win.
/// Returning null rather than 0 matters: an unmatched route renders the rail
/// with nothing highlighted instead of claiming you are on Home.
int? destinationIndexFor(List<NavDestinationSpec> destinations, String location) {
  final path = location.split('?').first;
  int? best;
  var bestLength = 0;
  for (var i = 0; i < destinations.length; i++) {
    for (final prefix in destinations[i].prefixes) {
      if (prefix.length <= bestLength) continue;
      if (path == prefix || path.startsWith('$prefix/')) {
        best = i;
        bestLength = prefix.length;
      }
    }
  }
  return best;
}

/// Navigates the rail, keeping the imperative stack at exactly `[Home]` or
/// `[Home, destination]`.
///
/// THIS IS THE PART THAT MUST NOT BE IMPROVISED. The rail is not itself in the
/// back stack, so the stack has to stay shallow by construction:
///  * UNWIND FIRST — everything a destination pushed on top of ITSELF (the
///    registration wizard, a child profile below `expanded`, a sync queue
///    item, a teacher form) comes off before the rail acts. Without this step
///    the two branches below both misfire: "to Home" pops a single level and
///    lands on the middle page, and rail-to-rail `replace`s that middle page,
///    leaving the stale destination underneath forever, so the stack deepens
///    by one on every drill-down for the rest of the session.
///  * to Home: pop the one remaining destination, and `go` when the bottom of
///    the stack is not Home at all (a deep link, where there is nothing to pop
///    back to);
///  * off Home: `push`, so the stack becomes depth 2;
///  * rail-to-rail: `replace`, which swaps the top and reuses the page key —
///    go_router 14.8.1 documents that as "the page key will be reused, this
///    will preserve the state and not run any page animation".
/// `go` would clear the imperative stack and make Android back exit the app;
/// a plain `push` everywhere would grow it without bound.
///
/// Neither `push` nor `replace` triggers `PopScope`, which is precisely why the
/// [unsavedWorkProvider] guard exists. `pop` DOES deliver
/// `onPopInvokedWithResult(didPop: true)`, which every `PopScope` in the app
/// returns from immediately, so the unwind cannot re-enter a confirm dialog.
Future<void> goDestination(BuildContext context, WidgetRef ref, String location) async {
  final router = ref.read(appRouterProvider);
  final delegate = router.routerDelegate;
  final here = currentLocation(router);

  final dirty = ref.read(unsavedWorkProvider);
  if (dirty != null) {
    // The rail is installed ABOVE the Navigator, so the rail's own context has
    // no Navigator to host a dialog in. The router's navigator does.
    final host = Navigator.maybeOf(context) != null ? context : delegate.navigatorKey.currentContext;
    if (host == null || !await confirmDialog(host, dirty)) return;
    // Someone navigated while the dialog was open: leave it to them.
    if (currentLocation(router) != here) return;
  }

  if (location == here) return;

  // STEP 1: back down to `[Home]` or `[Home, destination]`. The budget is the
  // stack depth, so a route that declines to come off (an `onExit` guard, a
  // pageless route) costs one wasted iteration instead of spinning forever.
  var budget = delegate.currentConfiguration.matches.length;
  while (budget-- > 0 && delegate.currentConfiguration.matches.length > 2 && router.canPop()) {
    router.pop();
  }
  // The unwind can have arrived on its own: tapping Beneficiaries from the
  // registration wizard is a "go back to the list", not a re-push of it.
  final at = currentLocation(router);
  if (location == at) return;

  if (location == Routes.home) {
    if (at != Routes.home && router.canPop()) router.pop();
    if (currentLocation(router) != Routes.home) router.go(Routes.home);
  } else if (at == Routes.home) {
    router.push(location);
  } else {
    router.replace(location);
  }
}

/// The rail's main destinations. The `ValueKey` goes on the ICON, not the
/// label: the label is absent from the tree when `labelType` is `none`, the
/// icon is there in all three label types.
List<NavigationRailDestination> railDestinations(List<NavDestinationSpec> specs) => [
      for (final spec in specs)
        NavigationRailDestination(
          icon: Icon(spec.icon, key: ValueKey('nav-dest-${spec.key}')),
          label: Text(spec.label),
        ),
    ];

/// One bottom-of-the-rail action (Sync centre, Settings).
///
/// Not a [NavigationRailDestination]: those live in the rail's own index space
/// and would make `selectedIndex` mean two different things.
class RailAction extends StatelessWidget {
  const RailAction({
    super.key,
    required this.spec,
    required this.extended,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final NavDestinationSpec spec;
  final bool extended;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.muted;
    final icon = Badge(
      isLabelVisible: badge != null,
      label: Text(badge ?? ''),
      child: Icon(spec.icon, color: color),
    );
    if (!extended) {
      // Semantics, not a Tooltip: the rail is installed ABOVE the Navigator,
      // so there is no Overlay ancestor for a tooltip to float in and building
      // one throws. The label is still announced to a screen reader.
      return Semantics(
        label: spec.label,
        button: true,
        child: IconButton(onPressed: onTap, icon: icon),
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.controlRadius,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                spec.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rail's `leading`, shown ONLY when the account has more than one
/// programme enabled — with one module (the common Makani case) a switcher is
/// dead chrome, so it is omitted rather than disabled.
///
/// The accent dot + name matches `_ModuleCard`'s header on Home.
class ModuleSwitcher extends ConsumerWidget {
  const ModuleSwitcher({super.key, required this.extended});

  final bool extended;

  static (String, Color) present(BmaModule module, AppLocalizations l10n) => switch (module) {
        BmaModule.mscc => (l10n.mscc, AppColors.primary),
        BmaModule.alp => (l10n.alp, AppColors.secondary),
        BmaModule.clm => (l10n.clm, AppColors.success),
      };

  /// Asks which programme to work in, as a CENTRED DIALOG on the router's
  /// navigator — not as a menu anchored to the switcher.
  ///
  /// THE RAIL HAS NO SURFACE TO DRAW A POPUP ON. It is installed ABOVE the
  /// Navigator, so the app's only `Overlay` is the one the page navigator owns
  /// and it begins AFTER the rail and its 1 px divider
  /// (`Offset(213, 0)`, `1067x800` on the target device). An anchored
  /// `showMenu` cannot reach back over the rail, and the anchor arithmetic
  /// cannot express that it wants to: `_PopupMenuRouteLayout` clamps the menu
  /// 8 px inside the overlay, so the old window-coordinate anchor AND an
  /// overlay-coordinate one both put the first item at `Rect(221, 56)` in
  /// English and at a right edge of `1059` in Arabic — measured identical,
  /// which is why merely re-expressing the coordinates fixes nothing.
  ///
  /// A dialog has no anchor to get wrong, it mirrors under `Directionality`
  /// for free, and it is the modality this app already uses for pickers at
  /// this width: `AppLayout.dialogPickers` is true from `medium` up and the
  /// rail exists only from 1000 px.
  Future<void> _pick(BuildContext context, WidgetRef ref, List<BmaModule> modules) async {
    final l10n = AppLocalizations.of(context);
    final host = ref.read(appRouterProvider).routerDelegate.navigatorKey.currentContext;
    if (host == null) return;
    final chosen = await showDialog<BmaModule>(
      context: host,
      builder: (dialogContext) => SimpleDialog(
        key: const ValueKey('nav-module-menu'),
        title: Text(l10n.switchModule),
        children: [
          for (final module in modules)
            SimpleDialogOption(
              key: ValueKey('nav-module-option-${module.name}'),
              onPressed: () => Navigator.of(dialogContext).pop(module),
              child: Row(
                children: [
                  _Dot(color: present(module, l10n).$2),
                  const SizedBox(width: 10),
                  Expanded(child: Text(present(module, l10n).$1)),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen != null) ref.read(currentModuleProvider.notifier).select(chosen);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final modules = ref.watch(currentProfileProvider)?.enabledModules ?? const <BmaModule>[];
    final current = ref.watch(currentModuleProvider);
    final (name, accent) = present(current, l10n);

    return Semantics(
      label: l10n.switchModule,
      button: true,
      child: InkWell(
        key: const ValueKey('nav-module-switch'),
        onTap: () => _pick(context, ref, modules),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
          child: extended
              ? Row(
                  children: [
                    _Dot(color: accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const Icon(Icons.expand_more, size: 18, color: AppColors.muted),
                  ],
                )
              : _Dot(color: accent),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
