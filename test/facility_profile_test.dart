import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/db/app_database.dart';
import 'package:bma_app/core/db/entity_dao.dart';
import 'package:bma_app/core/db/reference_dao.dart';
import 'package:bma_app/core/forms/reference_cache.dart';
import 'package:bma_app/core/models/reference_item.dart';
import 'package:bma_app/features/profiles/facility_profile.dart';
import 'package:bma_app/l10n/app_localizations_ar.dart';
import 'package:bma_app/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _labels = FacilityLabels(
  partner: 'Partner',
  governorate: 'Governorate',
  district: 'District',
  cadaster: 'Cadaster',
  type: 'Type',
  coordinates: 'Coordinates',
  schoolNumber: 'School number',
  workingDays: 'Working days',
  weekend: 'Weekend',
  bmaSchool: 'BMA school',
  yes: 'Yes',
  no: 'No',
  notRecorded: 'Not recorded',
);

/// Shapes taken from the mobile API bootstrap payload.
final _bekaa = ReferenceItem(kind: 'locations', id: 1, name: 'البقاع', nameEn: 'Bekaa');
final _zahle = ReferenceItem(kind: 'locations', id: 2, name: 'زحلة', nameEn: 'Zahle', parentId: 1);
final _barElias = ReferenceItem(kind: 'locations', id: 3, name: 'بر الياس', nameEn: 'Bar Elias', parentId: 2);
final _partner = ReferenceItem(kind: 'partners', id: 15, name: 'Test Partner');

final _center = ReferenceItem(
  kind: 'centers',
  id: 85,
  name: 'Amal Center',
  extra: const {
    'partner_id': 15,
    'governorate_id': 1,
    'caza_id': 2,
    'cadaster_id': 3,
    'type': 'Community Hub',
    'programs': ['BLN', 'CBECE'],
    'provided_packages': ['BLN', 'YBLN'],
    'is_active': true,
    'latitude': 33.7654321,
    'longitude': 35.9123456,
  },
);

final _school = ReferenceItem(
  kind: 'schools',
  id: 7,
  name: 'Bar Elias Public School',
  extra: const {
    'number': '1234',
    'governorate_id': 1,
    'district_id': 2,
    'cadaster_id': 3,
    'type': 'Public School',
    'is_bma': true,
    'is_closed': false,
    'working_days': ['Monday', 'Tuesday'],
    'weekend': ['Sunday'],
  },
);

