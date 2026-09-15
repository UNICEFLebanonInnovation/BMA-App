import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/config/settings_controller.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/db/reference_dao.dart';
import '../../core/forms/reference_cache.dart';
import '../../core/forms/reference_picker.dart';
import '../../core/layout/adaptive.dart';
import '../../core/layout/app_layout.dart';
import '../../core/models/entity_record.dart';
import '../../core/models/reference_item.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import '../tips/tip_card.dart';
import '../tips/tips_content.dart';
import 'attendance_roster.dart';

/// Daily attendance sheet for a centre (MSCC), school programme (ALP) or
/// bridging level (CLM), saved offline as an idempotent document.
///
/// THREE LAYOUTS, ONE STATE. `_selection`, `_rows`, `_load` and `_save` are
/// shared verbatim by all three, so the saved document cannot depend on the
/// width of the screen that produced it:
///
/// * compact (<600) — today's phone sheet, unchanged: one filter card, one
///   [Card] per child, Save in a bottom bar.
/// * medium (600–999, 9" portrait) — the same stacked sheet with the filters
///   in a two-across grid and the name column bounded so the toggle stops
///   drifting to the far edge.
/// * expanded (>=1000, 9" landscape) — a fixed session pane beside a scrolling
///   roster table. Landscape has LESS height than portrait, so the session
///   pane must not scroll and Save is pinned at its bottom.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key, required this.module});

  final BmaModule module;

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

/// One column of the roster table.
///
/// The SAME list drives the sticky header row and every body row, so a header
/// can never drift out of line with the cells under it. Exactly one of
/// [width] (fixed) and [flex] (share of what is left) is used.
@immutable
class _RosterColumn {
  const _RosterColumn({required this.id, required this.label, this.flex = 0, this.width});

  final String id;
  final String label;
  final int flex;
  final double? width;
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  late AttendanceSelection _selection;
  List<RosterRow>? _rows;
  EntityRecord? _existing;
  bool _loading = false;
  bool _saving = false;
  List<ChoiceRow> _programmes = const [];
  List<ChoiceRow> _sections = const [];
  List<ChoiceRow> _levels = const [];
  List<ChoiceRow> _absenceReasons = const [];
  List<ChoiceRow> _closeReasons = const [];
  List<ReferenceItem> _rounds = const [];
  List<ReferenceItem> _alpProgrammes = const [];

  /// Roster geometry. 60 px rows put 11 children on a 800 px-tall landscape
  /// screen where the phone card list shows five; the attendance segments are
  /// 60 px tall for the same reason they are the tallest control in the app —
  /// they are tapped ~25 times per class by someone standing up.
  static const double _rowHeight = 60;
  static const double _rowHeightOther = 92;
  static const double _cellGap = 8;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(currentProfileProvider);
    final today = DateTime.now();
    _selection = AttendanceSelection(
      module: widget.module,
      date: _iso(today),
      centerId: profile?.center?.id,
      schoolId: profile?.school?.id,
    );
    Future.microtask(_loadReference);
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadReference() async {
    final reference = ref.read(referenceDaoProvider);
    final cache = ref.read(referenceCacheProvider);
    final m = widget.module.key;
    _rounds = await cache.list('rounds.$m');
    final current = _rounds.where((r) => r.extra['current_year'] == true).toList();
    _programmes = await reference.choices('mscc.attendance.education_program');
    _sections = await reference.choices('mscc.attendance.class_section');
    _levels = await reference.choices('clm.attendance.registration_level');
    _absenceReasons = await reference.choices('$m.attendance.absence_reason');
    _closeReasons = await reference.choices('$m.attendance.close_reason');
    _alpProgrammes = await cache.list('alp_programs');
    if (!mounted) return;
    setState(() {
      _selection = _selection.copyWith(roundId: current.isNotEmpty ? current.first.id : (_rounds.isNotEmpty ? _rounds.first.id : null));
    });
  }

