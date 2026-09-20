import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/config/settings_controller.dart';
import '../../../core/db/entity_dao.dart';
import '../../../core/db/providers.dart';
import '../../../core/forms/reference_cache.dart';
import '../../../core/layout/adaptive.dart';
import '../../../core/models/form_schema.dart';
import '../../../core/models/reference_item.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/ui.dart';
import '../../../l10n/app_localizations.dart';
import '../analytics_models.dart';
import '../charts/bar_list_chart.dart';
import '../charts/chart_card.dart';
import '../charts/chart_palette.dart';
import '../charts/donut_chart.dart';
import '../charts/stacked_bar_chart.dart';
import '../nfe/nfe_analytics.dart' show AnalyticsLabels;
import '../widgets/filter_bar.dart';
import 'alp_registration_insights.dart';

/// The web platform's ALP registration dashboard ("Operational Insights"),
/// computed on the device: four headline figures, the learning-outcome block
/// and the eleven registration, household, inclusion and transition panels,
/// under the page's school / round / programme filters.
class AlpRegistrationInsightsScreen extends ConsumerStatefulWidget {
  const AlpRegistrationInsightsScreen({super.key});

  @override
  ConsumerState<AlpRegistrationInsightsScreen> createState() => _AlpRegistrationInsightsScreenState();
}

class _Loaded {
  const _Loaded({
    required this.source,
    required this.schools,
    required this.rounds,
    required this.programmes,
  });

  final AlpRegistrationSource source;
  final List<ReferenceItem> schools;
  final List<ReferenceItem> rounds;
  final List<ReferenceItem> programmes;
}

class _AlpRegistrationInsightsScreenState extends ConsumerState<AlpRegistrationInsightsScreen> {
  AlpRegistrationFilters _filters = AlpRegistrationFilters.none;
  final _memo = ComputeMemo<_Loaded, (AlpRegistrationFilters, String), AlpRegistrationInsights>();
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
        await dao.list(const RecordQuery(entity: AlpAnalyticsEntities.registration, limit: 50000));
    final gradings = await dao.list(const RecordQuery(entity: AlpAnalyticsEntities.grading, limit: 100000));
    final schools = await cache.ensure('schools');
    final rounds = await cache.ensure('rounds.alp');
    final programmes = await cache.ensure('alp_programs');
    final nationalities = await cache.ensure('nationalities');
    final disabilities = await cache.ensure('disabilities');
    final definitions = await cache.ensure('alp_grading_definitions');

    // The cash-support choices come from the registration form itself, so the
    // panel lists the programmes the platform offers rather than only the
    // ones this device happens to have seen.
    final schema = await ref.read(schemaProvider(AlpAnalyticsEntities.registration).future);
    final cashField = schema?.field('cash_support_programmes');
    final cashChoices = <(String, String)>[
      for (final ChoiceOption option in cashField?.choices ?? const <ChoiceOption>[])
        if (option.value.isNotEmpty) (option.value, option.labelFor(language)),
    ];

    List<ReferenceItem> sorted(Map<int, ReferenceItem> items) => items.values.toList()
      ..sort((a, b) => a.labelFor(language).toLowerCase().compareTo(b.labelFor(language).toLowerCase()));

