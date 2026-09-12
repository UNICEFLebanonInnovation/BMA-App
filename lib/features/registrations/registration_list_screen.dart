import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/models/entity_record.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import 'registration_helpers.dart';

enum _Filter { all, pending, attention }

class RegistrationListScreen extends ConsumerStatefulWidget {
  const RegistrationListScreen({super.key, required this.module});

  final BmaModule module;

  @override
  ConsumerState<RegistrationListScreen> createState() => _RegistrationListScreenState();
}

class _RegistrationListScreenState extends ConsumerState<RegistrationListScreen> {
  String _search = '';
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(currentProfileProvider);
    final entity = Entities.registrationFor(widget.module);
    ref.watch(dataVersionProvider);
    final states = switch (_filter) {
      _Filter.all => null,
      _Filter.pending => [SyncState.pending, SyncState.pushing],
      _Filter.attention => [SyncState.duplicate, SyncState.conflict, SyncState.error],
    };
    final future = ref.read(entityDaoProvider).list(RecordQuery(entity: entity, search: _search, states: states, limit: 300));
    final canRegister = profile?.capabilities(widget.module).canRegister ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.beneficiaries)),
      floatingActionButton: canRegister
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.newRegistration(widget.module)),
              icon: const Icon(Icons.person_add),
              label: Text(l10n.registerNew),
            )
          : null,
      body: Column(
        children: [
          const OfflineBanner(),
          SearchField(onChanged: (v) => setState(() => _search = v)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<_Filter>(
              segments: [
                ButtonSegment(value: _Filter.all, label: Text(l10n.beneficiaries)),
                ButtonSegment(value: _Filter.pending, label: Text(l10n.pending)),
                ButtonSegment(value: _Filter.attention, label: Text(l10n.kpiDuplicates)),
              ],
              selected: {_filter},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<EntityRecord>>(
              future: future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final records = snapshot.data!;
                if (records.isEmpty) return EmptyState(message: l10n.noResults, icon: Icons.people_outline);
                return ListView.separated(
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _RegistrationTile(record: records[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistrationTile extends StatelessWidget {
  const _RegistrationTile({required this.record});

  final EntityRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = RegistrationView(record);
    final subtitle = [
      if (view.motherName != null && view.motherName!.isNotEmpty) view.motherName,
      if (view.birthday != null) view.birthday,
      if (view.gender != null && view.gender!.isNotEmpty) view.gender,
      if (view.nationalityLabel != null) view.nationalityLabel,
      view.centerLabel ?? view.schoolLabel,
    ].whereType<String>().join(' · ');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: Text(view.fullName.isEmpty ? '?' : view.fullName.characters.first.toUpperCase(),
            style: const TextStyle(color: AppColors.primary)),
      ),
      title: Text(view.fullName.isEmpty ? l10n.unknown : view.fullName),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: SyncStateChip(record.syncState, compact: true),
      onTap: () => context.push(Routes.profile(record.uuid)),
    );
  }
}
