// The ALP registration / operational insights figures, computed from the
// records on the device. A port of BMA-NFE's `ALPDashboardDataView` and
// `build_learning_outcome_data` (student_registration/alp/views.py), whose
// chart keys carry the semantics of `DashboardDataView`
// (student_registration/mscc/views.py): family status is the child's marital
// status, the gender × age panel buckets on the birth YEAR, cash support
// counts each entry of a list field, and "moved between rounds" is the
// children enrolled in more than one round.
//
// Pure Dart: the screen loads records and reference lists, this file counts.
import 'package:flutter/foundation.dart' show immutable;

import '../../../core/config/app_config.dart';
import '../../../core/models/entity_record.dart';
import '../../../core/models/reference_item.dart';
import '../../registrations/registration_helpers.dart';
import '../analytics_models.dart';
import '../nfe/nfe_analytics.dart' show AnalyticsLabels, parseBirthYear;

/// Extra words these panels need beyond [AnalyticsLabels].
@immutable
class AlpLabels {
  const AlpLabels({
    required this.base,
    required this.notSpecified,
    required this.onTrack,
    required this.developing,
    required this.needsSupport,
    required this.improved,
    required this.stable,
    required this.declined,
    required this.movedFromEarlierRound,
    required this.newInRound,
  });

  final AnalyticsLabels base;
  final String notSpecified;
  final String onTrack;
  final String developing;
  final String needsSupport;
  final String improved;
  final String stable;
  final String declined;
  final String movedFromEarlierRound;
  final String newInRound;

  static const english = AlpLabels(
    base: AnalyticsLabels.english,
    notSpecified: 'Not specified',
    onTrack: 'On track',
    developing: 'Developing',
    needsSupport: 'Needs support',
    improved: 'Improved',
    stable: 'Stable',
    declined: 'Declined',
    movedFromEarlierRound: 'Moved from an earlier round',
    newInRound: 'New in this round',
  );
}

/// The age buckets of the web's gender × age panel
/// (`DashboardDataView.children_gender_age`), which are NOT the analytics
/// API's buckets: this page splits 5-9 / 10-14 where the analytics API uses
/// 5-11 / 12-14.
const alpAgeGroups = ['< 5', '5-9', '10-14', '15-17', '18+', 'Unknown'];

String alpAgeGroup(int? ageYears) {
  if (ageYears == null) return 'Unknown';
  if (ageYears < 5) return '< 5';
  if (ageYears < 10) return '5-9';
  if (ageYears < 15) return '10-14';
  if (ageYears < 18) return '15-17';
  return '18+';
}

/// The filters the ALP registration dashboard offers (the web page's
/// school / round / programme multi-selects, one value each here).
@immutable
class AlpRegistrationFilters {
  const AlpRegistrationFilters({this.schoolId, this.roundId, this.programmeId});

  final int? schoolId;
  final int? roundId;
  final int? programmeId;

  static const none = AlpRegistrationFilters();

  bool get isEmpty => schoolId == null && roundId == null && programmeId == null;

  AlpRegistrationFilters copyWith({
    int? schoolId,
    bool clearSchool = false,
    int? roundId,
    bool clearRound = false,
    int? programmeId,
    bool clearProgramme = false,
  }) =>
      AlpRegistrationFilters(
        schoolId: clearSchool ? null : (schoolId ?? this.schoolId),
        roundId: clearRound ? null : (roundId ?? this.roundId),
        programmeId: clearProgramme ? null : (programmeId ?? this.programmeId),
      );

  @override
  bool operator ==(Object other) =>
      other is AlpRegistrationFilters &&
      other.schoolId == schoolId &&
      other.roundId == roundId &&
      other.programmeId == programmeId;

  @override
  int get hashCode => Object.hash(schoolId, roundId, programmeId);
}

/// One grading definition: the subject and the range its grades are given in.
@immutable
class GradingDefinition {
  const GradingDefinition({required this.id, required this.material, required this.minGrade, required this.maxGrade});

