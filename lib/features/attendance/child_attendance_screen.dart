import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/layout/app_layout.dart';
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
          return LayoutBuilder(
            builder: (context, constraints) {
              final layout = AppLayout.forWidth(constraints.maxWidth);
              final wide = layout.width.atLeastMedium;
              return LayoutScope(
                layout: layout,
                child: ListView(
                  padding: EdgeInsets.all(wide ? 16 : 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(RegistrationView(registration).fullName, style: Theme.of(context).textTheme.titleMedium),
                    ),
                    if (!wide)
                      for (final month in byMonth.entries) _monthList(context, l10n, month.key, month.value)
                    else
                      // maxCrossAxisExtent 420 by hand: a Wrap rather than a
                      // GridView because a month is 4, 5 or 6 week rows tall
                      // and a fixed mainAxisExtent would clip the tallest.
                      _monthWrap(context, l10n, byMonth, constraints.maxWidth - (wide ? 32 : 24)),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  /// Today's phone card: the summary line and one dense [ListTile] per day.
  Widget _monthList(BuildContext context, AppLocalizations l10n, String month, List<_Entry> days) {
    return Card(
      key: ValueKey('month-$month'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(month, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(l10n.monthSummary(
              days.where((e) => e.attended == 'Yes').length,
              days.where((e) => e.attended == 'No').length,
            )),
          ),
          for (final e in days)
            ListTile(
              dense: true,
              leading: Icon(e.attended == 'No' ? Icons.close : Icons.check,
                  color: e.attended == 'No' ? AppColors.danger : AppColors.success),
              title: Text(e.date),
              subtitle: Text([e.programme, if (e.attended == 'No') e.reason].where((s) => s.isNotEmpty).join(' · ')),
            ),
        ],
      ),
    );
  }

  Widget _monthWrap(
      BuildContext context, AppLocalizations l10n, Map<String, List<_Entry>> byMonth, double available) {
    const spacing = 12.0;
    const maxExtent = 420.0;
    final columns = available <= 0 ? 1 : (available / maxExtent).ceil().clamp(1, byMonth.length.clamp(1, 4));
    final width = (available - spacing * (columns - 1)) / columns;
    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        for (final month in byMonth.entries)
          SizedBox(width: width, child: _MonthGrid(month: month.key, days: month.value, l10n: l10n)),
      ],
    );
  }
}

/// One month as a 7-column day grid: a whole term fits on one landscape
/// screen instead of five or six screens of dense list rows.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.days, required this.l10n});

  final String month;
  final List<_Entry> days;
  final AppLocalizations l10n;

  static const double _cellHeight = 34;

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    final firstDayOfWeek = materialL10n.firstDayOfWeekIndex;
    final narrow = materialL10n.narrowWeekdays;
    final byDate = <String, _Entry>{};
    for (final e in days) {
      byDate.putIfAbsent(e.date, () => e);
    }
    final year = int.tryParse(month.length >= 4 ? month.substring(0, 4) : '') ?? 0;
    final monthNumber = int.tryParse(month.length >= 7 ? month.substring(5, 7) : '') ?? 0;
    final valid = year > 0 && monthNumber >= 1 && monthNumber <= 12;
    final dayCount = valid ? DateTime(year, monthNumber + 1, 0).day : 0;
    // DateTime.weekday is 1..7 (Mon..Sun); narrowWeekdays is indexed 0..6 from
    // Sunday, which is the index space the leading-blank count works in.
    final firstIndex = valid ? DateTime(year, monthNumber, 1).weekday % 7 : 0;
    final leading = valid ? (firstIndex - firstDayOfWeek + 7) % 7 : 0;

    final cells = <Widget?>[
      for (var i = 0; i < leading; i++) null,
      for (var day = 1; day <= dayCount; day++) _dayCell(context, year, monthNumber, day, byDate),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Card(
      key: ValueKey('month-$month'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(month, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            Text(
              l10n.monthSummary(
                days.where((e) => e.attended == 'Yes').length,
                days.where((e) => e.attended == 'No').length,
              ),
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(narrow[(firstDayOfWeek + i) % 7],
                        maxLines: 1, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            for (var week = 0; week * 7 < cells.length; week++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  for (var i = 0; i < 7; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: cells[week * 7 + i] ?? const SizedBox(height: _cellHeight),
                      ),
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _dayCell(BuildContext context, int year, int month, int day, Map<String, _Entry> byDate) {
    final date = '$year-${this.month.substring(5, 7)}-${day.toString().padLeft(2, '0')}';
    final entry = byDate[date];
    final absent = entry?.attended == 'No';
    final present = entry?.attended == 'Yes';
    final colour = present
        ? AppColors.success
        : absent
            ? AppColors.danger
            : AppColors.muted;
    return InkWell(
      key: ValueKey('month-day-$date'),
      borderRadius: const BorderRadius.all(Radius.circular(6)),
      onTap: () => showMessage(
        context,
        [
          date,
          if (present) l10n.present,
          if (absent) l10n.absent,
          if (entry == null) l10n.noSheetForDay,
          if (absent && entry!.reason.isNotEmpty) entry.reason,
          if (entry != null && entry.programme.isNotEmpty) entry.programme,
        ].join(' · '),
      ),
      child: Container(
        height: _cellHeight,
        decoration: BoxDecoration(
          color: entry == null ? AppColors.surfaceAlt : colour.withValues(alpha: 0.15),
          border: Border.all(color: entry == null ? AppColors.border : colour.withValues(alpha: 0.45)),
          borderRadius: const BorderRadius.all(Radius.circular(6)),
        ),
        child: Center(
          child: Text(
            '$day',
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              fontWeight: entry == null ? FontWeight.w400 : FontWeight.w600,
              color: entry == null ? AppColors.muted : colour,
            ),
          ),
        ),
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
