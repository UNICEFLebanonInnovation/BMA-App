import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/config/settings_controller.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/forms/reference_cache.dart';
import '../../core/layout/adaptive.dart';
import '../../core/layout/app_layout.dart';
import '../../core/models/entity_record.dart';
import '../../core/models/reference_item.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import 'facility_profile.dart';

/// Read-only profile of the NFE centre the account works at, with the figures
/// held on this device and shortcuts into the daily work.
class CenterProfileScreen extends ConsumerWidget {
  const CenterProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return _FacilityScaffold(
      title: l10n.centerProfile,
      module: BmaModule.mscc,
      emptyMessage: l10n.profileNoCenter,
      icon: Icons.apartment_outlined,
      source: ref.watch(accountCenterProvider),
      buildProfile: (cache, dao, item, language, labels) =>
          buildCenterProfile(cache: cache, dao: dao, center: item, language: language, labels: labels),
    );
  }
}

/// Profile of the ALP school, with the same facts plus the editable school
/// profile form the web platform has.
class SchoolProfileScreen extends ConsumerWidget {
  const SchoolProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return _FacilityScaffold(
      title: l10n.schoolProfile,
      module: BmaModule.alp,
      emptyMessage: l10n.profileNoSchool,
      icon: Icons.school_outlined,
      source: ref.watch(accountSchoolProvider),
      editEntity: Entities.alpSchoolProfile,
      buildProfile: (cache, dao, item, language, labels) =>
          buildSchoolProfile(cache: cache, dao: dao, school: item, language: language, labels: labels),
    );
  }
}

typedef _ProfileBuilder = Future<FacilityProfile> Function(
  ReferenceCache cache,
  EntityDao dao,
  ReferenceItem item,
  String language,
  FacilityLabels labels,
);

class _FacilityScaffold extends ConsumerWidget {
  const _FacilityScaffold({
    required this.title,
    required this.module,
    required this.emptyMessage,
    required this.icon,
    required this.source,
    required this.buildProfile,
    this.editEntity,
  });

  final String title;
  final BmaModule module;
  final String emptyMessage;
  final IconData icon;
  final AsyncValue<ReferenceItem?> source;
  final _ProfileBuilder buildProfile;