  final int id;
  final String material;
  final int minGrade;
  final int maxGrade;
}

/// Everything the ALP insights count over.
class AlpRegistrationSource {
  const AlpRegistrationSource({
    required this.registrations,
    required this.gradings,
    required this.schools,
    required this.rounds,
    required this.programmes,
    required this.nationalities,
    required this.disabilities,
    required this.gradingDefinitions,
    required this.cashSupportChoices,
    required this.language,
    required this.today,
    this.referrals = const [],
    this.roundCount,
    this.defaultSchoolId,
    this.defaultPartnerId,
  });

  final List<EntityRecord> registrations;

  /// `alp.grading` records, linked to their registration by parent uuid / id.
  final List<EntityRecord> gradings;

  /// Records carrying a `referred_formal_education` value. ALP has no
  /// referral form on the device today, so this is normally empty and the
  /// panel says so rather than drawing an empty ring.
  final List<EntityRecord> referrals;
  final Map<int, ReferenceItem> schools;
  final Map<int, ReferenceItem> rounds;
  final Map<int, ReferenceItem> programmes;
  final Map<int, ReferenceItem> nationalities;
  final Map<int, ReferenceItem> disabilities;
  final Map<int, GradingDefinition> gradingDefinitions;

  /// `(value, label)` of `cash_support_programmes`, in the order the form
  /// declares them: the web draws one bar per choice, zero counts included.
  final List<(String, String)> cashSupportChoices;
  final String language;
  final DateTime today;

  /// Rounds the platform knows, for the "Programme rounds" figure, which the
  /// web takes from `ALPRound.objects.all()` and therefore does not filter.
  final int? roundCount;

  /// What the server forces onto a record typed offline.
  final int? defaultSchoolId;
  final int? defaultPartnerId;
}

/// One registration reduced to what the panels group on.
@immutable
class AlpRegistrationRow {
  const AlpRegistrationRow({
    required this.uuid,
    required this.childKey,
    required this.schoolId,
    required this.partnerId,
    required this.roundId,
    required this.roundLabel,
    required this.programmeId,
    required this.gender,
    required this.nationalityId,
    required this.nationalityLabel,
    required this.ageYears,
    required this.source,
    required this.familyStatus,
    required this.disabilityKey,
    required this.disabilityLabel,
    required this.cashSupport,
    required this.serverId,
  });

  final String uuid;

  /// Identity of the CHILD, so "children per round" counts people and not
  /// enrolments: the child's server id when known, else the record's uuid.
  final String childKey;
  final int? schoolId;
  final int? partnerId;
  final int? roundId;
  final String roundLabel;
  final int? programmeId;
  final String gender;
  final int? nationalityId;
  final String nationalityLabel;
  final int? ageYears;
  final String source;
  final String familyStatus;
  final String disabilityKey;
  final String disabilityLabel;
  final List<String> cashSupport;
  final int? serverId;

  String get ageGroup => alpAgeGroup(ageYears);
}

/// The learning-outcome block of the web page.
@immutable
class LearningOutcomes {
  const LearningOutcomes({
    required this.assessedChildren,
    required this.averageAchievement,
    required this.childrenWithFollowUp,
    required this.improvedChildren,
    required this.performanceBands,
    required this.progress,
    required this.subjects,
  });

  final int assessedChildren;

  /// Mean of every child's latest score, to one decimal; null when none.
  final double? averageAchievement;
  final int childrenWithFollowUp;
  final int improvedChildren;

  /// On track / Developing / Needs support, in that order.
  final List<ChartItem> performanceBands;

  /// Improved / Stable / Declined, in that order.
  final List<ChartItem> progress;

  /// Average percentage per subject, sorted by subject name. `count` holds
  /// the rounded percentage, which is what the bar draws.
  final List<ChartItem> subjects;

