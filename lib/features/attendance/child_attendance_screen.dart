import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/models/entity_record.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../registrations/registration_helpers.dart';

/// Attendance history of one beneficiary, grouped by month.
class ChildAttendanceScreen extends ConsumerWidget {
  const ChildAttendanceScreen({super.key, required this.uuid});

  final String uuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final record = ref.watch(recordProvider(uuid));
    return record.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: EmptyState(message: e.toString())),
      data: (r) {
        if (r == null) return Scaffold(appBar: AppBar(), body: EmptyState(message: l10n.noResults));
        return _Body(registration: r);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.registration});

  final EntityRecord registration;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.watch(dataVersionProvider);
    final dao = ref.read(entityDaoProvider);
    final module = Entities.moduleOf(registration.entity);
    final entity = Entities.attendanceFor(module);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.childMonth)),
      body: FutureBuilder<List<EntityRecord>>(
        future: dao.list(RecordQuery(entity: entity, limit: 5000, orderBy: 'natural_key DESC')),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final entries = <_Entry>[];
          for (final day in snapshot.data!) {
            final rows = ((day.data['children_attendance'] as List?) ?? const []).whereType<Map>();
            for (final row in rows) {
              final matchesId = row['registration_id'] != null && '${row['registration_id']}' == '${registration.serverId}';
              final matchesUuid = row['registration_uuid'] == registration.uuid;
              if (matchesId || matchesUuid) {
                entries.add(_Entry(
                  date: (day.data['attendance_date'] ?? '').toString(),
                  attended: (row['attended'] ?? '').toString(),
                  reason: (row['absence_reason'] ?? '').toString(),
                  programme: (day.data['education_program'] ?? day.data['registration_level'] ?? day.data['programme'] ?? '').toString(),
                ));
              }
            }
          }
          if (entries.isEmpty) return EmptyState(message: l10n.noResults, icon: Icons.event_busy);
          entries.sort((a, b) => b.date.compareTo(a.date));
          final byMonth = <String, List<_Entry>>{};
          for (final e in entries) {
            byMonth.putIfAbsent(e.date.length >= 7 ? e.date.substring(0, 7) : e.date, () => []).add(e);
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(RegistrationView(registration).fullName, style: Theme.of(context).textTheme.titleMedium),
              ),
              for (final month in byMonth.entries)
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        title: Text(month.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(l10n.monthSummary(
                          month.value.where((e) => e.attended == 'Yes').length,
                          month.value.where((e) => e.attended == 'No').length,
                        )),
                      ),
                      for (final e in month.value)
                        ListTile(
                          dense: true,
                          leading: Icon(e.attended == 'No' ? Icons.close : Icons.check,
                              color: e.attended == 'No' ? AppColors.danger : AppColors.success),
                          title: Text(e.date),
                          subtitle: Text([e.programme, if (e.attended == 'No') e.reason].where((s) => s.isNotEmpty).join(' · ')),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Entry {
  _Entry({required this.date, required this.attended, required this.reason, required this.programme});

  final String date;
  final String attended;
  final String reason;
  final String programme;
}
