import 'package:flutter/foundation.dart';

import '../models/form_schema.dart';

/// Signature used to resolve the display label of a value (for reveal rules
/// such as `label_contains` and for the review screen).
typedef LabelResolver = String? Function(FieldSpec field, Object? value);

/// Holds the values of a schema-driven form and validates them the way the
/// web platform does (required, patterns, bounds, confirm twins, reveals).
class SchemaFormController extends ChangeNotifier {
  SchemaFormController({
    required this.schema,
    Map<String, dynamic>? initial,
    Map<String, dynamic>? serverErrors,
    this.labelResolver,
    this.messages = const ValidationMessages(),
  })  : values = Map<String, dynamic>.from(initial ?? const {}),
        serverErrors = _normaliseErrors(serverErrors);

  final EntitySchema schema;
  final Map<String, dynamic> values;
  final LabelResolver? labelResolver;
  final ValidationMessages messages;

  Map<String, List<String>> errors = {};
  Map<String, List<String>> serverErrors;

  static Map<String, List<String>> _normaliseErrors(Map<String, dynamic>? raw) {
    if (raw == null) return {};
    return raw.map((key, value) {
      if (value is List) return MapEntry(key, value.map((e) => e.toString()).toList());
      return MapEntry(key, [value.toString()]);
    });
  }

  Object? value(String name) => values[name];

  void setValue(String name, Object? value) {
    if (values[name] == value) return;
    values[name] = value;
    errors.remove(name);
    serverErrors.remove(name);
    notifyListeners();
  }

  void setServerErrors(Map<String, dynamic>? raw) {
    serverErrors = _normaliseErrors(raw);
    notifyListeners();
  }

  String? labelOf(FieldSpec field, Object? value) {
    if (labelResolver != null) {
      final resolved = labelResolver!(field, value);
      if (resolved != null) return resolved;
    }
    if (field.choices.isNotEmpty) {
      for (final c in field.choices) {
        if (c.value == (value?.toString() ?? '')) return c.label;
      }
    }
    return value?.toString();
  }

  Set<String> get hiddenFields => schema.hiddenFields(values, (name, value) {
        final field = schema.field(name);
        return field == null ? value?.toString() : labelOf(field, value);
      });

  bool isVisible(FieldSpec field) => !field.isHidden && !hiddenFields.contains(field.name);

  List<String> errorsFor(String name) => [...?errors[name], ...?serverErrors[name]];

  List<String> get generalErrors => [...?errors['__all__'], ...?serverErrors['__all__']];

  static bool isEmpty(Object? value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    if (value is Iterable) return value.isEmpty;
    return false;
  }

  /// Validate the given fields (or all visible fields). Returns true when valid.
  bool validate({Iterable<String>? fields}) {
    final names = fields?.toSet() ?? schema.fields.map((f) => f.name).toSet();
    final hidden = hiddenFields;
    final newErrors = <String, List<String>>{};
    for (final field in schema.fields) {
      if (!names.contains(field.name) || field.isHidden || hidden.contains(field.name)) continue;
      final messagesForField = _validateField(field);
      if (messagesForField.isNotEmpty) newErrors[field.name] = messagesForField;
    }
    // Confirmation twins: `<field>_confirm` must equal `<field>`.
    for (final field in schema.fields) {
      if (!field.name.endsWith('_confirm') || !names.contains(field.name)) continue;
      final base = field.name.substring(0, field.name.length - '_confirm'.length);
      if (!schema.fields.any((f) => f.name == base) || hidden.contains(field.name)) continue;
      final a = values[base]?.toString().trim() ?? '';
      final b = values[field.name]?.toString().trim() ?? '';
      if (a.isNotEmpty && a != b) {
        newErrors.putIfAbsent(field.name, () => []).add(messages.confirmMismatch);
      }
    }
    errors
      ..removeWhere((key, _) => names.contains(key))
      ..addAll(newErrors);
    notifyListeners();
    return newErrors.isEmpty;
  }

  List<String> _validateField(FieldSpec field) {
    final value = values[field.name];
    final result = <String>[];
    if (field.required && isEmpty(value)) {
      result.add(messages.required);
      return result;
    }
    if (isEmpty(value)) return result;
    final text = value.toString();
    switch (field.type) {
      case 'number':
        final parsed = int.tryParse(text);
        if (parsed == null) {
          result.add(messages.invalidNumber);
        } else {
          if (field.minValue != null && parsed < field.minValue!) result.add(messages.invalidNumber);
          if (field.maxValue != null && parsed > field.maxValue!) result.add(messages.invalidNumber);
        }
        break;
      case 'decimal':
        if (double.tryParse(text) == null) result.add(messages.invalidNumber);
        break;
      case 'date':
        final date = DateTime.tryParse(text);
        if (date == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
          result.add(messages.invalidDate);
        }
        break;
      case 'text':
      case 'textarea':
      case 'email':
        if (field.maxLength != null && text.length > field.maxLength!) {
          result.add(messages.tooLong(field.maxLength!));
        }
        if (field.pattern != null && field.pattern!.isNotEmpty) {
          final regex = _compile(field.pattern!);
          if (regex != null && !regex.hasMatch(text)) result.add(messages.invalidFormat);
        }
        break;
    }
    return result;
  }

  static RegExp? _compile(String pythonPattern) {
    var pattern = pythonPattern;
    var caseInsensitive = false;
    if (pattern.startsWith('(?i)')) {
      caseInsensitive = true;
      pattern = pattern.substring(4);
    }
    try {
      return RegExp(pattern, caseSensitive: !caseInsensitive, unicode: true);
    } catch (_) {
      return null;
    }
  }

  /// Values ready to be stored: hidden (revealed-off) fields are dropped so
  /// that the server never receives stale conditional values.
  Map<String, dynamic> collect() {
    final hidden = hiddenFields;
    final result = <String, dynamic>{};
    for (final entry in values.entries) {
      if (hidden.contains(entry.key)) continue;
      result[entry.key] = entry.value;
    }
    return result;
  }
}

/// Localised validation messages (injected from AppLocalizations).
class ValidationMessages {
  const ValidationMessages({
    this.required = 'This field is required.',
    this.invalidNumber = 'Enter a valid number.',
    this.invalidDate = 'Enter a valid date (YYYY-MM-DD).',
    this.invalidFormat = 'Invalid format.',
    this.confirmMismatch = 'Values do not match.',
    this.tooLongTemplate = 'Maximum {max} characters.',
  });

  final String required;
  final String invalidNumber;
  final String invalidDate;
  final String invalidFormat;
  final String confirmMismatch;
  final String tooLongTemplate;

  String tooLong(int max) => tooLongTemplate.replaceAll('{max}', '$max');
}