  static const empty = LearningOutcomes(
    assessedChildren: 0,
    averageAchievement: null,
    childrenWithFollowUp: 0,
    improvedChildren: 0,
    performanceBands: [],
    progress: [],
    subjects: [],
  );
}

class AlpRegistrationInsights {
  const AlpRegistrationInsights({
    required this.totalRegistrations,
    required this.activeSchools,
    required this.partners,
    required this.programRounds,
    required this.learningOutcomes,
    required this.byGender,
    required this.genderByAgeGroup,
    required this.genderSeries,
    required this.byNationality,
    required this.bySource,
    required this.byRound,
    required this.familyStatus,
    required this.disabilityType,
    required this.cashSupport,
    required this.referredToFormalEducation,
    required this.movedBetweenRounds,
  });

  final int totalRegistrations;
  final int activeSchools;
  final int partners;
  final int programRounds;
  final LearningOutcomes learningOutcomes;
  final List<ChartItem> byGender;

  /// One row per age group, one value per entry of [genderSeries].
  final List<StackedRow> genderByAgeGroup;

  /// `(rawGenderValue, label)` of the series in [genderByAgeGroup].
  final List<(String, String)> genderSeries;
  final List<ChartItem> byNationality;
  final List<ChartItem> bySource;
  final List<ChartItem> byRound;
  final List<ChartItem> familyStatus;
  final List<ChartItem> disabilityType;
  final List<ChartItem> cashSupport;
  final List<ChartItem> referredToFormalEducation;

  /// One row per round, values `[moved, new]`.
  final List<StackedRow> movedBetweenRounds;
}

int? _int(Object? value) => value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

List<String> _stringList(Object? value) {
  if (value is List) {
    return [for (final e in value) e.toString().trim()].where((e) => e.isNotEmpty).toList();
  }
  final single = (value ?? '').toString().trim();
  return single.isEmpty ? const [] : [single];
}

/// Reduces the records to rows, reading both stored shapes.
List<AlpRegistrationRow> alpRegistrationRows(AlpRegistrationSource src, AlpLabels labels) {
  final rows = <AlpRegistrationRow>[];
  for (final record in src.registrations) {
    if (record.deleted || record.syncState == SyncState.discarded) continue;
    final view = RegistrationView(record);
    final data = record.data;
    final person = view.person;

    final roundId = _int(data['round']);
    final round = roundId == null ? null : src.rounds[roundId];
    final nationalityId = _int(view.nationalityId);
    final nationality = nationalityId == null ? null : src.nationalities[nationalityId];
    final birthYear = parseBirthYear(person?['birthday_year'] ?? view.flat['child_birthday_year']);
    final disabilityId = _int(person?['disability'] ?? view.flat['child_disability']);
    final disability = disabilityId == null ? null : src.disabilities[disabilityId];
    final disabilityLabel = disability?.labelFor(src.language) ??
        (person?['disability_label']?.toString().trim().isNotEmpty ?? false
            ? person!['disability_label'].toString()
            : labels.notSpecified);
    final familyStatus = (person?['marital_status'] ?? view.flat['child_marital_status'] ?? '').toString().trim();
    final source = (data['source_of_identification'] ?? '').toString().trim();
    final childId = _int(person?['id']);

    rows.add(AlpRegistrationRow(
      uuid: record.uuid,
      childKey: childId == null ? 'uuid:${record.uuid}' : 'child:$childId',
      schoolId: _int(data['school']) ?? src.defaultSchoolId,
      partnerId: _int(data['partner']) ?? src.defaultPartnerId,
      roundId: roundId,
      roundLabel: round?.labelFor(src.language) ??
          (data['round_label']?.toString().trim().isNotEmpty ?? false
              ? data['round_label'].toString()
              : labels.base.unknown),
      programmeId: _int(data['programme']),
      gender: (view.gender ?? '').trim(),
      nationalityId: nationalityId,
      nationalityLabel: nationality?.labelFor(src.language) ??
          ((view.nationalityLabel?.isNotEmpty ?? false) ? view.nationalityLabel! : labels.base.unknown),
      ageYears: birthYear == null ? null : src.today.year - birthYear,
      source: source.isEmpty ? labels.notSpecified : source,
      familyStatus: familyStatus.isEmpty ? labels.notSpecified : familyStatus,
      disabilityKey: '${disabilityId ?? ''}',
      disabilityLabel: disabilityLabel,
      cashSupport: _stringList(data['cash_support_programmes']),
      serverId: record.serverId,
    ));
  }
  return rows;
}

