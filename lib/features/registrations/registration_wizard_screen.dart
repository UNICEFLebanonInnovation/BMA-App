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
import '../../core/forms/schema_form_controller.dart';
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
  EntitySchema? _schema;
  EntityRecord? _editing;
  int _step = 0;
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
    for (final field in schema.fields.where((f) => f.isReference && f.ref != null && f.ref != 'parent')) {
      await cache.ensure(field.ref!);
    }
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
        messages: ValidationMessages(
          required: l10n.requiredField,
          invalidNumber: l10n.invalidNumber,
          invalidDate: l10n.invalidDate,
          confirmMismatch: l10n.confirmMismatch,
        ),
      );
    });
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
    setState(() => _step++);
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
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.possibleDuplicates),
        content: SizedBox(
          width: 420,
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
        body: Column(
          children: [
            LinearProgressIndicator(value: (_step + 1) / _stepCount, backgroundColor: AppColors.background),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                Text('${_step + 1}/$_stepCount', style: const TextStyle(color: AppColors.muted)),
                const SizedBox(width: 12),
                Expanded(child: Text(stepLabel, style: Theme.of(context).textTheme.titleMedium)),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                child: _isReview
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
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: _saving ? null : () => setState(() => _step--),
                      child: Text(l10n.back),
                    ),
                  const Spacer(),
                  if (!_isReview)
                    FilledButton(onPressed: _saving ? null : _next, child: Text(l10n.next))
                  else
                    FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: const Icon(Icons.save),
                      label: Text(l10n.submit),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
