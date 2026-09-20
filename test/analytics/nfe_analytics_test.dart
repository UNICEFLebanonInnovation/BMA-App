// The NFE Advanced Analytics compute layer against the rules of BMA-NFE's
// dashboard/views.py: filters, age buckets, the trend window, the latest
// programme and the two record shapes.
import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/models/entity_record.dart';
import 'package:bma_app/core/models/reference_item.dart';
import 'package:bma_app/features/analytics/analytics_models.dart';
import 'package:bma_app/features/analytics/nfe/nfe_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

final today = DateTime(2026, 9, 20);

EntityRecord serverRegistration(
  int id, {
  String gender = 'Male',
  int nationality = 1,
  String birthYear = '2015',
  int center = 1,
  int partner = 10,
  String created = '2026-09-12T21:43:26',
  List<Map<String, dynamic>>? summary,
}) =>
    EntityRecord(
      uuid: 'srv-$id',
      entity: Entities.msccRegistration,
      module: 'mscc',
      serverId: id,
      createdAt: created,
      data: {
        'id': id,
        'created': created,
        'center': center,
        'center_label': 'Server centre label',
        'partner': partner,
        'partner_label': 'Server partner label',
        'child': {
          'id': 100 + id,
          'first_name': 'A',
          'gender': gender,
          'nationality': nationality,
          'nationality_label': 'سوري',
          'birthday_year': birthYear,
          'birthday_month': '3',
          'birthday_day': '5',
        },
        'education_summary': summary ??
            [
              {'id': 1, 'education_program': 'BLN Level 1'},
              {'id': 2, 'education_program': 'BLN Level 2'},
            ],
      },
    );

EntityRecord localRegistration(String uuid, {String gender = 'Female', String? birthYear = '2019', int? center}) =>
    EntityRecord(
      uuid: uuid,
      entity: Entities.msccRegistration,
      module: 'mscc',
      syncState: SyncState.pending,
      createdAt: '2026-09-19T08:00:00',
      data: {
        'child_first_name': 'B',
        'child_gender': gender,
        'child_nationality': 2,
        'child_birthday_year': ?birthYear,
        'center': ?center,
      },
    );

EntityRecord localService(String uuid, String parentUuid, String programme, String created) => EntityRecord(
      uuid: uuid,
      entity: Entities.msccEducationService,
      module: 'mscc',
      parentUuid: parentUuid,
      syncState: SyncState.pending,
      createdAt: created,
      data: {'education_program': programme},
    );

EntityRecord teacher(int id, {String sex = 'Female', int nationality = 2, int center = 1, String created = '2026-09-01'}) =>
    EntityRecord(
      uuid: 't-$id',
      entity: Entities.msccTeacher,
      module: 'mscc',
      serverId: id,
      data: {'id': id, 'created': created, 'sex': sex, 'nationality': nationality, 'center': center},
    );

NfeAnalyticsSource source({
  List<EntityRecord> registrations = const [],
  List<EntityRecord> services = const [],
  List<EntityRecord> teachers = const [],
}) =>
    NfeAnalyticsSource(
      registrations: registrations,
      educationServices: services,
      teachers: teachers,
      centers: {
        1: const ReferenceItem(kind: 'centers', id: 1, name: 'مركز', nameEn: 'Centre One', extra: {'partner_id': 10}),
        2: const ReferenceItem(kind: 'centers', id: 2, name: 'مركز ٢', nameEn: 'Centre Two', extra: {'partner_id': 11}),
      },
      partners: {
        10: const ReferenceItem(kind: 'partners', id: 10, name: 'Partner Ten'),
        11: const ReferenceItem(kind: 'partners', id: 11, name: 'Partner Eleven'),
      },
      nationalities: {
        1: const ReferenceItem(kind: 'nationalities', id: 1, name: 'سوري', nameEn: 'Syrian'),
        2: const ReferenceItem(kind: 'nationalities', id: 2, name: 'لبناني', nameEn: 'Lebanese'),
      },
      programmeLabels: const {'BLN Level 1': 'BLN Level 1', 'BLN Level 2': 'BLN Level 2'},
      language: 'en',
      today: today,
      defaultPartnerId: 10,
      defaultCenterId: 1,
    );

