// The dashboards each programme offers, in one place, so Home, the rail and
// the hub screen can never disagree about what an account may open.
import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';

/// One analytics dashboard of a programme.
@immutable
class AnalyticsEntry {
  const AnalyticsEntry({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.location,
  });

  /// Suffix of the hub card's `ValueKey`: `analytics-entry-<key>`.
  final String key;
  final String title;
  final String description;
  final IconData icon;
  final String location;
}

/// Whether [module] has any analytics dashboards at all. Kept label-free so
/// the gate can be asked without an [AppLocalizations].
bool hasAnalytics(BmaModule module) => module == BmaModule.mscc || module == BmaModule.alp;

/// The dashboards of [module], in the order the hub lists them.
///
/// NFE mirrors the web platform's Advanced Analytics page; ALP mirrors its
/// four dashboards (registration, teacher, attendance, school). CLM has none
/// on the web either.
List<AnalyticsEntry> analyticsEntriesFor(BmaModule module, AppLocalizations l10n) => switch (module) {
      BmaModule.mscc => [
          AnalyticsEntry(
            key: 'nfe-advanced',
            title: l10n.advancedAnalytics,
            description: l10n.advancedAnalyticsDescription,
            icon: Icons.query_stats_outlined,
            location: Routes.nfeAdvancedAnalytics,
          ),
        ],
      BmaModule.alp => [
          AnalyticsEntry(
            key: 'alp-registration',
            title: l10n.alpRegistrationInsights,
            description: l10n.alpRegistrationInsightsDescription,
            icon: Icons.insights_outlined,
            location: Routes.alpRegistrationInsights,
          ),
          AnalyticsEntry(
            key: 'alp-teachers',
            title: l10n.alpTeacherDashboard,
            description: l10n.alpTeacherDashboardDescription,
            icon: Icons.badge_outlined,
            location: Routes.alpTeacherDashboard,
          ),
          AnalyticsEntry(
            key: 'alp-attendance',
            title: l10n.alpAttendanceDashboard,
            description: l10n.alpAttendanceDashboardDescription,
            icon: Icons.grid_on_outlined,
            location: Routes.alpAttendanceDashboard,
          ),
          AnalyticsEntry(
            key: 'alp-schools',
            title: l10n.alpSchoolDashboard,
            description: l10n.alpSchoolDashboardDescription,
            icon: Icons.map_outlined,
            location: Routes.alpSchoolDashboard,
          ),
        ],
      BmaModule.clm => const [],
    };
