import 'dart:convert';

import 'package:bma_app/core/config/app_config.dart';
import 'package:bma_app/core/models/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// The `user` block exactly as the BMA-NFE test deployment returned it from
/// `POST /api/mobile/v1/auth/login/` on 15 September 2026. Kept verbatim so a
/// change in the server contract fails here rather than on a tablet in a
/// centre. The token is deliberately not part of this fixture.
const _liveUserBlock = '''
{
  "id": 2,
  "username": "test_center",
  "first_name": "test",
  "last_name": "Center",
  "email": "",
  "is_staff": false,
  "is_superuser": false,
  "groups": ["MSCC", "MSCC_CENTER", "MSCC_FULL"],
  "partner": {"id": 15, "name": "Test Partner", "short_name": null},
  "center": {"id": 85, "name": "Amal Center", "partner_id": 15},
  "school": null,
  "schools": [],
  "modules": {
    "mscc": {"enabled": true, "can_register": true, "can_edit": true,
             "can_attend": true, "can_manage_teachers": true, "scope": "center"},
    "alp": {"enabled": false, "can_register": false, "can_edit": false,
            "can_attend": false, "can_manage_teachers": false, "scope": "none"},
    "clm": {"enabled": false, "can_register": false, "can_edit": false,
            "can_attend": false, "can_manage_teachers": false, "scope": "partner"}
  },
  "server_time": "2026-09-15T11:22:46.844376"
}
''';

void main() {
  late UserProfile profile;

  setUp(() {
    profile = UserProfile.fromJson(Map<String, dynamic>.from(jsonDecode(_liveUserBlock) as Map));
  });

  test('reads the identity a centre worker sees on the home screen', () {
    expect(profile.id, 2);
    expect(profile.username, 'test_center');
    expect(profile.displayName, 'test Center');
    expect(profile.groups, containsAll(['MSCC', 'MSCC_CENTER']));
    expect(profile.isStaff, isFalse);
  });

  test('keeps the scope line: a partner and a centre, no school', () {
    expect(profile.partner?.name, 'Test Partner');
    // A null short_name must not break the reference.
    expect(profile.partner?.extra['short_name'], isNull);
    expect(profile.center?.id, 85);
    expect(profile.center?.name, 'Amal Center');
    expect(profile.center?.extra['partner_id'], 15);
    expect(profile.school, isNull);
    expect(profile.schools, isEmpty);
  });

  test('enables Makani only, with every capability a centre account has', () {
    expect(profile.enabledModules, [BmaModule.mscc]);
    final mscc = profile.capabilities(BmaModule.mscc);
    expect(mscc.canRegister, isTrue);
    expect(mscc.canEdit, isTrue);
    expect(mscc.canAttend, isTrue);
    expect(mscc.canManageTeachers, isTrue);
    expect(mscc.scope, 'center');
  });

  test('treats the disabled modules as unusable whatever their scope says', () {
    for (final module in [BmaModule.alp, BmaModule.clm]) {
      final caps = profile.capabilities(module);
      expect(caps.enabled, isFalse, reason: '$module is disabled for this account');
      expect(caps.canRegister, isFalse);
      expect(caps.canAttend, isFalse);
    }
  });

  test('survives a round trip through the session store', () {
    final restored = UserProfile.fromJson(jsonDecode(jsonEncode(profile.toJson())) as Map<String, dynamic>);
    expect(restored.id, profile.id);
    expect(restored.displayName, profile.displayName);
    expect(restored.center?.name, profile.center?.name);
    expect(restored.enabledModules, profile.enabledModules);
    expect(restored.capabilities(BmaModule.mscc).scope, 'center');
  });
}
