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
import '../../core/forms/validation_messages.dart';
import '../../core/forms/schema_form_controller.dart';
import '../../core/layout/adaptive.dart';
import '../../core/layout/app_layout.dart';
import '../../core/layout/current_module.dart';
import '../../core/models/entity_record.dart';
import '../../core/models/form_schema.dart';
import '../../core/network/bma_api.dart';
import '../../core/sync/connectivity_service.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../../router.dart';
import 'registration_helpers.dart';

/// Multi-step registration form (identity → caregivers → … → review), driven
/// by the schema of the module's registration entity.
class RegistrationWizardScreen extends ConsumerStatefulWidget {
  const RegistrationWizardScreen({super.key, this.module, this.editUuid});

  final BmaModule? module;
  final String? editUuid;

  @override
  ConsumerState<RegistrationWizardScreen> createState() => _RegistrationWizardScreenState();
}

class _RegistrationWizardScreenState extends ConsumerState<RegistrationWizardScreen> {
  SchemaFormController? _controller;
  UnsavedWorkWatch? _unsaved;
  EntitySchema? _schema;
  EntityRecord? _editing;
  int _step = 0;

  /// Highest step reached in this session. LAYOUT ONLY: it drives the step
  /// rail's completed ticks. The flow itself is unchanged — `_next()` is still
  /// the only way forward, so the per-section validate() and the step-0
  /// duplicate check keep their exact timing.
  int _maxVisited = 0;
  bool _saving = false;
  List<EntityRecord> _localDuplicates = const [];
  List<Map<String, dynamic>> _serverDuplicates = const [];
  String? _loadError;
  final _scroll = ScrollController();

