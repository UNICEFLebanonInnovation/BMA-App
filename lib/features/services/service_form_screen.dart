import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/config/settings_controller.dart';
import '../../core/db/entity_dao.dart';
import '../../core/db/providers.dart';
import '../../core/db/reference_dao.dart';
import '../../core/forms/reference_cache.dart';
import '../../core/forms/schema_form.dart';
import '../../core/forms/schema_form_controller.dart';
import '../../core/models/entity_record.dart';
import '../../core/models/form_schema.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';
import '../registrations/registration_helpers.dart';

/// Generic form for every child entity of a registration (MSCC services,
/// referrals, grading, ALP grading, Bridging sub-forms, new round).
class ServiceFormScreen extends ConsumerStatefulWidget {
  const ServiceFormScreen({super.key, this.parentUuid, this.entity, this.editUuid});

  final String? parentUuid;
  final String? entity;
  final String? editUuid;

  @override
  ConsumerState<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends ConsumerState<ServiceFormScreen> {
  SchemaFormController? _controller;
  EntitySchema? _schema;
  EntityRecord? _parent;
  EntityRecord? _editing;
  bool _saving = false;
  String? _loadError;

  String get _entity => _editing?.entity ?? widget.entity!;

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
      if (_editing?.parentUuid != null) _parent = await dao.byUuid(_editing!.parentUuid!);
    } else if (widget.parentUuid != null) {
      _parent = await dao.byUuid(widget.parentUuid!);
    }
    final base = await ref.read(schemaProvider(_entity).future);
    if (base == null) {
      setState(() => _loadError = l10n.bootstrapRequired);
      return;
    }
    final schema = await _withExtraFields(base);
    Map<String, dynamic> initial;
    if (_editing != null) {
      initial = Map<String, dynamic>.from(_editing!.data)..removeWhere((k, v) => v == null);
    } else if (schema.kind == 'bridging_subform' && _parent != null) {
      // Bridging sub-forms edit fields of the registration itself: prefill.
      initial = SyncEngine.flattenIdentityPayload(_parent!.entity, Map.of(_parent!.data));
      initial.removeWhere((k, v) => v == null || !schema.fields.any((f) => f.name == k));
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

  /// Some web forms take parameters from the URL rather than the form
  /// (programme type, pre/post test, mid-assessment number). They are added
  /// as ordinary fields so the payload carries them.
  Future<EntitySchema> _withExtraFields(EntitySchema base) async {
    final extra = <FieldSpec>[];
    final reference = ref.read(referenceDaoProvider);
    if (base.key == 'mscc.education_grading' || base.key == 'mscc.youth_scoring' || base.key == 'mscc.school_grading') {
      final programmes = await reference.choices('mscc.education_service.education_program');
      extra.add(FieldSpec(
        name: 'programme_type',
        label: 'Programme type',
        labelAr: 'نوع البرنامج',
        type: 'select',
        required: true,
        choices: programmes.map((c) => ChoiceOption(value: c.value, label: c.label, labelAr: c.labelAr)).toList(),
      ));
      if (base.key != 'mscc.school_grading') {
        extra.add(const FieldSpec(
          name: 'pre_post',
          label: 'Test stage',
          labelAr: 'مرحلة الاختبار',
          type: 'select',
          required: true,
          choices: [ChoiceOption(value: 'pre', label: 'Pre-test'), ChoiceOption(value: 'post', label: 'Post-test')],
        ));
      }
    }
    if (base.key == 'clm.bridging_mid_assessment') {
      extra.add(const FieldSpec(
        name: 'number',
        label: 'Mid-assessment number',
        labelAr: 'رقم التقييم المرحلي',
        type: 'select',
        required: true,
        choices: [ChoiceOption(value: '1', label: 'Mid-test 1'), ChoiceOption(value: '2', label: 'Mid-test 2')],
      ));
    }
    if (extra.isEmpty) return base;
    final sections = [
      FormSection(key: 'parameters', label: 'Parameters', labelAr: 'المعطيات', fields: extra.map((f) => f.name).toList()),
      ...base.sections,
    ];
    return EntitySchema(
      key: base.key,
      module: base.module,
      label: base.label,
      kind: base.kind,
      parent: base.parent,
      identity: base.identity,
      multiple: base.multiple,
      pullable: base.pullable,
      description: base.description,
      fields: [...extra, ...base.fields],
      sections: sections,
      reveals: base.reveals,
      wizard: false,
      confirmFields: base.confirmFields,
    );
  }

  Map<String, dynamic> _defaults(EntitySchema schema) {
    final values = <String, dynamic>{};
    final today = DateTime.now();
    final iso = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    if (schema.field('registration_date') != null) values['registration_date'] = iso;
    if (_parent != null) {
      final view = RegistrationView(_parent!);
      if (schema.field('round') != null && view.roundId != null) values['round'] = view.roundId;
    }
    return values;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final controller = _controller!;
    if (!controller.validate()) return;
    setState(() => _saving = true);
    final dao = ref.read(entityDaoProvider);
    try {
      final values = controller.collect();
      if (_editing != null) {
        await dao.updateLocal(_editing!, values);
      } else {
        await dao.createLocal(entity: _entity, data: values, parent: _parent);
      }
      bumpDataVersion(ref);
      await ref.read(syncEngineProvider.notifier).refreshCounts();
      if (!mounted) return;
      showMessage(context, l10n.saveDraft);
      context.pop();
    } catch (e) {
      if (mounted) showMessage(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context);
    if (_editing == null) return;
    if (!await confirmDialog(context, l10n.deleteConfirm)) return;
    await ref.read(entityDaoProvider).markDeleted(_editing!);
    bumpDataVersion(ref);
    await ref.read(syncEngineProvider.notifier).refreshCounts();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    if (_loadError != null) {
      return Scaffold(appBar: AppBar(), body: EmptyState(message: _loadError!, icon: Icons.cloud_off));
    }
    if (_controller == null || _schema == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final schema = _schema!;
    final parentLabel = _parent?.label ?? '';
    final isNewRound = schema.key == Entities.msccNewRoundKey;
    return Scaffold(
      appBar: AppBar(
        title: Text(schema.label),
        actions: [
          if (_editing != null && _editing!.serverId == null)
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: l10n.delete, onPressed: _delete),
        ],
      ),
      body: Column(
        children: [
          if (parentLabel.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(parentLabel, style: const TextStyle(color: AppColors.muted)),
            ),
          if (isNewRound)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(schema.description, style: const TextStyle(color: AppColors.muted)),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SchemaForm(controller: _controller!, languageCode: language),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                OutlinedButton(onPressed: _saving ? null : () => context.pop(), child: Text(l10n.cancel)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: const Icon(Icons.save),
                  label: Text(isNewRound ? l10n.confirmRegistration : l10n.save),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
