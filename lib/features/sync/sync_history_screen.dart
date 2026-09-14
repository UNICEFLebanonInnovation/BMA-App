import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/providers.dart';
import '../../core/db/sync_dao.dart';
import '../../core/models/sync_models.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';

class SyncHistoryScreen extends ConsumerWidget {
  const SyncHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.watch(dataVersionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.syncHistory)),
      body: FutureBuilder<List<SyncBatch>>(
        future: ref.read(syncDaoProvider).history(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final batches = snapshot.data!;
          if (batches.isEmpty) return EmptyState(message: l10n.noHistory, icon: Icons.history);
          return ListView.builder(
            itemCount: batches.length,
            itemBuilder: (context, index) {
              final b = batches[index];
              final ok = b.status == 'completed';
              final problems = (b.summary['duplicate'] ?? 0) + (b.summary['conflict'] ?? 0) + (b.summary['error'] ?? 0);
              return ListTile(
                leading: Icon(ok ? (problems > 0 ? Icons.warning_amber : Icons.check_circle) : Icons.error,
                    color: ok ? (problems > 0 ? AppColors.warning : AppColors.success) : AppColors.danger),
                title: Text((b.finishedAt ?? b.startedAt).split('.').first.replaceFirst('T', ' ')),
                subtitle: Text('${l10n.items(b.itemCount)} · ${b.error ?? b.summary.entries.where((e) => e.key != 'total').map((e) => '${e.key} ${e.value}').join(', ')}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.pushReport(b.uuid)),
              );
            },
          );
        },
      ),
    );
  }
}
