import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/models/entity_record.dart';
import '../registrations/registration_helpers.dart';

/// Selection made on the attendance screen.
class AttendanceSelection {
  const AttendanceSelection({
    required this.module,
    required this.date,
    this.centerId,
    this.schoolId,
    this.roundId,
    this.programme,
    this.section,
    this.registrationLevel,
    this.dayOff = false,
    this.closeReason = '',
  });

  final BmaModule module;
  final String date; // YYYY-MM-DD
  final int? centerId;
  final int? schoolId;
  final int? roundId;

  /// MSCC: education programme key; ALP: programme id (as string).
  final String? programme;
  final String? section;
  final String? registrationLevel;
  final bool dayOff;
  final String closeReason;

  bool get complete {
    if (roundId == null || date.isEmpty) return false;
    switch (module) {
      case BmaModule.mscc:
        return centerId != null && (programme?.isNotEmpty ?? false) && (section?.isNotEmpty ?? false);
      case BmaModule.alp:
        return schoolId != null && (programme?.isNotEmpty ?? false);
      case BmaModule.clm:
        return schoolId != null && (registrationLevel?.isNotEmpty ?? false);
    }
  }

  String get entity => Entities.attendanceFor(module);

  /// Header part of the attendance document (same keys the server expects).
  Map<String, dynamic> toHeader() {
    switch (module) {
      case BmaModule.mscc:
        return {
          'round_id': roundId,
          'center_id': centerId,
          'attendance_date': date,
          'education_program': programme,
          'class_section': section,
          'attendance_day_off': dayOff ? 'Yes' : 'No',
          'close_reason': closeReason,
        };
      case BmaModule.alp:
        return {
          'round_id': roundId,
          'school_id': schoolId,
          'programme': int.tryParse(programme ?? '') ?? programme,
          'attendance_date': date,
          'attendance_day_off': dayOff ? 'Yes' : 'No',
          'close_reason': closeReason,
        };
      case BmaModule.clm:
        return {
          'round_id': roundId,
          'school_id': schoolId,
          'registration_level': registrationLevel,
          'attendance_date': date,
          'attendance_day_off': dayOff ? 'Yes' : 'No',
          'close_reason': closeReason,
        };
    }
  }

  String get naturalKey => EntityDao.naturalKeyFor(entity, toHeader()) ?? '';

  AttendanceSelection copyWith({
    String? date,
    int? centerId,
    int? schoolId,
    int? roundId,
    String? programme,
    String? section,
    String? registrationLevel,
    bool? dayOff,
    String? closeReason,
  }) =>
      AttendanceSelection(
        module: module,
        date: date ?? this.date,
        centerId: centerId ?? this.centerId,
        schoolId: schoolId ?? this.schoolId,
        roundId: roundId ?? this.roundId,
        programme: programme ?? this.programme,
        section: section ?? this.section,
        registrationLevel: registrationLevel ?? this.registrationLevel,
        dayOff: dayOff ?? this.dayOff,
        closeReason: closeReason ?? this.closeReason,
      );
}

/// One line of the attendance sheet.
class RosterRow {
  RosterRow({
    required this.registration,
    this.attended = 'Yes',
    this.absenceReason = '',
    this.absenceReasonOther = '',
  });

  final EntityRecord registration;
  String attended;
  String absenceReason;
  String absenceReasonOther;

  RegistrationView get view => RegistrationView(registration);

  Map<String, dynamic> toJson() {
    final view = this.view;
    return {
      if (registration.serverId != null) 'registration_id': registration.serverId,
      if (registration.serverId == null) 'registration_uuid': registration.uuid,
      if (view.personServerId != null) 'child_id': view.personServerId,
      'child_label': view.fullName,
      'attended': attended,
      'absence_reason': attended == 'No' ? absenceReason : '',
      'absence_reason_other': attended == 'No' && absenceReason == 'Other' ? absenceReasonOther : '',
    };
  }
}

/// Builds the roster the way the web `load_child_attendance` helpers do,
/// from the records available offline.
class AttendanceRoster {
  AttendanceRoster(this._dao);

  final EntityDao _dao;

