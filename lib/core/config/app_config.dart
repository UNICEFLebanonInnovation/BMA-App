/// Static configuration shared by the whole application.
class AppConfig {
  AppConfig._();

  /// Default server used when the user has not configured one yet. It can be
  /// changed on the login screen and in Settings.
  static const String defaultServerUrl = 'https://bma-nfe.unicef.org';

  /// REST prefix implemented by `student_registration.mobile_api`.
  static const String apiPrefix = '/api/mobile/v1';

  /// Maximum number of records sent in a single push request (mirrors the
  /// server-side limit documented in docs/mobile_sync_protocol.md).
  static const int pushBatchSize = 200;

  /// Page size used when pulling changes.
  static const int pullPageSize = 500;

  /// App version reported to the server on login and push.
  static const String appVersion = '1.0.0+1';

  /// Network timeouts.
  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration receiveTimeout = Duration(minutes: 3);
}

/// Identity modules of the platform. The server tells the app which ones the
/// signed-in user can use.
enum BmaModule { mscc, alp, clm }

extension BmaModuleKey on BmaModule {
  String get key => name;

  static BmaModule? fromKey(String? key) {
    switch (key) {
      case 'mscc':
        return BmaModule.mscc;
      case 'alp':
        return BmaModule.alp;
      case 'clm':
        return BmaModule.clm;
    }
    return null;
  }
}

/// Entity type keys used by both the server registry and the local database.
/// Keeping them in one place avoids typos across features.
class Entities {
  Entities._();

  static const msccRegistration = 'mscc.registration';
  static const msccTeacher = 'mscc.teacher';
  static const msccAttendanceDay = 'mscc.attendance_day';
  static const msccEducationService = 'mscc.education_service';
  static const msccReferral = 'mscc.referral';
  static const msccNewRoundKey = 'mscc.new_round';
  static const msccPss = 'mscc.pss';

  static const alpRegistration = 'alp.registration';
  static const alpTeacher = 'alp.teacher';
  static const alpGrading = 'alp.grading';
  static const alpAttendanceDay = 'alp.attendance_day';
  static const alpTeacherAttendanceDay = 'alp.teacher_attendance_day';
  static const alpSchoolProfile = 'alp.school_profile';

  static const clmBridging = 'clm.bridging';
  static const clmTeacher = 'clm.teacher';
  static const clmAttendanceDay = 'clm.attendance_day';

  /// Entities that identify a person and go through duplicate verification.
  static const identityEntities = {
    msccRegistration,
    alpRegistration,
    clmBridging,
  };

  /// Entities stored as idempotent documents keyed on a natural key.
  static const attendanceEntities = {
    msccAttendanceDay,
    alpAttendanceDay,
    alpTeacherAttendanceDay,
    clmAttendanceDay,
  };

  static String registrationFor(BmaModule module) {
    switch (module) {
      case BmaModule.mscc:
        return msccRegistration;
      case BmaModule.alp:
        return alpRegistration;
      case BmaModule.clm:
        return clmBridging;
    }
  }

  static String attendanceFor(BmaModule module) {
    switch (module) {
      case BmaModule.mscc:
        return msccAttendanceDay;
      case BmaModule.alp:
        return alpAttendanceDay;
      case BmaModule.clm:
        return clmAttendanceDay;
    }
  }

  static String teacherFor(BmaModule module) {
    switch (module) {
      case BmaModule.mscc:
        return msccTeacher;
      case BmaModule.alp:
        return alpTeacher;
      case BmaModule.clm:
        return clmTeacher;
    }
  }

  static BmaModule moduleOf(String entity) =>
      BmaModuleKey.fromKey(entity.split('.').first) ?? BmaModule.mscc;
}
