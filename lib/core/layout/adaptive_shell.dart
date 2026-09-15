// The persistent navigation rail, installed at `MaterialApp.router(builder:)`
// — ABOVE the Navigator.
//
// WHY HERE. A widget at the builder is painted once and stays put while pages
// push and pop underneath it, so the rail never slides in with a page
// transition (the tell that separates a tablet app from a stretched phone
// app). It needs ZERO edits to the route table: all 23 GoRoutes, the redirect
// and every push/pop call site are untouched. A ShellRoute would re-parent
// every route, render a rail beside Home's own module grid and change what
// `context.pop()` pops; `StatefulShellRoute.indexedStack` would additionally
// keep HomeShell mounted and break the `find.byType(HomeShell) findsNothing`
// assertions in tips_redirect_test.dart.
//
// NO SCAFFOLD IN HERE. `ScaffoldMessengerState` only presents a SnackBar in the
// ROOT registered Scaffold; a Scaffold above the Navigator would make every
// page's Scaffold non-root and re-anchor every `showMessage` to the window
// bottom, sliding under the rail. The shell is a plain Row — NavigationRail
// brings its own Material.
//
// THE TWO-THRESHOLD MODEL
//  * The SHELL reads WINDOW width (`MediaQuery.sizeOf`) to decide whether a
//    rail exists and how wide it is. It must: the rail CONSUMES width, so
//    deriving its existence from a pane-derived class would feed its own
//    presence back into the measurement.
//  * EVERYTHING BELOW reads the PANE width it was handed, through
//    `LayoutScope.of(context)` — never the window.
//  * TYPE SIZE AND CONTROL DENSITY follow the DEVICE (`shortestSide >= 640`),
//    not the box: a 16 px button label should not shrink because the button
//    sits in a 360 px pane, and it must not change when the tablet rotates. On
//    a 9" tablet `shortestSide` is 800 in both orientations, so the theme is
//    built once and rotation triggers no re-theme at all.
//
// ARITHMETIC ON THE TARGET HARDWARE
//  * 1280x800 landscape -> window >= 1200 -> extended rail 212 -> content 1067.
//  * 800x1280 portrait  -> window 800 < 1000 -> NO rail -> content 800.
//  * 412x915 phone      -> no rail -> content 412, byte-identical to today.
//  * 915x412 landscape  -> height 412 < 560 -> no rail -> content 915.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../auth/auth_controller.dart';
import '../sync/sync_engine.dart';
import '../theme/app_theme.dart';
import 'breakpoints.dart';
import 'current_module.dart';
import 'nav_destinations.dart';

enum RailMode { hidden, collapsed, extended }

/// Pre-app and modal routes the rail must not appear beside.
const _gateRoutes = {Routes.splash, Routes.login, Routes.setup, Routes.tips};

/// Whether the WINDOW could hold a rail at all, ignoring which route is open.
///
/// Split out from [railModeFor] because it is the only question the shell can
/// answer without listening to the router — and answering it first is what
/// lets the phone path return the page child with nothing wrapped around it.
bool railFitsWindow(Size window) =>
    window.width >= Breakpoints.railWindowMin && window.height >= Breakpoints.railMinHeight;

/// Whether a rail is shown for this window and location, and how wide.
///
/// Portrait deliberately gets none: 800 − 212 = 588 is too little for a
/// two-column form plus a rail, and portrait is the registration posture,
/// which wants the width for fields.
RailMode railModeFor(Size window, String location) {
  if (_gateRoutes.contains(location.split('?').first)) return RailMode.hidden;
  if (!railFitsWindow(window)) return RailMode.hidden;
  return window.width >= Breakpoints.railExtendedMin ? RailMode.extended : RailMode.collapsed;
}

