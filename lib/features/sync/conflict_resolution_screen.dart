import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/layout/adaptive.dart';
import '../../core/layout/app_layout.dart';
import '../../core/models/entity_record.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';

/// Side-by-side comparison of a locally edited record with the server copy
/// that changed in the meantime.
class ConflictResolutionScreen extends ConsumerWidget {
  const ConflictResolutionScreen({super.key, required this.uuid});

  final String uuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final record = ref.watch(recordProvider(uuid));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.resolveConflict)),
      body: record.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(message: e.toString()),
        data: (r) => r == null ? EmptyState(message: l10n.noResults) : _Body(record: r),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.record});

  final EntityRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final local = _flatten(record.entity, record.data);
    final server = _flatten(record.entity, record.conflictData ?? const {});
    final keys = {...local.keys, ...server.keys}.where((k) => '${local[k] ?? ''}' != '${server[k] ?? ''}').toList()
      ..sort();
    // The pane width, not the window: a conflict opened beside a rail must
    // fall back to the stacked cards rather than squeeze three columns.
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppLayout.forWidth(constraints.maxWidth);
        if (!layout.width.atLeastMedium) {
          // Compact keeps today's one-Card-per-field stack verbatim: three
          // columns inside 412 px would give each value about 90 px.
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    Text(l10n.conflictExplanation, style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(height: 12),
                    Text(l10n.fieldDifferences, style: Theme.of(context).textTheme.titleSmall),
                    if (keys.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Text(l10n.noResults)),
                    for (final key in keys)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(key, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(child: _cell(l10n.localVersion, local[key], AppColors.secondary)),
                              const SizedBox(width: 8),
                              Expanded(child: _cell(l10n.serverVersion, server[key], AppColors.warning)),
                            ]),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
              _footer(context, ref, l10n, layout),
            ],
          );
        }
        return AdaptiveBody(
          maxWidth: layout.readingMaxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(0, 12, 0, 12),
                child: Text(l10n.conflictExplanation, style: const TextStyle(color: AppColors.muted)),
              ),
              // The table hugs its rows (a two-field conflict is a two-row
              // table, not a half-empty full-height card) while the footer
              // stays pinned to the bottom of the screen: the inner Column
              // takes the height, the Flexible inside it does not.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [Flexible(child: _table(context, l10n, keys, local, server, layout))],
                ),
              ),
              _footer(context, ref, l10n, layout),
            ],
          ),
        );
      },
    );
  }

  /// field | your version | server version, with the header row pinned above
  /// its own scroll. One row per differing field instead of one Card per
  /// field: the whole diff is scannable without scrolling on a 9-inch panel.
  Widget _table(
    BuildContext context,
    AppLocalizations l10n,
    List<String> keys,
    Map<String, dynamic> local,
    Map<String, dynamic> server,
    AppLayout layout,
  ) {
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    return Card(
      key: const ValueKey('conflict-table'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.surfaceAlt,
            child: _tableRow(
              layout: layout,
              field: Text(l10n.fieldDifferences, style: labelStyle),
              local: Text(l10n.localVersion, style: labelStyle?.copyWith(color: AppColors.secondary)),
              server: Text(l10n.serverVersion, style: labelStyle?.copyWith(color: AppColors.warning)),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: keys.isEmpty
                ? Padding(padding: const EdgeInsets.all(12), child: Text(l10n.noResults))
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: keys.length,
                    itemBuilder: (context, i) {
                      final key = keys[i];
                      return Container(
                        key: ValueKey('conflict-row-$key'),
                        // Zebra striping instead of a card per field: the row
                        // boundary is what the eye needs, not a shadow.
                        color: i.isOdd ? AppColors.surfaceAlt.withValues(alpha: 0.45) : null,
                        child: _tableRow(
                          layout: layout,
                          field: Text(key, style: const TextStyle(fontWeight: FontWeight.w600)),
                          local: Text(_display(local[key])),
                          server: Text(_display(server[key])),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tableRow({
    required AppLayout layout,
    required Widget field,
    required Widget local,
    required Widget server,
  }) =>
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: layout.labelColumnWidth, child: field),
            const SizedBox(width: 12),
            Expanded(child: local),
            const SizedBox(width: 12),
            Expanded(child: server),
          ],
        ),
      );

  Widget _footer(BuildContext context, WidgetRef ref, AppLocalizations l10n, AppLayout layout) {
    final keepServer = OutlinedButton(
      key: const ValueKey('conflict-keep-server'),
      onPressed: () => _keepServer(context, ref),
      child: Text(l10n.keepServer),
    );
    final overwrite = FilledButton(
      key: const ValueKey('conflict-overwrite'),
      onPressed: () => _overwrite(context, ref),
      child: Text(l10n.overwriteServer),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 12),
        child: layout.width.atLeastMedium
            // Intrinsic width, trailing-aligned: two ~620 px buttons at
            // opposite corners are not a choice, they are a hazard.
            ? Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [keepServer, overwrite],
              )
            : Row(children: [
                Expanded(child: keepServer),
                const SizedBox(width: 8),
                Expanded(child: overwrite),
              ]),
      ),
    );
  }

  static String _display(Object? value) => value == null || value.toString().isEmpty ? '—' : value.toString();

  static Widget _cell(String title, Object? value, Color color) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: color, fontSize: 11)),
          Text(_display(value)),
        ]),
      );

  static Map<String, dynamic> _flatten(String entity, Map<String, dynamic> data) {
    final flat = Entities.identityEntities.contains(entity)
        ? SyncEngine.flattenIdentityPayload(entity, Map.of(data))
        : Map<String, dynamic>.from(data);
    flat.removeWhere((k, v) =>
        k.endsWith('_label') ||
        const {'id', 'created', 'modified', 'owner', 'modified_by', 'label', 'education_summary', 'child_id', 'student_id'}.contains(k) ||
        v is Map ||
        v is List && v.isNotEmpty && v.first is Map);
    return flat;
  }

  Future<void> _overwrite(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    await ref.read(entityDaoProvider).setResolution(record, {'action': 'overwrite'});
    bumpDataVersion(ref);
    await ref.read(syncEngineProvider.notifier).refreshCounts();
    if (!context.mounted) return;
    showMessage(context, l10n.resolvedLocally);
    context.pop();
  }

  Future<void> _keepServer(BuildContext context, WidgetRef ref) async {
    final dao = ref.read(entityDaoProvider);
    final serverData = record.conflictData;
    if (serverData != null) {
      await dao.put(record.copyWith(
        data: serverData,
        label: EntityDao.labelFor(record.entity, serverData),
        search: EntityDao.searchTextFor(record.entity, serverData),
        syncState: SyncState.synced,
        clearOp: true,
        clearConflict: true,
        clearResolution: true,
        clearError: true,
        serverModified: serverData['modified']?.toString(),
      ));
    } else {
      await dao.put(record.copyWith(syncState: SyncState.synced, clearOp: true, clearConflict: true));
    }
    bumpDataVersion(ref);
    await ref.read(syncEngineProvider.notifier).refreshCounts();
    if (context.mounted) context.pop();
  }
}
