import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/db/sync_dao.dart';
import '../../core/forms/reference_cache.dart';
import '../../core/models/entity_record.dart';
import '../../core/models/sync_models.dart';
import '../../core/sync/connectivity_service.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';

/// Sync centre: push/pull controls, outbox counts, records needing a
/// decision (duplicates, conflicts, errors) and the latest push report.
class SyncCenterScreen extends ConsumerWidget {
  const SyncCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final sync = ref.watch(syncEngineProvider);
    final online = ref.watch(isOnlineProvider);
    final engine = ref.read(syncEngineProvider.notifier);
    ref.watch(dataVersionProvider);
    final attentionFuture = ref.read(entityDaoProvider).list(const RecordQuery(
          states: [SyncState.duplicate, SyncState.conflict, SyncState.error],
          includeDeleted: true,
          orderBy: 'client_modified DESC',
          limit: 200,
        ));
    final latestFuture = ref.read(syncDaoProvider).latest();

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) showMessage(context, e.toString(), error: true);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.syncCenter),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: l10n.syncHistory,
            onPressed: () => context.push(Routes.syncHistory),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(8),
        children: [
          const OfflineBanner(),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(online ? Icons.wifi : Icons.wifi_off, color: online ? AppColors.success : AppColors.warning),
                    const SizedBox(width: 8),
                    Text(online ? l10n.online : l10n.offline),
                    const Spacer(),
                    Text(l10n.lastPull(sync.lastPull?.split('.').first.replaceFirst('T', ' ') ?? l10n.never),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final state in SyncState.values)
                      if ((sync.counts[state] ?? 0) > 0 && state != SyncState.synced)
                        Chip(
                          avatar: SyncStateChip(state, compact: true),
                          label: Text('${sync.counts[state]}'),
                        ),
                  ]),
                  if (sync.busy)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(value: sync.progress),
                    ),
                  if (sync.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(sync.error!, style: const TextStyle(color: AppColors.danger)),
                    ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: sync.busy || !online ? null : () => run(engine.push),
                        icon: const Icon(Icons.upload),
                        label: Text(l10n.pushNow),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: sync.busy || !online ? null : () => run(() => engine.pull()),
                        icon: const Icon(Icons.download),
                        label: Text(l10n.pullNow),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: sync.busy || !online
                        ? null
                        : () => run(() async {
                              await engine.bootstrap();
                              ref.read(referenceCacheProvider).invalidate();
                              await engine.pull(full: true);
                            }),
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.fullRefresh),
                  ),
                ],
              ),
            ),
          ),
          FutureBuilder<SyncBatch?>(
            future: latestFuture,
            builder: (context, snapshot) {
              final batch = snapshot.data;
              if (batch == null) return const SizedBox.shrink();
              return Card(
                child: ListTile(
                  leading: Icon(batch.status == 'completed' ? Icons.assignment_turned_in : Icons.error_outline,
                      color: batch.status == 'completed' ? AppColors.success : AppColors.danger),
                  title: Text(l10n.pushReport),
                  subtitle: Text(_summaryLine(l10n, batch)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(Routes.pushReport(batch.uuid)),
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
            child: Text(l10n.needsResolution, style: Theme.of(context).textTheme.titleMedium),
          ),
          FutureBuilder<List<EntityRecord>>(
            future: attentionFuture,
            builder: (context, snapshot) {
              final records = snapshot.data ?? const [];
              if (snapshot.hasData && records.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(sync.pendingCount == 0 ? l10n.noPendingWork : l10n.pendingChanges(sync.pendingCount),
                      style: const TextStyle(color: AppColors.muted)),
                );
              }
              return Column(children: [for (final r in records) _AttentionTile(record: r)]);
            },
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l10n.aboutSync, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  static String _summaryLine(AppLocalizations l10n, SyncBatch batch) {
    final s = batch.summary;
    final parts = <String>[
      if ((s['created'] ?? 0) > 0) '${l10n.summaryCreated} ${s['created']}',
      if ((s['updated'] ?? 0) > 0) '${l10n.summaryUpdated} ${s['updated']}',
      if ((s['merged'] ?? 0) > 0) '${l10n.summaryMerged} ${s['merged']}',
      if ((s['linked'] ?? 0) > 0) '${l10n.summaryLinked} ${s['linked']}',
      if ((s['duplicate'] ?? 0) > 0) '${l10n.summaryDuplicates} ${s['duplicate']}',
      if ((s['conflict'] ?? 0) > 0) '${l10n.summaryConflicts} ${s['conflict']}',
      if ((s['error'] ?? 0) > 0) '${l10n.summaryErrors} ${s['error']}',
      if ((s['skipped'] ?? 0) > 0) '${l10n.summarySkipped} ${s['skipped']}',
    ];
    final when = batch.finishedAt ?? batch.startedAt;
    return '${when.split('.').first.replaceFirst('T', ' ')} · ${parts.isEmpty ? batch.status : parts.join(', ')}';
  }
}

class _AttentionTile extends ConsumerWidget {
  const _AttentionTile({required this.record});

  final EntityRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final schemas = ref.watch(schemasProvider).value;
    final entityLabel = schemas?[record.entity]?.label ?? record.entity;
    final errorText = record.lastError?.entries
        .where((e) => e.key != 'server_data')
        .map((e) => '${e.key}: ${e.value is List ? (e.value as List).join(', ') : e.value}')
        .join('\n');
    return Card(
      child: ListTile(
        leading: SyncStateChip(record.syncState, compact: true),
        title: Text(record.label.isEmpty ? entityLabel : record.label),
        subtitle: Text([entityLabel, record.serverMessage ?? '', errorText ?? ''].where((s) => s.isNotEmpty).join('\n'),
            maxLines: 4, overflow: TextOverflow.ellipsis),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => openRecordForResolution(context, record),
        onLongPress: record.syncState == SyncState.error
            ? () async {
                // Allow re-sending an errored record after a server-side fix.
                await ref.read(entityDaoProvider).put(record.copyWith(syncState: SyncState.pending, clearError: true));
                bumpDataVersion(ref);
                if (context.mounted) showMessage(context, l10n.retry);
              }
            : null,
      ),
    );
  }
}

/// Navigate to the right place to deal with a record in a given state.
void openRecordForResolution(BuildContext context, EntityRecord record) {
  switch (record.syncState) {
    case SyncState.duplicate:
      context.push(Routes.resolveDuplicate(record.uuid));
      break;
    case SyncState.conflict:
      context.push(Routes.resolveConflict(record.uuid));
      break;
    default:
      if (Entities.identityEntities.contains(record.entity)) {
        context.push(Routes.editRegistration(record.uuid));
      } else if (record.entity.endsWith('.teacher')) {
        context.push(Routes.editTeacher(record.uuid));
      } else if (Entities.attendanceEntities.contains(record.entity)) {
        context.push(Routes.attendance(Entities.moduleOf(record.entity)));
      } else {
        context.push(Routes.editService(record.uuid));
      }
  }
}
