import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/settings_controller.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/forms/reference_cache.dart';
import '../../core/layout/adaptive.dart';
import '../../core/layout/app_layout.dart';
import '../../core/models/entity_record.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../registrations/registration_helpers.dart';

/// Offline dashboard computed from the records stored on the device.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.module});

  final BmaModule module;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.watch(dataVersionProvider);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.dashboard)),
      body: FutureBuilder<_Stats>(
        future: _compute(ref, language),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final s = snapshot.data!;
          final breakdowns = <(String, String, Map<String, int>)>[
            ('gender', l10n.byGender, s.byGender),
            ('nationality', l10n.byNationality, s.byNationality),
            ('age', l10n.byAgeGroup, s.byAge),
          ];
          // gutter: false — the ListView's own EdgeInsets.all(8) IS this
          // page's gutter today, and paying for a second one at 1280 costs a
          // whole KPI column (1104 px fits six 184 px tiles; 1040 fits five).
          return AdaptiveBody(
            gutter: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final layout = LayoutScope.of(context);
                // The box, never the window: `MediaQuery.size.width > 600`
                // used to be read here, which with a 212 px rail beside it
                // would pick the wide branch for a pane that is not wide.
                final inner = constraints.maxWidth - 16;
                final columns = layout.width.isExpanded
                    ? 3
                    : layout.width.atLeastMedium
                    ? 2
                    : 1;
                return ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    GridView(
                      key: const ValueKey('dash-kpis'),
                      // Extent-based, not count-based: six KPIs holding one
                      // number each become one readable band instead of six
                      // ~310x194 slabs. At 412 the delegate resolves to the
                      // same two 198x123.75 cells GridView.count(2) gives, so
                      // the phone does not move.
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        childAspectRatio: 1.6,
                      ),
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        StatTile(label: l10n.totalRegistrations, value: '${s.total}', icon: Icons.people),
                        StatTile(
                          label: l10n.attendanceRate,
                          value: s.attendanceTotal == 0
                              ? '—'
                              : '${(100 * s.attendancePresent / s.attendanceTotal).round()}%',
                          icon: Icons.fact_check,
                          color: AppColors.success,
                        ),
                        StatTile(label: l10n.servicesDelivered, value: '${s.services}', icon: Icons.medical_services),
                        StatTile(
                          label: l10n.kpiPendingPush,
                          value: '${s.pending}',
                          icon: Icons.cloud_upload,
                          color: AppColors.warning,
                        ),
                        StatTile(
                          label: l10n.kpiDuplicates,
                          value: '${s.attention}',
                          icon: Icons.warning_amber,
                          color: AppColors.danger,
                        ),
                        StatTile(label: l10n.attendanceDays, value: '${s.attendanceDays}', icon: Icons.calendar_month),
                      ],
                    ),
                    if (columns == 1)
                      for (final (slug, title, data) in breakdowns)
                        _Breakdown(key: ValueKey('dash-breakdown-$slug'), title: title, data: data, total: s.total)
                    else
                      // Wrap, not Row: the three cards hold different numbers
                      // of bars, and a Wrap lets each keep its natural height
                      // instead of stretching to the tallest.
                      Wrap(
                        key: const ValueKey('dash-breakdowns'),
                        children: [
                          for (final (slug, title, data) in breakdowns)
                            SizedBox(
                              width: inner / columns,
                              child: _Breakdown(
                                key: ValueKey('dash-breakdown-$slug'),
                                title: title,
                                data: data,
                                total: s.total,
                              ),
                            ),
                        ],
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<_Stats> _compute(WidgetRef ref, String language) async {
    final dao = ref.read(entityDaoProvider);
    final cache = ref.read(referenceCacheProvider);
    final registrations = await dao.list(RecordQuery(entity: Entities.registrationFor(module), limit: 20000));
    final stats = _Stats();
    stats.total = registrations.length;
    for (final r in registrations) {
      final view = RegistrationView(r);
      stats.byGender.update(view.gender?.isNotEmpty == true ? view.gender! : '—', (v) => v + 1, ifAbsent: () => 1);
      final nationality = view.nationalityLabel ?? await cache.label('nationalities', view.nationalityId, language);
      stats.byNationality.update(nationality.isEmpty ? '—' : nationality, (v) => v + 1, ifAbsent: () => 1);
      final age = view.age;
      final group = age == null
          ? '—'
          : age <= 5
          ? '0-5'
          : age <= 9
              ? '6-9'
              : age <= 14
                  ? '10-14'
                  : age <= 17
                      ? '15-17'
                      : '18+';
      stats.byAge.update(group, (v) => v + 1, ifAbsent: () => 1);
      if (r.syncState == SyncState.pending || r.syncState == SyncState.pushing) stats.pending++;
      if (r.syncState.needsAttention) stats.attention++;
    }
    final services = await dao.list(RecordQuery(module: module.key, limit: 50000));
    stats.services = services
        .where((s) => !Entities.identityEntities.contains(s.entity) &&
            !Entities.attendanceEntities.contains(s.entity) &&
            !s.entity.endsWith('.teacher'))
        .length;
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    final days = await dao.list(RecordQuery(entity: Entities.attendanceFor(module), limit: 5000));
    for (final day in days) {
      final date = DateTime.tryParse((day.data['attendance_date'] ?? '').toString());
      if (date == null || date.isBefore(cutoff)) continue;
      stats.attendanceDays++;
      for (final row in ((day.data['children_attendance'] as List?) ?? const []).whereType<Map>()) {
        stats.attendanceTotal++;
        if (row['attended'] == 'Yes') stats.attendancePresent++;
      }
    }
    return stats;
  }
}

class _Stats {
  int total = 0;
  int services = 0;
  int pending = 0;
  int attention = 0;
  int attendanceDays = 0;
  int attendanceTotal = 0;
  int attendancePresent = 0;
  final Map<String, int> byGender = {};
  final Map<String, int> byNationality = {};
  final Map<String, int> byAge = {};
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({super.key, required this.title, required this.data, required this.total});

  final String title;
  final Map<String, int> data;
  final int total;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final layout = LayoutScope.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The label column follows the token at medium+, but never eats
            // more than 40% of THIS card — three cards side by side are ~320
            // px each, where a literal 200 would leave 80 px of bar. At
            // compact the expression is min(120, 0.4 * 348) = 120, today's
            // literal, so the phone card is unchanged.
            final labelWidth = _min(
              layout.width.atLeastMedium ? layout.labelColumnWidth : 120.0,
              constraints.maxWidth * 0.4,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (entries.isEmpty) const Text('—'),
                for (final e in entries.take(8))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: labelWidth,
                          child: Text(e.key, overflow: TextOverflow.ellipsis),
                        ),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: total == 0 ? 0 : e.value / total,
                            minHeight: 10,
                            borderRadius: BorderRadius.circular(6),
                            backgroundColor: AppColors.background,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(width: 40, child: Text('${e.value}', textAlign: TextAlign.end)),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

double _min(double a, double b) => a < b ? a : b;
