// The ALP attendance heatmaps, computed from the sheets stored on the device.
// A port of BMA-NFE's `ALPAttendanceDashboardView` and
// `_aggregate_alp_attendance` (student_registration/alp/views.py): per
// attendance date, `total` is the number of child rows and `absent` the rows
// marked "No" — so a row left unmarked counts in the total but not as an
// absence, exactly as `Count(filter=Q(attended='No'))` does.
import 'package:flutter/foundation.dart' show immutable;

import '../../../core/models/entity_record.dart';
import '../../../core/models/reference_item.dart';
import '../analytics_models.dart';

/// Totals of one heatmap, for the line printed under its title.
@immutable
class HeatmapSummary {
  const HeatmapSummary({required this.present, required this.total, required this.days});

  final int present;
  final int total;

  /// Days that recorded at least one row.
  final int days;

  double? get rate => total == 0 ? null : present / total;

  static const empty = HeatmapSummary(present: 0, total: 0, days: 0);

  static HeatmapSummary of(Map<DateTime, HeatCell> cells) {
    var present = 0;
    var total = 0;
    var days = 0;
    for (final cell in cells.values) {
      present += cell.present;
      total += cell.total;
      if (cell.total > 0) days++;
    }
    return HeatmapSummary(present: present, total: total, days: days);
  }
}

/// One programme's heatmap.
@immutable
class ProgrammeHeatmap {
  const ProgrammeHeatmap({required this.key, required this.label, required this.cells, required this.summary});

  /// Programme id as text, or `unknown` for sheets with no programme.
  final String key;
  final String label;
  final Map<DateTime, HeatCell> cells;
  final HeatmapSummary summary;
}

class AlpAttendanceInsights {
  const AlpAttendanceInsights({
    required this.year,
    required this.years,
    required this.overall,
    required this.overallSummary,
    required this.byProgramme,
  });

  /// The year the maps are drawn for.
  final int year;

  /// Every year the device holds attendance for, newest first.
  final List<int> years;
  final Map<DateTime, HeatCell> overall;
  final HeatmapSummary overallSummary;
  final List<ProgrammeHeatmap> byProgramme;

  bool get isEmpty => overall.isEmpty;
}

class AlpAttendanceSource {
  const AlpAttendanceSource({
    required this.attendanceDays,
    required this.programmes,
    required this.language,
    required this.today,
  });

  /// `alp.attendance_day` records.
  final List<EntityRecord> attendanceDays;
  final Map<int, ReferenceItem> programmes;
  final String language;
  final DateTime today;
}

/// Aggregates the sheets into an overall map and one per programme.
///
/// The web always renders the current year and shows an empty grid when it
/// has no data. A field device that has just been set up would then open on a
/// blank page, so when no year is asked for and the current one is empty, the
/// newest year that HAS data is shown instead — the year selector still names
/// every year, so nothing is hidden.
AlpAttendanceInsights computeAlpAttendance(
  AlpAttendanceSource src, {
  int? year,
  required String unknownLabel,
}) {
  final perYear = <int, Map<DateTime, HeatCell>>{};
  final perYearProgramme = <int, Map<String, Map<DateTime, HeatCell>>>{};
  final programmeLabels = <String, String>{};

  for (final record in src.attendanceDays) {
    if (record.deleted || record.syncState == SyncState.discarded) continue;
    final date = parseDate(record.data['attendance_date']);
    if (date == null) continue;
    final day = dateOnly(date);

    var total = 0;
    var absent = 0;
    for (final row in ((record.data['children_attendance'] as List?) ?? const []).whereType<Map>()) {
      total++;
      if ((row['attended'] ?? '').toString() == 'No') absent++;
    }
    if (total == 0) continue;

    final programmeId = record.data['programme'] is num
        ? (record.data['programme'] as num).toInt()
        : int.tryParse(record.data['programme']?.toString() ?? '');
    final programmeKey = programmeId == null ? 'unknown' : '$programmeId';
    programmeLabels[programmeKey] =
        (programmeId == null ? null : src.programmes[programmeId]?.labelFor(src.language)) ??
            record.data['programme_label']?.toString() ??
            unknownLabel;

    void add(Map<DateTime, HeatCell> map) {
      final existing = map[day];
      map[day] = existing == null
          ? HeatCell(date: day, total: total, absent: absent)
          : existing.add(total, absent);
    }

    add(perYear.putIfAbsent(day.year, () => {}));
    add(perYearProgramme.putIfAbsent(day.year, () => {}).putIfAbsent(programmeKey, () => {}));
  }

  final years = perYear.keys.toList()..sort((a, b) => b.compareTo(a));
  final currentYear = src.today.year;
  final resolved = year ??
      (perYear.containsKey(currentYear) ? currentYear : (years.isNotEmpty ? years.first : currentYear));

  final overall = perYear[resolved] ?? <DateTime, HeatCell>{};
  final programmeMaps = perYearProgramme[resolved] ?? <String, Map<DateTime, HeatCell>>{};
  final programmeKeys = programmeMaps.keys.toList()
    ..sort((a, b) {
      // "Unknown" is the tail of the list, never its head.
      if (a == 'unknown') return 1;
      if (b == 'unknown') return -1;
      return (programmeLabels[a] ?? a).toLowerCase().compareTo((programmeLabels[b] ?? b).toLowerCase());
    });

  return AlpAttendanceInsights(
    year: resolved,
    years: years.isEmpty ? [resolved] : years,
    overall: overall,
    overallSummary: HeatmapSummary.of(overall),
    byProgramme: [
      for (final key in programmeKeys)
        ProgrammeHeatmap(
          key: key,
          label: programmeLabels[key] ?? unknownLabel,
          cells: programmeMaps[key]!,
          summary: HeatmapSummary.of(programmeMaps[key]!),
        ),
    ],
  );
}