  String get _entity => _editing?.entity ?? Entities.registrationFor(widget.module ?? BmaModule.mscc);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final l10n = AppLocalizations.of(context);
    // Captured before the first await: the watcher below is created after
    // several of them, and the container outlives this element anyway.
    final container = ProviderScope.containerOf(context, listen: false);
    final dao = ref.read(entityDaoProvider);
    if (widget.editUuid != null) {
      _editing = await dao.byUuid(widget.editUuid!);
    }
    final schema = await ref.read(schemaProvider(_entity).future);
    if (schema == null) {
      setState(() => _loadError = l10n.bootstrapRequired);
      return;
    }
    Map<String, dynamic> initial = {};
    if (_editing != null) {
      initial = SyncEngine.flattenIdentityPayload(_editing!.entity, Map.of(_editing!.data));
      initial.removeWhere((k, v) => v == null);
      // Server-side "_id" twins are not form fields.
      initial.removeWhere((k, _) => k == 'child_id' || k == 'student_id');
    } else {
      initial = _defaults(schema);
    }
    final cache = ref.read(referenceCacheProvider);
    final language = ref.read(settingsControllerProvider).locale.languageCode;
    // Warms reference lists AND shared choice lists, so the validator can
    // answer "is this one of the options?" synchronously while the worker types.
    await cache.warmFor(schema);
    setState(() {
      _schema = schema;
      _controller = SchemaFormController(
        schema: schema,
        initial: initial,
        serverErrors: _editing?.lastError,
        labelResolver: (field, value) {
          if (!field.isReference || field.ref == null) return null;
          final id = value is int ? value : int.tryParse(value?.toString() ?? '');
          return cache.cached(field.ref!, id)?.labelFor(language);
        },
        allowedValues: allowedValuesFrom(cache),
        messages: validationMessages(l10n, language),
      );
    });
    // A rail tap is a `push`/`replace`, and NEITHER triggers PopScope — so the
    // guard that defends this form against the back gesture cannot defend it
    // against the rail. Publish the dirty state instead and let
    // goDestination() ask before it navigates.
    _unsaved = UnsavedWorkWatch(
      container: container,
      controller: _controller!,
      message: l10n.unsavedChanges,
    );
  }

  @override
  void dispose() {
    _unsaved?.dispose();
    super.dispose();
  }

  Map<String, dynamic> _defaults(EntitySchema schema) {
    final profile = ref.read(currentProfileProvider);
    final values = <String, dynamic>{};
    if (schema.key == Entities.alpRegistration && profile?.school != null) {
      values['school'] = profile!.school!.id;
    }
    if (schema.key == Entities.clmBridging) {
      if (profile?.school != null) values['school'] = profile!.school!.id;
    }
    final today = DateTime.now();
    final iso = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    if (schema.field('registration_date') != null) values['registration_date'] = iso;
    return values;
  }

  List<String> get _stepSections => _schema!.sections.map((s) => s.key).toList();

  int get _stepCount => _stepSections.length + 1;

  bool get _isReview => _step == _stepSections.length;

  Future<void> _next() async {
    final controller = _controller!;
    final section = _schema!.sections[_step];
    if (!controller.validate(fields: section.fields)) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      return;
    }
    if (_step == 0 && _editing == null) {
      await _checkDuplicates();
      if (!mounted) return;
      if (_localDuplicates.isNotEmpty || _serverDuplicates.isNotEmpty) {
        final proceed = await _confirmDuplicates();
        if (!proceed) return;
      }
    }
    setState(() {
      _step++;
      if (_step > _maxVisited) _maxVisited = _step;
    });
    _scroll.jumpTo(0);
  }

  Future<void> _checkDuplicates() async {
    final dao = ref.read(entityDaoProvider);
    final values = _controller!.values;
    _localDuplicates = await dao.findLocalDuplicates(_entity, values);
    _serverDuplicates = const [];
    if (ref.read(isOnlineProvider)) {
      try {
        _serverDuplicates = await ref
            .read(bmaApiProvider)
            .duplicateCheck(_entity, values)
            .timeout(const Duration(seconds: 12));
      } catch (_) {
        // Offline or slow network: the server verifies again at push time.
      }
    }
  }

  Future<bool> _confirmDuplicates() async {
    final l10n = AppLocalizations.of(context);
    // 420 on a phone (today's literal), growing to at most 560 on a tablet.
    // The lower clamp matters: a bare `width * 0.5` would SHRINK the dialog to
    // ~206 px at 412.
    final dialogWidth = math.min(560.0, math.max(420.0, MediaQuery.sizeOf(context).width * 0.5));
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.possibleDuplicates),
        content: SizedBox(
          width: dialogWidth,
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(l10n.possibleDuplicatesHint),
              const SizedBox(height: 8),
              for (final r in _localDuplicates)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.phone_android),
                  title: Text(RegistrationView(r).fullName),
                  subtitle: Text(RegistrationView(r).birthday ?? ''),
                ),
              for (final d in _serverDuplicates)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.cloud),
                  title: Text(d['label']?.toString() ?? ''),
                  subtitle: Text([d['birthday'], d['center'] ?? d['school'], d['match']?['reason']]
                      .whereType<Object>()
                      .join(' · ')),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.next)),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final controller = _controller!;
    if (!controller.validate()) {
      // Jump to the first section with an error.
      for (var i = 0; i < _schema!.sections.length; i++) {
        if (_schema!.sections[i].fields.any(controller.errors.containsKey)) {
          setState(() => _step = i);
          break;
        }
      }
      return;
    }
    setState(() => _saving = true);
    final dao = ref.read(entityDaoProvider);
    final values = controller.collect();
    try {
      EntityRecord record;
      if (_editing != null) {
        // Keep the nested server data that the form does not manage
        // (ids, generated numbers) by storing the edited flat values on top.
        final merged = _mergeEdit(_editing!, values);
        record = await dao.updateLocal(_editing!, merged);
      } else {
        record = await dao.createLocal(entity: _entity, data: values);
      }
      bumpDataVersion(ref);
      await ref.read(syncEngineProvider.notifier).refreshCounts();
      if (!mounted) return;
      _unsaved?.clear();
      showMessage(context, l10n.saveDraft);
      context.pushReplacement(Routes.profile(record.uuid));
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// For edits the local copy becomes flat form values plus the identifiers
  /// the server needs (`child_id`) so that the push updates the same child.
  Map<String, dynamic> _mergeEdit(EntityRecord existing, Map<String, dynamic> values) {
    final view = RegistrationView(existing);
    final merged = Map<String, dynamic>.from(values);
    final personId = view.personServerId;
    if (personId != null) {
      merged[existing.entity == Entities.clmBridging ? 'student_id' : 'child_id'] = personId;
    }
    for (final key in ['center', 'partner', 'round', 'center_label', 'partner_label', 'round_label',
      'school_label', 'education_summary', 'dropout_date']) {
      if (existing.data.containsKey(key) && !merged.containsKey(key)) merged[key] = existing.data[key];
    }
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    final title = _editing != null ? l10n.edit : l10n.registerNew;
    if (_loadError != null) {
      return Scaffold(appBar: AppBar(title: Text(title)), body: EmptyState(message: _loadError!, icon: Icons.cloud_off));
    }
    if (_controller == null || _schema == null) {
      return Scaffold(appBar: AppBar(title: Text(title)), body: const Center(child: CircularProgressIndicator()));
    }
    final schema = _schema!;
    final controller = _controller!;
    final stepLabel = _isReview ? l10n.stepReview : schema.sections[_step].labelFor(language);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmDialog(context, l10n.cancel)) {
          if (context.mounted) context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: LayoutBuilder(builder: (context, constraints) {
          // The rail is chrome: it is decided from the box this screen was
          // handed and it consumes width, so everything below measures what is
          // LEFT once the rail and its divider are paid for.
          final outer = AppLayout.forWidth(constraints.maxWidth);
          final showRail = outer.width.isExpanded && outer.stepRailWidth > 0;

          final body = Column(
            children: [
              if (!showRail)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 0),
                  child: _capped(Row(children: [
                    Text('${_step + 1}/$_stepCount', style: const TextStyle(color: AppColors.muted)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(stepLabel, style: Theme.of(context).textTheme.titleMedium)),
                  ])),
                ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  child: _capped(
                    _isReview
                        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Text(l10n.reviewHint, style: const TextStyle(color: AppColors.muted)),
                            if (controller.generalErrors.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(controller.generalErrors.join('\n'),
                                    style: const TextStyle(color: AppColors.danger)),
                              ),
                            SchemaReview(
                              schema: schema,
                              values: controller.collect(),
                              languageCode: language,
                              labelResolver: controller.labelResolver,
                            ),
                          ])
                        : SchemaForm(
                            controller: controller,
                            languageCode: language,
                            sectionKeys: [schema.sections[_step].key],
                            showSectionTitles: false,
                          ),
                  ),
                ),
              ),
              // The footer is capped at the SAME width as the fields, so Back
              // and Next stay beside them rather than ~1200 px apart at
              // opposite corners of a 9-inch screen.
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
                  child: LayoutBuilder(builder: (context, footerConstraints) {
                    final layout = AppLayout.forWidth(footerConstraints.maxWidth);
                    final wide = layout.width.atLeastMedium;
                    return AdaptiveBody(
                      maxWidth: layout.formMaxWidth,
                      gutter: false,
                      child: Row(
                        mainAxisAlignment: wide ? MainAxisAlignment.end : MainAxisAlignment.start,
                        children: [
                          if (_step > 0)
                            OutlinedButton(
                              key: const ValueKey('wizard-back'),
                              onPressed: _saving ? null : () => setState(() => _step--),
                              child: Text(l10n.back),
                            ),
                          // Compact keeps the Spacer: today's phone footer.
                          if (wide) const SizedBox(width: 12) else const Spacer(),
                          if (!_isReview)
                            FilledButton(
                              key: const ValueKey('wizard-next'),
                              onPressed: _saving ? null : _next,
                              child: Text(l10n.next),
                            )
                          else
                            FilledButton.icon(
                              key: const ValueKey('wizard-next'),
                              onPressed: _saving ? null : _submit,
                              icon: const Icon(Icons.save),
                              label: Text(l10n.submit),
                            ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          );

          return Column(
            children: [
              LinearProgressIndicator(value: (_step + 1) / _stepCount, backgroundColor: AppColors.background),
              Expanded(
                child: showRail
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: outer.stepRailWidth,
                            child: _StepRail(
                              key: const ValueKey('wizard-step-rail'),
                              labels: [
                                for (final section in schema.sections) section.labelFor(language),
                                l10n.stepReview,
                              ],
                              sectionKeys: [for (final section in schema.sections) section.key, 'review'],
                              step: _step,
                              maxVisited: _maxVisited,
                              onTap: _saving ? null : (i) => setState(() => _step = i),
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: body),
                        ],
                      )
                    : body,
              ),
            ],
          );
        }),
      ),
    );
  }

  /// The form cap sits INSIDE the 16 px page padding, so the packer is handed
  /// the full `formMaxWidth` (760 in portrait → two columns; beside the 240 px
  /// step rail a 1280 px landscape window leaves ~1007, which is also two).
  /// `gutter: false` because the page padding is already paid; at compact the
  /// cap is infinite and the gutter zero, so on a phone this is a no-op and
  /// the tree below it is today's tree.
  Widget _capped(Widget child) => LayoutBuilder(
        builder: (context, constraints) => AdaptiveBody(
          maxWidth: AppLayout.forWidth(constraints.maxWidth).formMaxWidth,
          gutter: false,
          child: child,
        ),
      );
}