    final now = DateTime.now();
    return _Loaded(
      source: AlpRegistrationSource(
        registrations: registrations,
        gradings: gradings,
        schools: schools,
        rounds: rounds,
        programmes: programmes,
        nationalities: nationalities,
        disabilities: disabilities,
        gradingDefinitions: {
          for (final item in definitions.values)
            item.id: GradingDefinition(
              id: item.id,
              material: item.name,
              minGrade: (item.extra['min_grade'] as num?)?.toInt() ?? 0,
              maxGrade: (item.extra['max_grade'] as num?)?.toInt() ?? 0,
            ),
        },
        cashSupportChoices: cashChoices,
        language: language,
        today: DateTime(now.year, now.month, now.day),
        roundCount: rounds.length,
        defaultSchoolId: profile?.school?.id,
        defaultPartnerId: profile?.partner?.id,
      ),
      schools: sorted(schools),
      rounds: sorted(rounds),
      programmes: sorted(programmes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dataVersion = ref.watch(dataVersionProvider);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.alpRegistrationInsights)),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: FutureBuilder<_Loaded>(
              future: _load(dataVersion, language),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(message: snapshot.error.toString(), icon: Icons.error_outline);
                }
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final loaded = snapshot.data!;
                final labels = AlpLabels(
                  base: AnalyticsLabels(
                    unknown: l10n.unknown,
                    male: l10n.male,
                    female: l10n.female,
                    other: l10n.sectionOther,
                  ),
                  notSpecified: l10n.notSpecified,
                  onTrack: l10n.bandOnTrack,
                  developing: l10n.bandDeveloping,
                  needsSupport: l10n.bandNeedsSupport,
                  improved: l10n.progressImproved,
                  stable: l10n.progressStable,
                  declined: l10n.progressDeclined,
                  movedFromEarlierRound: l10n.movedFromEarlierRound,
                  newInRound: l10n.newInRound,
                );
                final insights = _memo.of(
                  loaded,
                  (_filters, l10n.localeName),
                  () => computeAlpRegistrationInsights(loaded.source, _filters, labels: labels),
                );
                return AdaptiveBody(
                  gutter: false,
                  child: ListView(
                    key: const ValueKey('alp-reg-list'),
                    padding: const EdgeInsets.all(8),
                    children: [
                      SourceNote(l10n.offlineFiguresNote),
                      _Filters(
                        loaded: loaded,
                        filters: _filters,
                        onChanged: (next) => setState(() => _filters = next),
                      ),
                      const SizedBox(height: 4),
                      _Kpis(insights: insights),
                      const SizedBox(height: 4),
                      _LearningOutcomesCard(outcomes: insights.learningOutcomes),
                      SectionHeader(l10n.registrationsAndBeneficiaries),
                      _RegistrationCharts(insights: insights, labels: labels),
                      SectionHeader(l10n.householdInclusionTransition),
                      _HouseholdCharts(insights: insights, labels: labels),
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

class _Filters extends StatelessWidget {
  const _Filters({required this.loaded, required this.filters, required this.onChanged});

  final _Loaded loaded;
  final AlpRegistrationFilters filters;
  final ValueChanged<AlpRegistrationFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = loaded.source.language;
    return Card(
      key: const ValueKey('alp-reg-filters'),
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
                    key: const ValueKey('alp-reg-filters-reset'),
                    onPressed: () => onChanged(AlpRegistrationFilters.none),
                    child: Text(l10n.resetFilters),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            FilterBar(
              children: [
                FilterDropdown<int>(
                  key: const ValueKey('alp-reg-filter-school'),
                  label: l10n.selectSchool,
                  allLabel: l10n.allSchools,
                  value: filters.schoolId,
                  options: [for (final s in loaded.schools) (s.id, s.labelFor(language))],
                  onChanged: (v) => onChanged(filters.copyWith(schoolId: v, clearSchool: v == null)),
                ),
                FilterDropdown<int>(
                  key: const ValueKey('alp-reg-filter-round'),
                  label: l10n.selectRound,
                  allLabel: l10n.allRounds,
                  value: filters.roundId,
                  options: [for (final r in loaded.rounds) (r.id, r.labelFor(language))],
                  onChanged: (v) => onChanged(filters.copyWith(roundId: v, clearRound: v == null)),
                ),
                FilterDropdown<int>(
                  key: const ValueKey('alp-reg-filter-programme'),
                  label: l10n.programmeLabel,
                  allLabel: l10n.allProgrammes,
                  value: filters.programmeId,
                  options: [for (final p in loaded.programmes) (p.id, p.labelFor(language))],
                  onChanged: (v) => onChanged(filters.copyWith(programmeId: v, clearProgramme: v == null)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.insights});

  final AlpRegistrationInsights insights;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KpiGrid(
      key: const ValueKey('alp-reg-kpis'),
      tiles: [
        KpiTile(
          label: l10n.totalRegistrations,
          value: '${insights.totalRegistrations}',
          icon: Icons.people_outline,
        ),
        KpiTile(
          label: l10n.activeSchools,
          value: '${insights.activeSchools}',
          icon: Icons.school_outlined,
          color: AppColors.success,
        ),
        KpiTile(
          label: l10n.partners,
          value: '${insights.partners}',
          icon: Icons.handshake_outlined,
          color: AppColors.secondary,
        ),
        KpiTile(label: l10n.programRounds, value: '${insights.programRounds}', icon: Icons.event_repeat_outlined),
      ],
    );
  }
}

/// The learning-outcome block: four figures and three panels, in one card so
/// it reads as the section the web page makes of it.
class _LearningOutcomesCard extends StatelessWidget {
  const _LearningOutcomesCard({required this.outcomes});

  final LearningOutcomes outcomes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final average = outcomes.averageAchievement;
    return ChartCard(
      key: const ValueKey('chart-learning-outcomes'),
      title: l10n.learningOutcomes,
      subtitle: l10n.learningOutcomesHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KpiGrid(
            key: const ValueKey('alp-outcome-kpis'),
            tiles: [
              KpiTile(label: l10n.childrenAssessed, value: '${outcomes.assessedChildren}', icon: Icons.fact_check_outlined),
              KpiTile(
                label: l10n.averageAchievement,
                value: average == null ? '—' : '${percentText(average, 100)}%',
                icon: Icons.trending_up,
                color: AppColors.secondary,
              ),
              KpiTile(
                label: l10n.followUpAssessments,
                value: '${outcomes.childrenWithFollowUp}',
                icon: Icons.repeat,
                color: AppColors.warning,
              ),
              KpiTile(
                label: l10n.childrenImproving,
                value: '${outcomes.improvedChildren}',
                icon: Icons.arrow_upward,
                color: AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (outcomes.assessedChildren == 0)
            EmptyChart(message: l10n.noAssessments, icon: Icons.school_outlined)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                // Three panels abreast once the card can give each ~230 px;
                // stacked below that, which is every phone and a narrow pane.
                final columns = constraints.maxWidth >= 690 ? 3 : 1;
                final width = constraints.maxWidth / columns;
                final panels = <Widget>[
                  _OutcomePanel(
                    title: l10n.latestPerformance,
                    child: DonutChart(
                      items: outcomes.performanceBands,
                      colorOf: (_, item) => _bandColor(item.key),
                      centerLabel: l10n.childrenAssessed,
                    ),
                  ),
                  _OutcomePanel(
                    title: l10n.progressSinceFirst,
                    child: outcomes.childrenWithFollowUp == 0
                        ? EmptyChart(message: l10n.noDataForFilters, icon: Icons.repeat)
                        : DonutChart(
                            items: outcomes.progress,
                            colorOf: (_, item) => _bandColor(item.key),
                            centerLabel: l10n.followUpAssessments,
                          ),
                  ),
                  _OutcomePanel(
                    title: l10n.achievementBySubject,
                    child: outcomes.subjects.isEmpty
                        ? EmptyChart(message: l10n.noDataForFilters)
                        : BarListChart(
                            items: outcomes.subjects,
                            // Subjects are percentages, so the bars are scaled
                            // against 100 rather than against each other: a
                            // "best subject" at 40% must not look full.
                            maxValue: 100,
                            valueText: (item) => '${percentText(item.exact ?? item.count, 100)}%',
                            initialLimit: 6,
                            showAllLabel: l10n.showAll,
                            showLessLabel: l10n.showLess,
                          ),
                  ),
                ];
                return Wrap(
                  children: [for (final panel in panels) SizedBox(width: width, child: panel)],
                );
              },
            ),
        ],
      ),
    );
  }

  /// The bands and the progress split are ORDERED and carry meaning, so they
  /// wear the status colours rather than categorical slots.
  static Color _bandColor(String key) => switch (key) {
        'On track' || 'Improved' => ChartPalette.good,
        'Developing' || 'Stable' => ChartPalette.middling,
        _ => ChartPalette.poor,
      };
}

class _OutcomePanel extends StatelessWidget {
  const _OutcomePanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _RegistrationCharts extends StatelessWidget {
  const _RegistrationCharts({required this.insights, required this.labels});

  final AlpRegistrationInsights insights;
  final AlpLabels labels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget orEmpty(int total, Widget chart) => total == 0 ? EmptyChart(message: l10n.noDataForFilters) : chart;
    Widget bars(List<ChartItem> items) => orEmpty(
          totalOf(items),
          BarListChart(
            items: items,
            showShare: true,
            showAllLabel: l10n.showAll,
            showLessLabel: l10n.showLess,
          ),
        );

    return ChartGrid(
      tiles: [
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-gender'),
            title: l10n.genderDistribution,
            child: orEmpty(
              totalOf(insights.byGender),
              DonutChart(items: insights.byGender, colorOf: genderColor),
            ),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-gender-age'),
            title: l10n.genderAgeGroupDistribution,
            child: insights.genderByAgeGroup.isEmpty
                ? EmptyChart(message: l10n.noDataForFilters)
                : StackedBarListChart(
                    rows: insights.genderByAgeGroup,
                    series: [
                      for (var i = 0; i < insights.genderSeries.length; i++)
                        (
                          insights.genderSeries[i].$2,
                          genderColor(i, ChartItem(key: insights.genderSeries[i].$1, label: '', count: 0)),
                        ),
                    ],
                  ),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-nationality'),
            title: l10n.nationalityBreakdown,
            child: bars(insights.byNationality),
          ),
        ),
        ChartTile(
          wide: true,
          child: ChartCard(
            key: const ValueKey('chart-source'),
            title: l10n.sourceOfIdentification,
            child: bars(insights.bySource),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-round'),
            title: l10n.registrationsPerRound,
            child: bars(insights.byRound),
          ),
        ),
      ],
    );
  }
}

class _HouseholdCharts extends StatelessWidget {
  const _HouseholdCharts({required this.insights, required this.labels});

  final AlpRegistrationInsights insights;
  final AlpLabels labels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget bars(List<ChartItem> items, {bool share = true}) => totalOf(items) == 0
        ? EmptyChart(message: l10n.noDataForFilters)
        : BarListChart(
            items: items,
            showShare: share,
            showAllLabel: l10n.showAll,
            showLessLabel: l10n.showLess,
          );

    return ChartGrid(
      tiles: [
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-family-status'),
            title: l10n.familyStatus,
            child: totalOf(insights.familyStatus) == 0
                ? EmptyChart(message: l10n.noDataForFilters)
                : DonutChart(items: foldTail(insights.familyStatus, otherLabel: labels.base.other)),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-disability'),
            title: l10n.disabilityType,
            child: bars(insights.disabilityType),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-cash-support'),
            title: l10n.cashSupport,
            // Zero-count choices are kept, so the share of a total that
            // counts each programme once would mislead: plain counts here.
            child: bars(insights.cashSupport, share: false),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-referred'),
            title: l10n.referredToFormalEducation,
            child: totalOf(insights.referredToFormalEducation) == 0
                ? EmptyChart(message: l10n.noReferralRecords, icon: Icons.swap_horiz)
                : DonutChart(items: foldTail(insights.referredToFormalEducation, otherLabel: labels.base.other)),
          ),
        ),
        ChartTile(
          wide: true,
          child: ChartCard(
            key: const ValueKey('chart-moved-rounds'),
            title: l10n.childrenMovedBetweenRounds,
            child: insights.movedBetweenRounds.isEmpty
                ? EmptyChart(message: l10n.noDataForFilters)
                : StackedBarListChart(
                    rows: insights.movedBetweenRounds,
                    series: [
                      (l10n.movedFromEarlierRound, ChartPalette.categorical[4]),
                      (l10n.newInRound, ChartPalette.categorical[2]),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
