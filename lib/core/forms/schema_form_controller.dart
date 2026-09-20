import 'package:flutter/foundation.dart';

import '../models/form_schema.dart';

/// Signature used to resolve the display label of a value (for reveal rules
/// such as `label_contains` and for the review screen).
typedef LabelResolver = String? Function(FieldSpec field, Object? value);

/// Resolves the set of values a non-inline choice field accepts. Null means
/// the list is not on the device, and the value is then accepted.
typedef AllowedValuesResolver = Set<String>? Function(FieldSpec field);

/// Holds the values of a schema-driven form and validates them the way the
/// web platform does (required, patterns, bounds, confirm twins, reveals).
class SchemaFormController extends ChangeNotifier {
  SchemaFormController({
    required this.schema,
    Map<String, dynamic>? initial,
    Map<String, dynamic>? serverErrors,
    this.labelResolver,
    this.allowedValues,
    this.messages = const ValidationMessages(),
    DateTime Function()? clock,
  })  : values = Map<String, dynamic>.from(initial ?? const {}),
        _clock = clock ?? DateTime.now,
        serverErrors = _normaliseErrors(serverErrors);

  final EntitySchema schema;
  final Map<String, dynamic> values;
  final LabelResolver? labelResolver;

  /// Permitted values for a field whose options are not inline: a `select`
  /// with `choices_ref`, or a `ref`/`multiref` pointing at a reference list.
  ///
  /// Returning null means "cannot tell" and the value is ACCEPTED. The app is
  /// offline-first, so a reference list that has not been pulled yet must
  /// never turn into a wall of errors on a form the worker can otherwise fill.
  final AllowedValuesResolver? allowedValues;

