/// Form descriptions served by `/api/mobile/v1/bootstrap/` (`schemas`).
///
/// They are generated on the server from the Django forms of the web
/// platform, so the app never hard-codes field lists, labels or choices.
class ChoiceOption {
  const ChoiceOption({required this.value, required this.label, this.labelAr});

  final String value;
  final String label;
  final String? labelAr;

  String labelFor(String languageCode) =>
      languageCode == 'ar' && (labelAr?.isNotEmpty ?? false) ? labelAr! : label;

  static ChoiceOption fromJson(Map<String, dynamic> json) => ChoiceOption(
        value: (json['value'] ?? '').toString(),
        label: (json['label'] ?? '').toString(),
        labelAr: json['label_ar']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'value': value,
        'label': label,
        if (labelAr != null) 'label_ar': labelAr,
      };
}

class FieldSpec {
  const FieldSpec({
    required this.name,
    required this.label,
    required this.type,
    this.labelAr,
    this.required = false,
    this.helpText = '',
    this.helpTextAr,
    this.placeholder = '',
    this.placeholderAr,
    this.maxLength,
    this.minValue,
    this.maxValue,
    this.pattern,
    this.choices = const [],
    this.ref,
  });

  final String name;
  final String label;
  final String? labelAr;

  /// text, textarea, number, decimal, date, datetime, boolean, select,
  /// multiselect, ref, multiref, email, file, hidden.
  final String type;
  final bool required;
  final String helpText;
  final String? helpTextAr;
  final String placeholder;
  final String? placeholderAr;
  final int? maxLength;
  final num? minValue;
  final num? maxValue;
  final String? pattern;
  final List<ChoiceOption> choices;

  /// Reference list key (e.g. `nationalities`, `rounds.mscc`, `parent`).
  final String? ref;

  bool get isHidden => type == 'hidden';
  bool get isMulti => type == 'multiselect' || type == 'multiref';
  bool get isReference => type == 'ref' || type == 'multiref';

  /// LAYOUT, not validation. Declared here rather than inside the packer so
  /// that `field_layout.dart` and `field_widgets.dart` cannot disagree about
  /// which fields own a whole row.
  ///
  /// A `textarea` renders four (six on a tablet row) lines, a `multiselect`
  /// wraps chips, a `multiref` joins labels with `', '` and a `file` renders a
  /// sentence — all of them want width. So does any field carrying a long
  /// help text, because `helperMaxLines: 3` would otherwise turn a half-width
  /// cell into a three-line paragraph under a one-line input.
  ///
  /// The 60-character test deliberately reads [helpText] (the English string)
  /// in both locales: the packing of a form must not change when the operator
  /// switches language mid-registration.
  bool get spansFullRow =>
      type == 'textarea' ||
      type == 'multiselect' ||
      type == 'multiref' ||
      type == 'file' ||
      helpText.length > 60;

  /// `<base>_confirm` twins read as one control and must share a row.
  ///
  /// The real bootstrap ships `confirm_fields: []`, so the suffix convention
  /// that `SchemaFormController.validate` already enforces is the
  /// authoritative one here too.
  bool get pairsWithPrevious => name.endsWith('_confirm');

  /// Name of the field this one confirms, or null when it is not a twin.
  String? get confirmBaseName =>
      pairsWithPrevious ? name.substring(0, name.length - '_confirm'.length) : null;

  String labelFor(String languageCode) =>
      languageCode == 'ar' && (labelAr?.isNotEmpty ?? false) ? labelAr! : label;

  String helpFor(String languageCode) =>
      languageCode == 'ar' && (helpTextAr?.isNotEmpty ?? false) ? helpTextAr! : helpText;

  String placeholderFor(String languageCode) => languageCode == 'ar' &&
          (placeholderAr?.isNotEmpty ?? false)
      ? placeholderAr!
      : placeholder;

