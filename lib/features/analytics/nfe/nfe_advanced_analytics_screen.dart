import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/settings_controller.dart';
import '../../../core/db/entity_dao.dart';
import '../../../core/db/providers.dart';
import '../../../core/forms/reference_cache.dart';
import '../../../core/layout/adaptive.dart';
import '../../../core/models/reference_item.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../l10n/app_localizations.dart';
import '../analytics_models.dart';
import '../charts/bar_list_chart.dart';
import '../charts/chart_card.dart';
import '../charts/chart_palette.dart';
import '../charts/crosstab_table.dart';
import '../charts/donut_chart.dart';
import '../charts/trend_line_chart.dart';
import '../widgets/filter_bar.dart';
import 'nfe_analytics.dart';

/// The web platform's Advanced Analytics page, computed on the device: five
/// headline figures, the daily registration trend, six breakdowns and the
/// programme × age-group cross-tab, under the same filters the analytics API
/// accepts (date range, partner, centre, programme, and — behind "More
/// filters" — nationality, gender and an age band).
///
/// The records are read once per data version; changing a filter recomputes
/// in memory, so the page answers a tap without another SQLite round trip.
class NfeAdvancedAnalyticsScreen extends ConsumerStatefulWidget {
  const NfeAdvancedAnalyticsScreen({super.key});

  @override
  ConsumerState<NfeAdvancedAnalyticsScreen> createState() => _NfeAdvancedAnalyticsScreenState();
}

/// The reference lists the filter controls offer, loaded with the records.
class _Loaded {
  const _Loaded({
    required this.source,
    required this.partners,
    required this.centers,
    required this.programmes,
    required this.nationalities,
    required this.genders,
  });

  final NfeAnalyticsSource source;
  final List<ReferenceItem> partners;
  final List<ReferenceItem> centers;

  /// `(value, label)` of the education programme choice list.
  final List<(String, String)> programmes;
  final List<ReferenceItem> nationalities;
  final List<(String, String)> genders;
}

class _NfeAdvancedAnalyticsScreenState extends ConsumerState<NfeAdvancedAnalyticsScreen> {
  AnalyticsFilters _filters = AnalyticsFilters.none;
  final _memo = ComputeMemo<_Loaded, (AnalyticsFilters, String), NfeAnalytics>();
  bool _moreFilters = false;
  Future<_Loaded>? _future;
  String? _loadKey;

  Future<_Loaded> _load(int dataVersion, String language) {
    final key = '$dataVersion|$language';
    if (_future == null || key != _loadKey) {
      _loadKey = key;
      _future = _read(language);
    }
    return _future!;
  }

  Future<_Loaded> _read(String language) async {
    final dao = ref.read(entityDaoProvider);
    final cache = ref.read(referenceCacheProvider);
    final profile = ref.read(currentProfileProvider);
    final registrations =
        await dao.list(const RecordQuery(entity: NfeAnalyticsEntities.registration, limit: 50000));
    final services =
        await dao.list(const RecordQuery(entity: NfeAnalyticsEntities.educationService, limit: 100000));
    final teachers = await dao.list(const RecordQuery(entity: NfeAnalyticsEntities.teacher, limit: 10000));
    final centers = await cache.ensure('centers');
    final partners = await cache.ensure('partners');
    final nationalities = await cache.ensure('nationalities');
    final programmeChoices = await cache.choices('mscc.education_service.education_program');
    final genderChoices = await cache.choices('child.gender');

    // Only partners the device knows through a centre or a record: the
    // bootstrap's partner list is the whole platform, which a centre user has
    // no use for.
    final partnerIds = <int>{
      for (final c in centers.values)
        if (c.extra['partner_id'] is num) (c.extra['partner_id'] as num).toInt(),
      for (final r in registrations)
        if (r.data['partner'] is num) (r.data['partner'] as num).toInt(),
      if (profile?.partner != null) profile!.partner!.id,
    };
    final partnerList = [for (final id in partnerIds) if (partners[id] != null) partners[id]!]
      ..sort((a, b) => a.labelFor(language).toLowerCase().compareTo(b.labelFor(language).toLowerCase()));
    final centerList = centers.values.toList()
      ..sort((a, b) => a.labelFor(language).toLowerCase().compareTo(b.labelFor(language).toLowerCase()));
    final nationalityList = nationalities.values.toList()
      ..sort((a, b) => a.labelFor(language).toLowerCase().compareTo(b.labelFor(language).toLowerCase()));

    final now = DateTime.now();
    return _Loaded(
      source: NfeAnalyticsSource(
        registrations: registrations,
        educationServices: services,
        teachers: teachers,
        centers: centers,
        partners: partners,
        nationalities: nationalities,
        programmeLabels: {for (final c in programmeChoices) if (c.value.isNotEmpty) c.value: c.labelFor(language)},
        language: language,
        today: DateTime(now.year, now.month, now.day),
        defaultPartnerId: profile?.partner?.id,
        defaultCenterId: profile?.center?.id,
      ),
      partners: partnerList,
      centers: centerList,
      programmes: [for (final c in programmeChoices) if (c.value.isNotEmpty) (c.value, c.labelFor(language))],
      nationalities: nationalityList,
      genders: [for (final c in genderChoices) if (c.value.isNotEmpty) (c.value, c.labelFor(language))],
    );
  }

