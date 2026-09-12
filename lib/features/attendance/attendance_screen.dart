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
import '../../core/models/entity_record.dart';
import '../../core/models/reference_item.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import 'attendance_roster.dart';

/// Daily attendance sheet for a centre (MSCC), school programme (ALP) or
/// bridging level (CLM), saved offline as an idempotent document.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key, required this.module});

  final BmaModule module;

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    final profile = ref.watch(currentProfileProvider);
    final scope = profile?.capabilities(widget.module).scope ?? 'none';
    return Scaffold(
      appBar: AppBar(title: Text(l10n.attendance)),
      body: Column(
        children: [
          const OfflineBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _filters(context, language, scope),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
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
                            icon: const Icon(Icons.done_all),
                            label: Text(l10n.markAllPresent),
                            onPressed: () => setState(() {
                              for (final r in _rows!) {
                                r.attended = 'Yes';
                              }
                            }),
                          ),
                        ]),
                      ),
                      for (final row in _rows!) _rowCard(row, l10n, language),
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
            ),
          ),
          if (_rows != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: FilledButton.icon(
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

  Widget _filters(BuildContext context, String language, String scope) {
    final l10n = AppLocalizations.of(context);
    final cache = ref.read(referenceCacheProvider);
    final children = <Widget>[];

    if (widget.module == BmaModule.mscc) {
      children.add(_refTile(
        label: l10n.selectCenter,
        kind: 'centers',
        value: _selection.centerId,
        language: language,
        enabled: scope != 'center',
        onPicked: (id) => setState(() => _selection = _selection.copyWith(centerId: id)),
      ));
    } else {
      children.add(_refTile(
        label: l10n.selectSchool,
        kind: 'schools',
        value: _selection.schoolId,
        language: language,
        enabled: scope != 'school',
        onPicked: (id) => setState(() => _selection = _selection.copyWith(schoolId: id)),
      ));
    }
    children.add(DropdownButtonFormField<int>(
      // ignore: deprecated_member_use
      value: _rounds.any((r) => r.id == _selection.roundId) ? _selection.roundId : null,
      decoration: InputDecoration(labelText: l10n.selectRound),
      items: _rounds.map((r) => DropdownMenuItem(value: r.id, child: Text(r.labelFor(language)))).toList(),
      onChanged: (v) {
        setState(() => _selection = _selection.copyWith(roundId: v));
        _resetRows();
      },
    ));
    switch (widget.module) {
      case BmaModule.mscc:
        children.add(_choiceDropdown(l10n.selectProgram, _programmes, _selection.programme, language,
            (v) => setState(() => _selection = _selection.copyWith(programme: v))));
        children.add(_choiceDropdown(l10n.selectSection, _sections, _selection.section, language,
            (v) => setState(() => _selection = _selection.copyWith(section: v))));
        break;
      case BmaModule.alp:
        children.add(DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: _alpProgrammes.any((p) => '${p.id}' == _selection.programme) ? _selection.programme : null,
          decoration: InputDecoration(labelText: l10n.selectProgram),
          items: _alpProgrammes.map((p) => DropdownMenuItem(value: '${p.id}', child: Text(p.labelFor(language)))).toList(),
          onChanged: (v) {
            setState(() => _selection = _selection.copyWith(programme: v));
            _resetRows();
          },
        ));
        break;
      case BmaModule.clm:
        children.add(_choiceDropdown(l10n.selectProgram, _levels, _selection.registrationLevel, language,
            (v) => setState(() => _selection = _selection.copyWith(registrationLevel: v))));
        break;
    }
    children.add(InkWell(
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
    ));
    cache.ensure('centers');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [for (final c in children) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: c)]),
      ),
    );
  }

  Widget _refTile({
    required String label,
    required String kind,
    required int? value,
    required String language,
    required bool enabled,
    required ValueChanged<int> onPicked,
  }) {
    final cache = ref.read(referenceCacheProvider);
    return FutureBuilder<Map<int, dynamic>>(
      future: cache.ensure(kind),
      builder: (context, snapshot) {
        final name = value == null ? '' : (snapshot.data?[value]?.labelFor(language) ?? '#$value');
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

  Widget _choiceDropdown(String label, List<ChoiceRow> choices, String? value, String language, ValueChanged<String?> onChanged) {
    final options = choices.where((c) => c.value.isNotEmpty).toList();
    return DropdownButtonFormField<String>(
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

  Widget _dayOffCard(AppLocalizations l10n, String language) {
    return Card(
      child: Column(children: [
        SwitchListTile(
          title: Text(l10n.dayOff),
          value: _selection.dayOff,
          onChanged: (v) => setState(() => _selection = _selection.copyWith(dayOff: v, closeReason: v ? _selection.closeReason : '')),
        ),
        if (_selection.dayOff)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _closeReasons.any((c) => c.value == _selection.closeReason) ? _selection.closeReason : null,
              decoration: InputDecoration(labelText: l10n.closeReason),
              items: _closeReasons
                  .where((c) => c.value.isNotEmpty)
                  .map((c) => DropdownMenuItem(value: c.value, child: Text(c.labelFor(language))))
                  .toList(),
              onChanged: (v) => setState(() => _selection = _selection.copyWith(closeReason: v ?? '')),
            ),
          ),
      ]),
    );
  }

  Widget _rowCard(RosterRow row, AppLocalizations l10n, String language) {
    final view = row.view;
    final absent = row.attended == 'No';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () => context.push(Routes.profile(row.registration.uuid)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(view.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text([view.motherName, view.birthday].whereType<String>().join(' · '),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ]),
                ),
              ),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'Yes', label: Text(l10n.present), icon: const Icon(Icons.check)),
                  ButtonSegment(value: 'No', label: Text(l10n.absent), icon: const Icon(Icons.close)),
                ],
                selected: {row.attended},
                showSelectedIcon: false,
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.selected)
                      ? (absent ? AppColors.danger.withValues(alpha: 0.15) : AppColors.success.withValues(alpha: 0.15))
                      : null),
                ),
                onSelectionChanged: (s) => setState(() => row.attended = s.first),
              ),
            ]),
            if (absent) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
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
}
