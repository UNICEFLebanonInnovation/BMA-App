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

/// One regex rule copied from a Django field's `validators=[...]`.
///
/// Carries its own message because the server's wording ("Only alphabetic
/// characters are allowed.") tells the worker what to do, where a generic
/// "Invalid format." leaves them guessing which character the field objects
/// to. A field may carry several, so this is a list rather than a pair of
/// scalars on [FieldSpec].
class PatternRule {
  const PatternRule({required this.pattern, this.message, this.messageAr});

  final String pattern;
  final String? message;
  final String? messageAr;

  String? messageFor(String languageCode) =>
      languageCode == 'ar' && (messageAr?.isNotEmpty ?? false) ? messageAr : message;

  static PatternRule fromJson(Map<String, dynamic> json) => PatternRule(
        pattern: (json['pattern'] ?? '').toString(),
        message: json['message']?.toString(),
        messageAr: json['message_ar']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'pattern': pattern,
        if (message != null) 'message': message,
        if (messageAr != null) 'message_ar': messageAr,
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
    this.minLength,
    this.minValue,
    this.maxValue,
    this.maxDigits,
    this.decimalPlaces,
    this.pattern,
    this.patterns = const [],
    this.minDate,
    this.maxDate,
    this.choices = const [],
    this.choicesRef,
    this.ref,
    this.script,
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
  final int? minLength;
  final num? minValue;
  final num? maxValue;
  final int? maxDigits;
  final int? decimalPlaces;

  /// The first entry of [patterns], kept so that an APK already installed in
  /// the field keeps working against a newer server. Read [effectivePatterns]
  /// instead: it is the union, and it carries the server's messages.
  final String? pattern;
  final List<PatternRule> patterns;

  /// `'today'`, or an ISO date. Declarative because the only bound the server
  /// states today is "not in the future", and an absolute date baked into a
  /// bootstrap would go stale the next morning.
  final String? minDate;
  final String? maxDate;

  final List<ChoiceOption> choices;

  /// Reference-list key holding this field's choices, for a `select` whose
  /// options live in a shared list (the attendance reasons). The picker and
  /// the validator both read it, so neither can offer or accept a value the
  /// other rejects.
  final String? choicesRef;

  /// Reference list key (e.g. `nationalities`, `rounds.mscc`, `parent`).
  final String? ref;

  /// Writing system this field must be typed in — `'arabic'`, or null for any.
  ///
  /// The website requires a child's and a caregiver's name in Arabic and
  /// enforces it in JavaScript (`checkArabicOnly`), not in a Django validator,
  /// so the rule had no way of reaching the app until it was named here.
  final String? script;

  bool get isArabicOnly => script == 'arabic';

  /// [patterns] when the server sent them, else the legacy single [pattern].
  List<PatternRule> get effectivePatterns {
    if (patterns.isNotEmpty) return patterns;
    if (pattern != null && pattern!.isNotEmpty) return [PatternRule(pattern: pattern!)];
    return const [];
  }

  /// Resolve [minDate]/[maxDate] against [today]. `null` when unset or
  /// unparseable: a bound nobody can read must not silently reject every value.
  static DateTime? resolveDateBound(String? bound, DateTime today) {
    if (bound == null || bound.isEmpty) return null;
    if (bound == 'today') return DateTime(today.year, today.month, today.day);
    final parsed = DateTime.tryParse(bound);
    return parsed == null ? null : DateTime(parsed.year, parsed.month, parsed.day);
  }

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
        minLength: (json['min_length'] as num?)?.toInt(),
        minValue: json['min_value'] as num?,
        maxValue: json['max_value'] as num?,
        maxDigits: (json['max_digits'] as num?)?.toInt(),
        decimalPlaces: (json['decimal_places'] as num?)?.toInt(),
        pattern: json['pattern']?.toString(),
        patterns: ((json['patterns'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PatternRule.fromJson(Map<String, dynamic>.from(e)))
            .where((p) => p.pattern.isNotEmpty)
            .toList(),
        minDate: json['min_date']?.toString(),
        maxDate: json['max_date']?.toString(),
        choices: ((json['choices'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ChoiceOption.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        choicesRef: json['choices_ref']?.toString(),
        ref: json['ref']?.toString(),
        script: json['script']?.toString(),
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
        if (minLength != null) 'min_length': minLength,
        if (minValue != null) 'min_value': minValue,
        if (maxValue != null) 'max_value': maxValue,
        if (maxDigits != null) 'max_digits': maxDigits,
        if (decimalPlaces != null) 'decimal_places': decimalPlaces,
        if (pattern != null) 'pattern': pattern,
        if (patterns.isNotEmpty) 'patterns': patterns.map((p) => p.toJson()).toList(),
        if (minDate != null) 'min_date': minDate,
        if (maxDate != null) 'max_date': maxDate,
        if (choices.isNotEmpty) 'choices': choices.map((c) => c.toJson()).toList(),
        if (choicesRef != null) 'choices_ref': choicesRef,
        if (ref != null) 'ref': ref,
        if (script != null) 'script': script,
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
  const RevealRule({
    required this.field,
    required this.show,
    this.inValues,
    this.notInValues,
    this.labelContains,
    this.require = false,
  });

  final String field;
  final List<String> show;

  /// Whether the revealed fields are REQUIRED while the rule holds.
  ///
  /// A reveal used to mean visibility only, but several rules are really
  /// conditional requirements: a reason for closing matters only on a day
  /// off, and a reason for absence only for a child marked absent. Without
  /// this the two would have to be `required: true` and then hidden, which
  /// would block every sheet that is not a day off.
  final bool require;
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
      require: json['require'] == true,
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
        if (require) 'require': true,
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
    this.rowFields = const [],
    this.rowReveals = const [],
    this.rowKey,
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

  /// Fields of ONE repeated row, for an entity that carries a roster: the
  /// per-child line of an attendance sheet. [fields] describes the header.
  final List<FieldSpec> rowFields;
  final List<RevealRule> rowReveals;

  /// Key under which the rows live in the record: `children_attendance` or
  /// `teachers_attendance`.
  final String? rowKey;

  /// The row schema as a schema in its own right, so one validator handles
  /// both the header and each row rather than growing a second code path.
  EntitySchema get rowSchema =>
      _rowSchemas[this] ??= EntitySchema(
        key: '$key#row',
        module: module,
        label: label,
        kind: kind,
        fields: rowFields,
        sections: const [],
        reveals: rowReveals,
      );

  static final Expando<EntitySchema> _rowSchemas = Expando<EntitySchema>('rowSchema');

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
        rowFields: ((json['row_fields'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => FieldSpec.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        rowReveals: ((json['row_reveals'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => RevealRule.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        rowKey: json['row_key']?.toString(),
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
        if (rowFields.isNotEmpty) 'row_fields': rowFields.map((f) => f.toJson()).toList(),
        if (rowReveals.isNotEmpty) 'row_reveals': rowReveals.map((r) => r.toJson()).toList(),
        if (rowKey != null) 'row_key': rowKey,
      };
}
