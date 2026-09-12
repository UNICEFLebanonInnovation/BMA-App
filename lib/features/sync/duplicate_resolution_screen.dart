import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
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
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(l10n.duplicateExplanation, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              Card(
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
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
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
              RadioGroup<_Action>(
                groupValue: _action,
                onChanged: (v) => setState(() => _action = v ?? _action),
                child: Column(children: [
                  RadioListTile<_Action>(
                    value: _Action.merge,
                    enabled: canMerge,
                    title: Text(l10n.mergeIntoExisting),
                    subtitle: Text(l10n.mergeExplanation),
                  ),
                  if (_action == _Action.merge)
                    Padding(
                      padding: const EdgeInsets.only(left: 32),
                      child: SwitchListTile(
                        title: Text(l10n.overwriteServer),
                        value: _overwrite,
                        onChanged: (v) => setState(() => _overwrite = v),
                      ),
                    ),
                  RadioListTile<_Action>(
                    value: _Action.link,
                    enabled: canLink,
                    title: Text(l10n.linkExistingChild),
                    subtitle: Text(l10n.linkExplanation),
                  ),
                  RadioListTile<_Action>(value: _Action.create, title: Text(l10n.createAnyway)),
                  RadioListTile<_Action>(value: _Action.discard, title: Text(l10n.discardLocal)),
                ]),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(children: [
              OutlinedButton(onPressed: () => context.pop(), child: Text(l10n.cancel)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _apply(context, record, selected),
                icon: const Icon(Icons.check),
                label: Text(l10n.apply),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _candidateCard(BuildContext context, Map<String, dynamic> c, int index) {
    final l10n = AppLocalizations.of(context);
    final match = c['match'] is Map ? Map<String, dynamic>.from(c['match'] as Map) : const <String, dynamic>{};
    final where = [c['center'], c['school'], c['partner'], c['round']].whereType<String>().join(' · ');
    return Card(
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
