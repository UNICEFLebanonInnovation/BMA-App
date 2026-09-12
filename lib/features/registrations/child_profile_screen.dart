import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/config/settings_controller.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/forms/reference_cache.dart';
import '../../core/forms/schema_form.dart';
import '../../core/models/entity_record.dart';
import '../../core/models/form_schema.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import 'registration_helpers.dart';

/// Beneficiary profile: summary header, information tab, services tab and
/// attendance tab, mirroring the web child profile.
class ChildProfileScreen extends ConsumerWidget {
  const ChildProfileScreen({super.key, required this.uuid});

  final String uuid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final record = ref.watch(recordProvider(uuid));
    return record.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: EmptyState(message: e.toString())),
      data: (r) {
        if (r == null) return Scaffold(appBar: AppBar(), body: EmptyState(message: l10n.noResults));
        return _ProfileBody(record: r);
      },
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.record});

  final EntityRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = RegistrationView(record);
    final profile = ref.watch(currentProfileProvider);
    final caps = profile?.capabilities(view.module);
    final canEdit = (caps?.canEdit ?? false) && record.syncState != SyncState.discarded;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(view.fullName.isEmpty ? l10n.profile : view.fullName),
          actions: [
            if (record.syncState.needsAttention)
              IconButton(
                icon: const Icon(Icons.warning_amber),
                tooltip: l10n.resolveDuplicate,
                onPressed: () => _openResolution(context, record),
              ),
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: l10n.edit,
                onPressed: () => context.push(Routes.editRegistration(record.uuid)),
              ),
            if (canEdit)
              PopupMenuButton<String>(
                onSelected: (value) => _onMenu(context, ref, value),
                itemBuilder: (context) => [
                  if (view.module == BmaModule.mscc && record.serverId != null)
                    PopupMenuItem(value: 'new_round', child: Text(l10n.newRound)),
                  PopupMenuItem(value: 'delete', child: Text(l10n.markDeleted)),
                ],
              ),
          ],
          bottom: TabBar(tabs: [
            Tab(text: l10n.info),
            Tab(text: l10n.services),
            Tab(text: l10n.attendance),
          ]),
        ),
        body: Column(
          children: [
            _Header(view: view),
            Expanded(
              child: TabBarView(children: [
                _InfoTab(record: record),
                _ServicesTab(record: record, canEdit: canEdit),
                _AttendanceTab(record: record),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  void _openResolution(BuildContext context, EntityRecord record) {
    if (record.syncState == SyncState.duplicate) {
      context.push(Routes.resolveDuplicate(record.uuid));
    } else if (record.syncState == SyncState.conflict) {
      context.push(Routes.resolveConflict(record.uuid));
    } else {
      context.push(Routes.editRegistration(record.uuid));
    }
  }

  Future<void> _onMenu(BuildContext context, WidgetRef ref, String value) async {
    final l10n = AppLocalizations.of(context);
    if (value == 'delete') {
      if (!await confirmDialog(context, l10n.deleteConfirm)) return;
      await ref.read(entityDaoProvider).markDeleted(record);
      bumpDataVersion(ref);
      await ref.read(syncEngineProvider.notifier).refreshCounts();
      if (context.mounted) context.pop();
    } else if (value == 'new_round') {
      context.push(Routes.newService(record.uuid, 'mscc.new_round'));
    }
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.view});

  final RegistrationView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    final cache = ref.watch(referenceCacheProvider);
    final nationalityId = view.nationalityId is int ? view.nationalityId as int : int.tryParse('${view.nationalityId}');
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Wrap(spacing: 12, runSpacing: 4, children: [
                if (view.number != null) Text('${l10n.childNumber}: ${view.number}', style: const TextStyle(color: AppColors.muted)),
                if (view.unicefId != null && view.unicefId != '0')
                  Text('${l10n.unicefId}: ${view.unicefId}', style: const TextStyle(color: AppColors.muted)),
              ]),
            ),
            SyncStateChip(view.record.syncState),
          ]),
          const SizedBox(height: 6),
          Wrap(spacing: 16, runSpacing: 2, children: [
            if (view.age != null) Text('${l10n.childAge}: ${view.age}'),
            if (view.gender != null && view.gender!.isNotEmpty) Text(view.gender!),
            if (view.birthday != null) Text(view.birthday!),
            FutureBuilder<String>(
              future: cache.label('nationalities', nationalityId, language),
              builder: (context, snap) => Text(view.nationalityLabel ?? snap.data ?? ''),
            ),
            if (view.centerLabel != null) Text('${l10n.registeredAt}: ${view.centerLabel}'),
            if (view.schoolLabel != null) Text('${l10n.registeredAt}: ${view.schoolLabel}'),
          ]),
          if (view.record.serverMessage != null && view.record.serverMessage!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(view.record.serverMessage!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

class _InfoTab extends ConsumerWidget {
  const _InfoTab({required this.record});

  final EntityRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    final schema = ref.watch(schemaProvider(record.entity));
    final cache = ref.watch(referenceCacheProvider);
    return schema.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(message: e.toString()),
      data: (s) {
        if (s == null) return EmptyState(message: l10n.bootstrapRequired);
        final values = SyncEngine.flattenIdentityPayload(record.entity, Map.of(record.data));
        return FutureBuilder<void>(
          future: Future.wait(s.fields.where((f) => f.isReference && f.ref != null && f.ref != 'parent').map((f) => cache.ensure(f.ref!))),
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SchemaReview(
              schema: s,
              values: values,
              languageCode: language,
              dense: true,
              labelResolver: (FieldSpec field, Object? value) {
                if (!field.isReference || field.ref == null) return null;
                final id = value is int ? value : int.tryParse(value?.toString() ?? '');
                return cache.cached(field.ref!, id)?.labelFor(language);
              },
            ),
          ),
        );
      },
    );
  }
}

