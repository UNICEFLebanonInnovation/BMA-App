import '../../core/config/app_config.dart';
import '../../core/models/entity_record.dart';
import '../../core/sync/sync_engine.dart';

/// Helpers to read identity records whatever their stored shape (nested
/// server shape or flat web-form shape).
class RegistrationView {
  RegistrationView(this.record) : flat = SyncEngine.flattenIdentityPayload(record.entity, Map.of(record.data));

  final EntityRecord record;
  final Map<String, dynamic> flat;

  BmaModule get module => Entities.moduleOf(record.entity);

  String get prefix => record.entity == Entities.clmBridging ? 'student_' : 'child_';

  Map<String, dynamic>? get person {
    final p = record.data['child'] ?? record.data['student'];
    return p is Map ? Map<String, dynamic>.from(p) : null;
  }

  String get fullName => record.label;

  String? get motherName => (person?['mother_fullname'] ?? flat['${prefix}mother_fullname'])?.toString();

  String? get gender => (person?['gender'] ?? person?['sex'] ?? flat['${prefix}gender'] ?? flat['${prefix}sex'])?.toString();

  String? get birthday {
    final y = (person?['birthday_year'] ?? flat['${prefix}birthday_year'])?.toString();
    final m = (person?['birthday_month'] ?? flat['${prefix}birthday_month'])?.toString();
    final d = (person?['birthday_day'] ?? flat['${prefix}birthday_day'])?.toString();
    if (y == null || y.isEmpty || y == '0') return null;
    return '$d/$m/$y';
  }

  int? get age {
    final y = int.tryParse((person?['birthday_year'] ?? flat['${prefix}birthday_year'] ?? '').toString());
    final m = int.tryParse((person?['birthday_month'] ?? flat['${prefix}birthday_month'] ?? '').toString());
    final d = int.tryParse((person?['birthday_day'] ?? flat['${prefix}birthday_day'] ?? '').toString());
    if (y == null || y == 0 || m == null || d == null) return null;
    final today = DateTime.now();
    var years = today.year - y;
    if (today.month < m || (today.month == m && today.day < d)) years -= 1;
    return years;
  }

  Object? get nationalityId => person?['nationality'] ?? flat['${prefix}nationality'];

  String? get nationalityLabel => person?['nationality_label']?.toString();

  String? get number => person?['number']?.toString();

  String? get unicefId => person?['unicef_id']?.toString();

  int? get personServerId => (person?['id'] as num?)?.toInt();

  String? get centerLabel => record.data['center_label']?.toString();

  String? get schoolLabel => record.data['school_label']?.toString();

  String? get partnerLabel => record.data['partner_label']?.toString();

  String? get roundLabel => record.data['round_label']?.toString();

  int? get roundId => (record.data['round'] as num?)?.toInt();

  int? get schoolId => (record.data['school'] as num?)?.toInt();

  int? get centerId => (record.data['center'] as num?)?.toInt();

  String? get registrationDate => record.data['registration_date']?.toString();

  /// Education services summary embedded by the server (MSCC) or empty.
  List<Map<String, dynamic>> get educationSummary =>
      ((record.data['education_summary'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  String? get dropoutDate => record.data['dropout_date']?.toString();
}
