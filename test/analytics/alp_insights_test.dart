// The ALP compute layers against the rules of BMA-NFE's alp/views.py:
// the registration insights (incl. learning outcomes), the teacher workforce
// indicators, the attendance aggregation and the school map figures.
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/models/entity_record.dart';
import 'package:bma_app/core/models/reference_item.dart';
import 'package:bma_app/features/analytics/alp/alp_attendance_heatmap.dart';
import 'package:bma_app/features/analytics/alp/alp_registration_insights.dart';
import 'package:bma_app/features/analytics/alp/alp_school_map_data.dart';
import 'package:bma_app/features/analytics/alp/alp_teacher_insights.dart';
import 'package:flutter_test/flutter_test.dart';

final today = DateTime(2026, 9, 20);

// --------------------------------------------------------------- fixtures

const schools = <int, ReferenceItem>{
  7: ReferenceItem(kind: 'schools', id: 7, name: 'مدرسة', nameEn: 'Bar Elias School', extra: {
    'number': '1234',
    'type': 'Public School',
    'governorate_id': 1,
    'district_id': 2,
    'cadaster_id': 3,
    'is_bma': true,
    'is_closed': false,
    'latitude': 33.75,
    'longitude': 35.9,
  }),
  8: ReferenceItem(kind: 'schools', id: 8, name: 'مدرسة ٢', nameEn: 'Zahle School', extra: {
    'number': '5678',
    'latitude': '33.85',
    'longitude': '35.92',
    'is_closed': true,
  }),
  9: ReferenceItem(kind: 'schools', id: 9, name: 'No coordinates', extra: {'latitude': null, 'longitude': 35.0}),
};

const rounds = <int, ReferenceItem>{
  1: ReferenceItem(kind: 'rounds.alp', id: 1, name: '2024-2025'),
  2: ReferenceItem(kind: 'rounds.alp', id: 2, name: '2025-2026', extra: {'current_year': true}),
};

const programmes = <int, ReferenceItem>{
  1: ReferenceItem(kind: 'alp_programs', id: 1, name: 'ALP'),
  2: ReferenceItem(kind: 'alp_programs', id: 2, name: 'Bridging'),
};

const nationalities = <int, ReferenceItem>{
  1: ReferenceItem(kind: 'nationalities', id: 1, name: 'سوري', nameEn: 'Syrian'),
  2: ReferenceItem(kind: 'nationalities', id: 2, name: 'لبناني', nameEn: 'Lebanese'),
};

const disabilities = <int, ReferenceItem>{
  1: ReferenceItem(kind: 'disabilities', id: 1, name: 'لا', nameEn: 'None'),
  2: ReferenceItem(kind: 'disabilities', id: 2, name: 'رؤية', nameEn: 'Seeing'),
};

const locations = <int, ReferenceItem>{
  1: ReferenceItem(kind: 'locations', id: 1, name: 'البقاع', nameEn: 'Bekaa'),
  2: ReferenceItem(kind: 'locations', id: 2, name: 'زحلة', nameEn: 'Zahle'),
  3: ReferenceItem(kind: 'locations', id: 3, name: 'بر الياس', nameEn: 'Bar Elias'),
};

const definitions = <int, GradingDefinition>{
  1: GradingDefinition(id: 1, material: 'Arabic', minGrade: 0, maxGrade: 20),
  2: GradingDefinition(id: 2, material: 'Math', minGrade: 0, maxGrade: 10),
  3: GradingDefinition(id: 3, material: 'Broken', minGrade: 5, maxGrade: 5),
};

