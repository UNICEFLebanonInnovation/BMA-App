import 'package:flutter/material.dart';

import '../models/form_schema.dart';
import 'field_widgets.dart';
import 'schema_form_controller.dart';

/// Renders the fields of an [EntitySchema] (optionally only some sections)
/// bound to a [SchemaFormController]. Conditional fields are hidden
/// according to the schema's reveal rules.
class SchemaForm extends StatelessWidget {
  const SchemaForm({
    super.key,
    required this.controller,
    required this.languageCode,
    this.sectionKeys,
    this.readOnly = false,
    this.showSectionTitles = true,
    this.excludeFields = const {},
  });

  final SchemaFormController controller;
  final String languageCode;
  final List<String>? sectionKeys;
  final bool readOnly;
  final bool showSectionTitles;
  final Set<String> excludeFields;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final schema = controller.schema;
        final sections = schema.sections.where((s) => sectionKeys == null || sectionKeys!.contains(s.key)).toList();
        final children = <Widget>[];
        final general = controller.generalErrors;
        if (general.isNotEmpty) {
          children.add(Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(general.join('\n'), style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            ),
          ));
        }
        for (final section in sections) {
          final fields = section.fields
              .map(schema.field)
              .whereType<FieldSpec>()
              .where((f) => !excludeFields.contains(f.name) && controller.isVisible(f))
              .toList();
          if (fields.isEmpty) continue;
          if (showSectionTitles && sections.length > 1) {
            children.add(Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(section.labelFor(languageCode), style: Theme.of(context).textTheme.titleMedium),
            ));
          }
          for (final field in fields) {
            children.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: SchemaFieldWidget(
                key: ValueKey('field-${field.name}'),
                field: field,
                controller: controller,
                languageCode: languageCode,
                readOnly: readOnly,
              ),
            ));
          }
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      },
    );
  }
}

/// Read-only summary of a form's values (review step, profile tab).
class SchemaReview extends StatelessWidget {
  const SchemaReview({
    super.key,
    required this.schema,
    required this.values,
    required this.languageCode,
    this.labelResolver,
    this.sectionKeys,
    this.dense = false,
  });

  final EntitySchema schema;
  final Map<String, dynamic> values;
  final String languageCode;
  final String? Function(FieldSpec field, Object? value)? labelResolver;
  final List<String>? sectionKeys;
  final bool dense;

  String _display(FieldSpec field, Object? value) {
    if (value == null || (value is String && value.isEmpty) || (value is List && value.isEmpty)) return '—';
    if (value is List) {
      return value.map((v) => _display(field, v)).join(', ');
    }
    if (labelResolver != null) {
      final resolved = labelResolver!(field, value);
      if (resolved != null) return resolved;
    }
    for (final c in field.choices) {
      if (c.value == value.toString()) return c.labelFor(languageCode);
    }
    if (value is bool) return value ? '✓' : '✗';
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final controller = SchemaFormController(schema: schema, initial: values, labelResolver: labelResolver);
    final hidden = controller.hiddenFields;
    final sections = schema.sections.where((s) => sectionKeys == null || sectionKeys!.contains(s.key)).toList();
    final children = <Widget>[];
    for (final section in sections) {
      final fields = section.fields
          .map(schema.field)
          .whereType<FieldSpec>()
          .where((f) => !f.isHidden && !hidden.contains(f.name))
          .toList();
      if (fields.isEmpty) continue;
      if (sections.length > 1) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
          child: Text(section.labelFor(languageCode), style: Theme.of(context).textTheme.titleSmall),
        ));
      }
      for (final field in fields) {
        children.add(ListTile(
          dense: dense,
          contentPadding: EdgeInsets.zero,
          title: Text(field.labelFor(languageCode), style: Theme.of(context).textTheme.bodySmall),
          subtitle: Text(_display(field, values[field.name]), style: Theme.of(context).textTheme.bodyMedium),
        ));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}
