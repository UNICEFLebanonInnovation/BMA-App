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
import '../nfe/nfe_analytics.dart' show AnalyticsLabels;
import '../widgets/filter_bar.dart';
import 'alp_registration_insights.dart' show AlpAnalyticsEntities;
import 'alp_teacher_insights.dart';

/// The web platform's ALP teacher dashboard, computed on the device: six
/// workforce indicators, five coverage and demographic panels and five
/// teaching-capacity panels, under the page's school / round filters.
class AlpTeacherDashboardScreen extends ConsumerStatefulWidget {
  const AlpTeacherDashboardScreen({super.key});

  @override
  ConsumerState<AlpTeacherDashboardScreen> createState() => _AlpTeacherDashboardScreenState();
}

class _Loaded {
  const _Loaded({required this.source, required this.schools, required this.rounds});

  final AlpTeacherSource source;
  final List<ReferenceItem> schools;
  final List<ReferenceItem> rounds;
}

class _AlpTeacherDashboardScreenState extends ConsumerState<AlpTeacherDashboardScreen> {
  AlpTeacherFilters _filters = AlpTeacherFilters.none;
  final _memo = ComputeMemo<_Loaded, (AlpTeacherFilters, String), AlpTeacherInsights>();
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
    final teachers = await dao.list(const RecordQuery(entity: AlpAnalyticsEntities.teacher, limit: 20000));
    final schools = await cache.ensure('schools');
    final rounds = await cache.ensure('rounds.alp');
    final nationalities = await cache.ensure('nationalities');
    final trainings = await cache.ensure('trainings');

    // The raw values the server stores (`arabic`, `ALP only`, `yes`) are not
    // labels; the form schema already carries the wording the website shows.
    final schema = await ref.read(schemaProvider(AlpAnalyticsEntities.teacher).future);
    Map<String, String> labelsOf(String field) => {
          for (final ChoiceOption option in schema?.field(field)?.choices ?? const <ChoiceOption>[])
            if (option.value.isNotEmpty) option.value: option.labelFor(language),
        };

    List<ReferenceItem> sorted(Map<int, ReferenceItem> items) => items.values.toList()
      ..sort((a, b) => a.labelFor(language).toLowerCase().compareTo(b.labelFor(language).toLowerCase()));

    return _Loaded(
      source: AlpTeacherSource(
        teachers: teachers,
        schools: schools,
        rounds: rounds,
        nationalities: nationalities,
        trainings: trainings,
        choiceLabels: {
          'subjects_provided': labelsOf('subjects_provided'),
          'registration_level': labelsOf('registration_level'),
          'teacher_assignment': labelsOf('teacher_assignment'),
          'extra_coaching': labelsOf('extra_coaching'),
        },
        language: language,
        defaultSchoolId: profile?.school?.id,
      ),
      schools: sorted(schools),
      rounds: sorted(rounds),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dataVersion = ref.watch(dataVersionProvider);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.alpTeacherDashboard)),
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
                final labels = AlpTeacherLabels(
                  base: AnalyticsLabels(
                    unknown: l10n.unknown,
                    male: l10n.male,
                    female: l10n.female,
                    other: l10n.sectionOther,
                  ),
                  notSpecified: l10n.notSpecified,
                  alpHours: l10n.alpHours,
                  privateSchoolHours: l10n.privateSchoolHours,
                );
                final insights = _memo.of(
                  loaded,
                  (_filters, l10n.localeName),
                  () => computeAlpTeacherInsights(loaded.source, _filters, labels: labels),
                );
                return AdaptiveBody(
                  gutter: false,
                  child: ListView(
                    key: const ValueKey('alp-teacher-list'),
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
                      if (insights.total == 0)
                        Card(
                          key: const ValueKey('alp-teacher-empty'),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: EmptyChart(message: l10n.noTeachersForFilters, icon: Icons.badge_outlined),
                          ),
                        )
                      else ...[
                        SectionHeader(l10n.coverageAndDemographics),
                        _CoverageCharts(insights: insights, labels: labels),
                        SectionHeader(l10n.teachingCapacityDevelopment),
                        _CapacityCharts(insights: insights, labels: labels),
                      ],
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
  final AlpTeacherFilters filters;
  final ValueChanged<AlpTeacherFilters> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = loaded.source.language;
    return Card(
      key: const ValueKey('alp-teacher-filters'),
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
                    key: const ValueKey('alp-teacher-filters-reset'),
                    onPressed: () => onChanged(AlpTeacherFilters.none),
                    child: Text(l10n.resetFilters),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            FilterBar(
              children: [
                FilterDropdown<int>(
                  key: const ValueKey('alp-teacher-filter-school'),
                  label: l10n.selectSchool,
                  allLabel: l10n.allSchools,
                  value: filters.schoolId,
                  options: [for (final s in loaded.schools) (s.id, s.labelFor(language))],
                  onChanged: (v) => onChanged(filters.copyWith(schoolId: v, clearSchool: v == null)),
                ),
                FilterDropdown<int>(
                  key: const ValueKey('alp-teacher-filter-round'),
                  label: l10n.selectRound,
                  allLabel: l10n.allRounds,
                  value: filters.roundId,
                  options: [for (final r in loaded.rounds) (r.id, r.labelFor(language))],
                  onChanged: (v) => onChanged(filters.copyWith(roundId: v, clearRound: v == null)),
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

  final AlpTeacherInsights insights;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String number(double value) => value == value.roundToDouble() ? value.toInt().toString() : value.toString();
    return KpiGrid(
      key: const ValueKey('alp-teacher-kpis'),
      tiles: [
        KpiTile(label: l10n.totalTeachers, value: '${insights.total}', icon: Icons.badge_outlined),
        KpiTile(
          label: l10n.activeSchools,
          value: '${insights.schools}',
          icon: Icons.school_outlined,
          color: AppColors.success,
        ),
        KpiTile(
          label: l10n.teachersTrained,
          value: '${insights.trained}',
          icon: Icons.workspace_premium_outlined,
          color: AppColors.warning,
          caption: l10n.teachersTrainedShare(number(insights.trainedPercent)),
        ),
        KpiTile(
          label: l10n.averageExperience,
          value: number(insights.averageExperience),
          icon: Icons.timeline,
          caption: l10n.yearsUnit,
        ),
        KpiTile(
          label: l10n.averageTraining,
          value: number(insights.averageSessions),
          icon: Icons.menu_book_outlined,
          caption: l10n.sessionsUnit,
        ),
        KpiTile(
          label: l10n.contactCoverage,
          value: '${number(insights.contactPercent)}%',
          icon: Icons.phone_outlined,
          color: AppColors.secondary,
        ),
      ],
    );
  }
}

class _CoverageCharts extends StatelessWidget {
  const _CoverageCharts({required this.insights, required this.labels});

  final AlpTeacherInsights insights;
  final AlpTeacherLabels labels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ChartGrid(
      tiles: [
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-gender'),
            title: l10n.gender,
            child: _donut(context, insights.gender, colorOf: genderColor),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-nationality'),
            title: l10n.nationality,
            child: _donut(context, foldTail(insights.nationality, otherLabel: labels.base.other)),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-assignment'),
            title: l10n.assignment,
            child: _donut(context, foldTail(insights.assignment, otherLabel: labels.base.other)),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-school'),
            title: l10n.teachersBySchool,
            child: _bars(context, insights.school),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-round'),
            title: l10n.teachersByRound,
            child: _bars(context, insights.round),
          ),
        ),
      ],
    );
  }
}

