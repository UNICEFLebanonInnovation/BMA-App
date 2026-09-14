import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/db/providers.dart';
import '../../core/models/user_profile.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import 'tips_content.dart';
import 'tips_controller.dart';

/// "Getting started" tour shown once per account (and tips version) on a
/// device, re-openable from Home and Settings.
class TipsWizardScreen extends ConsumerStatefulWidget {
  const TipsWizardScreen({super.key});

  @override
  ConsumerState<TipsWizardScreen> createState() => _TipsWizardScreenState();
}

class _TipsWizardScreenState extends ConsumerState<TipsWizardScreen> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _goTo(int i) =>
      _pages.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  Future<void> _finish() async {
    // Captured before the await: markSeen flips tipsPendingProvider.
    final firstRun = ref.read(tipsPendingProvider);
    final userId = ref.read(currentProfileProvider)?.id;
    if (userId != null) await ref.read(tipsControllerProvider.notifier).markSeen(userId);
    if (!mounted) return;
    if (firstRun || !context.canPop()) {
      context.go(Routes.home);
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(currentProfileProvider);
    final pages = tipPages(l10n, profile);
    final firstRun = ref.watch(tipsPendingProvider);
    final tablet = MediaQuery.sizeOf(context).shortestSide >= 600;
    final last = _index == pages.length - 1;

    return PopScope(
      // Page 0 pops only when pushed from Home/Settings; a first-run back
      // press on page 0 is a no-op (never silently marks the tips as seen).
      canPop: _index == 0 && !firstRun,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index > 0) _goTo(_index - 1);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.tipsTitle),
          actions: [
            if (firstRun && !last)
              TextButton(
                key: const ValueKey('tips-skip'),
                onPressed: _finish,
                child: Text(l10n.skip, style: const TextStyle(color: Colors.white)),
              ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  LinearProgressIndicator(value: (_index + 1) / pages.length, backgroundColor: AppColors.background),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          l10n.tipsStep(_index + 1, pages.length),
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    // Honours Directionality: RTL puts page 0 on the right.
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: pages.length,
                      onPageChanged: (i) => setState(() => _index = i),
                      itemBuilder: (_, i) => _TipPageView(page: pages[i], profile: profile, iconSize: tablet ? 112 : 72),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(
                      children: [
                        if (_index > 0)
                          OutlinedButton(
                            key: const ValueKey('tips-back'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(96, 52)),
                            onPressed: () => _goTo(_index - 1),
                            child: Text(l10n.back),
                          ),
                        if (_index > 0) const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            key: const ValueKey('tips-next'),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                            onPressed: last ? _finish : () => _goTo(_index + 1),
                            // arrow_forward has matchTextDirection: true, so it mirrors in RTL.
                            icon: Icon(last ? Icons.check : Icons.arrow_forward),
                            label: Text(last ? l10n.done : l10n.next),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TipPageView extends StatelessWidget {
  const _TipPageView({required this.page, required this.profile, required this.iconSize});

  final TipPage page;
  final UserProfile? profile;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      // Measured on the page width, before the 24 px padding, so the 720 px
      // tablet column qualifies for the side-by-side layout.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 700;
          final icon = ExcludeSemantics(
            child: Container(
              width: iconSize + 48,
              height: iconSize + 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary.withValues(alpha: 0.12),
              ),
              child: Icon(page.icon, size: iconSize, color: AppColors.primary),
            ),
          );
          final text = _PageText(page: page, profile: profile, align: wide ? TextAlign.start : TextAlign.center);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: wide
                ? Row(
                    key: const Key('tips-page-wide'),
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [icon, const SizedBox(width: 32), Expanded(child: text)],
                  )
                : Column(children: [icon, const SizedBox(height: 16), text]),
          );
        },
      ),
    );
  }
}

class _PageText extends StatelessWidget {
  const _PageText({required this.page, required this.profile, required this.align});

  final TipPage page;
  final UserProfile? profile;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final scopeParts = profile == null
        ? const <String>[]
        : [
            if (profile!.partner != null) profile!.partner!.name,
            if (profile!.center != null) profile!.center!.name,
            if (profile!.school != null) profile!.school!.name,
          ];
    return Column(
      crossAxisAlignment: align == TextAlign.start ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (page.kind == TipPageKind.welcome && profile != null) ...[
          Text(l10n.welcome(profile!.displayName), textAlign: align, style: textTheme.titleLarge),
          if (scopeParts.isNotEmpty)
            Text(scopeParts.join(' · '), textAlign: align, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
        ],
        Text(page.title, textAlign: align, style: textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(page.body, textAlign: align, style: textTheme.bodyLarge?.copyWith(height: 1.4)),
        if (page.kind == TipPageKind.data) ...[
          const SizedBox(height: 16),
          const _BootstrapStatusLine(),
        ],
      ],
    );
  }
}

/// Text-only footer of the "Your data" page: downloading / ready / missing.
/// Never a progress bar and never a button (the Home card offers Full refresh).
class _BootstrapStatusLine extends ConsumerWidget {
  const _BootstrapStatusLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final busy = ref.watch(syncEngineProvider.select((s) => s.busy));
    // valueOrNull: never rethrows if the lookup failed, the footer just stays hidden.
    final ready = ref.watch(bootstrapReadyProvider).valueOrNull;
    final String? text = busy
        ? l10n.loadingReference
        : ready == true
            ? l10n.tipsDataReady
            : ready == false
                ? l10n.bootstrapRequired
                : null;
    if (text == null) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(
          busy
              ? Icons.downloading
              : ready == true
                  ? Icons.check_circle_outline
                  : Icons.warning_amber_outlined,
          size: 18,
          color: ready == false && !busy ? AppColors.warning : AppColors.muted,
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
      ],
    );
  }
}
