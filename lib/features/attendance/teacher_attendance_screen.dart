import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/layout/app_layout.dart';
import '../../core/models/entity_record.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/app_localizations.dart';

/// ALP teacher attendance for one date (Present / Absent per teacher).
///
/// A school has 8–20 teachers, so at tablet width the right answer is not a
/// pane and not a longer list — it is NO SCROLLING: a grid of ~380 px cells
/// under one toolbar that holds the date, the tally, Mark all present and
/// Save. The phone keeps the full-width [ListTile] list and the bottom Save
/// bar, where `ListTile.trailing` pinning the toggle to the far edge is fine
/// because the far edge is 400 px away, not 1100.
class TeacherAttendanceScreen extends ConsumerStatefulWidget {
  const TeacherAttendanceScreen({super.key, required this.module});

  final BmaModule module;

  @override
  ConsumerState<TeacherAttendanceScreen> createState() => _TeacherAttendanceScreenState();
}

class _TeacherAttendanceScreenState extends ConsumerState<TeacherAttendanceScreen> {
  String _date = _iso(DateTime.now());
  List<EntityRecord> _teachers = const [];
  final Map<String, String> _status = {};
  EntityRecord? _existing;
  bool _loading = true;
  bool _saving = false;

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final dao = ref.read(entityDaoProvider);
    _teachers = await dao.list(RecordQuery(entity: Entities.teacherFor(widget.module), limit: 2000));
    _existing = await dao.byNaturalKey(Entities.alpTeacherAttendanceDay, _date);
    _status.clear();
    for (final t in _teachers) {
      _status[t.uuid] = 'Present';
    }
    if (_existing != null) {
      final rows = ((_existing!.data['teachers_attendance'] as List?) ?? const []).whereType<Map>();
      for (final row in rows) {
        for (final t in _teachers) {
          final matchesId = row['teacher_id'] != null && '${row['teacher_id']}' == '${t.serverId}';
          final matchesUuid = row['teacher_uuid'] == t.uuid;
          if (matchesId || matchesUuid) _status[t.uuid] = (row['status'] ?? 'Present').toString();
        }
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _saving = true);
    final dao = ref.read(entityDaoProvider);
    final data = {
      'attendance_date': _date,
      'teachers_attendance': [
        for (final t in _teachers)
          {
            if (t.serverId != null) 'teacher_id': t.serverId,
            if (t.serverId == null) 'teacher_uuid': t.uuid,
            'teacher_label': t.label,
            'status': _status[t.uuid] ?? 'Present',
          },
      ],
    };
    try {
      if (_existing != null) {
        _existing = await dao.updateLocal(_existing!, data);
      } else {
        _existing = await dao.createLocal(entity: Entities.alpTeacherAttendanceDay, data: data, naturalKey: _date);
      }
      bumpDataVersion(ref);
      await ref.read(syncEngineProvider.notifier).refreshCounts();
      if (mounted) showMessage(context, l10n.attendanceSaved);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _date = _iso(picked));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final present = _status.values.where((s) => s == 'Present').length;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.teacherAttendance)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final layout = AppLayout.forWidth(constraints.maxWidth);
          final wide = layout.width.atLeastMedium;
          return LayoutScope(
            layout: layout,
            child: Column(
              children: [
                const OfflineBanner(),
                if (wide) _toolbar(l10n, present) else _dateBand(l10n),
                if (_loading)
                  const Expanded(child: Center(child: CircularProgressIndicator()))
                else if (_teachers.isEmpty)
                  Expanded(child: EmptyState(message: l10n.noTeachers, icon: Icons.badge_outlined))
                else
                  Expanded(child: wide ? _grid(l10n) : _list(l10n, present)),
                if (!wide && !_loading && _teachers.isNotEmpty)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: FilledButton.icon(
                        key: const ValueKey('tatt-save'),
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

  /// Today's full-width date band (phone).
  Widget _dateBand(AppLocalizations l10n) => Padding(
        padding: const EdgeInsets.all(12),
        child: InkWell(
          key: const ValueKey('tatt-date'),
          onTap: _pickDate,
          child: InputDecorator(
            decoration: InputDecoration(labelText: l10n.selectDate, suffixIcon: const Icon(Icons.calendar_today)),
            child: Text(_date),
          ),
        ),
      );

  /// Date, tally, Mark all present and Save in one band, so the grid below
  /// gets the whole remaining height and never has to scroll.
  Widget _toolbar(AppLocalizations l10n, int present) {
    final absent = _teachers.length - present;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.start,
        children: [
          SizedBox(
            width: 220,
            child: InkWell(
              key: const ValueKey('tatt-date'),
              onTap: _pickDate,
              child: InputDecorator(
                decoration: InputDecoration(labelText: l10n.selectDate, suffixIcon: const Icon(Icons.calendar_today)),
                child: Text(_date),
              ),
            ),
          ),
          if (_teachers.isNotEmpty) ...[
            StatusPill(label: '$present ${l10n.present}', color: AppColors.success, large: true),
            StatusPill(label: '$absent ${l10n.absent}', color: AppColors.danger, large: true),
            TextButton.icon(
              key: const ValueKey('tatt-mark-all'),
              icon: const Icon(Icons.done_all),
              label: Text(l10n.markAllPresent),
              onPressed: () => setState(() {
                for (final t in _teachers) {
                  _status[t.uuid] = 'Present';
                }
              }),
            ),
            FilledButton.icon(
              key: const ValueKey('tatt-save'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: Text(l10n.save),
            ),
          ],
          if (_existing != null) SyncStateChip(_existing!.syncState),
        ],
      ),
    );
  }

  /// Today's phone list, unchanged apart from the row keys.
  Widget _list(AppLocalizations l10n, int present) => ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(l10n.teachersPresent(present), style: const TextStyle(color: AppColors.muted)),
          ),
          for (final t in _teachers)
            ListTile(
              key: ValueKey('tatt-row-${t.uuid}'),
              title: Text(t.label),
              trailing: _toggle(t, l10n),
            ),
          if (_existing != null) Padding(padding: const EdgeInsets.all(16), child: SyncStateChip(_existing!.syncState)),
        ],
      );

  /// 3 across at 1280, 2 at 800: every toggle stays beside the name it
  /// belongs to instead of being pinned ~1100 px away by [ListTile.trailing].
  Widget _grid(AppLocalizations l10n) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 400,
          mainAxisExtent: 96,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _teachers.length,
        itemBuilder: (context, index) {
          final t = _teachers[index];
          final assignment = [
            t.data['teacher_assignment'],
            t.data['center_label'] ?? t.data['school_label'],
          ].where((e) => e != null && e.toString().isNotEmpty).join(' · ');
          return Container(
            key: ValueKey('tatt-row-${t.uuid}'),
            padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: const BorderRadius.all(Radius.circular(AppRadius.card)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (assignment.isNotEmpty)
                        Text(assignment,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _toggle(t, l10n, compact: true),
              ],
            ),
          );
        },
      );

  Widget _toggle(EntityRecord t, AppLocalizations l10n, {bool compact = false}) => SegmentedButton<String>(
        segments: [
          ButtonSegment(value: 'Present', label: Text(l10n.present)),
          ButtonSegment(value: 'Absent', label: Text(l10n.absent)),
        ],
        selected: {_status[t.uuid] ?? 'Present'},
        showSelectedIcon: false,
        style: compact
            ? const ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 8)),
              )
            : null,
        onSelectionChanged: (s) => setState(() => _status[t.uuid] = s.first),
      );
}
