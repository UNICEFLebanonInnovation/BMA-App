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
import '../../core/sync/sync_engine.dart';
import '../../core/widgets/common.dart';
import '../../l10n/app_localizations.dart';

class TeacherFormScreen extends ConsumerStatefulWidget {
  const TeacherFormScreen({super.key, this.module, this.editUuid});

  final BmaModule? module;
  final String? editUuid;

  @override
  ConsumerState<TeacherFormScreen> createState() => _TeacherFormScreenState();
}

class _TeacherFormScreenState extends ConsumerState<TeacherFormScreen> {
  SchemaFormController? _controller;
  EntitySchema? _schema;
  EntityRecord? _editing;
  bool _saving = false;
  String? _loadError;

  String get _entity => _editing?.entity ?? Entities.teacherFor(widget.module ?? BmaModule.mscc);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final l10n = AppLocalizations.of(context);
    final dao = ref.read(entityDaoProvider);
    if (widget.editUuid != null) _editing = await dao.byUuid(widget.editUuid!);
    final schema = await ref.read(schemaProvider(_entity).future);
    if (schema == null) {
      setState(() => _loadError = l10n.bootstrapRequired);
      return;
    }
    final cache = ref.read(referenceCacheProvider);
    final language = ref.read(settingsControllerProvider).locale.languageCode;
    for (final field in schema.fields.where((f) => f.isReference && f.ref != null && f.ref != 'parent')) {
      await cache.ensure(field.ref!);
    }
    Map<String, dynamic> initial;
    if (_editing != null) {
      initial = Map<String, dynamic>.from(_editing!.data)..removeWhere((k, v) => v == null || k.endsWith('_label'));
    } else {
      initial = {};
      final profile = ref.read(currentProfileProvider);
      if (schema.field('center') != null && profile?.center != null) initial['center'] = profile!.center!.id;
      if (schema.field('school') != null && profile?.school != null) initial['school'] = profile!.school!.id;
      if (schema.field('round') != null) {
        final rounds = await cache.list('rounds.${Entities.moduleOf(_entity).key}');
        final current = rounds.where((r) => r.extra['current_year'] == true).toList();
        if (current.isNotEmpty) initial['round'] = current.first.id;
      }
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

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (!_controller!.validate()) return;
    setState(() => _saving = true);
    final dao = ref.read(entityDaoProvider);
    try {
      final values = _controller!.collect();
      if (_editing != null) {
        await dao.updateLocal(_editing!, values);
      } else {
        await dao.createLocal(entity: _entity, data: values);
      }
      bumpDataVersion(ref);
      await ref.read(syncEngineProvider.notifier).refreshCounts();
      if (!mounted) return;
      showMessage(context, l10n.saveDraft);
      context.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = ref.watch(settingsControllerProvider).locale.languageCode;
    if (_loadError != null) return Scaffold(appBar: AppBar(), body: EmptyState(message: _loadError!, icon: Icons.cloud_off));
    if (_controller == null || _schema == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.teacherForm),
        actions: [
          if (_editing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (!await confirmDialog(context, l10n.deleteConfirm)) return;
                await ref.read(entityDaoProvider).markDeleted(_editing!);
                bumpDataVersion(ref);
                if (context.mounted) context.pop();
              },
            ),
        ],
      ),
      body: Column(children: [
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
              OutlinedButton(onPressed: () => context.pop(), child: Text(l10n.cancel)),
              const Spacer(),
              FilledButton.icon(onPressed: _saving ? null : _submit, icon: const Icon(Icons.save), label: Text(l10n.save)),
            ]),
          ),
        ),
      ]),
    );
  }
}
