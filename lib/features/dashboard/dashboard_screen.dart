import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/config/settings_controller.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/forms/reference_cache.dart';
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
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.6,
                children: [
                  StatTile(label: l10n.totalRegistrations, value: '${s.total}', icon: Icons.people),
                  StatTile(
                      label: l10n.attendanceRate,
                      value: s.attendanceTotal == 0 ? '—' : '${(100 * s.attendancePresent / s.attendanceTotal).round()}%',
                      icon: Icons.fact_check,
                      color: AppColors.success),
                  StatTile(label: l10n.servicesDelivered, value: '${s.services}', icon: Icons.medical_services),
                  StatTile(label: l10n.kpiPendingPush, value: '${s.pending}', icon: Icons.cloud_upload, color: AppColors.warning),
                  StatTile(label: l10n.kpiDuplicates, value: '${s.attention}', icon: Icons.warning_amber, color: AppColors.danger),
                  StatTile(label: l10n.attendanceDays, value: '${s.attendanceDays}', icon: Icons.calendar_month),
                ],
              ),
              _Breakdown(title: l10n.byGender, data: s.byGender, total: s.total),
              _Breakdown(title: l10n.byNationality, data: s.byNationality, total: s.total),
              _Breakdown(title: l10n.byAgeGroup, data: s.byAge, total: s.total),
            ],
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
      final nationality = view.nationalityLabel ??
          await cache.label('nationalities', view.nationalityId, language);
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
  const _Breakdown({required this.title, required this.data, required this.total});

  final String title;
  final Map<String, int> data;
  final int total;

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (entries.isEmpty) const Text('—'),
            for (final e in entries.take(8))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 120, child: Text(e.key, overflow: TextOverflow.ellipsis)),
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
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