class _ServicesTab extends ConsumerWidget {
  const _ServicesTab({required this.record, required this.canEdit});

  final EntityRecord record;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    final children = ref.watch(childRecordsProvider(record.uuid));
    final schemas = ref.watch(schemasProvider).value ?? const <String, EntitySchema>{};
    final serviceSchemas = schemas.values
        .where((s) => s.parent == record.entity && !s.isAttendance)
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    final view = RegistrationView(record);
    return Column(
      children: [
        if (view.educationSummary.isNotEmpty)
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(l10n.educationHistory, style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final e in view.educationSummary)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.timeline),
                    title: Text('${e['education_program'] ?? ''} ${e['class_section'] ?? ''}'),
                    subtitle: Text('${e['registration_date'] ?? ''}'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: children.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState(message: e.toString()),
            data: (list) {
              final services = list.where((c) => !Entities.attendanceEntities.contains(c.entity)).toList();
              if (services.isEmpty) return EmptyState(message: l10n.noServices, icon: Icons.medical_services_outlined);
              return ListView.builder(
                itemCount: services.length,
                itemBuilder: (context, index) {
                  final s = services[index];
                  final schema = schemas[s.entity];
                  return ListTile(
                    leading: const Icon(Icons.assignment_outlined),
                    title: Text(schema?.label ?? s.entity),
                    subtitle: Text(s.label),
                    trailing: SyncStateChip(s.syncState, compact: true),
                    onTap: () => context.push(Routes.editService(s.uuid)),
                  );
                },
              );
            },
          ),
        ),
        if (canEdit && serviceSchemas.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: Text(l10n.addService),
                onPressed: () => _pickService(context, serviceSchemas, language),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _pickService(BuildContext context, List<EntitySchema> options, String language) async {
    final entity = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: options
            .map((s) => ListTile(
                  title: Text(s.label),
                  subtitle: s.description.isEmpty ? null : Text(s.description),
                  onTap: () => Navigator.of(context).pop(s.key),
                ))
            .toList(),
      ),
    );
    if (entity != null && context.mounted) {
      context.push(Routes.newService(record.uuid, entity));
    }
  }
}

class _AttendanceTab extends ConsumerWidget {
  const _AttendanceTab({required this.record});

  final EntityRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = RegistrationView(record);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (view.dropoutDate != null) InfoLine('Dropout', view.dropoutDate),
        if (view.registrationDate != null) InfoLine(l10n.registeredAt, view.registrationDate),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.calendar_month),
          label: Text(l10n.childMonth),
          onPressed: () => context.push(Routes.childAttendance(record.uuid)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.fact_check),
          label: Text(l10n.attendance),
          onPressed: () => context.push(Routes.attendance(view.module)),
        ),
      ],
    );
  }
}
