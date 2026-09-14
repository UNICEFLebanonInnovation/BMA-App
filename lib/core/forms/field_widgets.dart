import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/form_schema.dart';
import 'reference_cache.dart';
import 'reference_picker.dart';
import 'schema_form_controller.dart';

/// Renders one [FieldSpec] bound to a [SchemaFormController].
class SchemaFieldWidget extends ConsumerStatefulWidget {
  const SchemaFieldWidget({
    super.key,
    required this.field,
    required this.controller,
    required this.languageCode,
    this.readOnly = false,
  });

  final FieldSpec field;
  final SchemaFormController controller;
  final String languageCode;
  final bool readOnly;

  @override
  ConsumerState<SchemaFieldWidget> createState() => _SchemaFieldWidgetState();
}

class _SchemaFieldWidgetState extends ConsumerState<SchemaFieldWidget> {
  TextEditingController? _text;

  FieldSpec get field => widget.field;
  SchemaFormController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    if (_usesTextController) {
      _text = TextEditingController(text: controller.value(field.name)?.toString() ?? '');
    }
  }

  bool get _usesTextController =>
      const {'text', 'textarea', 'number', 'decimal', 'email'}.contains(field.type);

  @override
  void didUpdateWidget(covariant SchemaFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final external = controller.value(field.name)?.toString() ?? '';
    if (_text != null && _text!.text != external && !_focused) {
      _text!.text = external;
    }
  }

  bool _focused = false;

  @override
  void dispose() {
    _text?.dispose();
    super.dispose();
  }

  InputDecoration _decoration({Widget? suffix}) {
    final errors = controller.errorsFor(field.name);
    final label = field.labelFor(widget.languageCode);
    return InputDecoration(
      labelText: field.required ? '$label *' : label,
      helperText: field.helpFor(widget.languageCode).isEmpty ? null : field.helpFor(widget.languageCode),
      helperMaxLines: 3,
      hintText: field.placeholderFor(widget.languageCode).isEmpty ? null : field.placeholderFor(widget.languageCode),
      errorText: errors.isEmpty ? null : errors.join('\n'),
      errorMaxLines: 3,
      suffixIcon: suffix,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (field.type) {
      case 'hidden':
        return const SizedBox.shrink();
      case 'textarea':
        return _textField(maxLines: 4);
      case 'number':
        return _textField(keyboardType: TextInputType.number);
      case 'decimal':
        return _textField(keyboardType: const TextInputType.numberWithOptions(decimal: true));
      case 'email':
        return _textField(keyboardType: TextInputType.emailAddress);
      case 'date':
        return _dateField(context);
      case 'boolean':
        return _booleanField();
      case 'select':
        return _selectField();
      case 'multiselect':
        return _multiSelectField(context);
      case 'ref':
        return _refField(context, multi: false);
      case 'multiref':
        return _refField(context, multi: true);
      case 'file':
        return InputDecorator(
          decoration: _decoration(),
          child: const Text('Attachments are managed on the web platform.'),
        );
      default:
        return _textField();
    }
  }

  Widget _textField({int maxLines = 1, TextInputType? keyboardType}) {
    return Focus(
      onFocusChange: (f) => _focused = f,
      child: TextField(
        controller: _text,
        readOnly: widget.readOnly,
        maxLines: maxLines,
        maxLength: field.maxLength != null && field.maxLength! <= 500 ? field.maxLength : null,
        keyboardType: keyboardType,
        decoration: _decoration(),
        onChanged: (v) => controller.setValue(field.name, v),
      ),
    );
  }

  Widget _dateField(BuildContext context) {
    final raw = controller.value(field.name)?.toString() ?? '';
    return InkWell(
      onTap: widget.readOnly
          ? null
          : () async {
              final initial = DateTime.tryParse(raw) ?? DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(1950),
                lastDate: DateTime.now().add(const Duration(days: 366)),
              );
              if (picked != null) {
                controller.setValue(field.name, _iso(picked));
              }
            },
      child: InputDecorator(
        decoration: _decoration(
          suffix: raw.isEmpty || widget.readOnly
              ? const Icon(Icons.calendar_today)
              : IconButton(icon: const Icon(Icons.clear), onPressed: () => controller.setValue(field.name, '')),
        ),
        child: Text(raw.isEmpty ? ' ' : raw),
      ),
    );
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _booleanField() {
    final value = controller.value(field.name);
    final checked = value == true || value?.toString() == 'True' || value?.toString() == 'true';
    return InputDecorator(
      decoration: _decoration(),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: checked,
        title: Text(field.labelFor(widget.languageCode)),
        onChanged: widget.readOnly ? null : (v) => controller.setValue(field.name, v),
      ),
    );
  }

  Widget _selectField() {
    final current = controller.value(field.name)?.toString() ?? '';
    final options = field.choices.where((c) => c.value.isNotEmpty).toList();
    final hasCurrent = options.any((c) => c.value == current);
    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: hasCurrent ? current : null,
      isExpanded: true,
      decoration: _decoration(),
      items: options
          .map((c) => DropdownMenuItem<String>(
                value: c.value,
                child: Text(c.labelFor(widget.languageCode), overflow: TextOverflow.ellipsis, maxLines: 2),
              ))
          .toList(),
      onChanged: widget.readOnly ? null : (v) => controller.setValue(field.name, v ?? ''),
    );
  }

  Widget _multiSelectField(BuildContext context) {
    final raw = controller.value(field.name);
    final selected = raw is List ? raw.map((e) => e.toString()).toSet() : <String>{};
    return InputDecorator(
      decoration: _decoration(),
      child: Wrap(
        spacing: 6,
        runSpacing: -6,
        children: field.choices
            .where((c) => c.value.isNotEmpty)
            .map((c) => FilterChip(
                  label: Text(c.labelFor(widget.languageCode)),
                  selected: selected.contains(c.value),
                  onSelected: widget.readOnly
                      ? null
                      : (on) {
                          final next = {...selected};
                          if (on) {
                            next.add(c.value);
                          } else {
                            next.remove(c.value);
                          }
                          controller.setValue(field.name, next.toList());
                        },
                ))
            .toList(),
      ),
    );
  }

  Widget _refField(BuildContext context, {required bool multi}) {
    final kind = field.ref ?? '';
    if (kind == 'parent') return const SizedBox.shrink();
    final cache = ref.watch(referenceCacheProvider);
    final raw = controller.value(field.name);
    final ids = multi
        ? (raw is List ? raw.map((e) => e is int ? e : int.tryParse(e.toString())).whereType<int>().toSet() : <int>{})
        : {if (raw != null && raw.toString().isNotEmpty) (raw is int ? raw : int.tryParse(raw.toString()))}
            .whereType<int>()
            .toSet();
    return FutureBuilder<Map<int, dynamic>>(
      future: cache.ensure(kind),
      builder: (context, snapshot) {
        final map = snapshot.data ?? const {};
        final labels = ids.map((id) => map[id]?.labelFor(widget.languageCode) ?? '#$id').join(', ');
        return InkWell(
          onTap: widget.readOnly
              ? null
              : () async {
                  final result = await ReferencePickerSheet.show(
                    context,
                    kind: kind,
                    title: field.labelFor(widget.languageCode),
                    languageCode: widget.languageCode,
                    multi: multi,
                    selectedIds: ids,
                  );
                  if (result == null) return;
                  if (multi && result is List) {
                    controller.setValue(field.name, result.cast<int>());
                  } else if (!multi) {
                    // ignore: avoid_dynamic_calls
                    controller.setValue(field.name, (result as dynamic).id as int);
                  }
                },
          child: InputDecorator(
            decoration: _decoration(
              suffix: ids.isEmpty || widget.readOnly
                  ? const Icon(Icons.arrow_drop_down)
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => controller.setValue(field.name, multi ? <int>[] : null),
                    ),
            ),
            child: Text(labels.isEmpty ? ' ' : labels),
          ),
        );
      },
    );
  }
}
