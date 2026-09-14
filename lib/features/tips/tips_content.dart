import 'package:flutter/material.dart';

import '../../core/models/user_profile.dart';
import '../../l10n/app_localizations.dart';

/// Stable ids of the contextual TipCards (persisted as `<userId>:<id>`).
abstract final class TipIds {
  static const homeSync = 'home.sync';
  static const registrationsSearch = 'registrations.search';
  static const attendanceFlow = 'attendance.flow';
  static const syncCenter = 'sync.center';
}

enum TipPageKind { welcome, data, register, daily, push, resolve, safe }

class TipPage {
  const TipPage({required this.kind, required this.icon, required this.title, required this.body});

  final TipPageKind kind;
  final IconData icon;
  final String title;
  final String body;
}

bool _any(UserProfile? p, bool Function(ModuleCapabilities c) test) =>
    p == null || p.enabledModules.any((m) => test(p.capabilities(m)));

/// Pages in display order, tailored to the profile. `profile == null` yields all 7.
List<TipPage> tipPages(AppLocalizations l10n, UserProfile? profile) => [
      TipPage(kind: TipPageKind.welcome, icon: Icons.cloud_off, title: l10n.tipsWelcomeTitle, body: l10n.tipsWelcomeBody),
      TipPage(kind: TipPageKind.data, icon: Icons.cloud_download, title: l10n.tipsDataTitle, body: l10n.tipsDataBody),
      if (_any(profile, (c) => c.canRegister))
        TipPage(
            kind: TipPageKind.register, icon: Icons.person_add, title: l10n.tipsRegisterTitle, body: l10n.tipsRegisterBody),
      TipPage(kind: TipPageKind.daily, icon: Icons.fact_check, title: l10n.tipsDailyTitle, body: l10n.tipsDailyBody),
      TipPage(kind: TipPageKind.push, icon: Icons.cloud_upload, title: l10n.tipsPushTitle, body: l10n.tipsPushBody),
      if (_any(profile, (c) => c.canRegister || c.canEdit))
        TipPage(kind: TipPageKind.resolve, icon: Icons.call_merge, title: l10n.tipsResolveTitle, body: l10n.tipsResolveBody),
      TipPage(kind: TipPageKind.safe, icon: Icons.verified_user, title: l10n.tipsSafeTitle, body: l10n.tipsSafeBody),
    ];