/// The expanded-width step rail. Replaces the `1/4` line; it is an orientation
/// aid and a way BACK, never a way forward: only steps before the current one
/// are tappable, so `_next()` stays the single path onwards and the step-0
/// duplicate check cannot be skipped by jumping over it.
class _StepRail extends StatelessWidget {
  const _StepRail({
    super.key,
    required this.labels,
    required this.sectionKeys,
    required this.step,
    required this.maxVisited,
    required this.onTap,
  });

  final List<String> labels;
  final List<String> sectionKeys;
  final int step;
  final int maxVisited;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsetsDirectional.only(top: 8, bottom: 8),
      itemCount: labels.length,
      itemBuilder: (context, i) {
        final current = i == step;
        final visited = i <= maxVisited;
        final canTap = onTap != null && i < step;
        // null means "leave the text theme's own colour alone" — copyWith
        // treats a null colour as no change, so a visited step keeps the
        // default body colour and the Arabic font fallback with it.
        final Color? colour = current ? AppColors.primary : (visited ? null : AppColors.muted);
        return ListTile(
          key: ValueKey('wizard-step-${sectionKeys[i]}'),
          selected: current,
          selectedTileColor: AppColors.surfaceAlt,
          onTap: canTap ? () => onTap!(i) : null,
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: current
                ? AppColors.primary
                : visited
                    ? AppColors.success
                    : AppColors.background,
            child: visited && !current
                ? const Icon(Icons.check, size: 15, color: Colors.white)
                : Text(
                    '${i + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: current ? Colors.white : AppColors.muted,
                    ),
                  ),
          ),
          title: Text(
            labels[i],
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colour,
              fontWeight: current ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        );
      },
    );
  }
}
