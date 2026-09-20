import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/layout/adaptive.dart';
import '../../core/layout/app_layout.dart';
import '../../core/models/entity_record.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../registrations/registration_helpers.dart';

enum _Action { merge, link, create, discard }

/// Lets the field worker decide what to do with a registration the server
/// flagged as a duplicate: merge, link (same child, new enrolment), create
/// anyway or discard. The decision is applied on the next push.
class DuplicateResolutionScreen extends ConsumerStatefulWidget {
  const DuplicateResolutionScreen({super.key, required this.uuid});

  final String uuid;

  @override
  ConsumerState<DuplicateResolutionScreen> createState() => _DuplicateResolutionScreenState();
}

class _DuplicateResolutionScreenState extends ConsumerState<DuplicateResolutionScreen> {
  _Action _action = _Action.merge;
  int _candidateIndex = 0;
  bool _overwrite = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final record = ref.watch(recordProvider(widget.uuid));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.resolveDuplicate)),
      body: record.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(message: e.toString()),
        data: (r) => r == null ? EmptyState(message: l10n.noResults) : _body(context, r),
      ),
    );
  }

  Widget _body(BuildContext context, EntityRecord record) {
    final l10n = AppLocalizations.of(context);
    final view = RegistrationView(record);
    final candidates = record.duplicates;
    final selected = candidates.isEmpty ? null : candidates[_candidateIndex.clamp(0, candidates.length - 1)];
    final canMerge = selected != null && selected['registration_id'] != null;
    final canLink = selected != null && selected['child_id'] != null;

    // The box this screen was handed, never the window: with a rail beside it
    // the comparison must fall back to the stack honestly.
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppLayout.forWidth(constraints.maxWidth);
        if (layout.twoPane) {
          // "Is my record the same person as theirs?" is a comparison, so the
          // decision side is fixed and the candidates scroll beside it — the
          // field worker never scrolls back up to re-read the local version.
          return LayoutScope(
            layout: layout,
            child: TwoPane(
              paneWidth: layout.listPaneWidth,
              pane: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        _explanation(l10n),
                        const SizedBox(height: 12),
                        _localCard(context, l10n, view),
                        const SizedBox(height: 12),
                        _actions(context, l10n, canMerge: canMerge, canLink: canLink),
                      ],
                    ),
                  ),
                  _footer(context, l10n, record, selected),
                ],
              ),
              detail: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
                    child: Text(l10n.chooseCandidate, style: Theme.of(context).textTheme.titleSmall),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: RadioGroup<int>(
                      groupValue: _candidateIndex,
                      onChanged: (v) => setState(() => _candidateIndex = v ?? _candidateIndex),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: candidates.length,
                        itemBuilder: (context, i) => _candidateCard(context, candidates[i], i),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final content = Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _explanation(l10n),
                  const SizedBox(height: 12),
                  _localCard(context, l10n, view),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(4, 12, 4, 4),
                    child: Text(l10n.chooseCandidate, style: Theme.of(context).textTheme.titleSmall),
                  ),
                  RadioGroup<int>(
                    groupValue: _candidateIndex,
                    onChanged: (v) => setState(() => _candidateIndex = v ?? _candidateIndex),
                    child: Column(children: [
                      for (var i = 0; i < candidates.length; i++) _candidateCard(context, candidates[i], i),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  _actions(context, l10n, canMerge: canMerge, canLink: canLink),
                ],
              ),
            ),
            _footer(context, l10n, record, selected),
          ],
        );
        // Compact is returned unwrapped: the phone tree gains nothing.
        return layout.width.atLeastMedium
            ? AdaptiveBody(maxWidth: layout.readingMaxWidth, child: content)
            : content;
      },
    );
  }

  Widget _explanation(AppLocalizations l10n) =>
      Text(l10n.duplicateExplanation, style: const TextStyle(color: AppColors.muted));

  Widget _localCard(BuildContext context, AppLocalizations l10n, RegistrationView view) => Card(
        key: const ValueKey('dup-local'),
        color: AppColors.secondary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.localVersion, style: Theme.of(context).textTheme.titleSmall),
            Text(view.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text([view.motherName, view.birthday, view.gender].whereType<String>().join(' · ')),
            Text(l10n.localOnlyHint, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
      );

  Widget _actions(BuildContext context, AppLocalizations l10n, {required bool canMerge, required bool canLink}) {
    return RadioGroup<_Action>(
      groupValue: _action,
      onChanged: (v) => setState(() => _action = v ?? _action),
      child: Column(children: [
        RadioListTile<_Action>(
          key: const ValueKey('dup-action-merge'),
          value: _Action.merge,
          enabled: canMerge,
          title: Text(l10n.mergeIntoExisting),
          subtitle: Text(l10n.mergeExplanation),
        ),
        if (_action == _Action.merge)
          Padding(
            // Directional: in Arabic this nested switch belongs under the
            // merge option on the RIGHT, not indented from the left edge.
            padding: const EdgeInsetsDirectional.only(start: 32),
            child: SwitchListTile(
              key: const ValueKey('dup-overwrite'),
              title: Text(l10n.overwriteServer),
              value: _overwrite,
              onChanged: (v) => setState(() => _overwrite = v),
            ),
          ),
        RadioListTile<_Action>(
          key: const ValueKey('dup-action-link'),
          value: _Action.link,
          enabled: canLink,
          title: Text(l10n.linkExistingChild),
          subtitle: Text(l10n.linkExplanation),
        ),
        RadioListTile<_Action>(
            key: const ValueKey('dup-action-create'), value: _Action.create, title: Text(l10n.createAnyway)),
        RadioListTile<_Action>(
            key: const ValueKey('dup-action-discard'), value: _Action.discard, title: Text(l10n.discardLocal)),
      ]),
    );
  }

  Widget _footer(
    BuildContext context,
    AppLocalizations l10n,
    EntityRecord record,
    Map<String, dynamic>? selected,
  ) =>
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 12),
          child: Row(children: [
            OutlinedButton(
                key: const ValueKey('dup-cancel'), onPressed: () => context.pop(), child: Text(l10n.cancel)),
            const Spacer(),
            FilledButton.icon(
              key: const ValueKey('dup-apply'),
              onPressed: () => _apply(context, record, selected),
              icon: const Icon(Icons.check),
              label: Text(l10n.apply),
            ),
          ]),
        ),
      );

  /// Stable per-candidate key. Server ids are unique within a response; the
  /// index is the fallback for a candidate the server sent without one.
  static String candidateKeyId(Map<String, dynamic> c, int index) =>
      (c['registration_id'] ?? c['child_id'] ?? index).toString();

  Widget _candidateCard(BuildContext context, Map<String, dynamic> c, int index) {
    final l10n = AppLocalizations.of(context);
    final match = c['match'] is Map ? Map<String, dynamic>.from(c['match'] as Map) : const <String, dynamic>{};
    final where = [c['center'], c['school'], c['partner'], c['round']].whereType<String>().join(' · ');
    return Card(
      key: ValueKey('dup-candidate-${candidateKeyId(c, index)}'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: index == _candidateIndex ? AppColors.primary : Colors.transparent, width: 2),
      ),
      child: ListTile(
        leading: Radio<int>(value: index),
        title: Text(c['label']?.toString() ?? ''),
        subtitle: Text([
          [c['mother_fullname'], c['birthday'], c['gender'], c['nationality']].whereType<Object>().join(' · '),
          if (where.isNotEmpty) where,
          if (c['number'] != null) '${l10n.childNumber}: ${c['number']}',
          l10n.matchReason('${match['reason'] ?? ''} ${match['score'] != null ? '(${match['score']})' : ''}'),
          if (c['registration_id'] != null) l10n.serverRecordId('${c['registration_id']}'),
        ].join('\n')),
        isThreeLine: true,
        onTap: () => setState(() => _candidateIndex = index),
      ),
    );
  }

  Future<void> _apply(BuildContext context, EntityRecord record, Map<String, dynamic>? selected) async {
    final l10n = AppLocalizations.of(context);
    final dao = ref.read(entityDaoProvider);
    final resolution = switch (_action) {
      _Action.merge => {'action': 'merge', 'target_id': selected?['registration_id'], 'overwrite': _overwrite},
      _Action.link => {'action': 'link', 'target_id': selected?['child_id']},
      _Action.create => {'action': 'create'},
      _Action.discard => {'action': 'discard', if (selected?['registration_id'] != null) 'target_id': selected!['registration_id']},
    };
    await dao.setResolution(record, resolution);
    bumpDataVersion(ref);
    await ref.read(syncEngineProvider.notifier).refreshCounts();
    if (!context.mounted) return;
    showMessage(context, l10n.resolvedLocally);
    context.pop();
  }
}
