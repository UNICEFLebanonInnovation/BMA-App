// The ALP teacher workforce figures, computed from the records on the device.
// A port of BMA-NFE's `ALPTeacherDashboardDataView`
// (student_registration/alp/views.py): the same seven indicators and the same
// ten groupings, including the rules that are easy to get wrong —
// `Avg` ignores nulls, `trained` is "any training topic OR any session", and
// `grouped()` orders BY VALUE rather than by count.
import 'package:flutter/foundation.dart' show immutable;

import '../../../core/models/entity_record.dart';
import '../../../core/models/reference_item.dart';
import '../analytics_models.dart';
import '../nfe/nfe_analytics.dart' show AnalyticsLabels;

/// Extra words the teacher panels need.
@immutable
class AlpTeacherLabels {
  const AlpTeacherLabels({
    required this.base,
    required this.notSpecified,
    required this.alpHours,
    required this.privateSchoolHours,
  });

  final AnalyticsLabels base;
  final String notSpecified;
  final String alpHours;
  final String privateSchoolHours;

  static const english = AlpTeacherLabels(
    base: AnalyticsLabels.english,
    notSpecified: 'Not specified',
    alpHours: 'ALP',
    privateSchoolHours: 'Private school',
  );
}

@immutable
class AlpTeacherFilters {
  const AlpTeacherFilters({this.schoolId, this.roundId});

  final int? schoolId;
  final int? roundId;

  static const none = AlpTeacherFilters();

  bool get isEmpty => schoolId == null && roundId == null;

  AlpTeacherFilters copyWith({int? schoolId, bool clearSchool = false, int? roundId, bool clearRound = false}) =>
      AlpTeacherFilters(
        schoolId: clearSchool ? null : (schoolId ?? this.schoolId),
        roundId: clearRound ? null : (roundId ?? this.roundId),
      );

  @override
  bool operator ==(Object other) =>
      other is AlpTeacherFilters && other.schoolId == schoolId && other.roundId == roundId;

  @override
  int get hashCode => Object.hash(schoolId, roundId);
}

class AlpTeacherSource {
  const AlpTeacherSource({
    required this.teachers,
    required this.schools,
    required this.rounds,
    required this.nationalities,
    required this.trainings,
    required this.choiceLabels,
    required this.language,
    this.defaultSchoolId,
  });

  final List<EntityRecord> teachers;
  final Map<int, ReferenceItem> schools;
  final Map<int, ReferenceItem> rounds;
  final Map<int, ReferenceItem> nationalities;

  /// Training topics by id, for the "Training topics" panel.
  final Map<int, ReferenceItem> trainings;

  /// Field name → raw value → label, from the `alp.teacher` schema, for the
  /// choice fields the server sends as raw values (`arabic`, `ALP only`, …).
  final Map<String, Map<String, String>> choiceLabels;
  final String language;

  /// What the server forces onto a teacher typed offline.
  final int? defaultSchoolId;

  String label(String field, String value) => choiceLabels[field]?[value] ?? value;
}

@immutable
class AlpTeacherRow {
  const AlpTeacherRow({
    required this.schoolId,
    required this.schoolLabel,
    required this.roundId,
    required this.roundLabel,
    required this.sex,
    required this.nationalityId,
    required this.nationalityLabel,
    required this.assignment,
    required this.coaching,
    required this.subjects,
    required this.levels,
    required this.trainingIds,
    required this.trainingSessions,
    required this.yearsOfExperience,
    required this.hoursAlp,
    required this.hoursPrivate,
    required this.hasPhone,
  });

  final int? schoolId;
  final String schoolLabel;
  final int? roundId;
  final String roundLabel;
  final String sex;
  final int? nationalityId;
  final String nationalityLabel;
  final String assignment;
  final String coaching;
  final List<String> subjects;
  final List<String> levels;
  final List<int> trainingIds;
  final int? trainingSessions;
  final int? yearsOfExperience;
  final int hoursAlp;
  final int hoursPrivate;
  final bool hasPhone;

  /// `Q(trainings__isnull=False) | Q(training_sessions_attended__gt=0)`.
  bool get isTrained => trainingIds.isNotEmpty || (trainingSessions ?? 0) > 0;
}