  Future<void> _load() async {
    final l10n = AppLocalizations.of(context);
    if (!_selection.complete) {
      showMessage(context, l10n.selectionIncomplete, error: true);
      return;
    }
    setState(() => _loading = true);
    final dao = ref.read(entityDaoProvider);
    final rows = await AttendanceRoster(dao).build(_selection);
    _existing = await dao.byNaturalKey(_selection.entity, _selection.naturalKey);
    if (_existing != null) {
      AttendanceRoster.applySaved(rows, _existing!.data);
      _selection = _selection.copyWith(
        dayOff: (_existing!.data['attendance_day_off'] ?? 'No').toString().toLowerCase() == 'yes',
        closeReason: (_existing!.data['close_reason'] ?? '').toString(),
      );
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final rows = _rows ?? const [];
    if (_selection.dayOff && _selection.closeReason.isEmpty) {
      showMessage(context, l10n.requiredField, error: true);
      return;
    }
    for (final row in rows) {
      if (row.attended == 'No' && !_selection.dayOff) {
        if (row.absenceReason.isEmpty || (row.absenceReason == 'Other' && row.absenceReasonOther.trim().isEmpty)) {
          showMessage(context, '${row.view.fullName}: ${l10n.absenceReason} – ${l10n.requiredField}', error: true);
          return;
        }
      }
    }
    setState(() => _saving = true);
    final dao = ref.read(entityDaoProvider);
    final data = _selection.toHeader()
      ..['children_attendance'] = _selection.dayOff ? <Map<String, dynamic>>[] : rows.map((r) => r.toJson()).toList();
    try {
      if (_existing != null) {
        _existing = await dao.updateLocal(_existing!, data);
      } else {
        _existing = await dao.createLocal(entity: _selection.entity, data: data, naturalKey: _selection.naturalKey);
      }
      bumpDataVersion(ref);
      await ref.read(syncEngineProvider.notifier).refreshCounts();
      if (mounted) showMessage(context, l10n.attendanceSaved);
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetRows() => setState(() {
        _rows = null;
        _existing = null;
      });

  void _markAllPresent() => setState(() {
        for (final r in _rows!) {
          r.attended = 'Yes';
        }
      });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    final profile = ref.watch(currentProfileProvider);
    final scope = profile?.capabilities(widget.module).scope ?? 'none';
    return Scaffold(
      appBar: AppBar(title: Text(l10n.attendance)),
      // The width class comes from the BODY box, never from the window: with a
      // navigation rail beside it this screen is handed ~1067 px, not 1280.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = AppLayout.forWidth(constraints.maxWidth);
          return LayoutScope(
            layout: layout,
            child: Column(
              children: [
                const OfflineBanner(),
                Expanded(
                  child: layout.twoPane
                      ? TwoPane(
                          paneWidth: layout.sessionPaneWidth,
                          pane: _sessionPane(context, l10n, language, scope),
                          detail: _rosterPane(context, l10n, language),
                        )
                      : _stackedBody(context, l10n, language, scope, layout),
                ),
                // Expanded pins Save inside the session pane instead, where the
                // eye already is; a 1280 px-wide Save bar is not an improvement.
                if (!layout.twoPane && _rows != null)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: FilledButton.icon(
                        key: const ValueKey('att-save'),
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save),
                        label: Text(l10n.save),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------- compact / medium

  /// Today's phone sheet. At medium the filter card packs two across and the
  /// name column is bounded; everything else is the same tree.
  Widget _stackedBody(BuildContext context, AppLocalizations l10n, String language, String scope, AppLayout layout) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _filters(context, language, scope, layout),
        const SizedBox(height: 8),
        // Only until a roster is loaded so it never competes with the sheet.
        if (_rows == null && !_loading) TipCard(id: TipIds.attendanceFlow, text: l10n.tipAttendanceFlow),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              key: const ValueKey('att-load'),
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.download_done),
              label: Text(l10n.loadChildren),
            ),
          ),
        ]),
        if (_loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (_rows != null) ...[
          const SizedBox(height: 8),
          _dayOffCard(l10n, language),
          if (!_selection.dayOff) ...[
            if (_rows!.isEmpty)
              EmptyState(message: l10n.noChildrenForSelection, icon: Icons.person_off_outlined)
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Text(l10n.items(_rows!.length), style: const TextStyle(color: AppColors.muted)),
                  const Spacer(),
                  TextButton.icon(
                    key: const ValueKey('att-mark-all'),
                    icon: const Icon(Icons.done_all),
                    label: Text(l10n.markAllPresent),
                    onPressed: _markAllPresent,
                  ),
                ]),
              ),
              for (final row in _rows!) _rowCard(row, l10n, language, layout),
            ],
          ],
          if (_existing != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SyncStateChip(_existing!.syncState),
                const SizedBox(width: 8),
                if (_existing!.serverMessage != null)
                  Expanded(child: Text(_existing!.serverMessage!, style: const TextStyle(color: AppColors.muted))),
              ]),
            ),
        ],
      ],
    );
  }

  Widget _rowCard(RosterRow row, AppLocalizations l10n, String language, AppLayout layout) {
    final view = row.view;
    final absent = row.attended == 'No';
    final uuid = row.registration.uuid;
    final wide = layout.width.atLeastMedium;
    final name = InkWell(
      onTap: () => context.push(Routes.profile(uuid)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(view.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text([view.motherName, view.birthday].whereType<String>().join(' · '),
            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      ]),
    );
    return Card(
      key: ValueKey('att-row-$uuid'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              // Bounded at medium, and the toggle sits right after it rather
              // than at the far edge of a 776 px card: the control a teacher
              // taps 25 times stays within arm's reach of the name it marks.
              // At compact the name keeps today's unbounded Expanded.
              if (wide) ...[
                Flexible(child: SizedBox(width: 360, child: name)),
                const SizedBox(width: 16),
              ] else
                Expanded(child: name),
              _toggle(row, l10n, icons: !wide),
            ]),
            if (absent) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('att-reason-$uuid'),
                // ignore: deprecated_member_use
                value: _absenceReasons.any((c) => c.value == row.absenceReason && c.value.isNotEmpty) ? row.absenceReason : null,
                decoration: InputDecoration(labelText: l10n.absenceReason),
                items: _absenceReasons
                    .where((c) => c.value.isNotEmpty)
                    .map((c) => DropdownMenuItem(value: c.value, child: Text(c.labelFor(language))))
                    .toList(),
                onChanged: (v) => setState(() => row.absenceReason = v ?? ''),
              ),
              if (row.absenceReason == 'Other')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextFormField(
                    initialValue: row.absenceReasonOther,
                    decoration: InputDecoration(labelText: l10n.absenceReasonOther),
                    onChanged: (v) => row.absenceReasonOther = v,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- expanded

  /// Fixed 360 px pane: everything that describes the SESSION, and nothing
  /// that belongs to a child. It does not scroll in the normal case — the
  /// content is sized to fit 800 px minus the app bar — but it is wrapped in a
  /// scroll view so a 1.3x Arabic text scale degrades to scrolling rather than
  /// to a RenderFlex overflow. Save stays pinned below that scroll view.
  Widget _sessionPane(BuildContext context, AppLocalizations l10n, String language, String scope) {
    final rows = _rows;
    return Padding(
      key: const ValueKey('att-session-pane'),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Expanded, not Flexible: a loose Flexible lets the scroll view
          // shrink-wrap its content, which floats Save up under the tally
          // instead of pinning it to the bottom edge of the pane.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(bottom: 4),
                    child: Text(l10n.sessionLabel,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.muted)),
                  ),
                  _centerOrSchoolField(l10n, language, scope, readOnly: true),
                  const SizedBox(height: 8),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: _roundField(l10n, language, wide: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _dateField(l10n)),
                  ]),
                  const SizedBox(height: 8),
                  for (final field in _programmeFields(l10n, language, wide: true))
                    Padding(padding: const EdgeInsetsDirectional.only(bottom: 8), child: field),
                  FilledButton.icon(
                    key: const ValueKey('att-load'),
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.download_done),
                    label: Text(l10n.loadChildren),
                  ),
                  if (_loading)
                    const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                  if (rows != null) ...[
                    const SizedBox(height: 4),
                    SwitchListTile(
                      key: const ValueKey('att-dayoff'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.dayOff),
                      value: _selection.dayOff,
                      onChanged: (v) =>
                          setState(() => _selection = _selection.copyWith(dayOff: v, closeReason: v ? _selection.closeReason : '')),
                    ),
                    if (_selection.dayOff)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(bottom: 8),
                        child: _closeReasonField(l10n, language, wide: true),
                      ),
                    if (!_selection.dayOff) _tally(rows, l10n),
                    if (_existing != null) ...[
                      const SizedBox(height: 8),
                      SyncStateChip(_existing!.syncState),
                      if (_existing!.serverMessage != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(top: 6),
                          child: Text(_existing!.serverMessage!, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (rows != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(0, 10, 0, 12),
                child: FilledButton.icon(
                  key: const ValueKey('att-save'),
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save),
                  label: Text(l10n.save),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Present / absent / not marked, read across a desk.
  Widget _tally(List<RosterRow> rows, AppLocalizations l10n) {
    final present = rows.where((r) => r.attended == 'Yes').length;
    final absent = rows.where((r) => r.attended == 'No').length;
    final notMarked = rows.length - present - absent;
    return Padding(
      key: const ValueKey('att-tally'),
      padding: const EdgeInsetsDirectional.only(top: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          StatusPill(label: '$present ${l10n.present}', color: AppColors.success, large: true),
          StatusPill(label: '$absent ${l10n.absent}', color: AppColors.danger, large: true),
          StatusPill(label: '$notMarked ${l10n.notMarked}', color: AppColors.muted, large: true),
        ],
      ),
    );
  }

  /// The roster as a table: one shared column spec, a sticky tonal header and
  /// zebra-striped 60 px rows instead of one [Card] per child.
  Widget _rosterPane(BuildContext context, AppLocalizations l10n, String language) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final rows = _rows;
    if (rows == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TipCard(id: TipIds.attendanceFlow, text: l10n.tipAttendanceFlow),
          const SizedBox(height: 8),
          EmptyState(message: l10n.selectionIncomplete, icon: Icons.fact_check_outlined),
        ],
      );
    }
    if (_selection.dayOff) return EmptyState(message: l10n.dayOff, icon: Icons.event_busy);
    if (rows.isEmpty) return EmptyState(message: l10n.noChildrenForSelection, icon: Icons.person_off_outlined);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth - 24, l10n);
        return Column(
          key: const ValueKey('att-roster'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
              child: Row(children: [
                Text(l10n.items(rows.length), style: const TextStyle(color: AppColors.muted)),
                const Spacer(),
                TextButton.icon(
                  key: const ValueKey('att-mark-all'),
                  icon: const Icon(Icons.done_all),
                  label: Text(l10n.markAllPresent),
                  onPressed: _markAllPresent,
                ),
              ]),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surfaceAlt,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
                child: _rosterLine(
                  columns,
                  (column) => Text(
                    column.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) => _rosterRow(rows[index], index, columns, l10n, language),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Drops optional columns rather than squeezing the name to nothing: with a
  /// navigation rail and the session pane, this table is handed ~700 px, not
  /// 1280. Mother and birth date are the two that go.
  List<_RosterColumn> _columnsFor(double available, AppLocalizations l10n) {
    const nameMin = 180.0;
    const motherMin = 120.0;
    // 200 holds two 88 px segments with slack at a 1.3x Arabic text scale;
    // 240 holds 'Absence reason' and the longest reason label.
    final attendance = _RosterColumn(id: 'attendance', label: l10n.colAttendance, width: 200);
    final reason = _RosterColumn(id: 'reason', label: l10n.colReason, width: 240);
    final dob = _RosterColumn(id: 'dob', label: l10n.colBirthday, width: 110);
    final mother = _RosterColumn(id: 'mother', label: l10n.colMother, flex: 2);
    final name = _RosterColumn(id: 'name', label: l10n.colName, flex: 3);
    final columns = <_RosterColumn>[name, attendance, reason];
    // 3 columns -> 2 gaps, and one more gap for each optional column added.
    var fixed = attendance.width! + reason.width! + _cellGap * 2;
    if (available - fixed - dob.width! - _cellGap >= nameMin) {
      fixed += dob.width! + _cellGap;
      columns.insert(1, dob);
    }
    if (available - fixed - motherMin - _cellGap >= nameMin) {
      columns.insert(1, mother);
    }
    return columns;
  }

  /// Lays [cells] out against the shared column spec. Used by the header and
  /// by every body row, which is what keeps them aligned.
  Widget _rosterLine(List<_RosterColumn> columns, Widget Function(_RosterColumn column) cell) {
    final children = <Widget>[];
    for (var i = 0; i < columns.length; i++) {
      if (i > 0) children.add(const SizedBox(width: _cellGap));
      final column = columns[i];
      children.add(column.width != null
          ? SizedBox(width: column.width, child: cell(column))
          : Expanded(flex: column.flex, child: cell(column)));
    }
    return Row(children: children);
  }

  Widget _rosterRow(RosterRow row, int index, List<_RosterColumn> columns, AppLocalizations l10n, String language) {
    final view = row.view;
    final absent = row.attended == 'No';
    final other = absent && row.absenceReason == 'Other';
    final uuid = row.registration.uuid;
    return Container(
      key: ValueKey('att-row-$uuid'),
      // The reason column is ALWAYS rendered, so marking a child absent cannot
      // move the rows below the operator's finger. Only the free-text 'Other'
      // case grows the row, and it grows INSIDE the row.
      constraints: BoxConstraints(minHeight: other ? _rowHeightOther : _rowHeight),
      decoration: BoxDecoration(
        color: index.isOdd ? AppColors.surfaceAlt : null,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 0),
      child: _rosterLine(columns, (column) {
        switch (column.id) {
          case 'name':
            return InkWell(
              onTap: () => context.push(Routes.profile(uuid)),
              child: Text(view.fullName,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            );
          case 'mother':
            return Text(view.motherName ?? '',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted));
          case 'dob':
            return Text(view.birthday ?? '',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted));
          case 'attendance':
            return Align(
              alignment: AlignmentDirectional.centerStart,
              child: _toggle(row, l10n, icons: false, segmentHeight: _rowHeight),
            );
          default:
            return _reasonCell(row, l10n, language, enabled: absent, other: other);
        }
      }),
    );
  }

  /// Always present, disabled and empty until the child is marked absent.
  Widget _reasonCell(RosterRow row, AppLocalizations l10n, String language,
      {required bool enabled, required bool other}) {
    final options = _absenceReasons.where((c) => c.value.isNotEmpty).toList();
    final value = options.any((c) => c.value == row.absenceReason) ? row.absenceReason : null;
    final field = Container(
      height: 40,
      padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 6, 0),
      decoration: BoxDecoration(
        color: enabled ? AppColors.surface : null,
        border: Border.all(color: enabled ? AppColors.border : AppColors.border.withValues(alpha: 0.5)),
        borderRadius: const BorderRadius.all(Radius.circular(8)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: ValueKey('att-reason-${row.registration.uuid}'),
          value: enabled ? value : null,
          isExpanded: true,
          isDense: true,
          itemHeight: null,
          hint: Text(l10n.absenceReason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.muted.withValues(alpha: enabled ? 1 : 0.5), fontSize: 13)),
          items: options
              .map((c) => DropdownMenuItem(
                  value: c.value,
                  child: Text(c.labelFor(language), maxLines: 1, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: enabled ? (v) => setState(() => row.absenceReason = v ?? '') : null,
        ),
      ),
    );
    if (!other) return field;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        field,
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: TextFormField(
            initialValue: row.absenceReasonOther,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: l10n.absenceReasonOther,
              contentPadding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
            ),
            onChanged: (v) => row.absenceReasonOther = v,
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  /// Present / Absent. The check and close icons are dropped at tablet width:
  /// the success/danger tint already carries the meaning, and dropping them is
  /// what lets Arabic fit the attendance column at a 1.3x text scale.
  Widget _toggle(RosterRow row, AppLocalizations l10n, {required bool icons, double? segmentHeight}) {
    final absent = row.attended == 'No';
    return SegmentedButton<String>(
      key: ValueKey('att-toggle-${row.registration.uuid}'),
      segments: [
        ButtonSegment(value: 'Yes', label: Text(l10n.present), icon: icons ? const Icon(Icons.check) : null),
        ButtonSegment(value: 'No', label: Text(l10n.absent), icon: icons ? const Icon(Icons.close) : null),
      ],
      selected: {row.attended},
      showSelectedIcon: false,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected)
            ? (absent ? AppColors.danger.withValues(alpha: 0.15) : AppColors.success.withValues(alpha: 0.15))
            : null),
        // 60 px = 9.1 mm on this 168 px/inch panel: the tallest control in the
        // app, because it is the one tapped 25 times per class.
        minimumSize: segmentHeight == null ? null : WidgetStatePropertyAll(Size(88, segmentHeight)),
        padding: segmentHeight == null ? null : const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
      ),
      onSelectionChanged: (s) => setState(() => row.attended = s.first),
    );
  }

  // ------------------------------------------------------------------ fields

  Widget _filters(BuildContext context, String language, String scope, AppLayout layout) {
    final l10n = AppLocalizations.of(context);
    final cache = ref.read(referenceCacheProvider);
    final wide = layout.width.atLeastMedium;
    final children = <Widget>[
      _centerOrSchoolField(l10n, language, scope, readOnly: wide),
      _roundField(l10n, language, wide: wide),
      ..._programmeFields(l10n, language, wide: wide),
      _dateField(l10n),
    ];
    cache.ensure('centers');
    if (!wide) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [for (final c in children) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: c)]),
        ),
      );
    }
    // Two across: ~200 px of filter chrome instead of ~400, which is the
    // difference between seeing children on a portrait tablet and not.
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: children[i]),
          const SizedBox(width: 16),
          Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox.shrink()),
        ]),
      ));
    }
    return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: rows)));
  }

  Widget _centerOrSchoolField(AppLocalizations l10n, String language, String scope, {required bool readOnly}) {
    if (widget.module == BmaModule.mscc) {
      return _refTile(
        tileKey: const ValueKey('att-center'),
        label: l10n.selectCenter,
        kind: 'centers',
        value: _selection.centerId,
        language: language,
        enabled: scope != 'center',
        readOnly: readOnly,
        onPicked: (id) => setState(() => _selection = _selection.copyWith(centerId: id)),
      );
    }
    return _refTile(
      tileKey: const ValueKey('att-school'),
      label: l10n.selectSchool,
      kind: 'schools',
      value: _selection.schoolId,
      language: language,
      enabled: scope != 'school',
      readOnly: readOnly,
      onPicked: (id) => setState(() => _selection = _selection.copyWith(schoolId: id)),
    );
  }

  /// [wide] is the ONLY difference from today's field: `isExpanded` and the
  /// ellipsis are what keep a long label inside a half-width cell, and both
  /// are off at compact so the phone tree is unchanged.
  Widget _roundField(AppLocalizations l10n, String language, {required bool wide}) {
    return DropdownButtonFormField<int>(
      key: const ValueKey('att-round'),
      // ignore: deprecated_member_use
      value: _rounds.any((r) => r.id == _selection.roundId) ? _selection.roundId : null,
      isExpanded: wide,
      decoration: InputDecoration(labelText: l10n.selectRound),
      items: _rounds
          .map((r) => DropdownMenuItem(
              value: r.id, child: Text(r.labelFor(language), overflow: wide ? TextOverflow.ellipsis : null)))
          .toList(),
      onChanged: (v) {
        setState(() => _selection = _selection.copyWith(roundId: v));
        _resetRows();
      },
    );
  }

  List<Widget> _programmeFields(AppLocalizations l10n, String language, {required bool wide}) {
    switch (widget.module) {
      case BmaModule.mscc:
        return [
          _choiceDropdown(l10n.selectProgram, _programmes, _selection.programme, language,
              (v) => setState(() => _selection = _selection.copyWith(programme: v)),
              fieldKey: const ValueKey('att-programme')),
          _choiceDropdown(l10n.selectSection, _sections, _selection.section, language,
              (v) => setState(() => _selection = _selection.copyWith(section: v)),
              fieldKey: const ValueKey('att-section')),
        ];
      case BmaModule.alp:
        return [
          DropdownButtonFormField<String>(
            key: const ValueKey('att-programme'),
            // ignore: deprecated_member_use
            value: _alpProgrammes.any((p) => '${p.id}' == _selection.programme) ? _selection.programme : null,
            isExpanded: wide,
            decoration: InputDecoration(labelText: l10n.selectProgram),
            items: _alpProgrammes
                .map((p) => DropdownMenuItem(
                    value: '${p.id}', child: Text(p.labelFor(language), overflow: wide ? TextOverflow.ellipsis : null)))
                .toList(),
            onChanged: (v) {
              setState(() => _selection = _selection.copyWith(programme: v));
              _resetRows();
            },
          ),
        ];
      case BmaModule.clm:
        return [
          _choiceDropdown(l10n.selectProgram, _levels, _selection.registrationLevel, language,
              (v) => setState(() => _selection = _selection.copyWith(registrationLevel: v)),
              fieldKey: const ValueKey('att-level')),
        ];
    }
  }

  Widget _dateField(AppLocalizations l10n) {
    return InkWell(
      key: const ValueKey('att-date'),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.tryParse(_selection.date) ?? DateTime.now(),
          firstDate: DateTime(2015),
          lastDate: DateTime.now(),
        );
        if (picked != null) {
          setState(() => _selection = _selection.copyWith(date: _iso(picked)));
          _resetRows();
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: l10n.selectDate, suffixIcon: const Icon(Icons.calendar_today)),
        child: Text(_selection.date),
      ),
    );
  }

  Widget _refTile({
    required Key tileKey,
    required String label,
    required String kind,
    required int? value,
    required String language,
    required bool enabled,
    required ValueChanged<int> onPicked,
    bool readOnly = false,
  }) {
    final cache = ref.read(referenceCacheProvider);
    return FutureBuilder<Map<int, dynamic>>(
      key: tileKey,
      future: cache.ensure(kind),
      builder: (context, snapshot) {
        final name = value == null ? '' : (snapshot.data?[value]?.labelFor(language) ?? '#$value');
        // Scope-locked staff cannot change this: a disabled InputDecorator is
        // a control that does nothing, so at tablet width it becomes a fact.
        if (readOnly && !enabled) {
          return FactRow(label: label, value: name.isEmpty ? '—' : name, icon: Icons.place_outlined);
        }
        return InkWell(
          onTap: !enabled
              ? null
              : () async {
                  final result = await ReferencePickerSheet.show(context,
                      kind: kind, title: label, languageCode: language, selectedIds: {?value});
                  if (result is ReferenceItem) {
                    onPicked(result.id);
                    _resetRows();
                  }
                },
          child: InputDecorator(
            decoration: InputDecoration(labelText: label, suffixIcon: enabled ? const Icon(Icons.arrow_drop_down) : null),
            child: Text(name.isEmpty ? ' ' : name),
          ),
        );
      },
    );
  }

  Widget _choiceDropdown(String label, List<ChoiceRow> choices, String? value, String language, ValueChanged<String?> onChanged,
      {required Key fieldKey}) {
    final options = choices.where((c) => c.value.isNotEmpty).toList();
    return DropdownButtonFormField<String>(
      key: fieldKey,
      // ignore: deprecated_member_use
      value: options.any((c) => c.value == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options.map((c) => DropdownMenuItem(value: c.value, child: Text(c.labelFor(language), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) {
        onChanged(v);
        _resetRows();
      },
    );
  }

  Widget _closeReasonField(AppLocalizations l10n, String language, {required bool wide}) {
    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: _closeReasons.any((c) => c.value == _selection.closeReason) ? _selection.closeReason : null,
      isExpanded: wide,
      decoration: InputDecoration(labelText: l10n.closeReason),
      items: _closeReasons
          .where((c) => c.value.isNotEmpty)
          .map((c) => DropdownMenuItem(
              value: c.value, child: Text(c.labelFor(language), overflow: wide ? TextOverflow.ellipsis : null)))
          .toList(),
      onChanged: (v) => setState(() => _selection = _selection.copyWith(closeReason: v ?? '')),
    );
  }

  Widget _dayOffCard(AppLocalizations l10n, String language) {
    return Card(
      child: Column(children: [
        SwitchListTile(
          key: const ValueKey('att-dayoff'),
          title: Text(l10n.dayOff),
          value: _selection.dayOff,
          onChanged: (v) => setState(() => _selection = _selection.copyWith(dayOff: v, closeReason: v ? _selection.closeReason : '')),
        ),
        if (_selection.dayOff)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _closeReasonField(l10n, language, wide: false),
          ),
      ]),
    );
  }
}