  void _update(AnalyticsFilters next) => setState(() => _filters = next);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dataVersion = ref.watch(dataVersionProvider);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    final future = _load(dataVersion, language);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.advancedAnalytics)),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: FutureBuilder<_Loaded>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(message: snapshot.error.toString(), icon: Icons.error_outline);
                }
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final loaded = snapshot.data!;
                final labels = AnalyticsLabels(
                  unknown: l10n.unknown,
                  male: l10n.male,
                  female: l10n.female,
                  other: l10n.sectionOther,
                );
                final analytics = _memo.of(
                  loaded,
                  (_filters, l10n.localeName),
                  () => computeNfeAnalytics(loaded.source, _filters, labels: labels),
                );
                // gutter: false — the ListView's own 8 px IS the gutter, as on
                // the offline dashboard, so six KPI tiles still fit at 1280.
                return AdaptiveBody(
                  gutter: false,
                  child: ListView(
                    key: const ValueKey('nfe-analytics-list'),
                    padding: const EdgeInsets.all(8),
                    children: [
                      SourceNote(l10n.offlineFiguresNote),
                      _FiltersCard(
                        loaded: loaded,
                        filters: _filters,
                        more: _moreFilters,
                        onToggleMore: () => setState(() => _moreFilters = !_moreFilters),
                        onChanged: _update,
                      ),
                      const SizedBox(height: 4),
                      _Kpis(summary: analytics.summary),
                      const SizedBox(height: 4),
                      _Charts(analytics: analytics, labels: labels),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltersCard extends StatelessWidget {
  const _FiltersCard({
    required this.loaded,
    required this.filters,
    required this.more,
    required this.onToggleMore,
    required this.onChanged,
  });

  final _Loaded loaded;
  final AnalyticsFilters filters;
  final bool more;
  final VoidCallback onToggleMore;
  final ValueChanged<AnalyticsFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = loaded.source.language;
    // Centres of the chosen partner only, once a partner is picked.
    final centers = filters.partnerId == null
        ? loaded.centers
        : loaded.centers.where((c) => (c.extra['partner_id'] as num?)?.toInt() == filters.partnerId).toList();

    return Card(
      key: const ValueKey('nfe-filters'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_alt_outlined, size: 18, color: AppColors.muted),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.filters, style: Theme.of(context).textTheme.titleSmall)),
                if (!filters.isEmpty)
                  TextButton(
                    key: const ValueKey('nfe-filters-reset'),
                    onPressed: () => onChanged(AnalyticsFilters.none),
                    child: Text(l10n.resetFilters),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            FilterBar(
              trailing: TextButton.icon(
                key: const ValueKey('nfe-more-filters'),
                onPressed: onToggleMore,
                icon: Icon(more ? Icons.expand_less : Icons.expand_more, size: 18),
                label: Text(l10n.moreFilters),
              ),
              children: [
                DateRangeFilter(
                  fromLabel: l10n.dateFrom,
                  toLabel: l10n.dateTo,
                  anyLabel: l10n.anyDate,
                  from: filters.dateFrom,
                  to: filters.dateTo,
                  onChanged: (from, to) => onChanged(filters.copyWith(
                    dateFrom: from,
                    clearDateFrom: from == null,
                    dateTo: to,
                    clearDateTo: to == null,
                  )),
                ),
                FilterDropdown<int>(
                  key: const ValueKey('nfe-filter-partner'),
                  label: l10n.partner,
                  allLabel: l10n.allPartners,
                  value: filters.partnerId,
                  options: [for (final p in loaded.partners) (p.id, p.labelFor(language))],
                  // A new partner invalidates the centre: it may belong elsewhere.
                  onChanged: (v) => onChanged(filters.copyWith(
                    partnerId: v,
                    clearPartner: v == null,
                    clearCenter: v != filters.partnerId,
                  )),
                ),
                FilterDropdown<int>(
                  key: const ValueKey('nfe-filter-center'),
                  label: l10n.selectCenter,
                  allLabel: l10n.allCenters,
                  value: filters.centerId,
                  options: [for (final c in centers) (c.id, c.labelFor(language))],
                  onChanged: (v) => onChanged(filters.copyWith(centerId: v, clearCenter: v == null)),
                ),
                FilterDropdown<String>(
                  key: const ValueKey('nfe-filter-programme'),
                  label: l10n.programmeLabel,
                  allLabel: l10n.allProgrammes,
                  value: filters.programme,
                  options: loaded.programmes,
                  onChanged: (v) => onChanged(filters.copyWith(programme: v, clearProgramme: v == null)),
                ),
                if (more) ...[
                  FilterDropdown<int>(
                    key: const ValueKey('nfe-filter-nationality'),
                    label: l10n.nationality,
                    allLabel: l10n.allNationalities,
                    value: filters.nationalityId,
                    options: [for (final n in loaded.nationalities) (n.id, n.labelFor(language))],
                    onChanged: (v) => onChanged(filters.copyWith(nationalityId: v, clearNationality: v == null)),
                  ),
                  FilterDropdown<String>(
                    key: const ValueKey('nfe-filter-gender'),
                    label: l10n.gender,
                    allLabel: l10n.allGenders,
                    value: filters.gender,
                    options: loaded.genders,
                    onChanged: (v) => onChanged(filters.copyWith(gender: v, clearGender: v == null)),
                  ),
                  NumberFilterField(
                    key: const ValueKey('nfe-filter-age-min'),
                    label: l10n.ageMin,
                    value: filters.ageMin,
                    onChanged: (v) => onChanged(filters.copyWith(ageMin: v, clearAgeMin: v == null)),
                  ),
                  NumberFilterField(
                    key: const ValueKey('nfe-filter-age-max'),
                    label: l10n.ageMax,
                    value: filters.ageMax,
                    onChanged: (v) => onChanged(filters.copyWith(ageMax: v, clearAgeMax: v == null)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.summary});

  final NfeSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KpiGrid(
      key: const ValueKey('nfe-kpis'),
      tiles: [
        KpiTile(label: l10n.totalRegistrations, value: '${summary.totalRegistrations}', icon: Icons.people_outline),
        KpiTile(
          label: l10n.teachers,
          value: '${summary.totalTeachers}',
          icon: Icons.badge_outlined,
          color: AppColors.secondary,
        ),
        KpiTile(label: l10n.partners, value: '${summary.partners}', icon: Icons.handshake_outlined),
        KpiTile(label: l10n.centers, value: '${summary.centers}', icon: Icons.apartment_outlined),
        KpiTile(
          label: l10n.programmes,
          value: '${summary.programmes}',
          icon: Icons.school_outlined,
          color: AppColors.success,
        ),
      ],
    );
  }
}

class _Charts extends StatelessWidget {
  const _Charts({required this.analytics, required this.labels});

  final NfeAnalytics analytics;
  final AnalyticsLabels labels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final a = analytics;
    Widget orEmpty(List<ChartItem> items, Widget chart) =>
        totalOf(items) == 0 ? EmptyChart(message: l10n.noDataForFilters) : chart;
    Widget bars(List<ChartItem> items, {bool share = true}) => orEmpty(
          items,
          BarListChart(
            items: items,
            showShare: share,
            showAllLabel: l10n.showAll,
            showLessLabel: l10n.showLess,
          ),
        );
    Widget donut(List<ChartItem> items) =>
        orEmpty(items, DonutChart(items: foldTail(items, otherLabel: labels.other), colorOf: genderColor));

    return ChartGrid(
      tiles: [
        ChartTile(
          wide: true,
          child: ChartCard(
            key: const ValueKey('chart-trend'),
            title: l10n.registrationTrend,
            subtitle: a.trendIsWindow ? l10n.dailyRegistrationsLastDays(a.trendDays) : l10n.dailyRegistrations,
            child: a.summary.totalRegistrations == 0
                ? EmptyChart(message: l10n.noDataForFilters, icon: Icons.show_chart)
                : TrendLineChart(
                    points: a.trend,
                    detailText: (p) =>
                        '${_date(context, p.day)} · ${l10n.registrationsCount(p.count)}',
                  ),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-center'),
            title: l10n.registrationsByCenter,
            child: bars(a.byCenter),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-gender'),
            title: l10n.genderDistribution,
            child: donut(a.byGender),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-nationality'),
            title: l10n.nationalityDistribution,
            child: bars(a.byNationality),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-teacher-gender'),
            title: l10n.teacherGenderDistribution,
            child: donut(a.teachersBySex),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-teacher-nationality'),
            title: l10n.teacherNationalityDistribution,
            child: bars(a.teachersByNationality),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-teacher-center'),
            title: l10n.teachersByCenter,
            child: bars(a.teachersByCenter),
          ),
        ),
        ChartTile(
          wide: true,
          child: ChartCard(
            key: const ValueKey('chart-crosstab'),
            title: l10n.programmeVsAgeGroup,
            subtitle: l10n.programmeVsAgeGroupHint,
            child: a.programmeByAgeGroup.isEmpty
                ? EmptyChart(message: l10n.noDataForFilters, icon: Icons.grid_on_outlined)
                : CrosstabTable(
                    crosstab: a.programmeByAgeGroup,
                    rowHeader: l10n.programmeLabel,
                    columnHeader: l10n.ageGroup,
                    totalLabel: l10n.total,
                  ),
          ),
        ),
      ],
    );
  }

  static String _date(BuildContext context, DateTime day) =>
      MaterialLocalizations.of(context).formatMediumDate(day);
}