class AlpTeacherInsights {
  const AlpTeacherInsights({
    required this.total,
    required this.schools,
    required this.trained,
    required this.trainedPercent,
    required this.contactPercent,
    required this.averageExperience,
    required this.averageSessions,
    required this.gender,
    required this.nationality,
    required this.assignment,
    required this.school,
    required this.round,
    required this.subjects,
    required this.levels,
    required this.trainings,
    required this.hours,
    required this.coaching,
  });

  final int total;
  final int schools;
  final int trained;

  /// One decimal, as `round(x * 100 / total, 1)` gives.
  final double trainedPercent;
  final double contactPercent;
  final double averageExperience;
  final double averageSessions;
  final List<ChartItem> gender;
  final List<ChartItem> nationality;
  final List<ChartItem> assignment;
  final List<ChartItem> school;
  final List<ChartItem> round;
  final List<ChartItem> subjects;
  final List<ChartItem> levels;
  final List<ChartItem> trainings;

  /// Two items: ALP hours and private-school hours.
  final List<ChartItem> hours;
  final List<ChartItem> coaching;
}

int? _int(Object? value) => value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

List<String> _stringList(Object? value) {
  if (value is List) {
    return [for (final e in value) e.toString().trim()].where((e) => e.isNotEmpty).toList();
  }
  final single = (value ?? '').toString().trim();
  return single.isEmpty ? const [] : [single];
}

List<AlpTeacherRow> alpTeacherRows(AlpTeacherSource src, AlpTeacherLabels labels) {
  final rows = <AlpTeacherRow>[];
  for (final record in src.teachers) {
    if (record.deleted || record.syncState == SyncState.discarded) continue;
    final data = record.data;
    final schoolId = _int(data['school']) ?? src.defaultSchoolId;
    final school = schoolId == null ? null : src.schools[schoolId];
    final roundId = _int(data['round']);
    final round = roundId == null ? null : src.rounds[roundId];
    final nationalityId = _int(data['nationality']);
    final nationality = nationalityId == null ? null : src.nationalities[nationalityId];
    final nationalityLabel = data['nationality_label']?.toString().trim() ?? '';
    final phone = (data['phone_number'] ?? data['primary_phone_number'] ?? '').toString().trim();

    rows.add(AlpTeacherRow(
      schoolId: schoolId,
      schoolLabel: school?.labelFor(src.language) ??
          (data['school_label']?.toString().trim().isNotEmpty ?? false
              ? data['school_label'].toString()
              : labels.notSpecified),
      roundId: roundId,
      roundLabel: round?.labelFor(src.language) ??
          (data['round_label']?.toString().trim().isNotEmpty ?? false
              ? data['round_label'].toString()
              : labels.notSpecified),
      sex: (data['sex'] ?? data['gender'] ?? '').toString().trim(),
      nationalityId: nationalityId,
      nationalityLabel: nationality?.labelFor(src.language) ??
          (nationalityLabel.isNotEmpty ? nationalityLabel : labels.notSpecified),
      assignment: (data['teacher_assignment'] ?? '').toString().trim(),
      coaching: (data['extra_coaching'] ?? '').toString().trim(),
      subjects: _stringList(data['subjects_provided']),
      levels: _stringList(data['registration_level']),
      trainingIds: [for (final id in _stringList(data['trainings'])) ?int.tryParse(id)],
      trainingSessions: _int(data['training_sessions_attended']),
      yearsOfExperience: _int(data['years_of_experience']),
      hoursAlp: _int(data['teaching_hours_mscc']) ?? 0,
      hoursPrivate: _int(data['teaching_hours_private_school']) ?? 0,
      hasPhone: phone.isNotEmpty,
    ));
  }
  return rows;
}

bool _matches(AlpTeacherRow row, AlpTeacherFilters f) {
  if (f.schoolId != null && row.schoolId != f.schoolId) return false;
  if (f.roundId != null && row.roundId != f.roundId) return false;
  return true;
}

double _round1(double value) => (value * 10).round() / 10;