void main() {
  late AppDatabase db;
  late ReferenceCache cache;
  late EntityDao dao;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await AppDatabase.openInMemory();
    final reference = ReferenceDao(db);
    await reference.replaceKind('locations', [_bekaa, _zahle, _barElias]);
    await reference.replaceKind('partners', [_partner]);
    await reference.replaceKind('centers', [_center]);
    await reference.replaceKind('schools', [_school]);
    cache = ReferenceCache(reference);
    dao = EntityDao(db);
  });

  tearDown(() => db.close());

  Map<String, String> factsOf(List<(String, String, dynamic)> facts) =>
      {for (final (label, value, _) in facts) label: value};

  group('NFE centre profile', () {
    test('resolves the partner and the location chain', () async {
      final profile = await buildCenterProfile(
        cache: cache,
        dao: dao,
        center: _center,
        language: 'en',
        labels: _labels,
      );
      expect(profile.name, 'Amal Center');
      expect(profile.subtitle, 'Test Partner');
      final facts = factsOf(profile.facts);
      expect(facts['Partner'], 'Test Partner');
      expect(facts['Governorate'], 'Bekaa');
      expect(facts['District'], 'Zahle');
      expect(facts['Cadaster'], 'Bar Elias');
      expect(facts['Type'], 'Community Hub');
      expect(facts['Coordinates'], '33.76543, 35.91235');
    });

    test('follows the interface language for place names', () async {
      final profile = await buildCenterProfile(
        cache: cache,
        dao: dao,
        center: _center,
        language: 'ar',
        labels: _labels,
      );
      expect(factsOf(profile.facts)['Governorate'], 'البقاع');
    });

    test('merges the programmes with the packages the centre provides', () async {
      final profile = await buildCenterProfile(
        cache: cache,
        dao: dao,
        center: _center,
        language: 'en',
        labels: _labels,
      );
      expect(profile.programmes, containsAll(['BLN', 'CBECE', 'YBLN']));
      // BLN appears in both lists and must not be shown twice.
      expect(profile.programmes.where((p) => p == 'BLN'), hasLength(1));
      expect(profile.active, isTrue);
    });

    test('counts the work held on this device', () async {
      await dao.createLocal(entity: Entities.msccRegistration, data: {'child_first_name': 'Nour'});
      await dao.createLocal(entity: Entities.msccRegistration, data: {'child_first_name': 'Sara'});
      await dao.createLocal(
        entity: Entities.msccAttendanceDay,
        naturalKey: 'day-1',
        data: {'attendance_date': '2026-09-10'},
      );
      final profile = await buildCenterProfile(
        cache: cache,
        dao: dao,
        center: _center,
        language: 'en',
        labels: _labels,
      );
      expect(profile.registered, 2);
      expect(profile.attendanceDays, 1);
      expect(profile.pending, 3, reason: 'nothing has been pushed yet');
    });

    test('reports an inactive centre', () async {
      final closed = ReferenceItem(
        kind: 'centers',
        id: 86,
        name: 'Closed Centre',
        extra: const {'is_active': false},
      );
      final profile = await buildCenterProfile(
        cache: cache,
        dao: dao,
        center: closed,
        language: 'en',
        labels: _labels,
      );
      expect(profile.active, isFalse);
      // Unknown ids fall back rather than throwing.
      expect(factsOf(profile.facts)['Governorate'], 'Not recorded');
    });
  });

  group('ALP school profile', () {
    test('shows the number, the location chain and the school flags', () async {
      final profile = await buildSchoolProfile(
        cache: cache,
        dao: dao,
        school: _school,
        language: 'en',
        labels: _labels,
      );
      expect(profile.name, 'Bar Elias Public School');
      expect(profile.subtitle, 'School number 1234');
      final facts = factsOf(profile.facts);
      expect(facts['School number'], '1234');
      expect(facts['District'], 'Zahle');
      expect(facts['BMA school'], 'Yes');
      expect(facts['Working days'], 'Monday, Tuesday');
      expect(facts['Weekend'], 'Sunday');
      expect(profile.active, isTrue, reason: 'the school is not closed');
    });

    test('omits coordinates and day lists that the server did not send', () async {
      final sparse = ReferenceItem(
        kind: 'schools',
        id: 8,
        name: 'Sparse School',
        extra: const {'number': '9', 'is_closed': true},
      );
      final profile = await buildSchoolProfile(
        cache: cache,
        dao: dao,
        school: sparse,
        language: 'en',
        labels: _labels,
      );
      final labels = profile.facts.map((f) => f.$1).toList();
      expect(labels, isNot(contains('Coordinates')));
      expect(labels, isNot(contains('Working days')));
      expect(profile.active, isFalse);
    });

    test('counts ALP work separately from NFE work', () async {
      await dao.createLocal(entity: Entities.msccRegistration, data: {'child_first_name': 'Nour'});
      await dao.createLocal(entity: Entities.alpRegistration, data: {'child_first_name': 'Rami'});
      final profile = await buildSchoolProfile(
        cache: cache,
        dao: dao,
        school: _school,
        language: 'en',
        labels: _labels,
      );
      expect(profile.registered, 1);
      expect(profile.pending, 1);
    });
  });

  group('module naming', () {
    test('the Makani module is presented as NFE in both languages', () {
      expect(AppLocalizationsEn().mscc, 'NFE');
      expect(AppLocalizationsAr().mscc, isNot(contains('مكاني')));
      expect(AppLocalizationsAr().mscc, 'التعليم غير النظامي');
    });

    test('the profile screens have titles in both languages', () {
      for (final l10n in [AppLocalizationsEn(), AppLocalizationsAr()]) {
        expect(l10n.centerProfile, isNotEmpty);
        expect(l10n.schoolProfile, isNotEmpty);
      }
      expect(AppLocalizationsEn().centerProfile, isNot(AppLocalizationsAr().centerProfile));
    });
  });
}
