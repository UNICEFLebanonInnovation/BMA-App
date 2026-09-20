import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/layout/adaptive.dart';
import '../../core/layout/app_layout.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/app_localizations.dart';
import 'analytics_catalog.dart';

/// The list of a programme's analytics dashboards: one card each, with a
/// line saying what the dashboard answers. Every dashboard behind it is
/// computed from the records on the device, which the intro says once.
class AnalyticsHubScreen extends StatelessWidget {
  const AnalyticsHubScreen({super.key, required this.module});

  final BmaModule module;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = analyticsEntriesFor(module, l10n);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.analytics)),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: entries.isEmpty
                ? EmptyState(message: l10n.noAnalyticsForModule, icon: Icons.query_stats_outlined)
                : AdaptiveBody(
                    maxWidth: AppLayout.medium.contentMaxWidth,
                    child: ListView(
                      key: const ValueKey('analytics-hub-list'),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                          child: Text(
                            l10n.analyticsHubIntro,
                            style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.35),
                          ),
                        ),
                        for (final entry in entries)
                          AppCard(
                            key: ValueKey('analytics-entry-${entry.key}'),
                            onTap: () => context.push(entry.location),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.primary.withValues(alpha: 0.10),
                                  ),
                                  child: Icon(entry.icon, color: AppColors.primary),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                      const SizedBox(height: 3),
                                      Text(
                                        entry.description,
                                        style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.3),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right, color: AppColors.muted),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