/// Wraps every page: applies the device-class theme, and on a wide enough
/// window puts the navigation rail beside the Navigator.
class AdaptiveShell extends ConsumerStatefulWidget {
  const AdaptiveShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends ConsumerState<AdaptiveShell> {
  late final GoRouter _router = ref.read(appRouterProvider);

  /// The current location, republished to the rail only when it CHANGES.
  ///
  /// The shell listens to the router delegate rather than watching a provider
  /// because the rail has to react to `push`/`pop`/`replace`, which no provider
  /// sees. Seeded with the splash route — a gate route — so the very first
  /// frame, before the router has parsed anything, shows no rail.
  final ValueNotifier<String> _location = ValueNotifier<String>(Routes.splash);

  @override
  void initState() {
    super.initState();
    _router.routerDelegate.addListener(_onRoute);
    _onRoute();
  }

  @override
  void dispose() {
    _router.routerDelegate.removeListener(_onRoute);
    _location.dispose();
    super.dispose();
  }

  /// Republishes the location and keeps [currentModuleProvider] on the
  /// programme the location addresses, so the rail's module-scoped
  /// destinations still point somewhere sensible once you are on `/sync` or
  /// `/settings`, which carry no `:module` segment.
  ///
  /// BOTH WRITES ARE DEFERRED WHEN A FRAME IS IN FLIGHT. The delegate notifies
  /// from inside the Router's own `didChangeDependencies` on the first route,
  /// and the shell is the Router's ANCESTOR: marking it dirty there is the
  /// "setState() called during build" error, and writing to a provider there
  /// would mark the ProviderScope dirty during a build for the same reason. A
  /// rail tap, which is where responsiveness would actually be visible, fires
  /// this from an event handler with no frame in flight and takes the
  /// immediate path.
  void _onRoute() {
    final location = currentLocation(_router);
    final module = moduleOfLocation(location);
    void apply() {
      if (!mounted) return;
      _location.value = location;
      if (module != null && ref.read(currentModuleProvider) != module) {
        ref.read(currentModuleProvider.notifier).select(module);
      }
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      apply();
    } else {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    }
  }

  @override
  Widget build(BuildContext context) {
    // sizeOf, NEVER MediaQuery.of: the Android activity declares
    // windowSoftInputMode="adjustResize", so `of` would subscribe to viewInsets
    // and rebuild the whole app on every keystroke.
    final window = MediaQuery.sizeOf(context);
    final themed = Theme(
      data: AppTheme.cached(tablet: window.shortestSide >= Breakpoints.tabletShortestSide),
      child: widget.child,
    );

    // THE PHONE PATH, and the only branch a 412x915 or 915x412 device can
    // reach: the page child is returned untouched — no Row, no rail, not even
    // a listener on the location.
    if (!railFitsWindow(window)) return themed;

    // `themed` is CAPTURED, not rebuilt. This builder re-runs on every route
    // change so the gate routes can hide the rail, but it hands the same
    // widget instance back each time, and an identical widget short-circuits
    // Element.updateChild — the page subtree is not rebuilt.
    return ValueListenableBuilder<String>(
      valueListenable: _location,
      builder: (context, location, _) {
        final mode = railModeFor(window, location);
        if (mode == RailMode.hidden) return themed;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BmaNavigationRail(mode: mode, location: location),
            const VerticalDivider(width: 1),
            Expanded(child: themed),
          ],
        );
      },
    );
  }
}

/// The rail itself. Rebuilt on every route change (and on every sync-count
/// change) while the page beside it is not.
class BmaNavigationRail extends ConsumerWidget {
  const BmaNavigationRail({super.key, required this.mode, required this.location});

  final RailMode mode;

  /// Path of the page beside the rail, handed down by the shell rather than
  /// read back out of the router: the shell is the one thing that knows the
  /// location has settled.
  final String location;

  /// Vertical budget for the fixed chrome: the rail's top spacer, the module
  /// switcher and the two trailing actions.
  static const double _chromeHeight = 180;
  static const double _labelledDestination = 76;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(currentProfileProvider);
    final module = ref.watch(currentModuleProvider);
    final sync = ref.watch(syncEngineProvider);
    final extended = mode == RailMode.extended;

    final destinations = destinationsFor(profile, module, l10n);
    final trailing = trailingDestinationsFor(l10n);
    final selected = destinationIndexFor(destinations, location);
    final attention = sync.pendingCount + sync.attentionCount;
    final modules = profile?.enabledModules ?? const [];

    return SizedBox(
      width: extended ? railExtendedWidth : railCollapsedWidth,
      child: LayoutBuilder(
        builder: (context, box) {
          // Labels are dropped rather than overflowed on a short window — the
          // height gate allows 560, where seven labelled destinations plus the
          // chrome would not fit.
          final labelled =
              box.maxHeight >= _chromeHeight + destinations.length * _labelledDestination;
          return NavigationRail(
            key: const ValueKey('nav-rail'),
            extended: extended,
            minExtendedWidth: railExtendedWidth,
            labelType: extended || !labelled
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            selectedIndex: selected,
            leading: modules.length > 1 ? ModuleSwitcher(extended: extended) : null,
            destinations: railDestinations(destinations),
            onDestinationSelected: (index) =>
                goDestination(context, ref, destinations[index].location),
            // NOT wrapped in an Expanded: the rail's own destination list is
            // already inside one, and a second Expanded would split the height
            // in half and overflow a seven-destination rail at 800 px tall.
            // Without it the destinations keep the slack and this sits at the
            // bottom, which is the intent.
            trailing: Align(
              alignment: AlignmentDirectional.bottomCenter,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final spec in trailing)
                      RailAction(
                        key: ValueKey('nav-dest-${spec.key}'),
                        spec: spec,
                        extended: extended,
                        selected: destinationIndexFor([spec], location) != null,
                        badge: spec.key == 'sync' && attention > 0 ? '$attention' : null,
                        onTap: () => goDestination(context, ref, spec.location),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
