import 'package:bma_app/core/forms/schema_form_controller.dart';
import 'package:bma_app/core/models/form_schema.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rules every schema-driven form applies. Each of these was silently
/// unenforced before: the value saved on the device, then failed on push.
void main() {
  SchemaFormController make(
    List<FieldSpec> fields, {
    Map<String, dynamic> values = const {},
    List<RevealRule> reveals = const [],
    AllowedValuesResolver? allowed,
    DateTime Function()? clock,
  }) =>
      SchemaFormController(
        schema: EntitySchema(
          key: 'test',
          module: 'mscc',
          label: 'Test',
          kind: 'form',
          fields: fields,
          sections: const [],
          reveals: reveals,
        ),
        initial: values,
        allowedValues: allowed,
        clock: clock,
      );

  group('letters-only names (the thirteen fields the export used to drop)', () {
    // The pattern and message the server attaches via only_letters_validator.
    const namePattern = r'^[A-Za-zء-يٮ-ۓ\s]+$';
    final field = FieldSpec(
      name: 'child_first_name',
      label: "Child's First Name",
      type: 'text',
      required: true,
      patterns: const [
        PatternRule(
          pattern: namePattern,
          message: 'Only alphabetic characters are allowed.',
          messageAr: 'يُسمح بالأحرف الأبجدية فقط.',
        ),
      ],
    );

    test('a Latin name passes', () {
      expect(make([field], values: {'child_first_name': 'Omar'}).validate(), isTrue);
    });

    test('an Arabic name passes', () {
      expect(make([field], values: {'child_first_name': 'محمد'}).validate(), isTrue);
    });

    test('a name with a digit is rejected, with the server wording', () {
      final c = make([field], values: {'child_first_name': 'Omar2'});
      expect(c.validate(), isFalse);
      expect(c.errorsFor('child_first_name'), ['Only alphabetic characters are allowed.']);
    });

    test('punctuation is rejected', () {
      expect(make([field], values: {'child_first_name': 'Omar!'}).validate(), isFalse);
    });

    test('the Arabic message is used when the interface is Arabic', () {
      final c = SchemaFormController(
        schema: EntitySchema(
            key: 't', module: 'mscc', label: 'T', kind: 'form', fields: [field], sections: const []),
        initial: const {'child_first_name': 'Omar2'},
        messages: const ValidationMessages(languageCode: 'ar'),
      )..validate();
      expect(c.errorsFor('child_first_name'), ['يُسمح بالأحرف الأبجدية فقط.']);
    });

    test('a pattern Dart cannot compile is ignored rather than failing everything', () {
      final broken = FieldSpec(
        name: 'x',
        label: 'X',
        type: 'text',
        patterns: const [PatternRule(pattern: r'(?<broken')],
      );
      expect(make([broken], values: {'x': 'anything'}).validate(), isTrue);
    });
  });

  group('choice membership', () {
    const field = FieldSpec(
      name: 'sex',
      label: 'Gender',
      type: 'select',
      choices: [ChoiceOption(value: 'Male', label: 'Male'), ChoiceOption(value: 'Female', label: 'Female')],
    );

    test('a listed value passes', () {
      expect(make([field], values: {'sex': 'Male'}).validate(), isTrue);
    });

    test('a value that is not on the list is rejected', () {
      expect(make([field], values: {'sex': 'Other'}).validate(), isFalse);
    });

    test('a ref is checked against the cached list', () {
      const ref = FieldSpec(name: 'nationality', label: 'Nationality', type: 'ref', ref: 'nationalities');
      expect(make([ref], values: {'nationality': 2}, allowed: (_) => {'1', '2'}).validate(), isTrue);
      expect(make([ref], values: {'nationality': 99}, allowed: (_) => {'1', '2'}).validate(), isFalse);
    });

    test('a list that is not on the device yet is not treated as invalid', () {
      const ref = FieldSpec(name: 'nationality', label: 'Nationality', type: 'ref', ref: 'nationalities');
      expect(make([ref], values: {'nationality': 99}, allowed: (_) => null).validate(), isTrue);
    });

    test('a multiselect rejects one bad member', () {
      const multi = FieldSpec(
        name: 'subjects',
        label: 'Subjects',
        type: 'multiselect',
        choices: [ChoiceOption(value: 'math', label: 'Math'), ChoiceOption(value: 'arabic', label: 'Arabic')],
      );
      expect(make([multi], values: {'subjects': ['math']}).validate(), isTrue);
      expect(make([multi], values: {'subjects': ['math', 'chemistry']}).validate(), isFalse);
    });
  });

  group('a required checkbox must actually be ticked', () {
    const consent = FieldSpec(name: 'consent', label: 'Consent', type: 'boolean', required: true);

    test('false is not a filled-in value', () {
      expect(make([consent], values: {'consent': false}).validate(), isFalse);
    });

    test('true passes', () {
      expect(make([consent], values: {'consent': true}).validate(), isTrue);
    });

    test('an OPTIONAL checkbox left unticked is fine', () {
      const optional = FieldSpec(name: 'flag', label: 'Flag', type: 'boolean');
      expect(make([optional], values: {'flag': false}).validate(), isTrue);
    });
  });

  group('numbers, lengths and dates', () {
    test('an integer honours both bounds', () {
      const age = FieldSpec(name: 'age', label: 'Age', type: 'number', minValue: 3, maxValue: 18);
      expect(make([age], values: {'age': '10'}).validate(), isTrue);
      expect(make([age], values: {'age': '2'}).validate(), isFalse);
      expect(make([age], values: {'age': '19'}).validate(), isFalse);
    });

    test('a decimal honours its places', () {
      const w = FieldSpec(name: 'weight', label: 'Weight', type: 'decimal', decimalPlaces: 2, maxValue: 200);
      expect(make([w], values: {'weight': '31.25'}).validate(), isTrue);
      expect(make([w], values: {'weight': '31.257'}).validate(), isFalse);
      expect(make([w], values: {'weight': '500'}).validate(), isFalse);
    });

    test('min and max length', () {
      const code = FieldSpec(name: 'code', label: 'Code', type: 'text', minLength: 3, maxLength: 5);
      expect(make([code], values: {'code': 'abcd'}).validate(), isTrue);
      expect(make([code], values: {'code': 'ab'}).validate(), isFalse);
      expect(make([code], values: {'code': 'abcdef'}).validate(), isFalse);
    });

    test('an email must look like one', () {
      const email = FieldSpec(name: 'email', label: 'Email', type: 'email');
      expect(make([email], values: {'email': 'hala@example.org'}).validate(), isTrue);
      expect(make([email], values: {'email': 'hala.example.org'}).validate(), isFalse);
      expect(make([email], values: {'email': 'hala@'}).validate(), isFalse);
    });

    test('a date bound of today rejects tomorrow', () {
      const d = FieldSpec(name: 'when', label: 'When', type: 'date', maxDate: 'today');
      DateTime clock() => DateTime(2026, 3, 12);
      expect(make([d], values: {'when': '2026-03-12'}, clock: clock).validate(), isTrue);
      expect(make([d], values: {'when': '2026-03-13'}, clock: clock).validate(), isFalse);
    });
  });

  group('a reveal can make a field required while it holds', () {
    final fields = [
      const FieldSpec(name: 'has_id', label: 'Has ID', type: 'select', choices: [
        ChoiceOption(value: 'Yes', label: 'Yes'),
        ChoiceOption(value: 'No', label: 'No'),
      ]),
      const FieldSpec(name: 'id_number', label: 'ID number', type: 'text'),
    ];
    const reveals = [RevealRule(field: 'has_id', show: ['id_number'], inValues: ['Yes'], require: true)];

    test('required while revealed', () {
      final c = make(fields, values: {'has_id': 'Yes'}, reveals: reveals);
      expect(c.validate(), isFalse);
      expect(c.errorsFor('id_number'), isNotEmpty);
    });

    test('not required while hidden', () {
      expect(make(fields, values: {'has_id': 'No'}, reveals: reveals).validate(), isTrue);
    });

    test('a reveal WITHOUT require only controls visibility', () {
      const soft = [RevealRule(field: 'has_id', show: ['id_number'], inValues: ['Yes'])];
      expect(make(fields, values: {'has_id': 'Yes'}, reveals: soft).validate(), isTrue);
    });
  });
}