bool _matches(AlpRegistrationRow row, AlpRegistrationFilters f) {
  if (f.schoolId != null && row.schoolId != f.schoolId) return false;
  if (f.roundId != null && row.roundId != f.roundId) return false;
  if (f.programmeId != null && row.programmeId != f.programmeId) return false;
  return true;
}

/// `_normalise_grade`: a grade as a percentage of its definition's range,
/// clamped to 0..100. Null when the value is not a number or the range is
/// empty.
double? normaliseGrade(Object? value, GradingDefinition definition) {
  final number = value is num ? value.toDouble() : double.tryParse(value?.toString() ?? '');
  if (number == null) return null;
  final range = definition.maxGrade - definition.minGrade;
  if (range <= 0) return null;
  final percentage = (number - definition.minGrade) / range * 100;
  return percentage.clamp(0.0, 100.0);
}

/// `build_learning_outcome_data`, over the gradings of [registrations].
LearningOutcomes buildLearningOutcomes({
  required List<EntityRecord> gradings,
  required Map<int, GradingDefinition> definitions,
  required Set<String> registrationUuids,
  required Set<int> registrationServerIds,
  required AlpLabels labels,
}) {
  // Assessments per registration, each `(created, mean score, raw grades)`.
  final assessments = <String, List<(DateTime, double, Map<String, dynamic>)>>{};
  for (final grading in gradings) {
    if (grading.deleted || grading.syncState == SyncState.discarded) continue;
    final parentUuid = grading.parentUuid;
    final parentId = grading.parentServerId ?? _int(grading.data['registration']);
    final key = parentUuid != null && registrationUuids.contains(parentUuid)
        ? 'uuid:$parentUuid'
        : (parentId != null && registrationServerIds.contains(parentId) ? 'id:$parentId' : null);
    if (key == null) continue;

    final raw = grading.data['grading_data'];
    final grades = raw is Map ? Map<String, dynamic>.from(raw) : const <String, dynamic>{};
    final scores = <double>[];
    for (final entry in grades.entries) {
      final definition = definitions[int.tryParse(entry.key) ?? -1];
      if (definition == null) continue;
      final percentage = normaliseGrade(entry.value, definition);
      if (percentage != null) scores.add(percentage);
    }
    if (scores.isEmpty) continue;
    final created = parseDate(grading.data['created']) ?? parseDate(grading.createdAt) ?? DateTime(1970);
    assessments
        .putIfAbsent(key, () => [])
        .add((created, scores.reduce((a, b) => a + b) / scores.length, grades));
  }

  final latestScores = <double>[];
  final progress = {'Improved': 0, 'Stable': 0, 'Declined': 0};
  final subjectTotals = <int, List<double>>{};
  for (final list in assessments.values) {
    list.sort((a, b) => a.$1.compareTo(b.$1));
    final latest = list.last;
    latestScores.add(latest.$2);
    for (final entry in latest.$3.entries) {
      final definition = definitions[int.tryParse(entry.key) ?? -1];
      if (definition == null) continue;
      final percentage = normaliseGrade(entry.value, definition);
      if (percentage != null) subjectTotals.putIfAbsent(definition.id, () => []).add(percentage);
    }
    if (list.length > 1) {
      final change = latest.$2 - list.first.$2;
      if (change > 0.5) {
        progress['Improved'] = progress['Improved']! + 1;
      } else if (change < -0.5) {
        progress['Declined'] = progress['Declined']! + 1;
      } else {
        progress['Stable'] = progress['Stable']! + 1;
      }
    }
  }

  if (latestScores.isEmpty) return LearningOutcomes.empty;

  var onTrack = 0;
  var developing = 0;
  var needsSupport = 0;
  for (final score in latestScores) {
    if (score >= 75) {
      onTrack++;
    } else if (score >= 50) {
      developing++;
    } else {
      needsSupport++;
    }
  }

  final subjects = <ChartItem>[];
  for (final entry in subjectTotals.entries) {
    final definition = definitions[entry.key]!;
    final mean = entry.value.reduce((a, b) => a + b) / entry.value.length;
    subjects.add(ChartItem(key: '${definition.id}', label: definition.material, count: _round1(mean).round()));
  }
  subjects.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));

  return LearningOutcomes(
    assessedChildren: latestScores.length,
    averageAchievement: _round1(latestScores.reduce((a, b) => a + b) / latestScores.length),
    childrenWithFollowUp: progress.values.fold(0, (a, b) => a + b),
    improvedChildren: progress['Improved']!,
    performanceBands: [
      ChartItem(key: 'On track', label: labels.onTrack, count: onTrack),
      ChartItem(key: 'Developing', label: labels.developing, count: developing),
      ChartItem(key: 'Needs support', label: labels.needsSupport, count: needsSupport),
    ],
    progress: [
      ChartItem(key: 'Improved', label: labels.improved, count: progress['Improved']!),
      ChartItem(key: 'Stable', label: labels.stable, count: progress['Stable']!),
      ChartItem(key: 'Declined', label: labels.declined, count: progress['Declined']!),
    ],
    subjects: subjects,
  );
}