  static FieldSpec fromJson(Map<String, dynamic> json) => FieldSpec(
        name: json['name'] as String,
        label: (json['label'] ?? json['name']).toString(),
        labelAr: json['label_ar']?.toString(),
        type: (json['type'] ?? 'text').toString(),
        required: json['required'] == true,
        helpText: (json['help_text'] ?? '').toString(),
        helpTextAr: json['help_text_ar']?.toString(),
        placeholder: (json['placeholder'] ?? '').toString(),
        placeholderAr: json['placeholder_ar']?.toString(),
        maxLength: (json['max_length'] as num?)?.toInt(),
        minValue: json['min_value'] as num?,
        maxValue: json['max_value'] as num?,
        pattern: json['pattern']?.toString(),
        choices: ((json['choices'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ChoiceOption.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        ref: json['ref']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'label': label,
        if (labelAr != null) 'label_ar': labelAr,
        'type': type,
        'required': required,
        'help_text': helpText,
        if (helpTextAr != null) 'help_text_ar': helpTextAr,
        'placeholder': placeholder,
        if (placeholderAr != null) 'placeholder_ar': placeholderAr,
        if (maxLength != null) 'max_length': maxLength,
        if (minValue != null) 'min_value': minValue,
        if (maxValue != null) 'max_value': maxValue,
        if (pattern != null) 'pattern': pattern,
        if (choices.isNotEmpty) 'choices': choices.map((c) => c.toJson()).toList(),
        if (ref != null) 'ref': ref,
      };
}

class FormSection {
  const FormSection({
    required this.key,
    required this.label,
    required this.fields,
    this.labelAr,
  });

  final String key;
  final String label;
  final String? labelAr;
  final List<String> fields;

  String labelFor(String languageCode) =>
      languageCode == 'ar' && (labelAr?.isNotEmpty ?? false) ? labelAr! : label;

  static FormSection fromJson(Map<String, dynamic> json) => FormSection(
        key: json['key'] as String,
        label: (json['label'] ?? json['key']).toString(),
        labelAr: json['label_ar']?.toString(),
        fields: ((json['fields'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        if (labelAr != null) 'label_ar': labelAr,
        'fields': fields,
      };
}

/// Conditional visibility rule: `when` describes a condition on one field,
/// `show` the fields revealed while it holds.
class RevealRule {
  const RevealRule({required this.field, required this.show, this.inValues, this.notInValues, this.labelContains});

  final String field;
  final List<String> show;
  final List<String>? inValues;
  final List<String>? notInValues;
  final String? labelContains;

  static RevealRule fromJson(Map<String, dynamic> json) {
    final when = Map<String, dynamic>.from((json['when'] as Map?) ?? const {});
    List<String>? list(Object? v) => v == null ? null : (v as List).map((e) => e.toString()).toList();
    return RevealRule(
      field: (when['field'] ?? '').toString(),
      show: ((json['show'] as List?) ?? const []).map((e) => e.toString()).toList(),
      inValues: list(when['in']),
      notInValues: list(when['not_in']),
      labelContains: when['label_contains']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'when': {
          'field': field,
          if (inValues != null) 'in': inValues,
          if (notInValues != null) 'not_in': notInValues,
          if (labelContains != null) 'label_contains': labelContains,
        },
        'show': show,
      };

  /// Evaluate the rule. [value] is the current raw value of [field] and
  /// [valueLabel] its display label (for `label_contains`).
  bool matches(Object? value, String? valueLabel) {
    final v = value == null ? '' : value.toString();
    if (inValues != null) return inValues!.contains(v);
    if (notInValues != null) return !notInValues!.contains(v);
    if (labelContains != null) {
      return (valueLabel ?? '').toLowerCase().contains(labelContains!.toLowerCase());
    }
    return v.isNotEmpty;
  }
}

class EntitySchema {
  const EntitySchema({
    required this.key,
    required this.module,
    required this.label,
    required this.kind,
    required this.fields,
    required this.sections,
    this.parent,
    this.identity = false,
    this.multiple = true,
    this.pullable = true,
    this.description = '',
    this.reveals = const [],
    this.wizard = false,
    this.confirmFields = const [],
  });

  final String key;
  final String module;
  final String label;
  final String kind;
  final String? parent;
  final bool identity;
  final bool multiple;
  final bool pullable;
  final String description;
  final List<FieldSpec> fields;
  final List<FormSection> sections;
  final List<RevealRule> reveals;
  final bool wizard;
  final List<String> confirmFields;

  FieldSpec? field(String name) {
    for (final f in fields) {
      if (f.name == name) return f;
    }
    return null;
  }

  bool get isAttendance => kind == 'attendance' || kind == 'teacher_attendance';

  /// Every field name that any [RevealRule] can show — i.e. every field whose
  /// presence in the form depends on another field's value.
  ///
  /// The form packer forces a row break immediately before and after each
  /// contiguous run of these, so that flipping a reveal can never move a
  /// field that sits above it. It asks on every keystroke (the controller
  /// notifies on `setValue`), so the answer is computed once per schema and
  /// cached. An [Expando] rather than a field because [EntitySchema] has a
  /// const constructor.
  Set<String> get revealTargets =>
      _revealTargets[this] ??= Set.unmodifiable({for (final rule in reveals) ...rule.show});

  static final Expando<Set<String>> _revealTargets = Expando<Set<String>>('revealTargets');

  /// Names of the fields hidden by reveal rules given the current [values].
  Set<String> hiddenFields(Map<String, dynamic> values, String? Function(String field, Object? value) labelOf) {
    final controlled = <String>{};
    final shown = <String>{};
    for (final rule in reveals) {
      controlled.addAll(rule.show);
      final value = values[rule.field];
      if (rule.matches(value, labelOf(rule.field, value))) {
        shown.addAll(rule.show);
      }
    }
    return controlled.difference(shown);
  }

  static EntitySchema fromJson(Map<String, dynamic> json) => EntitySchema(
        key: json['key'] as String,
        module: (json['module'] ?? 'mscc').toString(),
        label: (json['label'] ?? json['key']).toString(),
        kind: (json['kind'] ?? 'form').toString(),
        parent: json['parent']?.toString(),
        identity: json['identity'] == true,
        multiple: json['multiple'] != false,
        pullable: json['pullable'] != false,
        description: (json['description'] ?? '').toString(),
        fields: ((json['fields'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => FieldSpec.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        sections: ((json['sections'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => FormSection.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        reveals: ((json['reveals'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => RevealRule.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        wizard: json['wizard'] == true,
        confirmFields: ((json['confirm_fields'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'module': module,
        'label': label,
        'kind': kind,
        'parent': parent,
        'identity': identity,
        'multiple': multiple,
        'pullable': pullable,
        'description': description,
        'fields': fields.map((f) => f.toJson()).toList(),
        'sections': sections.map((s) => s.toJson()).toList(),
        'reveals': reveals.map((r) => r.toJson()).toList(),
        'wizard': wizard,
        'confirm_fields': confirmFields,
      };
}
