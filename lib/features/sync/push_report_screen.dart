import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/db/sync_dao.dart';
import '../../core/layout/adaptive.dart';
import '../../core/layout/app_layout.dart';
import '../../core/models/entity_record.dart';
import '../../core/models/sync_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import 'sync_center_screen.dart';

/// Detailed report of one push batch: what was created, updated, merged,
/// flagged as duplicate, in conflict or rejected — with a way to act on each.
class PushReportScreen extends ConsumerWidget {
  const PushReportScreen({super.key, required this.batchUuid});

  final String batchUuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.watch(dataVersionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pushReport)),
      body: FutureBuilder<SyncBatch?>(
        future: ref.read(syncDaoProvider).byUuid(batchUuid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.connectionState == ConnectionState.done) return EmptyState(message: l10n.noHistory);
            return const Center(child: CircularProgressIndicator());
          }
          final batch = snapshot.data!;
          final report = batch.report;
          return LayoutBuilder(builder: (context, constraints) {
            final layout = AppLayout.forWidth(constraints.maxWidth);
            final content = ListView(
              padding: const EdgeInsets.all(8),
              children: [
                Card(
                  key: const ValueKey('report-summary'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.reportFor(batch.serverBatchId?.toString() ?? batch.uuid.substring(0, 8)),
                            style: Theme.of(context).textTheme.titleMedium),
                        Text((batch.finishedAt ?? batch.startedAt).split('.').first.replaceFirst('T', ' '),
                            style: const TextStyle(color: AppColors.muted)),
                        if (batch.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(batch.error!, style: const TextStyle(color: AppColors.danger)),
                          ),
                        const SizedBox(height: 8),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _SummaryChip(l10n.summaryCreated, batch.summary['created'], AppColors.success),
                          _SummaryChip(l10n.summaryUpdated, batch.summary['updated'], AppColors.success),
                          _SummaryChip(l10n.summaryMerged, batch.summary['merged'], AppColors.secondary),
                          _SummaryChip(l10n.summaryLinked, batch.summary['linked'], AppColors.secondary),
                          _SummaryChip(l10n.summaryDuplicates, batch.summary['duplicate'], AppColors.danger),
                          _SummaryChip(l10n.summaryConflicts, batch.summary['conflict'], AppColors.danger),
                          _SummaryChip(l10n.summaryErrors, batch.summary['error'], AppColors.danger),
                          _SummaryChip(l10n.summarySkipped, batch.summary['skipped'], AppColors.muted),
                          _SummaryChip(l10n.summaryDiscarded, batch.summary['discarded'], AppColors.muted),
                        ]),
                      ],
                    ),
                  ),
                ),
                ..._results(layout, report),
              ],
            );
            // Compact is returned unwrapped so the phone tree is untouched;
            // above it the report is centred at contentMaxWidth.
            return layout.width.atLeastMedium
                ? AdaptiveBody(maxWidth: layout.contentMaxWidth, child: content)
                : content;
          });
        },
      ),
    );
  }

  /// Result tiles: one per row below expanded, two per row at expanded, where
  /// a single ~1050 px tile for one status line is mostly empty space.
  static List<Widget> _results(AppLayout layout, PushReport? report) {
    final tiles = [for (final result in report?.results ?? const <PushItemResult>[]) _ResultTile(result: result)];
    if (!layout.width.isExpanded) return tiles;
    return [
      for (var i = 0; i < tiles.length; i += 2)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: tiles[i]),
            Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox.shrink()),
          ],
        ),
    ];
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip(this.label, this.count, this.color);

  final String label;
  final int? count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (count == null || count == 0) return const SizedBox.shrink();
    return Chip(
      label: Text('$label: $count', style: TextStyle(color: color)),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      backgroundColor: color.withValues(alpha: 0.08),
    );
  }
}

class _ResultTile extends ConsumerWidget {
  const _ResultTile({required this.result});

  final PushItemResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final schemas = ref.watch(schemasProvider).value;
    final entityLabel = schemas?[result.entity]?.label ?? result.entity;
    final color = switch (result.status) {
      'created' || 'updated' || 'merged' || 'linked' || 'deleted' => AppColors.success,
      'duplicate' || 'conflict' || 'error' => AppColors.danger,
      _ => AppColors.muted,
    };
    final errors = result.errors.entries
        .where((e) => e.key != 'server_data')
        .map((e) => '${e.key}: ${e.value is List ? (e.value as List).join(', ') : e.value}')
        .join('\n');
    // Read from this element's own position: inside a pane the tile sees the
    // pane's class, not the window's.
    final layout = LayoutScope.of(context);
    return FutureBuilder<EntityRecord?>(
      future: ref.read(entityDaoProvider).byUuid(result.clientUuid),
      builder: (context, snapshot) {
        final record = snapshot.data;
        final label = record?.label ?? result.dataAfter?['label']?.toString() ?? '';
        return Card(
          key: ValueKey('report-result-${result.clientUuid}'),
          child: ListTile(
            leading: Icon(_icon(result.status), color: color),
            title: Text(label.isEmpty ? entityLabel : label),
            subtitle: Text(
              [
                '$entityLabel · ${_statusLabel(l10n, result.status)}',
                if (result.serverId != null) l10n.serverRecordId('${result.serverId}'),
                if (result.message.isNotEmpty) result.message,
                if (errors.isNotEmpty) errors,
                if (result.duplicates.isNotEmpty)
                  result.duplicates.map((d) => '• ${d['label']} (${d['match']?['reason']})').join('\n'),
              ].join('\n'),
              // The 6-line clamp exists because a phone-width tile turns a
              // server error into a wall of text; the extra width above
              // compact absorbs it, so the clamp is relaxed rather than kept.
              maxLines: layout.width.atLeastMedium ? 12 : 6,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: record == null ? null : const Icon(Icons.chevron_right),
            onTap: record == null
                ? null
                : () {
                    if (record.syncState.needsAttention) {
                      openRecordForResolution(context, record);
                    } else {
                      context.push(Routes.profile(record.uuid));
                    }
                  },
          ),
        );
      },
    );
  }

  static IconData _icon(String status) => switch (status) {
        'created' => Icons.add_circle_outline,
        'updated' => Icons.check_circle_outline,
        'merged' => Icons.merge,
        'linked' => Icons.link,
        'duplicate' => Icons.people,
        'conflict' => Icons.call_split,
        'error' => Icons.error_outline,
        'skipped' => Icons.pause_circle_outline,
        'discarded' => Icons.delete_outline,
        'deleted' => Icons.delete,
        _ => Icons.help_outline,
      };

  static String _statusLabel(AppLocalizations l10n, String status) => switch (status) {
        'created' => l10n.summaryCreated,
        'updated' => l10n.summaryUpdated,
        'merged' => l10n.summaryMerged,
        'linked' => l10n.summaryLinked,
        'duplicate' => l10n.duplicate,
        'conflict' => l10n.conflict,
        'error' => l10n.error,
        'skipped' => l10n.summarySkipped,
        'discarded' => l10n.discarded,
        _ => status,
      };
}