EntityRecord alpRegistration(
  int id, {
  String gender = 'Male',
  int nationality = 1,
  String birthYear = '2015',
  int school = 7,
  int round = 2,
  int programme = 1,
  int? childId,
  String maritalStatus = 'Single',
  int disability = 1,
  String source = 'Awareness Session',
  List<String> cash = const [],
}) =>
    EntityRecord(
      uuid: 'alp-$id',
      entity: Entities.alpRegistration,
      module: 'alp',
      serverId: id,
      data: {
        'id': id,
        'school': school,
        'school_label': 'S',
        'round': round,
        'round_label': rounds[round]?.name,
        'programme': programme,
        'source_of_identification': source,
        'cash_support_programmes': cash,
        'child': {
          'id': childId ?? 100 + id,
          'first_name': 'C$id',
          'gender': gender,
          'nationality': nationality,
          'nationality_label': 'سوري',
          'birthday_year': birthYear,
          'marital_status': maritalStatus,
          'disability': disability,
          'disability_label': 'لا',
        },
      },
    );

EntityRecord alpGrading(String uuid, {String? parentUuid, int? parentId, required Map<String, Object?> grades, required String created}) =>
    EntityRecord(
      uuid: uuid,
      entity: Entities.alpGrading,
      module: 'alp',
      parentUuid: parentUuid,
      parentServerId: parentId,
      data: {'grading_data': grades, 'created': created, 'registration': parentId},
    );

AlpRegistrationSource regSource({
  List<EntityRecord> registrations = const [],
  List<EntityRecord> gradings = const [],
  List<EntityRecord> referrals = const [],
  List<(String, String)> cashChoices = const [('None', 'None'), ('Haddi', 'Haddi')],
}) =>
    AlpRegistrationSource(
      registrations: registrations,
      gradings: gradings,
      referrals: referrals,
      schools: schools,
      rounds: rounds,
      programmes: programmes,
      nationalities: nationalities,
      disabilities: disabilities,
      gradingDefinitions: definitions,
      cashSupportChoices: cashChoices,
      language: 'en',
      today: today,
      defaultSchoolId: 7,
      defaultPartnerId: 10,
    );

EntityRecord alpTeacher(
  int id, {
  String sex = 'Female',
  int? nationality = 2,
  int? school = 7,
  int? round = 2,
  String assignment = 'ALP only',
  String coaching = 'no',
  List<String> subjects = const ['arabic'],
  List<String> levels = const ['Level one'],
  List<int> trainings = const [1],
  int? sessions = 3,
  int? experience = 5,
  int? hoursAlp = 20,
  int? hoursPrivate,
  String phone = '03-111222',
}) =>
    EntityRecord(
      uuid: 't-$id',
      entity: Entities.alpTeacher,
      module: 'alp',
      serverId: id,
      data: {
        'id': id,
        'sex': sex,
        'nationality': nationality,
        'school': school,
        'round': round,
        'teacher_assignment': assignment,
        'extra_coaching': coaching,
        'subjects_provided': subjects,
        'registration_level': levels,
        'trainings': trainings,
        'training_sessions_attended': sessions,
        'years_of_experience': experience,
        'teaching_hours_mscc': hoursAlp,
        'teaching_hours_private_school': hoursPrivate,
        'phone_number': phone,
      },
    );

AlpTeacherSource teacherSource(List<EntityRecord> teachers) => AlpTeacherSource(
      teachers: teachers,
      schools: schools,
      rounds: rounds,
      nationalities: nationalities,
      trainings: const {
        1: ReferenceItem(kind: 'trainings', id: 1, name: 'Child protection'),
        2: ReferenceItem(kind: 'trainings', id: 2, name: 'Arabic literacy'),
      },
      choiceLabels: const {
        'subjects_provided': {'arabic': 'Arabic', 'math': 'Mathematics'},
        'registration_level': {'Level one': 'Level one'},
        'teacher_assignment': {'ALP only': 'ALP only', 'ALP and FE': 'ALP and FE'},
        'extra_coaching': {'yes': 'Yes', 'no': 'No'},
      },
      language: 'en',
      defaultSchoolId: 7,
    );