void main() {
  group('age buckets', () {
    test('mirror _annotate_age', () {
      expect(nfeAgeGroup(null), 'Unknown');
      expect(nfeAgeGroup(0), '0-4');
      expect(nfeAgeGroup(4), '0-4');
      expect(nfeAgeGroup(5), '5-11');
      expect(nfeAgeGroup(11), '5-11');
      expect(nfeAgeGroup(12), '12-14');
      expect(nfeAgeGroup(14), '12-14');
      expect(nfeAgeGroup(15), '15-17');
      expect(nfeAgeGroup(17), '15-17');
      expect(nfeAgeGroup(18), '18+');
      expect(nfeAgeGroup(40), '18+');
    });

    test('birth year must be exactly four digits, as the server regex says', () {
      expect(parseBirthYear('2015'), 2015);
      expect(parseBirthYear(2015), 2015);
      expect(parseBirthYear(' 2015 '), 2015);
      expect(parseBirthYear('15'), isNull);
      expect(parseBirthYear(''), isNull);
      expect(parseBirthYear(null), isNull);
      expect(parseBirthYear('abcd'), isNull);
    });

    test('age is a difference of YEARS, not a birthday age', () {
      // Born in December 2015: a birthday age on 2026-09-20 is 10, the
      // server's ExtractYear(Now()) - birth_year is 11 and lands in 5-11.
      final rows = nfeRegistrationRows(source(registrations: [serverRegistration(1, birthYear: '2015')]), AnalyticsLabels.english);
      expect(rows.single.ageYears, 11);
      expect(rows.single.ageGroup, '5-11');
    });
  });

  group('rows', () {
    test('server shape: labels from the reference lists in the interface language', () {
      final rows = nfeRegistrationRows(source(registrations: [serverRegistration(1)]), AnalyticsLabels.english);
      final r = rows.single;
      expect(r.centerId, 1);
      expect(r.centerLabel, 'Centre One');
      expect(r.partnerId, 10);
      expect(r.partnerLabel, 'Partner Ten');
      expect(r.gender, 'Male');
      expect(r.nationalityId, 1);
      expect(r.nationalityLabel, 'Syrian');
      expect(r.created, DateTime(2026, 9, 12));
      // Latest education service = highest id, as _latest_programme_subquery.
      expect(r.programme, 'BLN Level 2');
    });

    test('Arabic labels use the Arabic reference names', () {
      final src = NfeAnalyticsSource(
        registrations: [serverRegistration(1)],
        educationServices: const [],
        teachers: const [],
        centers: source().centers,
        partners: source().partners,
        nationalities: source().nationalities,
        programmeLabels: const {},
        language: 'ar',
        today: today,
      );
      final r = nfeRegistrationRows(src, AnalyticsLabels.english).single;
      expect(r.centerLabel, 'مركز');
      expect(r.nationalityLabel, 'سوري');
    });

    test('form shape: a pending registration counts at the account centre and partner', () {
      final rows = nfeRegistrationRows(source(registrations: [localRegistration('p1')]), AnalyticsLabels.english);
      final r = rows.single;
      expect(r.centerId, 1);
      expect(r.centerLabel, 'Centre One');
      expect(r.partnerId, 10);
      expect(r.gender, 'Female');
      expect(r.nationalityLabel, 'Lebanese');
      expect(r.ageYears, 7);
      // Dated by the local creation time when the server has not stamped it.
      expect(r.created, DateTime(2026, 9, 19));
      expect(r.programme, 'Unknown');
    });

    test('form shape: the latest LOCAL education service is the programme', () {
      final rows = nfeRegistrationRows(
        source(
          registrations: [localRegistration('p1')],
          services: [
            localService('s1', 'p1', 'BLN Level 1', '2026-09-19T09:00:00'),
            localService('s2', 'p1', 'BLN Level 3', '2026-09-19T10:00:00'),
            localService('s3', 'other', 'YBLN', '2026-09-19T11:00:00'),
          ],
        ),
        AnalyticsLabels.english,
      );
      expect(rows.single.programme, 'BLN Level 3');
    });

    test('an unknown nationality id keeps the server label, then falls back to Unknown', () {
      final withLabel = serverRegistration(1, nationality: 99);
      final rows = nfeRegistrationRows(source(registrations: [withLabel]), AnalyticsLabels.english);
      expect(rows.single.nationalityLabel, 'سوري');
      final noLabel = localRegistration('p1')..data['child_nationality'] = 99;
      final rows2 = nfeRegistrationRows(source(registrations: [noLabel]), AnalyticsLabels.english);
      expect(rows2.single.nationalityLabel, 'Unknown');
    });

    test('deleted and discarded records are skipped', () {
      final deleted = serverRegistration(1).copyWith(deleted: true);
      final discarded = localRegistration('p1').copyWith(syncState: SyncState.discarded);
      final rows = nfeRegistrationRows(source(registrations: [deleted, discarded, serverRegistration(2)]), AnalyticsLabels.english);
      expect(rows, hasLength(1));
    });
  });

  group('filters', () {
    final regs = [
      serverRegistration(1, gender: 'Male', nationality: 1, birthYear: '2015', center: 1, partner: 10, created: '2026-09-01T10:00:00'),
      serverRegistration(2, gender: 'Female', nationality: 2, birthYear: '2020', center: 2, partner: 11, created: '2026-09-10T10:00:00'),
      serverRegistration(3, gender: 'Female', nationality: 1, birthYear: '', center: 1, partner: 10, created: '2026-08-01T10:00:00',
          summary: const [
            {'id': 5, 'education_program': 'BLN Level 1'}
          ]),
    ];
    final teachers = [teacher(1, center: 1, created: '2026-09-05'), teacher(2, center: 2, sex: 'Male', created: '2026-07-01')];
    final src = source(registrations: regs, teachers: teachers);

    test('no filter: everything, distinct counts include every value', () {
      final a = computeNfeAnalytics(src, AnalyticsFilters.none);
      expect(a.summary.totalRegistrations, 3);
      expect(a.summary.totalTeachers, 2);
      expect(a.summary.partners, 2);
      expect(a.summary.centers, 2);
      expect(a.summary.programmes, 2); // BLN Level 2 (x2 via default summary) and BLN Level 1
    });

    test('date range is inclusive and date-only, on created', () {
      final a = computeNfeAnalytics(src, AnalyticsFilters(dateFrom: DateTime(2026, 9, 1), dateTo: DateTime(2026, 9, 10)));
      expect(a.summary.totalRegistrations, 2);
      // Teachers take the same date window.
      expect(a.summary.totalTeachers, 1);
      final onlyTo = computeNfeAnalytics(src, AnalyticsFilters(dateTo: DateTime(2026, 8, 31)));
      expect(onlyTo.summary.totalRegistrations, 1);
    });

    test('partner and centre apply to registrations and teachers', () {
      final byPartner = computeNfeAnalytics(src, const AnalyticsFilters(partnerId: 11));
      expect(byPartner.summary.totalRegistrations, 1);
      expect(byPartner.summary.totalTeachers, 1);
      expect(byPartner.teachersBySex.single.key, 'Male');
      final byCenter = computeNfeAnalytics(src, const AnalyticsFilters(centerId: 1));
      expect(byCenter.summary.totalRegistrations, 2);
      expect(byCenter.summary.totalTeachers, 1);
    });

    test('programme, nationality and gender apply to registrations only', () {
      expect(computeNfeAnalytics(src, const AnalyticsFilters(programme: 'BLN Level 1')).summary.totalRegistrations, 1);
      expect(computeNfeAnalytics(src, const AnalyticsFilters(programme: 'BLN Level 1')).summary.totalTeachers, 2);
      expect(computeNfeAnalytics(src, const AnalyticsFilters(nationalityId: 2)).summary.totalRegistrations, 1);
      expect(computeNfeAnalytics(src, const AnalyticsFilters(gender: 'Female')).summary.totalRegistrations, 2);
    });

    test('an age bound excludes an unknown age, like age_years__gte', () {
      // Ages here are 11, 6 and unknown. A bound that admits every KNOWN age
      // still drops the unknown one, which is what the server's
      // `age_years__gte` does to a null.
      expect(computeNfeAnalytics(src, const AnalyticsFilters(ageMin: 0)).summary.totalRegistrations, 2);
      expect(computeNfeAnalytics(src, const AnalyticsFilters(ageMax: 99)).summary.totalRegistrations, 2);
      expect(computeNfeAnalytics(src, const AnalyticsFilters(ageMin: 5)).summary.totalRegistrations, 2);
      expect(computeNfeAnalytics(src, const AnalyticsFilters(ageMin: 7)).summary.totalRegistrations, 1);
      expect(computeNfeAnalytics(src, const AnalyticsFilters(ageMax: 11)).summary.totalRegistrations, 2);
      expect(computeNfeAnalytics(src, const AnalyticsFilters(ageMin: 6, ageMax: 6)).summary.totalRegistrations, 1);
      expect(computeNfeAnalytics(src, const AnalyticsFilters(ageMin: 30)).summary.totalRegistrations, 0);
    });

    test('an empty result still yields every panel, with an empty window trend', () {
      final a = computeNfeAnalytics(src, const AnalyticsFilters(ageMin: 30));
      expect(a.isEmpty, isFalse); // teachers are unfiltered by age
      expect(a.byGender, isEmpty);
      expect(a.programmeByAgeGroup.isEmpty, isTrue);
      expect(a.trend, hasLength(30));
      expect(a.trend.first.day, DateTime(2026, 8, 22));
      expect(a.trend.last.day, today);
      expect(a.trend.every((p) => p.count == 0), isTrue);
    });
  });

  group('trend', () {
    test('without a date range the series covers the last 30 days only', () {
      final src = source(registrations: [
        serverRegistration(1, created: '2026-09-20T01:00:00'),
        serverRegistration(2, created: '2026-09-20T23:00:00'),
        serverRegistration(3, created: '2026-08-22T12:00:00'), // day 1 of the window
        serverRegistration(4, created: '2026-08-21T12:00:00'), // outside
      ]);
      final a = computeNfeAnalytics(src, AnalyticsFilters.none);
      expect(a.trendIsWindow, isTrue);
      expect(a.summary.totalRegistrations, 4, reason: 'the window trims the trend, not the totals');
      expect(a.trend.first, TrendPoint(DateTime(2026, 8, 22), 1));
      expect(a.trend.last, TrendPoint(DateTime(2026, 9, 20), 2));
      expect(a.trend, hasLength(30));
      expect(a.trend.fold(0, (s, p) => s + p.count), 3);
    });

    test('with a date range the series runs from the first to the last counted day', () {
      final src = source(registrations: [
        serverRegistration(1, created: '2026-03-03T01:00:00'),
        serverRegistration(2, created: '2026-03-07T23:00:00'),
      ]);
      final a = computeNfeAnalytics(src, AnalyticsFilters(dateFrom: DateTime(2026, 1, 1), dateTo: DateTime(2026, 6, 30)));
      expect(a.trendIsWindow, isFalse);
      expect(a.trend.map((p) => p.count).toList(), [1, 0, 0, 0, 1]);
      expect(a.trend.first.day, DateTime(2026, 3, 3));
    });
  });

  group('breakdowns and cross-tab', () {
    final src = source(registrations: [
      serverRegistration(1, gender: 'Male', birthYear: '2015'),
      serverRegistration(2, gender: 'Female', birthYear: '2015'),
      serverRegistration(3, gender: 'Female', birthYear: '2010'),
      serverRegistration(4, gender: '', birthYear: 'x', summary: const [
        {'id': 9, 'education_program': 'BLN Level 1'}
      ]),
    ]);
    final a = computeNfeAnalytics(src, AnalyticsFilters.none);

    test('sorted by count then label, blanks are Unknown', () {
      expect(a.byGender.map((i) => '${i.key}:${i.count}').toList(), ['Female:2', 'Male:1', 'Unknown:1']);
      expect(a.byGender.last.label, 'Unknown');
      expect(a.byAgeGroup.map((i) => '${i.key}:${i.count}').toList(), ['5-11:2', '15-17:1', 'Unknown:1']);
      expect(a.byProgramme.first.label, 'BLN Level 2');
    });

    test('programme rows by size, age groups in bucket order, totals add up', () {
      final ct = a.programmeByAgeGroup;
      expect(ct.rows, ['BLN Level 2', 'BLN Level 1']);
      expect(ct.columns, ['5-11', '15-17', 'Unknown']);
      expect(ct.at('BLN Level 2', '5-11'), 2);
      expect(ct.at('BLN Level 2', '15-17'), 1);
      expect(ct.at('BLN Level 1', 'Unknown'), 1);
      expect(ct.at('BLN Level 1', '5-11'), 0);
      expect(ct.rowTotal('BLN Level 2'), 3);
      expect(ct.columnTotal('5-11'), 2);
      expect(ct.total, 4);
      expect(ct.maxCount, 2);
    });

    test('labels are localised through AnalyticsLabels', () {
      const ar = AnalyticsLabels(unknown: 'غير معروف', male: 'ذكر', female: 'أنثى', other: 'أخرى');
      final b = computeNfeAnalytics(src, AnalyticsFilters.none, labels: ar);
      expect(b.byGender.map((i) => i.label).toList(), ['أنثى', 'ذكر', 'غير معروف']);
      expect(b.programmeByAgeGroup.columns.last, 'غير معروف');
    });
  });

  _reviewRegressions();

  _memoTests();

  group('model helpers', () {
    test('foldTail keeps the head and sums the rest', () {
      final items = [for (var i = 0; i < 10; i++) ChartItem(key: 'k$i', label: 'L$i', count: 10 - i)];
      final folded = foldTail(items, keep: 7, otherLabel: 'Other');
      expect(folded, hasLength(8));
      expect(folded.last.label, 'Other');
      expect(folded.last.count, 3 + 2 + 1);
      expect(foldTail(items.take(8).toList(), keep: 7, otherLabel: 'Other'), hasLength(8), reason: 'no fold for one extra');
    });

    test('percentText prints one decimal only when needed', () {
      expect(percentText(1, 3), '33.3');
      expect(percentText(1, 4), '25');
      expect(percentText(0, 0), '0');
      expect(percentText(2, 3), '66.7');
    });

    test('copyWith clears a field only when asked', () {
      const f = AnalyticsFilters(partnerId: 1, centerId: 2);
      expect(f.copyWith(centerId: null).centerId, 2);
      expect(f.copyWith(clearCenter: true).centerId, isNull);
      expect(f.copyWith(clearCenter: true).partnerId, 1);
      expect(AnalyticsFilters.none.isEmpty, isTrue);
      expect(f.isEmpty, isFalse);
      expect(f, const AnalyticsFilters(partnerId: 1, centerId: 2));
    });
  });
}

