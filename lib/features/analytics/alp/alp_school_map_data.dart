// The ALP school dashboard figures, assembled from the reference data and the
// records on the device. A port of BMA-NFE's `ALPSchoolDashboardView` and
// `ALPSchoolGeoDataView` (student_registration/alp/views.py): the schools in
// scope, the ones that carry GPS coordinates, and the students and teachers
// those mapped schools hold.
//
// Kept free of the map package so the arithmetic can be tested without one:
// coordinates leave here as plain doubles.
import 'package:flutter/foundation.dart' show immutable;

import '../../../core/models/entity_record.dart';
import '../../../core/models/reference_item.dart';

/// Labels this file needs from the caller.
@immutable
class AlpSchoolLabels {
  const AlpSchoolLabels({required this.unknown, required this.notRecorded});

  final String unknown;
  final String notRecorded;

  static const english = AlpSchoolLabels(unknown: 'Unknown', notRecorded: 'Not recorded');
}

/// One school with coordinates, ready to place on the map.
@immutable
class MappedSchool {
  const MappedSchool({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.students,
    required this.teachers,
    this.number,
    this.type,
    this.governorate,
    this.district,
    this.cadaster,
    this.isClosed = false,
    this.isBma = false,
    this.operatingShift,
    this.directorName,
    this.phone,
    this.digitalHub,
    this.adminStaff,
  });

  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final int students;
  final int teachers;

  /// CERD number.
  final String? number;
  final String? type;
  final String? governorate;
  final String? district;
  final String? cadaster;
  final bool isClosed;
  final bool isBma;

  /// Details the editable school profile adds when one is on the device. The
  /// web popup also lists capacity, CWD access and internet, which the mobile
  /// bootstrap does not send — those rows are left out rather than shown blank.
  final String? operatingShift;
  final String? directorName;
  final String? phone;
  final String? digitalHub;
  final String? adminStaff;

  /// "cadaster, district", or whichever of the two is known.
  String? get placeLabel {
    final parts = [cadaster, district].whereType<String>().where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  String get coordinates => '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}

class AlpSchoolDashboard {
  const AlpSchoolDashboard({
    required this.accessibleSchools,
    required this.mappedSchools,
    required this.students,
    required this.teachers,
    required this.unmappedCount,
  });

  /// Every school in the account's scope, whatever the filter — the web's
  /// "Accessible schools" comes from the unfiltered queryset.
  final int accessibleSchools;
  final List<MappedSchool> mappedSchools;

  /// Totals over the MAPPED schools, as the web page sums its markers.
  final int students;
  final int teachers;

  /// Schools that match the filter but carry no coordinates.
  final int unmappedCount;
}

/// The schools an ALP account may report on.
///
/// NOT every school in the bootstrap: `reference_data` sends the account's own
/// school PLUS every `is_bma` school when the account also has MSCC, and the
/// web's `ALPSchoolDashboardView` scopes to `user.school_id` alone (its geo
/// view returns an empty list outright for an account with no school). Taking
/// the raw list would put dozens of MSCC centres' schools on an ALP map and
/// inflate "Accessible schools" to match.
///
/// A school also qualifies when an ALP record on the device names it, so a
/// device that legitimately holds more than one school still maps them all.
List<ReferenceItem> alpSchoolsInScope({
  required Iterable<ReferenceItem> schools,
  required Iterable<EntityRecord> registrations,
  required Iterable<EntityRecord> teachers,
  int? accountSchoolId,
}) {
  final wanted = <int>{?accountSchoolId};
  for (final record in [...registrations, ...teachers]) {
    if (record.deleted) continue;
    final id = _int(record.data['school']);
    if (id != null) wanted.add(id);
  }
  return [for (final school in schools) if (wanted.contains(school.id)) school];
}

class AlpSchoolSource {
  const AlpSchoolSource({
    required this.schools,
    required this.registrations,
    required this.teachers,
    required this.locations,
    required this.language,
    this.schoolProfiles = const [],
    this.defaultSchoolId,
  });

  final List<ReferenceItem> schools;
  final List<EntityRecord> registrations;
  final List<EntityRecord> teachers;

  /// `alp.school_profile` records, one per school at most.
  final List<EntityRecord> schoolProfiles;
  final Map<int, ReferenceItem> locations;
  final String language;

  /// What the server forces onto a record typed offline.
  final int? defaultSchoolId;
}

int? _int(Object? value) => value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

/// Coordinates arrive as numbers from the bootstrap and as strings from a
/// form, and either may be absent — a school needs BOTH to be placed.
double? _coordinate(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

String? _text(Object? value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

String? _place(Map<int, ReferenceItem> locations, Object? id, String language) {
  final numeric = _int(id);
  if (numeric == null) return null;
  return locations[numeric]?.labelFor(language);
}

/// Builds the dashboard for the optional [schoolId] filter.
AlpSchoolDashboard computeAlpSchoolDashboard(
  AlpSchoolSource src, {
  int? schoolId,
  AlpSchoolLabels labels = AlpSchoolLabels.english,
}) {
  int countBySchool(List<EntityRecord> records, int id) {
    var count = 0;
    for (final record in records) {
      if (record.deleted || record.syncState == SyncState.discarded) continue;
      final recordSchool = _int(record.data['school']) ?? src.defaultSchoolId;
      if (recordSchool == id) count++;
    }
    return count;
  }

  final profiles = <int, Map<String, dynamic>>{
    for (final record in src.schoolProfiles)
      if (!record.deleted && _int(record.data['id'] ?? record.serverId) != null)
        _int(record.data['id'] ?? record.serverId)!: record.data,
  };

  final filtered = schoolId == null ? src.schools : src.schools.where((s) => s.id == schoolId).toList();
  final mapped = <MappedSchool>[];
  var unmapped = 0;
  for (final school in filtered) {
    final extra = school.extra;
    final profile = profiles[school.id];
    final latitude = _coordinate(extra['latitude'] ?? profile?['latitude']);
    final longitude = _coordinate(extra['longitude'] ?? profile?['longitude']);
    if (latitude == null || longitude == null) {
      unmapped++;
      continue;
    }
    mapped.add(MappedSchool(
      id: school.id,
      name: school.labelFor(src.language),
      latitude: latitude,
      longitude: longitude,
      students: countBySchool(src.registrations, school.id),
      teachers: countBySchool(src.teachers, school.id),
      number: _text(extra['number'] ?? profile?['number']),
      type: _text(extra['type'] ?? profile?['type']),
      governorate: _place(src.locations, extra['governorate_id'] ?? profile?['governorate'], src.language),
      district: _place(src.locations, extra['district_id'] ?? profile?['district'], src.language),
      cadaster: _place(src.locations, extra['cadaster_id'] ?? profile?['cadaster'], src.language),
      isClosed: extra['is_closed'] == true,
      isBma: extra['is_bma'] == true,
      operatingShift: _text(profile?['operating_shift']),
      directorName: _text(profile?['director_name']),
      phone: _text(profile?['land_phone_number']),
      digitalHub: _text(profile?['have_digital_hub']),
      adminStaff: _text(profile?['admin_staff_number']),
    ));
  }
  mapped.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return AlpSchoolDashboard(
    accessibleSchools: src.schools.length,
    mappedSchools: mapped,
    students: mapped.fold(0, (sum, s) => sum + s.students),
    teachers: mapped.fold(0, (sum, s) => sum + s.teachers),
    unmappedCount: unmapped,
  );
}