  final ValidationMessages messages;
  final DateTime Function() _clock;

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
    final conditional = conditionallyRequired;
    final newErrors = <String, List<String>>{};
    for (final field in schema.fields) {
      if (!names.contains(field.name) || field.isHidden || hidden.contains(field.name)) continue;
      final messagesForField = _validateField(field, alsoRequired: conditional.contains(field.name));
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

  /// Fields a currently-active reveal rule makes required.
  ///
  /// `close_reason` on a day off, `absence_reason` for an absent child: the
  /// field is optional in general and required exactly while its rule holds,
  /// which is what the server checks too.
  Set<String> get conditionallyRequired {
    final result = <String>{};
    for (final rule in schema.reveals) {
      if (!rule.require) continue;
      final value = values[rule.field];
      final field = schema.field(rule.field);
      if (rule.matches(value, field == null ? value?.toString() : labelOf(field, value))) {
        result.addAll(rule.show);
      }
    }
    return result;
  }

  List<String> _validateField(FieldSpec field, {bool alsoRequired = false}) {
    final value = values[field.name];
    final result = <String>[];
    final required = field.required || alsoRequired;

    // A required BooleanField on the server means "must be true" -- an
    // unchecked consent box is not a filled-in one. `isEmpty` cannot say so,
    // because `false` is a perfectly present value for every other purpose.
    if (required && field.type == 'boolean' && value != true) {
      return [messages.required];
    }
    if (required && isEmpty(value)) return [messages.required];
    if (isEmpty(value)) return result;

    final text = value.toString();
    switch (field.type) {
      case 'number':
        final parsed = int.tryParse(text);
        if (parsed == null) {
          result.add(messages.invalidNumber);
        } else {
          _checkBounds(parsed, field, result);
        }
        break;
      case 'decimal':
        final parsed = double.tryParse(text);
        if (parsed == null) {
          result.add(messages.invalidNumber);
        } else {
          _checkBounds(parsed, field, result);
          final places = text.contains('.') ? text.split('.').last.length : 0;
          if (field.decimalPlaces != null && places > field.decimalPlaces!) {
            result.add(messages.tooManyDecimals(field.decimalPlaces!));
          }
          if (field.maxDigits != null) {
            final digits = text.replaceAll(RegExp(r'[^0-9]'), '').replaceFirst(RegExp(r'^0+(?=\d)'), '').length;
            if (digits > field.maxDigits!) result.add(messages.invalidNumber);
          }
        }
        break;
      case 'date':
        _checkDate(text, field, result);
        break;
      case 'select':
        _checkChoice(text, field, result);
        break;
      case 'multiselect':
      case 'multiref':
        final allowed = _allowedFor(field);
        if (allowed != null && value is Iterable) {
          for (final item in value) {
            if (!allowed.contains(item.toString())) {
              result.add(messages.invalidChoice);
              break;
            }
          }
        }
        break;
      case 'ref':
        _checkChoice(text, field, result);
        break;
      case 'email':
        if (!_emailPattern.hasMatch(text)) result.add(messages.invalidEmail);
        _checkText(text, field, result);
        break;
      case 'text':
      case 'textarea':
        _checkText(text, field, result);
        break;
    }
    return result;
  }

  void _checkBounds(num parsed, FieldSpec field, List<String> result) {
    if (field.minValue != null && parsed < field.minValue!) {
      result.add(messages.valueTooSmall(field.minValue!));
    }
    if (field.maxValue != null && parsed > field.maxValue!) {
      result.add(messages.valueTooLarge(field.maxValue!));
    }
  }

  void _checkText(String text, FieldSpec field, List<String> result) {
    if (field.maxLength != null && text.length > field.maxLength!) {
      result.add(messages.tooLong(field.maxLength!));
    }
    if (field.minLength != null && text.length < field.minLength!) {
      result.add(messages.tooShort(field.minLength!));
    }
    for (final rule in field.effectivePatterns) {
      final regex = _compile(rule.pattern);
      // A pattern Dart cannot compile is dropped rather than failed: the
      // server still enforces it, and rejecting every value would be worse
      // than accepting one the push will catch.
      if (regex == null || regex.hasMatch(text)) continue;
      result.add(rule.messageFor(messages.languageCode) ?? messages.invalidFormat);
    }
  }

  void _checkDate(String text, FieldSpec field, List<String> result) {
    final date = DateTime.tryParse(text);
    if (date == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
      result.add(messages.invalidDate);
      return;
    }
    final today = _clock();
    final day = DateTime(date.year, date.month, date.day);
    final min = FieldSpec.resolveDateBound(field.minDate, today);
    final max = FieldSpec.resolveDateBound(field.maxDate, today);
    if (max != null && day.isAfter(max)) {
      result.add(field.maxDate == 'today' ? messages.dateInFuture : messages.dateTooLate);
    }
    if (min != null && day.isBefore(min)) result.add(messages.dateTooEarly);
  }

  void _checkChoice(String text, FieldSpec field, List<String> result) {
    final allowed = _allowedFor(field);
    if (allowed != null && !allowed.contains(text)) result.add(messages.invalidChoice);
  }

  /// Inline choices first, then the injected resolver. Null = cannot tell.
  Set<String>? _allowedFor(FieldSpec field) {
    if (field.choices.isNotEmpty) {
      return {for (final c in field.choices) c.value};
    }
    return allowedValues?.call(field);
  }

  /// Deliberately permissive: the job here is to catch the typo the worker can
  /// still fix, not to out-parse the server's own EmailValidator.
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$');

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
    this.tooShortTemplate = 'At least {min} characters.',
    this.invalidEmail = 'Enter a valid email address.',
    this.invalidChoice = 'Choose one of the listed options.',
    this.valueTooSmallTemplate = 'Must be {min} or more.',
    this.valueTooLargeTemplate = 'Must be {max} or less.',
    this.dateInFuture = 'The date cannot be in the future.',
    this.dateTooEarly = 'The date is too early.',
    this.dateTooLate = 'The date is too late.',
    this.tooManyDecimalsTemplate = 'At most {max} decimal places.',
    this.languageCode = 'en',
  });

  final String required;
  final String invalidNumber;
  final String invalidDate;
  final String invalidFormat;
  final String confirmMismatch;
  final String tooLongTemplate;
  final String tooShortTemplate;
  final String invalidEmail;
  final String invalidChoice;
  final String valueTooSmallTemplate;
  final String valueTooLargeTemplate;
  final String dateInFuture;
  final String dateTooEarly;
  final String dateTooLate;
  final String tooManyDecimalsTemplate;

  /// Which of a server rule's two messages to show. The rules travel with the
  /// schema in both languages, so the interface language picks one.
  final String languageCode;

  String tooLong(int max) => tooLongTemplate.replaceAll('{max}', '$max');
  String tooShort(int min) => tooShortTemplate.replaceAll('{min}', '$min');
  String valueTooSmall(num min) => valueTooSmallTemplate.replaceAll('{min}', _n(min));
  String valueTooLarge(num max) => valueTooLargeTemplate.replaceAll('{max}', _n(max));
  String tooManyDecimals(int max) => tooManyDecimalsTemplate.replaceAll('{max}', '$max');

  static String _n(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';
}