double _round1(double value) => (value * 10).round() / 10;

/// Computes every panel of the dashboard for [filters].
AlpRegistrationInsights computeAlpRegistrationInsights(
  AlpRegistrationSource src,
  AlpRegistrationFilters filters, {
  AlpLabels labels = AlpLabels.english,
}) {
  final rows = alpRegistrationRows(src, labels).where((r) => _matches(r, filters)).toList();

  List<ChartItem> breakdown(String Function(AlpRegistrationRow) key, String Function(AlpRegistrationRow) label) {
    final tally = <String, int>{};
    final labelOf = <String, String>{};
    for (final r in rows) {
      final k = key(r);
      tally.update(k, (v) => v + 1, ifAbsent: () => 1);
      labelOf[k] = label(r);
    }
    return itemsFromTally(tally, (k) => labelOf[k] ?? k);
  }

  String genderKey(String raw) => raw.isEmpty ? 'Unknown' : raw;

  // --- gender × age group: the web draws a pie of "Male - 5-9" slices, which
  // cannot be compared; the same counts read as stacked bars, one row per age
  // group, without changing a number.
  final genderValues = <String>{for (final r in rows) genderKey(r.gender)}.toList()
    ..sort((a, b) {
      const order = {'Male': 0, 'Female': 1, 'Unknown': 9};
      final oa = order[a] ?? 5;
      final ob = order[b] ?? 5;
      return oa != ob ? oa.compareTo(ob) : a.compareTo(b);
    });
  final genderSeries = [for (final g in genderValues) (g, labels.base.gender(g == 'Unknown' ? '' : g))];
  final ageRows = <StackedRow>[];
  for (final group in alpAgeGroups) {
    final values = [
      for (final g in genderValues) rows.where((r) => r.ageGroup == group && genderKey(r.gender) == g).length,
    ];
    if (values.fold(0, (a, b) => a + b) == 0) continue;
    ageRows.add(StackedRow(
      key: group,
      label: group == 'Unknown' ? labels.base.unknown : group,
      values: values,
    ));
  }

  // --- children (not enrolments) per round, and the moved/new split.
  final childrenByRound = <int?, Set<String>>{};
  final roundLabels = <int?, String>{};
  final roundsPerChild = <String, Set<int?>>{};
  for (final r in rows) {
    childrenByRound.putIfAbsent(r.roundId, () => {}).add(r.childKey);
    roundLabels[r.roundId] = r.roundLabel;
    roundsPerChild.putIfAbsent(r.childKey, () => {}).add(r.roundId);
  }
  final roundOrder = childrenByRound.keys.toList()
    ..sort((a, b) => (roundLabels[a] ?? '').toLowerCase().compareTo((roundLabels[b] ?? '').toLowerCase()));
  final byRound = [
    for (final id in roundOrder)
      ChartItem(key: '${id ?? ''}', label: roundLabels[id]!, count: childrenByRound[id]!.length),
  ];
  final movedChildren = {for (final e in roundsPerChild.entries) if (e.value.length > 1) e.key};
  final movedBetweenRounds = [
    for (final id in roundOrder)
      () {
        final children = childrenByRound[id]!;
        final moved = children.where(movedChildren.contains).length;
        return StackedRow(
          key: '${id ?? ''}',
          label: roundLabels[id]!,
          values: [moved, children.length - moved],
        );
      }(),
  ];

  // --- cash support: one bar per choice, in the form's order, zero counts
  // kept — the web builds the list from CASH_SUPPORT_PROGRAMMES, not from the
  // data, so a programme nobody receives still shows as zero.
  final cashTally = <String, int>{};
  for (final r in rows) {
    for (final value in r.cashSupport) {
      cashTally.update(value, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  final cashSupport = src.cashSupportChoices.isEmpty
      ? itemsFromTally(cashTally, (k) => k)
      : [
          for (final (value, label) in src.cashSupportChoices)
            ChartItem(key: value, label: label, count: cashTally[value] ?? 0),
        ];

  // --- referrals to formal education, when the device holds any.
  final referralTally = <String, int>{};
  for (final record in src.referrals) {
    if (record.deleted) continue;
    final value = (record.data['referred_formal_education'] ?? '').toString().trim();
    referralTally.update(value.isEmpty ? labels.notSpecified : value, (v) => v + 1, ifAbsent: () => 1);
  }

  final uuids = {for (final r in rows) r.uuid};
  final serverIds = {for (final r in rows) if (r.serverId != null) r.serverId!};

  return AlpRegistrationInsights(
    totalRegistrations: rows.length,
    activeSchools: rows.map((r) => r.schoolId).whereType<int>().toSet().length,
    partners: rows.map((r) => r.partnerId).whereType<int>().toSet().length,
    programRounds: src.roundCount ?? src.rounds.length,
    learningOutcomes: buildLearningOutcomes(
      gradings: src.gradings,
      definitions: src.gradingDefinitions,
      registrationUuids: uuids,
      registrationServerIds: serverIds,
      labels: labels,
    ),
    byGender: breakdown((r) => genderKey(r.gender), (r) => labels.base.gender(r.gender)),
    genderByAgeGroup: ageRows,
    genderSeries: genderSeries,
    byNationality: breakdown((r) => '${r.nationalityId ?? ''}', (r) => r.nationalityLabel),
    bySource: breakdown((r) => r.source, (r) => r.source),
    byRound: byRound,
    familyStatus: breakdown((r) => r.familyStatus, (r) => r.familyStatus),
    disabilityType: breakdown((r) => r.disabilityKey, (r) => r.disabilityLabel),
    cashSupport: cashSupport,
    referredToFormalEducation: itemsFromTally(referralTally, (k) => k),
    movedBetweenRounds: movedBetweenRounds,
  );
}

/// The entity keys this dashboard reads.
class AlpAnalyticsEntities {
  AlpAnalyticsEntities._();

  static const registration = Entities.alpRegistration;
  static const grading = Entities.alpGrading;
  static const teacher = Entities.alpTeacher;
  static const attendanceDay = Entities.alpAttendanceDay;
  static const schoolProfile = Entities.alpSchoolProfile;
}