  /// Entity of the editable profile form, when the module has one.
  final String? editEntity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: source.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(message: e.toString(), icon: Icons.error_outline),
        data: (item) {
          if (item == null) {
            return EmptyState(message: emptyMessage, icon: icon);
          }
          return FutureBuilder<FacilityProfile>(
            future: buildProfile(
              ref.watch(referenceCacheProvider),
              ref.watch(entityDaoProvider),
              item,
              language,
              _labels(l10n),
            ),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return _ProfileBody(
                profile: snapshot.data!,
                module: module,
                icon: icon,
                editEntity: editEntity,
              );
            },
          );
        },
      ),
    );
  }

  static FacilityLabels _labels(AppLocalizations l10n) => FacilityLabels(
        partner: l10n.partner,
        governorate: l10n.governorate,
        district: l10n.district,
        cadaster: l10n.cadaster,
        type: l10n.facilityType,
        coordinates: l10n.coordinates,
        schoolNumber: l10n.schoolNumber,
        workingDays: l10n.workingDays,
        weekend: l10n.weekendLabel,
        bmaSchool: l10n.bmaSchool,
        yes: l10n.yes,
        no: l10n.no,
        notRecorded: l10n.notRecorded,
      );
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({
    required this.profile,
    required this.module,
    required this.icon,
    this.editEntity,
  });

  final FacilityProfile profile;
  final BmaModule module;
  final IconData icon;
  final String? editEntity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final hero = HeroHeader(
      title: profile.name,
      subtitle: profile.subtitle,
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: Colors.white.withValues(alpha: 0.18),
        child: Icon(icon, color: Colors.white),
      ),
      footer: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          StatusPill(
            key: const ValueKey('profile-status'),
            label: profile.active ? l10n.activeLabel : l10n.inactiveLabel,
            color: profile.active ? AppColors.success : AppColors.muted,
            icon: profile.active ? Icons.check_circle_outline : Icons.pause_circle_outline,
          ),
          for (final programme in profile.programmes)
            StatusPill(label: programme, color: AppColors.secondary, icon: Icons.school_outlined),
        ],
      ),
    );
    final stats = <Widget>[
      StatTile(
        label: l10n.registeredChildren,
        value: '${profile.registered}',
        icon: Icons.groups_outlined,
        onTap: () => context.push(Routes.registrations(module)),
      ),
      StatTile(
        label: l10n.attendanceDays,
        value: '${profile.attendanceDays}',
        icon: Icons.fact_check_outlined,
        color: AppColors.secondary,
        onTap: () => context.push(Routes.attendance(module)),
      ),
      StatTile(
        label: l10n.kpiPendingPush,
        value: '${profile.pending}',
        icon: Icons.cloud_upload_outlined,
        color: profile.pending > 0 ? AppColors.warning : AppColors.success,
        onTap: () => context.push(Routes.sync),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppLayout.forWidth(constraints.maxWidth);
        if (!layout.width.atLeastMedium) {
          // The phone tree, unchanged: no scope, no wrapper, no cap.
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const OfflineBanner(),
              hero,
              SectionHeader(l10n.atAGlance),
              StatRow(tiles: stats),
              SectionHeader(l10n.locationLabel),
              _FactsCard(facts: profile.facts),
              if (editEntity != null) _EditProfileCard(entity: editEntity!),
            ],
          );
        }
        final statsPane = Column(
          key: const ValueKey('profile-stats-pane'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(l10n.atAGlance),
            _StatBand(tiles: stats),
            if (editEntity != null) _EditProfileCard(entity: editEntity!),
          ],
        );
        final factsPane = Column(
          key: const ValueKey('profile-facts-pane'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(l10n.locationLabel),
            _FactsCard(facts: profile.facts),
          ],
        );
        return LayoutScope(
          layout: layout,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const OfflineBanner(),
              // The gradient band stays full bleed; HeroHeader caps its own
              // content and raises the title from the width class.
              hero,
              AdaptiveBody(
                child: layout.width.isExpanded
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Facts lead: they are the bulk of the page. The
                          // figures and the edit entry point sit in a fixed
                          // secondary column, which a plain Row mirrors to the
                          // right-hand side under Directionality.rtl.
                          Expanded(child: factsPane),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: layout.listPaneWidth,
                            child: LayoutScope(
                              layout: AppLayout.forWidth(layout.listPaneWidth),
                              child: statsPane,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [statsPane, factsPane],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The location/facts card. Splits into two columns once its own box is wide
/// enough to give each column a readable value area; below that it is the
/// single stacked column the phone has today.
class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.facts});

  final List<(String label, String value, IconData icon)> facts;

  /// A 2-up split needs ~260 px per column before the value area gets tighter
  /// than the phone's 412 - 24 - 32 - 132 - 8 = 216. At the expanded facts
  /// pane (574 px inside the card) each column is 275.
  static const double _splitAt = 520;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (facts.length < 4 || constraints.maxWidth < _splitAt) {
            return Column(children: [for (final (l, v, i) in facts) FactRow(label: l, value: v, icon: i)]);
          }
          final half = (facts.length + 1) ~/ 2;
          // 132 explicitly, not layout.labelColumnWidth: each column here is
          // roughly 280 px, where the expanded 200 token would leave under 80
          // px for the value. The token is for a full-width fact list.
          Widget column(Iterable<(String, String, IconData)> rows) => Column(
                children: [for (final (l, v, i) in rows) FactRow(label: l, value: v, icon: i, labelWidth: 132)],
              );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: column(facts.take(half))),
              const SizedBox(width: 24),
              Expanded(child: column(facts.skip(half))),
            ],
          );
        },
      ),
    );
  }
}

/// Three figures on one line that always fit.
///
/// [StatRow] is used verbatim at compact. At medium+ it pins each tile to
/// statTileWidth (260/280), and three of those plus the gaps need 796 px —
/// more than an 800 px portrait tablet has once the page gutter is paid, so
/// the row would overflow. This takes the token as a CEILING and falls back to
/// an equal share, which is the same layout wherever StatRow would have fitted.
class _StatBand extends StatelessWidget {
  const _StatBand({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutScope.of(context);
    if (!layout.width.atLeastMedium) return StatRow(tiles: tiles);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final n = tiles.length;
          final share = (constraints.maxWidth - 8 * (n - 1)) / n;
          final w = layout.statTileWidth < share ? layout.statTileWidth : share;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  SizedBox(width: w, child: tiles[i]),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Opens the editable profile form for modules that have one (ALP schools).
class _EditProfileCard extends ConsumerWidget {
  const _EditProfileCard({required this.entity});

  final String entity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.watch(dataVersionProvider);
    return FutureBuilder<List<EntityRecord>>(
      future: ref.watch(entityDaoProvider).list(RecordQuery(entity: entity, limit: 1)),
      builder: (context, snapshot) {
        final existing = (snapshot.data ?? const <EntityRecord>[]).firstOrNull;
        return AppCard(
          key: const ValueKey('profile-edit'),
          onTap: () => existing == null
              ? context.push(Routes.standaloneForm(entity))
              : context.push(Routes.editService(existing.uuid)),
          child: Row(
            children: [
              const Icon(Icons.edit_note_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.schoolProfile, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      existing == null ? l10n.addService : l10n.edit,
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (existing != null) SyncStateChip(existing.syncState, compact: true),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        );
      },
    );
  }
}