AlpTeacherInsights computeAlpTeacherInsights(
  AlpTeacherSource src,
  AlpTeacherFilters filters, {
  AlpTeacherLabels labels = AlpTeacherLabels.english,
}) {
  final rows = alpTeacherRows(src, labels).where((r) => _matches(r, filters)).toList();
  final total = rows.length;

  double percent(int value) => total == 0 ? 0 : _round1(value * 100 / total);

  /// `Avg(field)` ignores nulls: a teacher who never recorded a figure must
  /// not drag the mean towards zero.
  double average(Iterable<int?> values) {
    final present = values.whereType<int>().toList();
    if (present.isEmpty) return 0;
    return _round1(present.reduce((a, b) => a + b) / present.length);
  }

  /// `values(field).annotate(Count).order_by(field)`: grouped BY VALUE, in
  /// value order, blanks last under "Not specified".
  List<ChartItem> grouped(String Function(AlpTeacherRow) key, String Function(AlpTeacherRow) label) {
    final tally = <String, int>{};
    final labelOf = <String, String>{};
    for (final r in rows) {
      final raw = key(r);
      final k = raw.isEmpty ? '' : raw;
      tally.update(k, (v) => v + 1, ifAbsent: () => 1);
      labelOf[k] = raw.isEmpty ? labels.notSpecified : label(r);
    }
    final keys = tally.keys.toList()
      ..sort((a, b) {
        // The blank group sorts last rather than first: "Not specified" is
        // the tail of a list, not its head.
        if (a.isEmpty) return 1;
        if (b.isEmpty) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    return [for (final k in keys) ChartItem(key: k, label: labelOf[k]!, count: tally[k]!)];
  }

  /// Each entry of a list field counted once, in first-seen order.
  List<ChartItem> fromLists(List<String> Function(AlpTeacherRow) values, String field) {
    final tally = <String, int>{};
    for (final r in rows) {
      for (final value in values(r)) {
        tally.update(value, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    return [for (final e in tally.entries) ChartItem(key: e.key, label: src.label(field, e.key), count: e.value)];
  }

  // Training topics: `order_by('-y', 'trainings__name')`.
  final trainingTally = <int, int>{};
  for (final r in rows) {
    for (final id in r.trainingIds.toSet()) {
      trainingTally.update(id, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  final trainings = [
    for (final e in trainingTally.entries)
      ChartItem(
        key: '${e.key}',
        label: src.trainings[e.key]?.labelFor(src.language) ?? labels.notSpecified,
        count: e.value,
      ),
  ]..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

  return AlpTeacherInsights(
    total: total,
    schools: rows.map((r) => r.schoolId).whereType<int>().toSet().length,
    trained: rows.where((r) => r.isTrained).length,
    trainedPercent: percent(rows.where((r) => r.isTrained).length),
    contactPercent: percent(rows.where((r) => r.hasPhone).length),
    averageExperience: average(rows.map((r) => r.yearsOfExperience)),
    averageSessions: average(rows.map((r) => r.trainingSessions)),
    gender: grouped((r) => r.sex, (r) => labels.base.gender(r.sex)),
    nationality: grouped((r) => r.nationalityId == null ? '' : r.nationalityLabel, (r) => r.nationalityLabel),
    assignment: grouped((r) => r.assignment, (r) => src.label('teacher_assignment', r.assignment)),
    school: grouped((r) => r.schoolId == null ? '' : r.schoolLabel, (r) => r.schoolLabel),
    round: grouped((r) => r.roundId == null ? '' : r.roundLabel, (r) => r.roundLabel),
    subjects: fromLists((r) => r.subjects, 'subjects_provided'),
    levels: fromLists((r) => r.levels, 'registration_level'),
    trainings: trainings,
    hours: [
      ChartItem(key: 'alp', label: labels.alpHours, count: rows.fold(0, (sum, r) => sum + r.hoursAlp)),
      ChartItem(
        key: 'private',
        label: labels.privateSchoolHours,
        count: rows.fold(0, (sum, r) => sum + r.hoursPrivate),
      ),
    ],
    coaching: grouped((r) => r.coaching, (r) => src.label('extra_coaching', r.coaching)),
  );
}
