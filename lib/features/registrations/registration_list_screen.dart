import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/layout/adaptive.dart';
import '../../core/layout/app_layout.dart';
import '../../core/models/entity_record.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../tips/tip_card.dart';
import '../tips/tips_content.dart';
import 'child_profile_view.dart';
import 'registration_helpers.dart';

enum _Filter { all, pending, attention }

/// The beneficiaries list. On a wide window it is the app's only routed
/// master-detail: the selected child is a `?sel=` query parameter on this same
/// route, so the page (and therefore the search text, the filter and the scroll
/// offset) survives a selection, the URL is shareable and rotation keeps the
/// selection. On a phone it is exactly the list it has always been.
class RegistrationListScreen extends ConsumerStatefulWidget {
  const RegistrationListScreen({super.key, required this.module, this.selectedUuid});

  final BmaModule module;

  /// `?sel=` from the router. Honoured only where a detail pane exists.
  final String? selectedUuid;

  @override
  ConsumerState<RegistrationListScreen> createState() => _RegistrationListScreenState();
}

class _RegistrationListScreenState extends ConsumerState<RegistrationListScreen> {
  String _search = '';
  _Filter _filter = _Filter.all;

  // The 300-row query used to be rebuilt on every build(), which meant every
  // keystroke AND every selection re-issued it. It is now memoised on
  // (entity, search, filter, dataVersion) — the only inputs that can change its
  // result — so tapping a row costs nothing.
  Future<List<EntityRecord>>? _future;
  String? _queryKey;

  List<SyncState>? get _states => switch (_filter) {
        _Filter.all => null,
        _Filter.pending => [SyncState.pending, SyncState.pushing],
        _Filter.attention => [SyncState.duplicate, SyncState.conflict, SyncState.error],
      };

  Future<List<EntityRecord>> _records(int dataVersion) {
    final entity = Entities.registrationFor(widget.module);
    final key = '$entity|$_search|${_filter.name}|$dataVersion';
    if (_future == null || key != _queryKey) {
      _queryKey = key;
      _future = ref.read(entityDaoProvider).list(
            RecordQuery(entity: entity, search: _search, states: _states, limit: 300),
          );
    }
    return _future!;
  }

  void _select(String uuid, {required bool twoPane}) {
    if (twoPane) {
      // `replace`, never `pushReplacement`: go_router reuses the page key, so
      // this State (search text, filter, scroll) is preserved and the stack
      // depth never changes. A `push` here would stack profiles behind the
      // list; a `pushReplacement` would rebuild the page and clear the search.
      context.replace(Routes.registrationsSelected(widget.module, uuid));
    } else {
      context.push(Routes.profile(uuid));
    }
  }

  void _clearSelection() => context.replace(Routes.registrations(widget.module));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(currentProfileProvider);
    final dataVersion = ref.watch(dataVersionProvider);
    final future = _records(dataVersion);
    final canRegister = profile?.capabilities(widget.module).canRegister ?? false;

    final sel = widget.selectedUuid;
    // A `?sel=` that no longer resolves (deleted, or pasted from another
    // device) must not leave a dead detail pane behind: show the placeholder
    // and heal the URL after the frame.
    final selected = sel == null ? null : ref.watch(recordProvider(sel));
    final selectionMissing = selected != null && selected.hasValue && selected.value == null;
    if (selectionMissing) {
      // Read HERE, in build() and only while a stale selection exists, not
      // inside the callback: `ModalRoute.of` also subscribes this element to
      // `isCurrent`, so the moment a covering route pops this screen rebuilds
      // and the heal below runs for real. Registering that dependency on
      // every build would rebuild a 300-row list on every push and pop.
      final route = ModalRoute.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.selectedUuid != sel) return;
        // ONLY HEAL WHAT IS ON SCREEN. `replace` acts on the TOP of the stack,
        // not on this page, so healing while Settings or the edit wizard is
        // pushed above would destroy that screen and put a second copy of this
        // list in its place — silently, because `replace` triggers no PopScope
        // and never consults unsavedWorkProvider, so an in-progress edit would
        // go with it. A stale `?sel=` is harmless while it is covered.
        if (route != null && !route.isCurrent) return;
        _clearSelection();
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppLayout.forWidth(constraints.maxWidth);
        final wide = layout.width.atLeastMedium;
        final twoPane = layout.twoPane;
        final selectedUuid = twoPane && !selectionMissing ? sel : null;

