import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/db/providers.dart';
import '../../core/forms/reference_cache.dart';
import '../../core/models/entity_record.dart';
import '../../core/models/reference_item.dart';

/// Everything the centre and school profiles show, assembled from reference
/// data already on the device plus counts from the local records. Nothing here
/// needs the network, so the profiles work in the field.
class FacilityProfile {
  const FacilityProfile({
    required this.name,
    required this.facts,
    required this.programmes,
    required this.registered,
    required this.attendanceDays,
    required this.pending,
    this.subtitle,
    this.active = true,
    this.statusLabel,
  });

  final String name;
  final String? subtitle;

  /// Ordered label/value pairs; values are already localised and resolved.
  final List<(String label, String value, IconData icon)> facts;
  final List<String> programmes;
  final int registered;
  final int attendanceDays;
  final int pending;
  final bool active;
  final String? statusLabel;
}

/// Labels a profile needs from the caller, so this file stays free of
/// AppLocalizations and remains unit-testable.
class FacilityLabels {
  const FacilityLabels({
    required this.partner,
    required this.governorate,
    required this.district,
    required this.cadaster,
    required this.type,
    required this.coordinates,
    required this.schoolNumber,
    required this.workingDays,
    required this.weekend,
    required this.bmaSchool,
    required this.yes,
    required this.no,
    required this.notRecorded,
  });

  final String partner;
  final String governorate;
  final String district;
  final String cadaster;
  final String type;
  final String coordinates;
  final String schoolNumber;
  final String workingDays;
  final String weekend;
  final String bmaSchool;
  final String yes;
  final String no;
  final String notRecorded;
}

String _text(Object? value, String fallback) {
  final s = (value ?? '').toString().trim();
  return s.isEmpty ? fallback : s;
}

List<String> _stringList(Object? value) {
  if (value is List) {
    return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
  }
  final single = (value ?? '').toString().trim();
  return single.isEmpty ? const [] : [single];
}

/// Resolves a location id to its localised name.
Future<String?> _place(ReferenceCache cache, Object? id, String language) async {
  if (id == null) return null;
  final numeric = id is num ? id.toInt() : int.tryParse(id.toString());
  if (numeric == null) return null;
  final item = await cache.item('locations', numeric);
  return item?.labelFor(language);
}

/// Builds the NFE centre profile for [center].
Future<FacilityProfile> buildCenterProfile({
  required ReferenceCache cache,
  required EntityDao dao,
  required ReferenceItem center,
  required String language,
  required FacilityLabels labels,
}) async {
  final extra = center.extra;
  final partner = await cache.item('partners', (extra['partner_id'] as num?)?.toInt());
  final facts = <(String, String, IconData)>[
    (labels.partner, partner?.labelFor(language) ?? labels.notRecorded, Icons.handshake_outlined),
    (
      labels.governorate,
      await _place(cache, extra['governorate_id'], language) ?? labels.notRecorded,
      Icons.map_outlined,
    ),
    (
      labels.district,
      await _place(cache, extra['caza_id'], language) ?? labels.notRecorded,
      Icons.location_city_outlined,
    ),
    (
      labels.cadaster,
      await _place(cache, extra['cadaster_id'], language) ?? labels.notRecorded,
      Icons.place_outlined,
    ),
    (labels.type, _text(extra['type'], labels.notRecorded), Icons.category_outlined),
  ];
  final coordinates = _coordinates(extra);
  if (coordinates != null) {
    facts.add((labels.coordinates, coordinates, Icons.my_location_outlined));
  }

  return FacilityProfile(
    name: center.labelFor(language),
    subtitle: partner?.labelFor(language),
    facts: facts,
    programmes: {..._stringList(extra['programs']), ..._stringList(extra['provided_packages'])}.toList(),
    active: extra['is_active'] != false,
    registered: await dao.count(entity: Entities.msccRegistration),
    attendanceDays: await dao.count(entity: Entities.msccAttendanceDay),
    pending: await dao.count(module: BmaModule.mscc.key, states: const [SyncState.pending]),
  );
}

/// Builds the ALP school profile for [school].
Future<FacilityProfile> buildSchoolProfile({
  required ReferenceCache cache,
  required EntityDao dao,
  required ReferenceItem school,
  required String language,
  required FacilityLabels labels,
}) async {
  final extra = school.extra;
  final facts = <(String, String, IconData)>[
    (labels.schoolNumber, _text(extra['number'], labels.notRecorded), Icons.tag),
    (
      labels.governorate,
      await _place(cache, extra['governorate_id'], language) ?? labels.notRecorded,
      Icons.map_outlined,
    ),
    (
      labels.district,
      await _place(cache, extra['district_id'], language) ?? labels.notRecorded,
      Icons.location_city_outlined,
    ),
    (
      labels.cadaster,
      await _place(cache, extra['cadaster_id'], language) ?? labels.notRecorded,
      Icons.place_outlined,
    ),
    (labels.type, _text(extra['type'], labels.notRecorded), Icons.category_outlined),
    (labels.bmaSchool, extra['is_bma'] == true ? labels.yes : labels.no, Icons.verified_outlined),
  ];
  final working = _stringList(extra['working_days']);
  if (working.isNotEmpty) {
    facts.add((labels.workingDays, working.join(', '), Icons.calendar_today_outlined));
  }
  final weekend = _stringList(extra['weekend']);
  if (weekend.isNotEmpty) {
    facts.add((labels.weekend, weekend.join(', '), Icons.weekend_outlined));
  }
  final coordinates = _coordinates(extra);
  if (coordinates != null) {
    facts.add((labels.coordinates, coordinates, Icons.my_location_outlined));
  }

  return FacilityProfile(
    name: school.labelFor(language),
    subtitle: _text(extra['number'], '').isEmpty ? null : '${labels.schoolNumber} ${extra['number']}',
    facts: facts,
    programmes: const [],
    active: extra['is_closed'] != true,
    registered: await dao.count(entity: Entities.alpRegistration),
    attendanceDays: await dao.count(entity: Entities.alpAttendanceDay),
    pending: await dao.count(module: BmaModule.alp.key, states: const [SyncState.pending]),
  );
}

String? _coordinates(Map<String, dynamic> extra) {
  final lat = extra['latitude'];
  final lng = extra['longitude'];
  if (lat == null || lng == null) return null;
  final latitude = double.tryParse(lat.toString());
  final longitude = double.tryParse(lng.toString());
  if (latitude == null || longitude == null) return null;
  return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
}

/// The centre the signed-in account works at, or null when the reference data
/// has not been downloaded yet.
final accountCenterProvider = FutureProvider<ReferenceItem?>((ref) async {
  ref.watch(dataVersionProvider);
  final id = ref.watch(currentProfileProvider)?.center?.id;
  if (id == null) return null;
  return ref.watch(referenceCacheProvider).item('centers', id);
});

/// The school an ALP account works at.
final accountSchoolProvider = FutureProvider<ReferenceItem?>((ref) async {
  ref.watch(dataVersionProvider);
  final id = ref.watch(currentProfileProvider)?.school?.id;
  if (id == null) return null;
  return ref.watch(referenceCacheProvider).item('schools', id);
});
