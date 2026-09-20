import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/settings_controller.dart';
import '../../../core/db/entity_dao.dart';
import '../../../core/db/providers.dart';
import '../../../core/forms/reference_cache.dart';
import '../../../core/layout/adaptive.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/ui.dart';
import '../../../l10n/app_localizations.dart';
import '../analytics_models.dart';
import '../charts/chart_card.dart';
import '../charts/heatmap_calendar.dart';
import '../widgets/filter_bar.dart';
import 'alp_attendance_heatmap.dart';
import 'alp_registration_insights.dart' show AlpAnalyticsEntities;

/// The web platform's ALP attendance dashboard, computed on the device: the
/// overall month × day heatmap for the selected year, then one per programme.
class AlpAttendanceDashboardScreen extends ConsumerStatefulWidget {
  const AlpAttendanceDashboardScreen({super.key});

  @override
  ConsumerState<AlpAttendanceDashboardScreen> createState() => _AlpAttendanceDashboardScreenState();
}

class _AlpAttendanceDashboardScreenState extends ConsumerState<AlpAttendanceDashboardScreen> {
  /// Null means "the year the data suggests"; a pick pins it.
  int? _year;
  final _memo = ComputeMemo<AlpAttendanceSource, (int?, String), AlpAttendanceInsights>();
  Future<AlpAttendanceSource>? _future;
  String? _loadKey;

  Future<AlpAttendanceSource> _load(int dataVersion, String language) {
    final key = '$dataVersion|$language';
    if (_future == null || key != _loadKey) {
      _loadKey = key;
      _future = _read(language);
    }
    return _future!;
  }

  Future<AlpAttendanceSource> _read(String language) async {
    final dao = ref.read(entityDaoProvider);
    final cache = ref.read(referenceCacheProvider);
    final days = await dao.list(const RecordQuery(entity: AlpAnalyticsEntities.attendanceDay, limit: 20000));
    final programmes = await cache.ensure('alp_programs');
    final now = DateTime.now();
    return AlpAttendanceSource(
      attendanceDays: days,
      programmes: programmes,
      language: language,
      today: DateTime(now.year, now.month, now.day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dataVersion = ref.watch(dataVersionProvider);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.alpAttendanceDashboard)),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: FutureBuilder<AlpAttendanceSource>(
              future: _load(dataVersion, language),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return EmptyState(message: snapshot.error.toString(), icon: Icons.error_outline);
                }
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final insights = _memo.of(
                  snapshot.data!,
                  (_year, l10n.unknown),
                  () => computeAlpAttendance(snapshot.data!, year: _year, unknownLabel: l10n.unknown),
                );
                return AdaptiveBody(
                  gutter: false,
                  child: ListView(
                    key: const ValueKey('alp-attendance-list'),
                    padding: const EdgeInsets.all(8),
                    children: [
                      SourceNote(l10n.offlineFiguresNote),
                      _YearCard(
                        years: insights.years,
                        year: insights.year,
                        onChanged: (value) => setState(() => _year = value),
                      ),
                      const SizedBox(height: 4),
                      KpiGrid(
                        key: const ValueKey('alp-attendance-kpis'),
                        tiles: [
                          KpiTile(
                            label: l10n.attendanceDays,
                            value: '${insights.overallSummary.days}',
                            icon: Icons.calendar_month,
                          ),
                          KpiTile(
                            label: l10n.attendanceRateLabel,
                            value: _rate(insights.overallSummary),
                            icon: Icons.fact_check_outlined,
                            color: AppColors.success,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ChartCard(
                        key: const ValueKey('chart-attendance-overall'),
                        title: '${l10n.overallAttendance} (${insights.year})',
                        subtitle: l10n.attendanceHeatmapHint,
                        child: insights.isEmpty
                            ? EmptyChart(message: l10n.noAttendanceForYear, icon: Icons.grid_on_outlined)
                            : AttendanceHeatmap(
                                year: insights.year,
                                cells: insights.overall,
                                rateLabel: l10n.attendanceRateLabel,
                                detailText: (cell) => _detail(context, cell),
                              ),
                      ),
                      if (insights.byProgramme.isNotEmpty) ...[
                        SectionHeader(l10n.attendanceByProgramme),
                        for (var i = 0; i < insights.byProgramme.length; i++)
                          ChartCard(
                            key: ValueKey('chart-attendance-programme-$i'),
                            title: insights.byProgramme[i].label,
                            subtitle: _summaryLine(context, insights.byProgramme[i].summary),
                            child: AttendanceHeatmap(
                              year: insights.year,
                              cells: insights.byProgramme[i].cells,
                              rateLabel: l10n.attendanceRateLabel,
                              detailText: (cell) => _detail(context, cell),
                            ),
                          ),
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

  static String _rate(HeatmapSummary summary) =>
      summary.rate == null ? '—' : '${percentText(summary.present, summary.total)}%';

  static String _summaryLine(BuildContext context, HeatmapSummary summary) {
    final l10n = AppLocalizations.of(context);
    return '${summary.present} / ${summary.total} · ${l10n.attendanceRateLabel} ${_rate(summary)}';
  }

  static String _detail(BuildContext context, HeatCell cell) {
    final l10n = AppLocalizations.of(context);
    return l10n.heatmapCellDetail(
      MaterialLocalizations.of(context).formatMediumDate(cell.date),
      cell.present,
      cell.total,
      percentText(cell.present, cell.total),
    );
  }
}

/// The year selector. Not a [FilterDropdown]: there is no "all years" answer
/// — a heatmap is drawn for exactly one year.
class _YearCard extends StatelessWidget {
  const _YearCard({required this.years, required this.year, required this.onChanged});

  final List<int> years;
  final int year;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final options = years.contains(year) ? years : [year, ...years];
    return Card(
      key: const ValueKey('alp-attendance-filters'),
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
              ],
            ),
            const SizedBox(height: 8),
            FilterBar(
              children: [
                DropdownButtonFormField<int>(
                  key: const ValueKey('alp-attendance-year'),
                  initialValue: year,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.yearLabel),
                  items: [
                    for (final y in options) DropdownMenuItem<int>(value: y, child: Text('$y')),
                  ],
                  onChanged: onChanged,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
