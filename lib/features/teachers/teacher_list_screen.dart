import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/models/entity_record.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';

class TeacherListScreen extends ConsumerStatefulWidget {
  const TeacherListScreen({super.key, required this.module});

  final BmaModule module;

  @override
  ConsumerState<TeacherListScreen> createState() => _TeacherListScreenState();
}

class _TeacherListScreenState extends ConsumerState<TeacherListScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.watch(dataVersionProvider);
    final profile = ref.watch(currentProfileProvider);
    final canManage = profile?.capabilities(widget.module).canManageTeachers ?? false;
    final future = ref.read(entityDaoProvider).list(RecordQuery(entity: Entities.teacherFor(widget.module), search: _search, limit: 500));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.teachers)),
      floatingActionButton: canManage
          ? FloatingActionButton(
              onPressed: () => context.push(Routes.newTeacher(widget.module)),
              child: const Icon(Icons.add),
            )
          : null,
      body: Column(
        children: [
          SearchField(onChanged: (v) => setState(() => _search = v)),
          Expanded(
            child: FutureBuilder<List<EntityRecord>>(
              future: future,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final teachers = snapshot.data!;
                if (teachers.isEmpty) return EmptyState(message: l10n.noTeachers, icon: Icons.badge_outlined);
                return ListView.separated(
                  itemCount: teachers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final t = teachers[index];
                    final subtitle = [
                      t.data['primary_phone_number'] ?? t.data['phone_number'],
                      t.data['teacher_assignment'],
                      t.data['center_label'] ?? t.data['school_label'],
                    ].where((e) => e != null && e.toString().isNotEmpty).join(' · ');
                    return ListTile(
                      leading: const Icon(Icons.badge),
                      title: Text(t.label),
                      subtitle: Text(subtitle),
                      trailing: SyncStateChip(t.syncState, compact: true),
                      onTap: canManage ? () => context.push(Routes.editTeacher(t.uuid)) : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
