import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/models/entity_record.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';

/// ALP teacher attendance for one date (Present / Absent per teacher).
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final present = _status.values.where((s) => s == 'Present').length;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.teacherAttendance)),
      body: Column(
        children: [
          const OfflineBanner(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: InkWell(
              onTap: () async {
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
              },
              child: InputDecorator(
                decoration: InputDecoration(labelText: l10n.selectDate, suffixIcon: const Icon(Icons.calendar_today)),
                child: Text(_date),
              ),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_teachers.isEmpty)
            Expanded(child: EmptyState(message: l10n.noTeachers, icon: Icons.badge_outlined))
          else
            Expanded(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(l10n.teachersPresent(present), style: const TextStyle(color: AppColors.muted)),
                  ),
                  for (final t in _teachers)
                    ListTile(
                      title: Text(t.label),
                      trailing: SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'Present', label: Text(l10n.present)),
                          ButtonSegment(value: 'Absent', label: Text(l10n.absent)),
                        ],
                        selected: {_status[t.uuid] ?? 'Present'},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => setState(() => _status[t.uuid] = s.first),
                      ),
                    ),
                  if (_existing != null)
                    Padding(padding: const EdgeInsets.all(16), child: SyncStateChip(_existing!.syncState)),
                ],
              ),
            ),
          if (!_loading && _teachers.isNotEmpty)
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
}
