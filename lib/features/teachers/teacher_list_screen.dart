import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/layout/app_layout.dart';
import '../../core/models/entity_record.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/ui.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';

/// The teacher roster. Deliberately NOT a two-pane screen: TeacherFormScreen's
/// Cancel and Save both `context.pop()`, and embedding it would mean rewriting
/// that contract for a list edited twice a week. It gains a card grid instead.
class TeacherListScreen extends ConsumerStatefulWidget {
  const TeacherListScreen({super.key, required this.module});

  final BmaModule module;

  @override
  ConsumerState<TeacherListScreen> createState() => _TeacherListScreenState();
}

class _TeacherListScreenState extends ConsumerState<TeacherListScreen> {
  String _search = '';

  // Memoised on (entity, search, dataVersion): a 500-row query no longer runs
  // once per build.
  Future<List<EntityRecord>>? _future;
  String? _queryKey;

  Future<List<EntityRecord>> _teachers(int dataVersion) {
    final entity = Entities.teacherFor(widget.module);
    final key = '$entity|$_search|$dataVersion';
    if (_future == null || key != _queryKey) {
      _queryKey = key;
      _future = ref.read(entityDaoProvider).list(RecordQuery(entity: entity, search: _search, limit: 500));
    }
    return _future!;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dataVersion = ref.watch(dataVersionProvider);
    final profile = ref.watch(currentProfileProvider);
    final canManage = profile?.capabilities(widget.module).canManageTeachers ?? false;
    final future = _teachers(dataVersion);

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppLayout.forWidth(constraints.maxWidth);
        final wide = layout.width.atLeastMedium;
        final searchField = SearchField(
          key: const ValueKey('teachers-search'),
          onChanged: (v) => setState(() => _search = v),
        );

        return LayoutScope(
          layout: layout,
          child: Scaffold(
            appBar: AppBar(title: Text(l10n.teachers)),
            // The bare circular FAB is dropped at tablet width, where the
            // primary action is a labelled button in the toolbar instead.
            floatingActionButton: canManage && !wide
                ? FloatingActionButton(
                    key: const ValueKey('teachers-add'),
                    onPressed: () => context.push(Routes.newTeacher(widget.module)),
                    child: const Icon(Icons.add),
                  )
                : null,
            body: Column(
              children: [
                const OfflineBanner(),
                if (wide && canManage)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 12, 0),
                    child: Row(children: [
                      Expanded(child: searchField),
                      FilledButton.icon(
                        key: const ValueKey('teachers-add'),
                        icon: const Icon(Icons.add),
                        label: Text(l10n.teacherForm),
                        onPressed: () => context.push(Routes.newTeacher(widget.module)),
                      ),
                    ]),
                  )
                else
                  searchField,
                Expanded(
                  child: FutureBuilder<List<EntityRecord>>(
                    future: future,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final teachers = snapshot.data!;
                      if (teachers.isEmpty) return EmptyState(message: l10n.noTeachers, icon: Icons.badge_outlined);
                      if (!wide) {
                        return ListView.separated(
                          itemCount: teachers.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final t = teachers[index];
                            return ListTile(
                              key: ValueKey('teacher-card-${t.uuid}'),
                              leading: const Icon(Icons.badge),
                              title: Text(t.label),
                              subtitle: Text(_subtitle(t)),
                              trailing: SyncStateChip(t.syncState, compact: true),
                              onTap: canManage ? () => context.push(Routes.editTeacher(t.uuid)) : null,
                            );
                          },
                        );
                      }
                      // 3 across at 1280, 2 at 800, which is what the spec
                      // asks for. Its literal 380 would have given FOUR at
                      // 1280: the grid gets 1280 - 2 x 32 of gutter = 1216 px,
                      // and 1216 / 380 rounds up to 4. Any cap in (406, 608]
                      // gives 3 there and 2 at 800; 440 sits in the middle and
                      // still gives 3 once the navigation rail takes its 212.
                      // The extent grows with the text scale so an Arabic 1.3x
                      // card cannot overflow.
                      final scaler = MediaQuery.textScalerOf(context);
                      return GridView.builder(
                        padding: EdgeInsets.all(layout.gutter),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 440,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 60 + scaler.scale(62),
                        ),
                        itemCount: teachers.length,
                        itemBuilder: (context, index) => _TeacherCard(
                          key: ValueKey('teacher-card-${teachers[index].uuid}'),
                          record: teachers[index],
                          subtitle: _subtitle(teachers[index]),
                          onTap: canManage ? () => context.push(Routes.editTeacher(teachers[index].uuid)) : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _subtitle(EntityRecord t) => [
        t.data['primary_phone_number'] ?? t.data['phone_number'],
        t.data['teacher_assignment'],
        t.data['center_label'] ?? t.data['school_label'],
      ].where((e) => e != null && e.toString().isNotEmpty).join(' · ');
}

class _TeacherCard extends StatelessWidget {
  const _TeacherCard({super.key, required this.record, required this.subtitle, this.onTap});

  final EntityRecord record;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(record.label),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.label,
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
                    const Spacer(),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SyncStateChip(record.syncState),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