// The memo the screens recompute through. Its whole job is to NOT recompute
// on a rebuild that changed nothing, so the test is about identity.
void _memoTests() {
  group('ComputeMemo', () {
    test('recomputes only when the source identity or the key changes', () {
      final memo = ComputeMemo<List<int>, String, Object>();
      final source = [1, 2, 3];
      var calls = 0;
      Object compute() {
        calls++;
        return Object();
      }

      final first = memo.of(source, 'a', compute);
      expect(calls, 1);
      expect(identical(memo.of(source, 'a', compute), first), isTrue, reason: 'same inputs, same answer');
      expect(calls, 1);

      final second = memo.of(source, 'b', compute);
      expect(calls, 2);
      expect(identical(second, first), isFalse);

      // An equal but DIFFERENT list is a new load, and must recompute.
      memo.of([1, 2, 3], 'b', compute);
      expect(calls, 3);
    });

    test('a null answer is an answer, and is not recomputed either', () {
      final memo = ComputeMemo<String, int, String?>();
      var calls = 0;
      String? compute() {
        calls++;
        return null;
      }

      expect(memo.of('s', 1, compute), isNull);
      expect(memo.of('s', 1, compute), isNull);
      expect(calls, 1, reason: 'the slot knows it is filled; it does not infer that from the value');
      memo.of('s', 2, compute);
      expect(calls, 2);
    });
  });
}

