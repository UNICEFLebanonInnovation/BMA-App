// The website requires a child's and a caregiver's name in ARABIC.
//
// The rule is not a Django validator: it is checkArabicOnly() in
// static/js/validator.js, bound on blur to the `arabic_fields` lists in
// mscc.js, alp.js, registrations.js, bridging.js and project.js. It accepts
// U+0600-U+06FF or a space and silently discards everything else.
//
// The app reaches the same end state -- only Arabic is ever stored -- but by
// blocking the keystroke rather than deleting text that is already on screen.
// Stripping on blur empties the field entirely when the whole name was typed
// in Latin, which offline is lost data rather than a re-typed field.
import 'package:bma_app/core/forms/schema_form_controller.dart';
import 'package:bma_app/core/forms/script_input.dart';
import 'package:bma_app/core/models/form_schema.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const muhammad = 'محمد';
  const ali = 'علي';

  group('the pattern matches the website character for character', () {
    test('Arabic letters pass', () {
      expect(isArabicOnly(muhammad), isTrue);
      expect(isArabicOnly('$muhammad $ali'), isTrue, reason: 'space is allowed');
    });

    test('Arabic-Indic digits and punctuation pass, because 1536..1791 includes them', () {
      expect(isArabicOnly('٣٤'), isTrue);
      expect(isArabicOnly('محمد، علي'), isTrue);
    });

    test('Latin, Western digits and symbols do not', () {
      for (final bad in ['Omar', '${muhammad}x', '$muhammad 2', '$muhammad!', 'محمد-علي', '']) {
        expect(isArabicOnly(bad), isFalse, reason: bad);
      }
    });
  });

  group('the formatter blocks instead of deleting', () {
    const f = ArabicOnlyFormatter();
    TextEditingValue v(String text, [int? at]) =>
        TextEditingValue(text: text, selection: TextSelection.collapsed(offset: at ?? text.length));

    test('an Arabic keystroke is kept', () {
      expect(f.formatEditUpdate(v(''), v(muhammad)).text, muhammad);
    });

    test('a Latin keystroke never appears', () {
      expect(f.formatEditUpdate(v(muhammad), v('${muhammad}x')).text, muhammad);
    });

    test('text already typed is never rewritten by a rejected keystroke', () {
      final out = f.formatEditUpdate(v(muhammad), v('${muhammad}9'));
      expect(out.text, muhammad, reason: 'the name survives');
      expect(out.selection.baseOffset, muhammad.length, reason: 'the caret stays put');
    });

    test('a paste keeps the Arabic and drops the rest', () {
      expect(f.formatEditUpdate(v(''), v('Omar $muhammad 12')).text, ' $muhammad ');
    });

    test('deleting still works', () {
      expect(f.formatEditUpdate(v(muhammad), v('محم')).text, 'محم');
      expect(f.formatEditUpdate(v(muhammad), v('')).text, '');
    });

    test('the caret lands after the kept text when a paste is filtered', () {
      final out = f.formatEditUpdate(v(''), v('ab$muhammad', 2 + muhammad.length));
      expect(out.text, muhammad);
      expect(out.selection.baseOffset, muhammad.length);
    });
  });

  group('the validator enforces it on values the formatter never saw', () {
    // A pulled record, a merge or a restored draft all bypass the keyboard.
    SchemaFormController controllerFor(String value) => SchemaFormController(
          schema: const EntitySchema(
            key: 'mscc.registration',
            module: 'mscc',
            label: 'Registration',
            kind: 'identity',
            sections: [],
            fields: [
              FieldSpec(
                name: 'child_first_name',
                label: "Child's First Name",
                type: 'text',
                required: true,
                script: 'arabic',
                patterns: [
                  PatternRule(
                    pattern: arabicOnlyPattern,
                    message: 'Please write this in Arabic.',
                    messageAr: 'يرجى الكتابة بالعربية.',
                  ),
                ],
              ),
            ],
          ),
          initial: {'child_first_name': value},
        );

    test('an Arabic name passes', () {
      expect(controllerFor(muhammad).validate(), isTrue);
    });

    test('a Latin name the worker typed is rejected with the reason', () {
      final c = controllerFor('')..setValue('child_first_name', 'Omar');
      expect(c.validate(), isFalse);
      expect(c.errorsFor('child_first_name'), ['Please write this in Arabic.']);
    });

    test('a name that is mostly Arabic is still rejected', () {
      final c = controllerFor('')..setValue('child_first_name', '${muhammad}x');
      expect(c.validate(), isFalse);
    });

    test('a Latin name ALREADY on the record is left alone', () {
      // The website behaves this way too: Django accepts a Latin name and only
      // the on-blur JS strips it, so a record the worker never touched saves
      // unchanged. Twelve of the twenty-eight names in a real pull are Latin.
      final c = controllerFor('Omar');
      expect(c.validate(), isTrue, reason: 'an untouched pulled value must not block an unrelated edit');
    });

    test('but editing it holds the worker to the rule', () {
      final c = controllerFor('Omar')..setValue('child_first_name', 'Omar2');
      expect(c.validate(), isFalse);
      expect(c.errorsFor('child_first_name'), ['Please write this in Arabic.']);
    });

    test('and replacing it with Arabic is accepted', () {
      final c = controllerFor('Omar')..setValue('child_first_name', muhammad);
      expect(c.validate(), isTrue);
    });

    test('a NEW record is held to the rule from the first keystroke', () {
      final c = SchemaFormController(
        schema: controllerFor('').schema,
        initial: const {},
      )..setValue('child_first_name', 'Omar');
      expect(c.validate(), isFalse);
    });

    test('the schema flag and the pattern agree', () {
      final field = controllerFor(muhammad).schema.fields.first;
      expect(field.isArabicOnly, isTrue);
      expect(field.effectivePatterns.single.pattern, arabicOnlyPattern);
    });
  });

  group('the shipped bootstrap marks the right fields', () {
    test('a field with no script flag is unaffected', () {
      const plain = FieldSpec(name: 'child_address', label: 'Address', type: 'text');
      expect(plain.isArabicOnly, isFalse);
    });
  });
}
