import 'dart:math' as math;

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
import '../../core/layout/app_layout.dart';
import '../../core/models/entity_record.dart';
import '../../core/models/form_schema.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import 'registration_helpers.dart';

/// The beneficiary profile body — summary, information tab, services tab and
/// attendance tab — rendered in one of two hosts.
///
/// * `embedded: false` is the route at `/record/:uuid`: the same
///   [DefaultTabController] + [Scaffold] + [AppBar] + [PopupMenuButton] the
///   phone has always shown.
/// * `embedded: true` is the detail pane of the two-pane beneficiaries list.
///   It builds NO [Scaffold] (the list screen owns it) and the app bar actions
///   become labelled buttons in the identity panel.
///
/// The two hosts share one action list, so an action can never exist in one and
/// not the other, and they share one destructive path: the `context.pop()` that
/// follows "mark deleted" becomes `onClosed!()` when embedded. Popping from a
/// pane would dismiss the whole list screen, which is why [onClosed] is not
/// optional in that mode.
class ChildProfileView extends ConsumerWidget {
  const ChildProfileView({
    super.key,
    required this.uuid,
    this.embedded = false,
    this.onClosed,
  }) : assert(!embedded || onClosed != null, 'An embedded profile must be able to close itself.');

  final String uuid;

  /// True when this renders inside another screen's Scaffold.
  final bool embedded;

  /// Invoked instead of `context.pop()` when the record is dismissed.
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final record = ref.watch(recordProvider(uuid));
    return record.when(
      loading: () => _frame(const Center(child: CircularProgressIndicator())),
      error: (e, _) => _frame(EmptyState(message: e.toString())),
      data: (r) {
        if (r == null) return _frame(EmptyState(message: l10n.noResults));
        return _ProfileBody(record: r, embedded: embedded, onClosed: onClosed);
      },
    );
  }

  /// The placeholder chrome. Unchanged for the route; bare inside a pane.
  Widget _frame(Widget body) => embedded ? body : Scaffold(appBar: AppBar(), body: body);
}

/// One row of the shared action list. `overflow` marks the items that live in
/// the app bar's popup menu rather than beside it.
@immutable
class _ProfileAction {
  const _ProfileAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onSelected,
    this.overflow = false,
    this.primary = false,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback onSelected;
  final bool overflow;
  final bool primary;