class _CapacityCharts extends StatelessWidget {
  const _CapacityCharts({required this.insights, required this.labels});

  final AlpTeacherInsights insights;
  final AlpTeacherLabels labels;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ChartGrid(
      tiles: [
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-subjects'),
            title: l10n.subjectsProvided,
            // The rows count teacher-SUBJECT pairs, so a share of their sum
            // would answer a question nobody asked ("what fraction of the
            // subjects taught is Arabic?"). The teacher count is the
            // denominator a workforce page means.
            child: _bars(context, insights.subjects, total: insights.total),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-levels'),
            title: l10n.gradeLevelsSupported,
            child: _bars(context, insights.levels, total: insights.total),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-trainings'),
            title: l10n.trainingTopics,
            child: _bars(context, insights.trainings, total: insights.total),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-hours'),
            title: l10n.teachingHours,
            // Hours, not people: a share of a total number of hours is not a
            // figure anyone asks for, so only the count is printed.
            child: _bars(
              context,
              insights.hours,
              share: false,
              valueText: (item) => '${item.count} ${l10n.hoursUnit}',
              valueWidth: 92,
            ),
          ),
        ),
        ChartTile(
          child: ChartCard(
            key: const ValueKey('chart-coaching'),
            title: l10n.extraCoaching,
            child: _donut(context, insights.coaching),
          ),
        ),
      ],
    );
  }
}

Widget _bars(
  BuildContext context,
  List<ChartItem> items, {
  bool share = true,
  int? total,
  String Function(ChartItem)? valueText,
  double? valueWidth,
}) {
  final l10n = AppLocalizations.of(context);
  if (totalOf(items) == 0) return EmptyChart(message: l10n.noDataForFilters);
  return BarListChart(
    items: items,
    total: total,
    showShare: share,
    valueText: valueText,
    valueWidth: valueWidth,
    showAllLabel: l10n.showAll,
    showLessLabel: l10n.showLess,
  );
}

Widget _donut(BuildContext context, List<ChartItem> items, {Color Function(int, ChartItem)? colorOf}) {
  final l10n = AppLocalizations.of(context);
  if (totalOf(items) == 0) return EmptyChart(message: l10n.noDataForFilters);
  return DonutChart(items: items, colorOf: colorOf ?? (i, _) => ChartPalette.series(i));
}