        final addButton = FilledButton.icon(
          key: const ValueKey('reg-add'),
          icon: const Icon(Icons.person_add),
          label: Text(l10n.registerNew),
          onPressed: () => context.push(Routes.newRegistration(widget.module)),
        );
        final searchField = SearchField(
          key: const ValueKey('reg-search'),
          onChanged: (v) => setState(() => _search = v),
        );
        final filter = SegmentedButton<_Filter>(
          key: const ValueKey('reg-filter'),
          segments: [
            ButtonSegment(value: _Filter.all, label: Text(l10n.beneficiaries)),
            ButtonSegment(value: _Filter.pending, label: Text(l10n.pending)),
            ButtonSegment(value: _Filter.attention, label: Text(l10n.kpiDuplicates)),
          ],
          selected: {_filter},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _filter = s.first),
        );

        final pane = Column(
          key: const ValueKey('reg-list-pane'),
          children: [
            const OfflineBanner(),
            // The floating action button would sit over the detail pane, so
            // from `medium` up the primary action joins the search row.
            if (wide && canRegister)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 12, 0),
                child: Row(children: [
                  Expanded(child: searchField),
                  addButton,
                ]),
              )
            else
              searchField,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: wide ? Align(alignment: AlignmentDirectional.centerStart, child: filter) : filter,
            ),
            // Fixed child above the list: hidden while the keyboard is open so the
            // column always fits a short viewport.
            if (MediaQuery.viewInsetsOf(context).bottom == 0)
              TipCard(id: TipIds.registrationsSearch, text: l10n.tipRegistrationsSearch),
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
                    itemBuilder: (context, index) {
                      final record = records[index];
                      return _RegistrationTile(
                        key: ValueKey('reg-row-${record.uuid}'),
                        record: record,
                        selected: record.uuid == selectedUuid,
                        // The 400 px list pane is itself `compact`, so the row
                        // keeps its stacked shape there; only a full-width
                        // tablet list spreads into columns.
                        multiColumn: wide && !twoPane,
                        labelledChip: wide,
                        onTap: () => _select(record.uuid, twoPane: twoPane),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );

        final body = TwoPane(
          paneWidth: layout.listPaneWidth,
          pane: pane,
          detail: selectedUuid == null
              ? null
              : KeyedSubtree(
                  key: const ValueKey('reg-detail-pane'),
                  // Keyed on the uuid so selecting another child rebuilds the
                  // profile from scratch instead of re-using its tab state.
                  child: KeyedSubtree(
                    key: ValueKey(selectedUuid),
                    child: ChildProfileView(
                      uuid: selectedUuid,
                      embedded: true,
                      onClosed: _clearSelection,
                    ),
                  ),
                ),
          placeholder: EmptyState(
            key: const ValueKey('reg-detail-empty'),
            message: l10n.selectBeneficiary,
            icon: Icons.person_search,
          ),
        );

        return LayoutScope(
          layout: layout,
          child: Scaffold(
            appBar: AppBar(title: Text(l10n.beneficiaries)),
            floatingActionButton: canRegister && !wide
                ? FloatingActionButton.extended(
                    key: const ValueKey('reg-add'),
                    onPressed: () => context.push(Routes.newRegistration(widget.module)),
                    icon: const Icon(Icons.person_add),
                    label: Text(l10n.registerNew),
                  )
                : null,
            // Back clears the selection before it leaves the screen, so the
            // detail pane behaves like a page even though it never pushed one.
            body: PopScope(
              canPop: selectedUuid == null,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                _clearSelection();
              },
              child: body,
            ),
          ),
        );
      },
    );
  }
}

class _RegistrationTile extends StatelessWidget {
  const _RegistrationTile({
    super.key,
    required this.record,
    required this.onTap,
    this.selected = false,
    this.multiColumn = false,
    this.labelledChip = false,
  });

  final EntityRecord record;
  final VoidCallback onTap;

  /// Tinted because it is the child shown in the detail pane.
  final bool selected;

  /// Spreads the subtitle into real columns. Only on a wide single-column list.
  final bool multiColumn;

  /// From `medium` up the sync state is a labelled chip, not an 18 px glyph.
  final bool labelledChip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final view = RegistrationView(record);
    final name = view.fullName.isEmpty ? l10n.unknown : view.fullName;
    final facility = view.centerLabel ?? view.schoolLabel;
    final chip = SyncStateChip(record.syncState, compact: !labelledChip);

    Widget row;
    if (multiColumn) {
      row = Row(
        children: [
          InitialsAvatar(name),
          const SizedBox(width: 14),
          Expanded(flex: 3, child: _cell(name, strong: true)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _cell(view.motherName)),
          const SizedBox(width: 12),
          SizedBox(width: 110, child: _cell(view.birthday)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: _cell(facility)),
          const SizedBox(width: 12),
          chip,
        ],
      );
    } else {
      final subtitle = [
        if (view.motherName != null && view.motherName!.isNotEmpty) view.motherName,
        if (view.birthday != null) view.birthday,
        if (view.gender != null && view.gender!.isNotEmpty) view.gender,
        if (view.nationalityLabel != null) view.nationalityLabel,
        facility,
      ].whereType<String>().join(' · ');
      row = Row(
        children: [
          InitialsAvatar(name),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.25),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          chip,
        ],
      );
    }

    final tile = InkWell(
      onTap: onTap,
      child: Padding(
        padding: multiColumn
            ? const EdgeInsets.symmetric(horizontal: 24, vertical: 14)
            : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: row,
      ),
    );
    // The wrapper exists only for the selected row, so an unselected row — the
    // only kind a phone ever renders — keeps exactly today's tree.
    if (!selected) return tile;
    return Material(color: AppColors.surfaceAlt, child: tile);
  }

  Widget _cell(String? value, {bool strong = false}) => Text(
        value == null || value.isEmpty ? '—' : value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: strong
            ? const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)
            : const TextStyle(color: AppColors.muted, fontSize: 13),
      );
}