// ---------------------------------------------------------------------------
// Regressions found by review. Each of these was wrong once.
// ---------------------------------------------------------------------------
void _reviewRegressions() {
  group('the account scope is a default for LOCAL work only', () {
    test('a pulled registration with no centre keeps none, and is not moved into the account\'s', () {
      // Inventing a centre here put rows into a centre the website's own
      // "Registrations by centre" leaves out, and made them match a centre
      // filter they should miss.
      final orphan = EntityRecord(
        uuid: 'srv-9',
        entity: Entities.msccRegistration,
        module: 'mscc',
        serverId: 9,
        data: const {
          'id': 9,
          'created': '2026-09-12T10:00:00',
          'child': {'id': 9, 'first_name': 'X', 'gender': 'Male', 'birthday_year': '2015'},
        },
      );
      final rows = nfeRegistrationRows(source(registrations: [orphan]), AnalyticsLabels.english);
      expect(rows.single.centerId, isNull);
      expect(rows.single.partnerId, isNull);

      final src = source(registrations: [orphan, serverRegistration(1, center: 1, partner: 10)]);
      // Both the website and this count a null as its own distinct value.
      expect(computeNfeAnalytics(src, AnalyticsFilters.none).summary.centers, 2);
      // ...and a filter on the account's centre does not sweep the orphan in.
      expect(computeNfeAnalytics(src, const AnalyticsFilters(centerId: 1)).summary.totalRegistrations, 1);

      // A record typed offline still counts where the server will put it.
      final local = localRegistration('p1');
      expect(nfeRegistrationRows(source(registrations: [local]), AnalyticsLabels.english).single.centerId, 1);
    });

    test('a teacher takes their partner from their centre alone', () {
      // `center__partner_id` is a join: a teacher whose centre is not on this
      // device matches no partner, rather than falling back to the account's.
      final offCentre = teacher(5, center: 77);
      final rows = nfeTeacherRows(source(teachers: [offCentre]), AnalyticsLabels.english);
      expect(rows.single.centerId, 77);
      expect(rows.single.partnerId, isNull);
      expect(
        computeNfeAnalytics(source(teachers: [offCentre]), const AnalyticsFilters(partnerId: 10)).summary.totalTeachers,
        0,
      );
      // A teacher typed offline has no centre of their own yet.
      final local = EntityRecord(
        uuid: 't-local',
        entity: Entities.msccTeacher,
        module: 'mscc',
        syncState: SyncState.pending,
        data: const {'first_name': 'N', 'sex': 'Female'},
      );
      final localRow = nfeTeacherRows(source(teachers: [local]), AnalyticsLabels.english).single;
      expect(localRow.centerId, 1);
      expect(localRow.partnerId, 10);
    });
  });

  test('the trend window is 30 CALENDAR days, whatever the clock does', () {
    // Subtracting 29x24h from a local midnight lands on 01:00 of the intended
    // day across an autumn fall-back, and the day filter then drops that whole
    // day — the FIRST day of the window, which is exactly the one seeded here.
    final src = source(registrations: [
      serverRegistration(1, created: '2026-10-12T09:00:00'),
      serverRegistration(2, created: '2026-11-10T09:00:00'),
      serverRegistration(3, created: '2026-10-11T09:00:00'), // one day outside
    ]);
    final autumn = NfeAnalyticsSource(
      registrations: src.registrations,
      educationServices: const [],
      teachers: const [],
      centers: src.centers,
      partners: src.partners,
      nationalities: src.nationalities,
      programmeLabels: src.programmeLabels,
      language: 'en',
      today: DateTime(2026, 11, 10),
      defaultCenterId: 1,
      defaultPartnerId: 10,
    );
    final a = computeNfeAnalytics(autumn, AnalyticsFilters.none);
    expect(a.trend, hasLength(30));
    expect(a.trend.first, TrendPoint(DateTime(2026, 10, 12), 1), reason: 'the window keeps its first day');
    expect(a.trend.last, TrendPoint(DateTime(2026, 11, 10), 1));
    expect(a.trend.fold(0, (sum, p) => sum + p.count), 2, reason: 'the day before the window is not counted');
    expect(a.summary.totalRegistrations, 3, reason: 'the window trims the trend, never the totals');
    // Every point is a calendar day apart, with no hour drifting in.
    for (final p in a.trend) {
      expect(p.day.hour, 0);
    }
  });

  test('a measure keeps its decimal while its bar keeps its integer', () {
    const item = ChartItem(key: 'a', label: 'Arabic', count: 68, exact: 67.5);
    expect(item.exact, 67.5);
    expect(item.count, 68);
    expect(item, const ChartItem(key: 'a', label: 'Arabic', count: 68, exact: 67.5));
    expect(item == const ChartItem(key: 'a', label: 'Arabic', count: 68), isFalse);
    // A count chart leaves it null, and nothing downstream has to care.
    expect(const ChartItem(key: 'a', label: 'A', count: 3).exact, isNull);
  });
}