  Future<List<RosterRow>> build(AttendanceSelection selection) async {
    final registrations = await _dao.list(RecordQuery(entity: Entities.registrationFor(selection.module), limit: 5000));
    final rows = <RosterRow>[];
    for (final registration in registrations) {
      if (registration.syncState == SyncState.discarded) continue;
      if (await _eligible(registration, selection)) {
        rows.add(RosterRow(registration: registration));
      }
    }
    rows.sort((a, b) => a.registration.label.toLowerCase().compareTo(b.registration.label.toLowerCase()));
    return rows;
  }

  Future<bool> _eligible(EntityRecord registration, AttendanceSelection s) async {
    final view = RegistrationView(registration);
    final date = s.date;
    switch (s.module) {
      case BmaModule.mscc:
        final sameCenter = view.centerId == null || view.centerId == s.centerId;
        if (!sameCenter) return false;
        if (_droppedOut(view.dropoutDate, date)) return false;
        final services = await _dao.childrenOf(registration, entity: Entities.msccEducationService);
        var enrolled = false;
        for (final service in services) {
          final d = service.data;
          final sameRound = d['round'] == null || '${d['round']}' == '${s.roundId}' || '${view.roundId}' == '${s.roundId}';
          if (d['education_program'] == s.programme &&
              d['class_section'] == s.section &&
              sameRound &&
              _onOrBefore(d['registration_date']?.toString(), date)) {
            enrolled = true;
          }
        }
        if (!enrolled) {
          // Server-side summary for pulled registrations without local service rows.
          for (final e in view.educationSummary) {
            if (e['education_program'] == s.programme &&
                e['class_section'] == s.section &&
                (e['round'] == null || '${e['round']}' == '${s.roundId}') &&
                _onOrBefore(e['registration_date']?.toString(), date)) {
              enrolled = true;
            }
          }
        }
        if (!enrolled) return false;
        final referrals = await _dao.childrenOf(registration, entity: Entities.msccReferral);
        for (final r in referrals) {
          if (r.data['recommended_learning_path'] == 'Drop out' && _droppedOut(r.data['dropout_date']?.toString(), date)) {
            return false;
          }
        }
        return true;
      case BmaModule.alp:
        final sameSchool = view.schoolId == null || view.schoolId == s.schoolId;
        return sameSchool &&
            '${view.roundId}' == '${s.roundId}' &&
            '${registration.data['programme']}' == '${s.programme}' &&
            _onOrBefore(view.registrationDate, date);
      case BmaModule.clm:
        final sameSchool = view.schoolId == null || view.schoolId == s.schoolId;
        if (!sameSchool || '${view.roundId}' != '${s.roundId}') return false;
        if (registration.data['registration_level'] != s.registrationLevel) return false;
        if (!_onOrBefore(view.registrationDate, date)) return false;
        if (registration.data['learning_result'] == 'dropout' &&
            _droppedOut(registration.data['dropout_date']?.toString(), date)) {
          return false;
        }
        return true;
    }
  }

  static bool _onOrBefore(String? registrationDate, String date) {
    if (registrationDate == null || registrationDate.isEmpty) return false;
    return registrationDate.compareTo(date) <= 0;
  }

  static bool _droppedOut(String? dropoutDate, String date) {
    if (dropoutDate == null || dropoutDate.isEmpty) return false;
    return dropoutDate.compareTo(date) <= 0;
  }

  /// Merge a previously saved sheet into the roster rows.
  static void applySaved(List<RosterRow> rows, Map<String, dynamic> saved) {
    final savedRows = ((saved['children_attendance'] as List?) ?? const []).whereType<Map>().toList();
    for (final row in rows) {
      for (final s in savedRows) {
        final matchesId = s['registration_id'] != null && '${s['registration_id']}' == '${row.registration.serverId}';
        final matchesUuid = s['registration_uuid'] != null && s['registration_uuid'] == row.registration.uuid;
        if (matchesId || matchesUuid) {
          row.attended = (s['attended'] ?? 'Yes').toString();
          row.absenceReason = (s['absence_reason'] ?? '').toString();
          row.absenceReasonOther = (s['absence_reason_other'] ?? '').toString();
        }
      }
    }
  }
}
