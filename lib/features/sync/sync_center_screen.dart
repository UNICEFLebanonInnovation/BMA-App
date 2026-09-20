import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/db/sync_dao.dart';
import '../../core/forms/reference_cache.dart';
import '../../core/layout/adaptive.dart';
import '../../core/layout/app_layout.dart';
import '../../core/models/entity_record.dart';
import '../../core/models/sync_models.dart';
import '../../core/sync/connectivity_service.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../tips/tip_card.dart';
import '../tips/tips_content.dart';

/// Width of the leading status pane at expanded (the spec's 420). Wide enough
/// for the counts and the three sync actions, narrow enough that the queue —
/// the actual work, currently below the fold — gets the rest of the screen.
const double _statusPaneWidth = 420;

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
      // The WINDOW is never read here: the branch is on the box this screen was
      // handed, so a rail (or any future pane) narrows the layout honestly.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = AppLayout.forWidth(constraints.maxWidth);
          if (layout.twoPane) {
            // Intra-screen split, no routing involved: status and actions on
            // the leading side, the resolution queue on the trailing side with
            // its heading pinned above a scroll of its own.
            return LayoutScope(
              layout: layout,
              child: TwoPane(
                paneWidth: _statusPaneWidth,
                pane: ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    const OfflineBanner(),
                    // The pane is a 420 px box, so AppLayout.forWidth gives
                    // it the COMPACT tokens — deliberately: everything inside
                    // reads the width it was handed, and at 420 the two
                    // stretched sync buttons are ~178 px, not the ~620 px this
                    // commit exists to stop.
                    _statusCard(context, l10n, sync, online, engine, ref, run,
                        AppLayout.forWidth(_statusPaneWidth)),
                    TipCard(id: TipIds.syncCenter, text: l10n.tipSyncCenter),
                    _latestCard(context, l10n, latestFuture),
                    _aboutSync(l10n),
                  ],
                ),
                detail: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _queueHeading(context, l10n),
                    const Divider(height: 1),
                    Expanded(child: _attentionList(l10n, sync, attentionFuture, scroll: true)),
                  ],
                ),
              ),
            );
          }
          // Below expanded this is today's single column, verbatim; at medium
          // it is centred at contentMaxWidth with a real gutter, and at compact
          // it is returned unwrapped so the phone tree gains nothing at all.
          final content = ListView(
            padding: const EdgeInsets.all(8),
            children: [
              const OfflineBanner(),
              _statusCard(context, l10n, sync, online, engine, ref, run, layout),
              TipCard(id: TipIds.syncCenter, text: l10n.tipSyncCenter),
              _latestCard(context, l10n, latestFuture),
              _queueHeading(context, l10n),
              _attentionList(l10n, sync, attentionFuture, scroll: false),
              _aboutSync(l10n),
            ],
          );
          return layout.width.atLeastMedium
              ? AdaptiveBody(maxWidth: layout.contentMaxWidth, child: content)
              : content;
        },
      ),
    );
  }

  Widget _statusCard(
    BuildContext context,
    AppLocalizations l10n,
    SyncStatus sync,
    bool online,
    SyncEngine engine,
    WidgetRef ref,
    Future<void> Function(Future<void> Function()) run,
    AppLayout layout,
  ) {
    final busy = sync.busy || !online;
    final push = FilledButton.icon(
      key: const ValueKey('sync-push'),
      onPressed: busy ? null : () => run(engine.push),
      icon: const Icon(Icons.upload),
      label: Text(l10n.pushNow),
    );
    final pull = OutlinedButton.icon(
      key: const ValueKey('sync-pull'),
      onPressed: busy ? null : () => run(() => engine.pull()),
      icon: const Icon(Icons.download),
      label: Text(l10n.pullNow),
    );
    final refresh = TextButton.icon(
      key: const ValueKey('sync-refresh'),
      onPressed: busy
          ? null
          : () => run(() async {
                await engine.bootstrap();
                ref.read(referenceCacheProvider).invalidate();
                await engine.pull(full: true);
              }),
      icon: const Icon(Icons.refresh),
      label: Text(l10n.fullRefresh),
    );
    return Card(
      key: const ValueKey('sync-status-pane'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(online ? Icons.wifi : Icons.wifi_off, color: online ? AppColors.success : AppColors.warning),
              const SizedBox(width: 8),
              Text(online ? l10n.online : l10n.offline),
              // Expanded, not Spacer + Text: the timestamp is painted at the
              // end of the same free space, so this is pixel-identical
              // wherever the line fits, and it WRAPS instead of overflowing
              // where it does not — which today it does in a 420 px pane, and
              // in Arabic at 1.3x on the phone too.
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Text(
                    l10n.lastPull(sync.lastPull?.split('.').first.replaceFirst('T', ' ') ?? l10n.never),
                    textAlign: TextAlign.end,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final state in SyncState.values)
                if ((sync.counts[state] ?? 0) > 0 && state != SyncState.synced)
                  Chip(
                    // forceIcon: the avatar slot is ~18 px square and
                    // cannot hold the labelled Chip that `compact: true`
                    // now promotes to at tablet width.
                    avatar: SyncStateChip(state, compact: true, forceIcon: true),
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
            if (layout.width.atLeastMedium)
              // Intrinsic width instead of two ~620 px Expandeds. Wrap, not
              // Row, so Arabic at 1.3x runs onto a second line rather than
              // overflowing the pane.
              Wrap(spacing: 8, runSpacing: 8, children: [push, pull, refresh])
            else ...[
              Row(children: [
                Expanded(child: push),
                const SizedBox(width: 8),
                Expanded(child: pull),
              ]),
              const SizedBox(height: 8),
              refresh,
            ],
          ],
        ),
      ),
    );
  }

  Widget _latestCard(BuildContext context, AppLocalizations l10n, Future<SyncBatch?> latestFuture) {
    return FutureBuilder<SyncBatch?>(
      future: latestFuture,
      builder: (context, snapshot) {
        final batch = snapshot.data;
        if (batch == null) return const SizedBox.shrink();
        return Card(
          child: ListTile(
            key: const ValueKey('sync-latest-batch'),
            leading: Icon(batch.status == 'completed' ? Icons.assignment_turned_in : Icons.error_outline,
                color: batch.status == 'completed' ? AppColors.success : AppColors.danger),
            title: Text(l10n.pushReport),
            subtitle: Text(_summaryLine(l10n, batch)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.pushReport(batch.uuid)),
          ),
        );
      },
    );
  }

  Widget _queueHeading(BuildContext context, AppLocalizations l10n) => Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 16, 12, 4),
        child: Text(l10n.needsResolution, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _aboutSync(AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(l10n.aboutSync, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      );

  /// [scroll] true builds the trailing pane's own scrollable; false keeps the
  /// shrink-wrapping Column that today's single ListView needs.
  Widget _attentionList(
    AppLocalizations l10n,
    SyncStatus sync,
    Future<List<EntityRecord>> attentionFuture, {
    required bool scroll,
  }) {
    return FutureBuilder<List<EntityRecord>>(
      key: const ValueKey('sync-queue'),
      future: attentionFuture,
      builder: (context, snapshot) {
        final records = snapshot.data ?? const [];
        if (snapshot.hasData && records.isEmpty) {
          final empty = Padding(
            padding: const EdgeInsets.all(12),
            child: Text(sync.pendingCount == 0 ? l10n.noPendingWork : l10n.pendingChanges(sync.pendingCount),
                style: const TextStyle(color: AppColors.muted)),
          );
          return scroll ? ListView(padding: const EdgeInsets.all(8), children: [empty]) : empty;
        }
        if (scroll) {
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: records.length,
            itemBuilder: (context, i) => _AttentionTile(record: records[i]),
          );
        }
        return Column(children: [for (final r in records) _AttentionTile(record: r)]);
      },
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
      key: ValueKey('sync-queue-${record.uuid}'),
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
