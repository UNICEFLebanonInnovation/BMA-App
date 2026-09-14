import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/db/sync_dao.dart';
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
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              Card(
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
              if (report != null)
                for (final result in report.results) _ResultTile(result: result),
            ],
          );
        },
      ),
    );
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
    return FutureBuilder<EntityRecord?>(
      future: ref.read(entityDaoProvider).byUuid(result.clientUuid),
      builder: (context, snapshot) {
        final record = snapshot.data;
        final label = record?.label ?? result.dataAfter?['label']?.toString() ?? '';
        return Card(
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
              maxLines: 6,
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