  Key get key => ValueKey('profile-action-$id');
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.record, required this.embedded, this.onClosed});

  final EntityRecord record;
  final bool embedded;
  final VoidCallback? onClosed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final view = RegistrationView(record);
    final profile = ref.watch(currentProfileProvider);
    final caps = profile?.capabilities(view.module);
    final canEdit = (caps?.canEdit ?? false) && record.syncState != SyncState.discarded;
    final actions = _actions(context, ref, l10n, view, canEdit);
    final overflow = actions.where((a) => a.overflow).toList();
    final tabs = [
      Tab(text: l10n.info),
      Tab(text: l10n.services),
      Tab(text: l10n.attendance),
    ];

    if (embedded) {
      return DefaultTabController(
        length: 3,
        child: _content(view: view, actions: actions, tabs: tabs, canEdit: canEdit),
      );
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(view.fullName.isEmpty ? l10n.profile : view.fullName),
          actions: [
            for (final a in actions.where((a) => !a.overflow))
              IconButton(
                key: a.key,
                icon: Icon(a.icon),
                tooltip: a.label,
                onPressed: a.onSelected,
              ),
            if (overflow.isNotEmpty)
              PopupMenuButton<String>(
                onSelected: (value) => overflow.firstWhere((a) => a.id == value).onSelected(),
                itemBuilder: (context) => [
                  for (final a in overflow)
                    PopupMenuItem(key: a.key, value: a.id, child: Text(a.label)),
                ],
              ),
          ],
          bottom: TabBar(tabs: tabs),
        ),
        // The route owns the app bar, so its actions are NOT repeated in the
        // identity panel: an empty list renders no buttons there.
        body: _content(view: view, actions: const [], tabs: tabs, canEdit: canEdit),
      ),
    );
  }

  /// The part both hosts render. Measures its own box and installs a scope, so
  /// the Info tab's [SchemaReview] packs against the real pane width rather
  /// than the window.
  Widget _content({
    required RegistrationView view,
    required List<_ProfileAction> actions,
    required List<Tab> tabs,
    required bool canEdit,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppLayout.forWidth(constraints.maxWidth);
        // identityPaneWidth is 0 below expanded; the detail pane of a 1280 px
        // window is 879 px, i.e. `medium`, and it still wants the panel.
        final preferred = layout.identityPaneWidth > 0 ? layout.identityPaneWidth : 340.0;
        // The panel SHRINKS BEFORE IT DISAPPEARS, down to 300 px, because the
        // tab body needs 360 — below that the tabs would be narrower than a
        // phone and the header band is the better answer. A hard
        // `preferred + 360` floor cost the panel on the exact device this
        // layout is for: with the navigation rail installed the embedded
        // detail pane is 1280 − 212 rail − 1 − 400 list − 1 = 666 px.
        final identityWidth = math.min(preferred, constraints.maxWidth - 360);
        final split = identityWidth >= 300;
        final bodies = [
          _InfoTab(record: record),
          _ServicesTab(record: record, canEdit: canEdit),
          _AttendanceTab(record: record),
        ];

        if (!split) {
          // Unchanged tree: header band above the tab bodies.
          return LayoutScope(
            layout: layout,
            child: Column(
              children: [
                _Header(view: view),
                if (embedded) TabBar(tabs: tabs),
                Expanded(child: TabBarView(children: bodies)),
              ],
            ),
          );
        }
        return LayoutScope(
          layout: layout,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: identityWidth,
                child: _IdentityPanel(view: view, actions: actions),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    if (embedded) TabBar(tabs: tabs),
                    Expanded(child: TabBarView(children: bodies)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// The single source of truth for what this profile can do. Both the app bar
  /// and the identity panel render this list; the order is the order the phone
  /// has always shown (resolve, edit, then the overflow menu).
  List<_ProfileAction> _actions(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    RegistrationView view,
    bool canEdit,
  ) {
    return [
      if (record.syncState.needsAttention)
        _ProfileAction(
          id: 'resolve',
          icon: Icons.warning_amber,
          label: l10n.resolveDuplicate,
          onSelected: () => _openResolution(context, record),
        ),
      if (canEdit)
        _ProfileAction(
          id: 'edit',
          icon: Icons.edit,
          label: l10n.edit,
          primary: true,
          onSelected: () => context.push(Routes.editRegistration(record.uuid)),
        ),
      if (canEdit && view.module == BmaModule.mscc && record.serverId != null)
        _ProfileAction(
          id: 'newround',
          icon: Icons.autorenew,
          label: l10n.newRound,
          overflow: true,
          onSelected: () => context.push(Routes.newService(record.uuid, 'mscc.new_round')),
        ),
      if (canEdit)
        _ProfileAction(
          id: 'delete',
          icon: Icons.delete_outline,
          label: l10n.markDeleted,
          overflow: true,
          onSelected: () => _markDeleted(context, ref),
        ),
    ];
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

  Future<void> _markDeleted(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    if (!await confirmDialog(context, l10n.deleteConfirm)) return;
    await ref.read(entityDaoProvider).markDeleted(record);
    bumpDataVersion(ref);
    await ref.read(syncEngineProvider.notifier).refreshCounts();
    // THE PANE CONTRACT: popping here would dismiss the beneficiaries list, not
    // the record. The host clears its own selection instead.
    if (embedded) {
      onClosed!();
      return;
    }
    if (context.mounted) context.pop();
  }
}

/// The 340 px identity column shown beside the tabs on a wide box.
class _IdentityPanel extends ConsumerWidget {
  const _IdentityPanel({required this.view, required this.actions});

  final RegistrationView view;
  final List<_ProfileAction> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    final cache = ref.watch(referenceCacheProvider);
    final nationalityId = view.nationalityId is int ? view.nationalityId as int : int.tryParse('${view.nationalityId}');
    final name = view.fullName.isEmpty ? l10n.profile : view.fullName;
    final text = Theme.of(context).textTheme;
    // Gender and nationality have no label string of their own, so they read
    // as one muted line under the name rather than as invented FactRow labels.
    // The nationality may only be an id locally, hence the same cache lookup
    // the header band does.
    final identityLine = FutureBuilder<String>(
      future: cache.label('nationalities', nationalityId, language),
      builder: (context, snap) {
        final parts = [
          if (view.gender != null && view.gender!.isNotEmpty) view.gender!,
          if ((view.nationalityLabel ?? snap.data ?? '').isNotEmpty) view.nationalityLabel ?? snap.data!,
        ];
        if (parts.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(parts.join(' · '), style: text.bodyMedium?.copyWith(color: AppColors.muted)),
        );
      },
    );
    // The value column is what is left of 340 after the padding, so the label
    // column is pinned narrow here rather than following the token (180/200).
    const labelWidth = 116.0;

    return Container(
      key: const ValueKey('profile-identity'),
      color: AppColors.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: InitialsAvatar(name, radius: 34),
            ),
            const SizedBox(height: 12),
            Text(name, style: text.titleLarge),
            identityLine,
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SyncStateChip(view.record.syncState),
            ),
            if (view.record.serverMessage != null && view.record.serverMessage!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  view.record.serverMessage!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 12),
                ),
              ),
            const Divider(height: 24),
            if (view.number != null) FactRow(label: l10n.childNumber, value: view.number!, labelWidth: labelWidth),
            if (view.unicefId != null && view.unicefId != '0')
              FactRow(label: l10n.unicefId, value: view.unicefId!, labelWidth: labelWidth),
            if (view.age != null) FactRow(label: l10n.childAge, value: '${view.age}', labelWidth: labelWidth),
            if (view.birthday != null) FactRow(label: l10n.colBirthday, value: view.birthday!, labelWidth: labelWidth),
            if (view.centerLabel != null)
              FactRow(label: l10n.registeredAt, value: view.centerLabel!, labelWidth: labelWidth),
            if (view.schoolLabel != null)
              FactRow(label: l10n.registeredAt, value: view.schoolLabel!, labelWidth: labelWidth),
            if (actions.isNotEmpty) ...[
              const Divider(height: 24),
              for (final a in actions) ...[
                if (a.primary)
                  FilledButton.icon(key: a.key, icon: Icon(a.icon), label: Text(a.label), onPressed: a.onSelected)
                else
                  OutlinedButton.icon(key: a.key, icon: Icon(a.icon), label: Text(a.label), onPressed: a.onSelected),
                const SizedBox(height: 8),
              ],
            ],
          ],
        ),
      ),
    );
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
            // SchemaReview packs itself: one column on the phone, two from
            // 1000 px and three from 1400. ~81 fields, one measured box.
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
    final wide = LayoutScope.of(context).width.atLeastMedium;
    final addButton = FilledButton.icon(
      icon: const Icon(Icons.add),
      label: Text(l10n.addService),
      onPressed: () => _pickService(context, serviceSchemas, language),
    );
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
              // Content-sized and pinned to the start edge on a desk; centred
              // by the Column's default alignment on the phone, as today.
              child: wide
                  ? Align(alignment: AlignmentDirectional.centerStart, child: addButton)
                  : addButton,
            ),
          ),
      ],
    );
  }

  Future<void> _pickService(BuildContext context, List<EntitySchema> options, String language) async {
    Widget body(BuildContext sheetContext) => ListView(
          shrinkWrap: true,
          children: options
              .map((s) => ListTile(
                    title: Text(s.label),
                    subtitle: s.description.isEmpty ? null : Text(s.description),
                    onTap: () => Navigator.of(sheetContext).pop(s.key),
                  ))
              .toList(),
        );
    // Modality is a DEVICE question, and this runs from a tap callback, so the
    // scope is read WITHOUT registering a dependency — same rule as
    // ReferencePickerSheet.show.
    final scope = context.getInheritedWidgetOfExactType<LayoutScope>();
    final asDialog = scope == null ? isTabletDevice(context) : scope.layout.dialogPickers;
    final entity = asDialog
        ? await showDialog<String>(
            context: context,
            builder: (dialogContext) => Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480, maxHeight: 560),
                child: body(dialogContext),
              ),
            ),
          )
        : await showModalBottomSheet<String>(
            context: context,
            builder: (context) => body(context),
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
    final wide = LayoutScope.of(context).width.atLeastMedium;
    final month = FilledButton.icon(
      icon: const Icon(Icons.calendar_month),
      label: Text(l10n.childMonth),
      onPressed: () => context.push(Routes.childAttendance(record.uuid)),
    );
    final sheet = OutlinedButton.icon(
      icon: const Icon(Icons.fact_check),
      label: Text(l10n.attendance),
      onPressed: () => context.push(Routes.attendance(view.module)),
    );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (view.dropoutDate != null) InfoLine('Dropout', view.dropoutDate),
        if (view.registrationDate != null) InfoLine(l10n.registeredAt, view.registrationDate),
        const SizedBox(height: 12),
        // A ListView stretches its children, so on the phone these stay the
        // full-width bars they have always been.
        if (wide)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(spacing: 12, runSpacing: 12, children: [month, sheet]),
          )
        else ...[
          month,
          const SizedBox(height: 8),
          sheet,
        ],
      ],
    );
  }
}
