import '../config/app_config.dart';

class NamedRef {
  const NamedRef({required this.id, required this.name, this.extra = const {}});

  final int id;
  final String name;
  final Map<String, dynamic> extra;

  static NamedRef? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = Map<String, dynamic>.from(json);
    if (map['id'] == null) return null;
    return NamedRef(
      id: (map['id'] as num).toInt(),
      name: (map['name'] ?? '').toString(),
      extra: map..remove('id')..remove('name'),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, ...extra};
}

class ModuleCapabilities {
  const ModuleCapabilities({
    required this.enabled,
    required this.canRegister,
    required this.canEdit,
    required this.canAttend,
    required this.canManageTeachers,
    required this.scope,
  });

  final bool enabled;
  final bool canRegister;
  final bool canEdit;
  final bool canAttend;
  final bool canManageTeachers;
  final String scope;

  static ModuleCapabilities fromJson(Object? json) {
    final map = json is Map ? Map<String, dynamic>.from(json) : const <String, dynamic>{};
    return ModuleCapabilities(
      enabled: map['enabled'] == true,
      canRegister: map['can_register'] == true,
      canEdit: map['can_edit'] == true,
      canAttend: map['can_attend'] == true,
      canManageTeachers: map['can_manage_teachers'] == true,
      scope: (map['scope'] ?? 'none').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'can_register': canRegister,
        'can_edit': canEdit,
        'can_attend': canAttend,
        'can_manage_teachers': canManageTeachers,
        'scope': scope,
      };

  static const none = ModuleCapabilities(
      enabled: false, canRegister: false, canEdit: false, canAttend: false, canManageTeachers: false, scope: 'none');
}

/// Profile block returned by login / `/me/`.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.groups,
    required this.modules,
    this.email = '',
    this.partner,
    this.center,
    this.school,
    this.schools = const [],
    this.isStaff = false,
    this.isSuperuser = false,
  });

  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final List<String> groups;
  final NamedRef? partner;
  final NamedRef? center;
  final NamedRef? school;
  final List<NamedRef> schools;
  final Map<BmaModule, ModuleCapabilities> modules;
  final bool isStaff;
  final bool isSuperuser;

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isEmpty ? username : full;
  }

  ModuleCapabilities capabilities(BmaModule module) => modules[module] ?? ModuleCapabilities.none;

  List<BmaModule> get enabledModules =>
      BmaModule.values.where((m) => capabilities(m).enabled).toList();

  static UserProfile fromJson(Map<String, dynamic> json) {
    final modulesJson = json['modules'] is Map ? Map<String, dynamic>.from(json['modules'] as Map) : const {};
    return UserProfile(
      id: (json['id'] as num).toInt(),
      username: (json['username'] ?? '').toString(),
      firstName: (json['first_name'] ?? '').toString(),
      lastName: (json['last_name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      groups: ((json['groups'] as List?) ?? const []).map((e) => e.toString()).toList(),
      partner: NamedRef.fromJson(json['partner']),
      center: NamedRef.fromJson(json['center']),
      school: NamedRef.fromJson(json['school']),
      schools: ((json['schools'] as List?) ?? const [])
          .map(NamedRef.fromJson)
          .whereType<NamedRef>()
          .toList(),
      modules: {
        for (final m in BmaModule.values) m: ModuleCapabilities.fromJson(modulesJson[m.key]),
      },
      isStaff: json['is_staff'] == true,
      isSuperuser: json['is_superuser'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'groups': groups,
        'partner': partner?.toJson(),
        'center': center?.toJson(),
        'school': school?.toJson(),
        'schools': schools.map((s) => s.toJson()).toList(),
        'modules': {for (final e in modules.entries) e.key.key: e.value.toJson()},
        'is_staff': isStaff,
        'is_superuser': isSuperuser,
      };
}