EntityRecord attendanceDay(String date, {int? programme = 1, required List<String?> attended, bool deleted = false}) =>
    EntityRecord(
      uuid: 'a-$date-$programme-${attended.length}',
      entity: Entities.alpAttendanceDay,
      module: 'alp',
      deleted: deleted,
      data: {
        'school_id': 7,
        'round_id': 2,
        'programme': programme,
        'attendance_date': date,
        'children_attendance': [
          for (var i = 0; i < attended.length; i++) {'registration_id': i, 'attended': attended[i]},
        ],
      },
    );

void main() {
  group('ALP registration insights', () {
    test('KPIs: schools, partners and the unfiltered round count', () {
      final insights = computeAlpRegistrationInsights(
        regSource(registrations: [
          alpRegistration(1, school: 7),
          alpRegistration(2, school: 8),
          alpRegistration(3, school: 7),
        ]),
        AlpRegistrationFilters.none,
      );
      expect(insights.totalRegistrations, 3);
      expect(insights.activeSchools, 2);
      expect(insights.partners, 1, reason: 'ALP records carry no partner; the account supplies it');
      expect(insights.programRounds, 2, reason: 'ALPRound.objects.all(), unaffected by the filters');
    });

    test('each filter narrows the rows', () {
      final src = regSource(registrations: [
        alpRegistration(1, school: 7, round: 1, programme: 1),
        alpRegistration(2, school: 8, round: 2, programme: 2),
        alpRegistration(3, school: 7, round: 2, programme: 1),
      ]);
      expect(computeAlpRegistrationInsights(src, const AlpRegistrationFilters(schoolId: 7)).totalRegistrations, 2);
      expect(computeAlpRegistrationInsights(src, const AlpRegistrationFilters(roundId: 2)).totalRegistrations, 2);
      expect(computeAlpRegistrationInsights(src, const AlpRegistrationFilters(programmeId: 2)).totalRegistrations, 1);
      expect(
        computeAlpRegistrationInsights(src, const AlpRegistrationFilters(schoolId: 7, roundId: 2)).totalRegistrations,
        1,
      );
    });

    test('a registration typed offline counts at the account school', () {
      final local = EntityRecord(
        uuid: 'local-1',
        entity: Entities.alpRegistration,
        module: 'alp',
        syncState: SyncState.pending,
        data: const {
          'child_first_name': 'Hasan',
          'child_gender': 'Female',
          'child_nationality': 2,
          'child_birthday_year': '2018',
          'child_marital_status': '',
          'round': 2,
          'programme': 1,
        },
      );
      final rows = alpRegistrationRows(regSource(registrations: [local]), AlpLabels.english);
      expect(rows.single.schoolId, 7);
      expect(rows.single.partnerId, 10);
      expect(rows.single.ageYears, 8);
      expect(rows.single.familyStatus, 'Not specified');
      expect(rows.single.nationalityLabel, 'Lebanese');
    });

    test('the age buckets are the dashboard page\'s, not the analytics API\'s', () {
      expect(alpAgeGroup(null), 'Unknown');
      expect(alpAgeGroup(4), '< 5');
      expect(alpAgeGroup(5), '5-9');
      expect(alpAgeGroup(9), '5-9');
      expect(alpAgeGroup(10), '10-14');
      expect(alpAgeGroup(14), '10-14');
      expect(alpAgeGroup(15), '15-17');
      expect(alpAgeGroup(18), '18+');
    });

    test('gender by age group stacks the genders per bucket, blanks as Unknown', () {
      final insights = computeAlpRegistrationInsights(
        regSource(registrations: [
          alpRegistration(1, gender: 'Male', birthYear: '2015'), // 11 → 10-14
          alpRegistration(2, gender: 'Female', birthYear: '2015'),
          alpRegistration(3, gender: 'Female', birthYear: '2019'), // 7 → 5-9
          alpRegistration(4, gender: '', birthYear: 'zz'), // Unknown
        ]),
        AlpRegistrationFilters.none,
      );
      expect(insights.genderSeries.map((s) => s.$1).toList(), ['Male', 'Female', 'Unknown']);
      final rows = {for (final r in insights.genderByAgeGroup) r.key: r.values};
      expect(rows['5-9'], [0, 1, 0]);
      expect(rows['10-14'], [1, 1, 0]);
      expect(rows['Unknown'], [0, 0, 1]);
      expect(rows.containsKey('< 5'), isFalse, reason: 'an empty bucket is not drawn');
    });

    test('registrations per round count CHILDREN, and moved/new splits them', () {
      // Child 500 enrols in both rounds; child 501 only in the newer one.
      final src = regSource(registrations: [
        alpRegistration(1, round: 1, childId: 500),
        alpRegistration(2, round: 2, childId: 500),
        alpRegistration(3, round: 2, childId: 501),
      ]);
      final insights = computeAlpRegistrationInsights(src, AlpRegistrationFilters.none);
      expect(insights.totalRegistrations, 3);
      final byRound = {for (final i in insights.byRound) i.label: i.count};
      expect(byRound['2024-2025'], 1);
      expect(byRound['2025-2026'], 2);
      final moved = {for (final r in insights.movedBetweenRounds) r.label: r.values};
      expect(moved['2024-2025'], [1, 0], reason: 'the child appears in a second round, so it is "moved" in both');
      expect(moved['2025-2026'], [1, 1]);
    });

    test('cash support lists every choice in form order, zero counts kept', () {
      final insights = computeAlpRegistrationInsights(
        regSource(registrations: [
          alpRegistration(1, cash: const ['Haddi']),
          alpRegistration(2, cash: const ['Haddi', 'None']),
        ]),
        AlpRegistrationFilters.none,
      );
      expect(insights.cashSupport.map((i) => '${i.key}:${i.count}').toList(), ['None:1', 'Haddi:2']);
    });

    test('with no choice list the observed values are used instead', () {
      final insights = computeAlpRegistrationInsights(
        regSource(registrations: [alpRegistration(1, cash: const ['WFP cash assistance'])], cashChoices: const []),
        AlpRegistrationFilters.none,
      );
      expect(insights.cashSupport.single.key, 'WFP cash assistance');
    });

    test('family status and disability resolve labels, blanks become Not specified', () {
      final insights = computeAlpRegistrationInsights(
        regSource(registrations: [
          alpRegistration(1, maritalStatus: 'Single', disability: 2),
          alpRegistration(2, maritalStatus: '', disability: 1),
        ]),
        AlpRegistrationFilters.none,
      );
      expect(insights.familyStatus.map((i) => i.label).toSet(), {'Single', 'Not specified'});
      expect(insights.disabilityType.map((i) => i.label).toSet(), {'Seeing', 'None'});
    });

    test('with no referral records the panel is empty rather than zeroed', () {
      final insights = computeAlpRegistrationInsights(
        regSource(registrations: [alpRegistration(1)]),
        AlpRegistrationFilters.none,
      );
      expect(insights.referredToFormalEducation, isEmpty);
    });
  });

  group('learning outcomes', () {
    test('a grade is a percentage of its definition range, clamped', () {
      expect(normaliseGrade(10, definitions[1]!), 50);
      expect(normaliseGrade('20', definitions[1]!), 100);
      expect(normaliseGrade(-5, definitions[1]!), 0);
      expect(normaliseGrade(99, definitions[1]!), 100);
      expect(normaliseGrade('abc', definitions[1]!), isNull);
      expect(normaliseGrade(5, definitions[3]!), isNull, reason: 'an empty range cannot be normalised');
    });

    test('the latest assessment per child drives the bands and the subjects', () {
      final src = regSource(
        registrations: [alpRegistration(1), alpRegistration(2)],
        gradings: [
          // Child 1: 50% then 90% — improved, on track.
          alpGrading('g1', parentId: 1, grades: {'1': 10}, created: '2026-01-01T00:00:00'),
          alpGrading('g2', parentId: 1, grades: {'1': 18, '2': 9}, created: '2026-06-01T00:00:00'),
          // Child 2: one assessment at 20% — needs support, no follow-up.
          alpGrading('g3', parentId: 2, grades: {'1': 4}, created: '2026-03-01T00:00:00'),
        ],
      );
      final o = computeAlpRegistrationInsights(src, AlpRegistrationFilters.none).learningOutcomes;
      expect(o.assessedChildren, 2);
      // (90 + 20) / 2
      expect(o.averageAchievement, 55.0);
      expect(o.childrenWithFollowUp, 1);
      expect(o.improvedChildren, 1);
      expect({for (final b in o.performanceBands) b.key: b.count},
          {'On track': 1, 'Developing': 0, 'Needs support': 1});
      expect({for (final p in o.progress) p.key: p.count}, {'Improved': 1, 'Stable': 0, 'Declined': 0});
      // Arabic: latest of child 1 is 90, child 2 is 20 → 55. Math: only child 1's 90.
      expect({for (final s in o.subjects) s.label: s.count}, {'Arabic': 55, 'Math': 90});
    });

    test('stable and declined use the ±0.5 point thresholds', () {
      LearningOutcomes outcomesFor(num first, num second) => computeAlpRegistrationInsights(
            regSource(registrations: [alpRegistration(1)], gradings: [
              alpGrading('a', parentId: 1, grades: {'1': first}, created: '2026-01-01T00:00:00'),
              alpGrading('b', parentId: 1, grades: {'1': second}, created: '2026-02-01T00:00:00'),
            ]),
            AlpRegistrationFilters.none,
          ).learningOutcomes;
      // 10 → 10.1 out of 20 is +0.5 points: not an improvement.
      expect(outcomesFor(10, 10.1).progress.firstWhere((p) => p.key == 'Stable').count, 1);
      expect(outcomesFor(10, 11).progress.firstWhere((p) => p.key == 'Improved').count, 1);
      expect(outcomesFor(11, 10).progress.firstWhere((p) => p.key == 'Declined').count, 1);
    });

    test('a grading for an unknown definition, or for a filtered-out child, is ignored', () {
      final src = regSource(
        registrations: [alpRegistration(1, school: 7), alpRegistration(2, school: 8)],
        gradings: [
          alpGrading('g1', parentId: 1, grades: {'99': 10}, created: '2026-01-01T00:00:00'),
          alpGrading('g2', parentId: 2, grades: {'1': 20}, created: '2026-01-01T00:00:00'),
        ],
      );
      expect(computeAlpRegistrationInsights(src, AlpRegistrationFilters.none).learningOutcomes.assessedChildren, 1);
      final filtered = computeAlpRegistrationInsights(src, const AlpRegistrationFilters(schoolId: 7));
      expect(filtered.learningOutcomes.assessedChildren, 0, reason: 'child 2 is out of scope');
      expect(filtered.learningOutcomes.averageAchievement, isNull);
    });

    test('a grading attached by parent uuid counts too', () {
      final local = EntityRecord(
        uuid: 'local-1',
        entity: Entities.alpRegistration,
        module: 'alp',
        syncState: SyncState.pending,
        data: const {'child_first_name': 'H', 'child_gender': 'Male', 'round': 2},
      );
      final src = regSource(
        registrations: [local],
        gradings: [alpGrading('g1', parentUuid: 'local-1', grades: {'2': 8}, created: '2026-02-01T00:00:00')],
      );
      final o = computeAlpRegistrationInsights(src, AlpRegistrationFilters.none).learningOutcomes;
      expect(o.assessedChildren, 1);
      expect(o.averageAchievement, 80.0);
    });
  });

  group('ALP teacher insights', () {
    test('the indicators follow the server, nulls and all', () {
      final insights = computeAlpTeacherInsights(
        teacherSource([
          alpTeacher(1, experience: 4, sessions: 2, trainings: const [1]),
          alpTeacher(2, experience: null, sessions: null, trainings: const [], phone: ''),
          alpTeacher(3, experience: 9, sessions: 4, trainings: const [], phone: '03-999'),
        ]),
        AlpTeacherFilters.none,
      );
      expect(insights.total, 3);
      // Trained: #1 by topic, #3 by sessions; #2 has neither.
      expect(insights.trained, 2);
      expect(insights.trainedPercent, 66.7);
      expect(insights.contactPercent, 66.7);
      // Averages skip the nulls: (4 + 9) / 2 and (2 + 4) / 2.
      expect(insights.averageExperience, 6.5);
      expect(insights.averageSessions, 3.0);
      expect(insights.schools, 1);
    });

    test('zero teachers gives zero percentages rather than a division by zero', () {
      final insights = computeAlpTeacherInsights(teacherSource(const []), AlpTeacherFilters.none);
      expect(insights.total, 0);
      expect(insights.trainedPercent, 0);
      expect(insights.contactPercent, 0);
      expect(insights.averageExperience, 0);
      expect(insights.hours.map((h) => h.count).toList(), [0, 0]);
    });

    test('groupings are ordered by value with the blank group last', () {
      final insights = computeAlpTeacherInsights(
        teacherSource([
          alpTeacher(1, sex: 'Male', assignment: 'ALP and FE'),
          alpTeacher(2, sex: 'Female', assignment: 'ALP only'),
          alpTeacher(3, sex: '', assignment: ''),
          alpTeacher(4, sex: 'Female', assignment: 'ALP only'),
        ]),
        AlpTeacherFilters.none,
      );
      expect(insights.gender.map((i) => '${i.key}:${i.count}').toList(), ['Female:2', 'Male:1', ':1']);
      expect(insights.gender.last.label, 'Not specified');
      expect(insights.assignment.map((i) => i.label).toList(), ['ALP and FE', 'ALP only', 'Not specified']);
    });

    test('list fields count each entry and wear their form labels', () {
      final insights = computeAlpTeacherInsights(
        teacherSource([
          alpTeacher(1, subjects: const ['arabic', 'math'], levels: const ['Level one']),
          alpTeacher(2, subjects: const ['arabic'], levels: const []),
        ]),
        AlpTeacherFilters.none,
      );
      expect({for (final i in insights.subjects) i.label: i.count}, {'Arabic': 2, 'Mathematics': 1});
      expect(insights.levels.single.count, 1);
    });

    test('training topics are ordered by count then name, and counted once per teacher', () {
      final insights = computeAlpTeacherInsights(
        teacherSource([
          alpTeacher(1, trainings: const [1, 2, 1]),
          alpTeacher(2, trainings: const [2]),
        ]),
        AlpTeacherFilters.none,
      );
      expect(insights.trainings.map((i) => '${i.label}:${i.count}').toList(),
          ['Arabic literacy:2', 'Child protection:1']);
    });

    test('teaching hours are summed into two bars', () {
      final insights = computeAlpTeacherInsights(
        teacherSource([
          alpTeacher(1, hoursAlp: 20, hoursPrivate: 5),
          alpTeacher(2, hoursAlp: 10, hoursPrivate: null),
        ]),
        AlpTeacherFilters.none,
      );
      expect({for (final h in insights.hours) h.key: h.count}, {'alp': 30, 'private': 5});
    });

    test('an offline teacher counts at the account school, and the filters narrow', () {
      final local = EntityRecord(
        uuid: 'local-t',
        entity: Entities.alpTeacher,
        module: 'alp',
        syncState: SyncState.pending,
        data: const {'first_name': 'A', 'sex': 'Female', 'round': 1},
      );
      final src = teacherSource([alpTeacher(1, school: 8, round: 2), local]);
      expect(computeAlpTeacherInsights(src, AlpTeacherFilters.none).total, 2);
      expect(computeAlpTeacherInsights(src, const AlpTeacherFilters(schoolId: 7)).total, 1);
      expect(computeAlpTeacherInsights(src, const AlpTeacherFilters(roundId: 2)).total, 1);
    });
  });

  group('ALP attendance heatmaps', () {
    AlpAttendanceSource src(List<EntityRecord> days) => AlpAttendanceSource(
          attendanceDays: days,
          programmes: programmes,
          language: 'en',
          today: today,
        );

    test('total counts every row, absent only the ones marked No', () {
      final insights = computeAlpAttendance(
        src([attendanceDay('2026-09-10', attended: ['Yes', 'No', null, ''])]),
        unknownLabel: 'Unknown',
      );
      final cell = insights.overall[DateTime(2026, 9, 10)]!;
      expect(cell.total, 4);
      expect(cell.absent, 1);
      expect(cell.present, 3);
      expect(cell.rate, 0.75);
    });

    test('two programmes on one date merge overall and stay apart per programme', () {
      final insights = computeAlpAttendance(
        src([
          attendanceDay('2026-09-10', programme: 1, attended: ['Yes', 'Yes']),
          attendanceDay('2026-09-10', programme: 2, attended: ['No']),
        ]),
        unknownLabel: 'Unknown',
      );
      expect(insights.overall[DateTime(2026, 9, 10)]!.total, 3);
      expect(insights.overall[DateTime(2026, 9, 10)]!.absent, 1);
      expect(insights.byProgramme.map((p) => p.label).toList(), ['ALP', 'Bridging']);
      expect(insights.byProgramme.first.summary.total, 2);
      expect(insights.byProgramme.last.summary.present, 0);
    });

    test('a sheet with no programme is labelled Unknown and sorted last', () {
      final insights = computeAlpAttendance(
        src([
          attendanceDay('2026-09-10', programme: null, attended: ['Yes']),
          attendanceDay('2026-09-11', programme: 2, attended: ['Yes']),
        ]),
        unknownLabel: 'Unknown',
      );
      expect(insights.byProgramme.map((p) => p.label).toList(), ['Bridging', 'Unknown']);
    });

    test('years are listed newest first and the current year wins when it has data', () {
      final insights = computeAlpAttendance(
        src([
          attendanceDay('2025-05-10', attended: ['Yes']),
          attendanceDay('2026-05-10', attended: ['Yes', 'No']),
        ]),
        unknownLabel: 'Unknown',
      );
      expect(insights.years, [2026, 2025]);
      expect(insights.year, 2026);
      expect(insights.overall.length, 1);
      // An explicit pick wins over the default.
      final picked = computeAlpAttendance(
        src([attendanceDay('2025-05-10', attended: ['Yes'])]),
        year: 2025,
        unknownLabel: 'Unknown',
      );
      expect(picked.year, 2025);
    });

    test('with nothing in the current year the newest year that HAS data is shown', () {
      final insights = computeAlpAttendance(
        src([attendanceDay('2024-05-10', attended: ['Yes'])]),
        unknownLabel: 'Unknown',
      );
      expect(insights.year, 2024);
      expect(insights.isEmpty, isFalse);
    });

    test('empty, deleted, dateless and row-less sheets contribute nothing', () {
      final empty = computeAlpAttendance(src(const []), unknownLabel: 'Unknown');
      expect(empty.isEmpty, isTrue);
      expect(empty.year, today.year);
      expect(empty.years, [today.year]);

      final skipped = computeAlpAttendance(
        src([
          attendanceDay('2026-09-10', attended: ['Yes'], deleted: true),
          attendanceDay('not-a-date', attended: ['Yes']),
          attendanceDay('2026-09-12', attended: const []),
        ]),
        unknownLabel: 'Unknown',
      );
      expect(skipped.isEmpty, isTrue);
    });
  });

  group('ALP school map', () {
    AlpSchoolSource src({int? filterAwareDefault = 7, List<EntityRecord> profiles = const []}) => AlpSchoolSource(
          schools: schools.values.toList(),
          registrations: [
            alpRegistration(1, school: 7),
            alpRegistration(2, school: 7),
            alpRegistration(3, school: 8),
            EntityRecord(
              uuid: 'local',
              entity: Entities.alpRegistration,
              module: 'alp',
              syncState: SyncState.pending,
              data: const {'child_first_name': 'X'},
            ),
          ],
          teachers: [alpTeacher(1, school: 7), alpTeacher(2, school: 8)],
          schoolProfiles: profiles,
          locations: locations,
          language: 'en',
          defaultSchoolId: filterAwareDefault,
        );

    test('only schools with BOTH coordinates are mapped; strings parse', () {
      final dashboard = computeAlpSchoolDashboard(src());
      expect(dashboard.accessibleSchools, 3);
      expect(dashboard.mappedSchools.map((s) => s.id).toList(), [7, 8]);
      expect(dashboard.unmappedCount, 1);
      expect(dashboard.mappedSchools.last.latitude, 33.85);
    });

    test('students and teachers are counted per school, offline rows at the account school', () {
      final dashboard = computeAlpSchoolDashboard(src());
      final barElias = dashboard.mappedSchools.firstWhere((s) => s.id == 7);
      expect(barElias.students, 3, reason: 'two server rows plus the offline one');
      expect(barElias.teachers, 1);
      expect(dashboard.students, 4);
      expect(dashboard.teachers, 2);
    });

    test('the filter narrows the markers but never the accessible count', () {
      final dashboard = computeAlpSchoolDashboard(src(), schoolId: 8);
      expect(dashboard.accessibleSchools, 3);
      expect(dashboard.mappedSchools.single.id, 8);
      expect(dashboard.students, 1);
      expect(dashboard.unmappedCount, 0);

      final unmapped = computeAlpSchoolDashboard(src(), schoolId: 9);
      expect(unmapped.mappedSchools, isEmpty);
      expect(unmapped.unmappedCount, 1);
      expect(unmapped.students, 0);
    });

    test('location names resolve, an unknown id is left out, and the status reads through', () {
      final school = computeAlpSchoolDashboard(src()).mappedSchools.first;
      expect(school.name, 'Bar Elias School');
      expect(school.governorate, 'Bekaa');
      expect(school.placeLabel, 'Bar Elias, Zahle');
      expect(school.isBma, isTrue);
      expect(school.isClosed, isFalse);
      expect(school.coordinates, '33.75000, 35.90000');
      final closed = computeAlpSchoolDashboard(src()).mappedSchools.last;
      expect(closed.isClosed, isTrue);
      expect(closed.governorate, isNull);
    });

    test('a school profile on the device adds the operational rows', () {
      final profile = EntityRecord(
        uuid: 'sp',
        entity: Entities.alpSchoolProfile,
        module: 'alp',
        serverId: 7,
        data: const {
          'id': 7,
          'operating_shift': 'Morning',
          'director_name': 'Nadia',
          'land_phone_number': '08-100200',
          'have_digital_hub': 'Yes',
          'admin_staff_number': '4',
        },
      );
      final school = computeAlpSchoolDashboard(src(profiles: [profile])).mappedSchools.first;
      expect(school.operatingShift, 'Morning');
      expect(school.directorName, 'Nadia');
      expect(school.phone, '08-100200');
      expect(school.digitalHub, 'Yes');
      expect(school.adminStaff, '4');
      // A school with no profile keeps them null rather than blank.
      expect(computeAlpSchoolDashboard(src(profiles: [profile])).mappedSchools.last.directorName, isNull);
    });
  });
}
