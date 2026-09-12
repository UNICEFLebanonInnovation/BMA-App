import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
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
    final keys = {...local.keys, ...server.keys}.where((k) => '${local[k] ?? ''}' != '${server[k] ?? ''}').toList()..sort();
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
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _keepServer(context, ref),
                  child: Text(l10n.keepServer),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => _overwrite(context, ref),
                  child: Text(l10n.overwriteServer),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  static Widget _cell(String title, Object? value, Color color) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: color, fontSize: 11)),
          Text(value == null || value.toString().isEmpty ? '—' : value.toString()),
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
