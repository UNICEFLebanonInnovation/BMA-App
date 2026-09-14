import 'package:bma_app/core/forms/schema_form_controller.dart';
import 'package:bma_app/core/models/form_schema.dart';
import 'package:flutter_test/flutter_test.dart';

EntitySchema _schema() => EntitySchema.fromJson({
      'key': 'mscc.registration',
      'module': 'mscc',
      'label': 'Registration',
      'kind': 'identity',
      'identity': true,
      'wizard': true,
      'fields': [
        {'name': 'child_first_name', 'label': 'First name', 'type': 'text', 'required': true, 'max_length': 5},
        {
          'name': 'child_gender',
          'label': 'Gender',
          'type': 'select',
          'required': true,
          'choices': [
            {'value': '', 'label': '----'},
            {'value': 'Male', 'label': 'Male'},
            {'value': 'Female', 'label': 'Female'},
          ],
        },
        {'name': 'have_labour', 'label': 'Labour', 'type': 'select', 'choices': [
          {'value': 'No', 'label': 'No'}, {'value': 'Yes - Morning', 'label': 'Yes - Morning'}]},
        {'name': 'labour_hours', 'label': 'Hours', 'type': 'number', 'required': true, 'min_value': 1},
        {'name': 'first_phone_number', 'label': 'Phone', 'type': 'text', 'pattern': r'^\d{2}-\d{6}$'},
        {'name': 'first_phone_number_confirm', 'label': 'Confirm phone', 'type': 'text'},
        {'name': 'registration_date', 'label': 'Date', 'type': 'date'},
        {'name': 'child_nationality', 'label': 'Nationality', 'type': 'ref', 'ref': 'nationalities'},
        {'name': 'child_nationality_other', 'label': 'Other nationality', 'type': 'text', 'required': true},
        {'name': 'student_old', 'label': 'Old', 'type': 'hidden'},
      ],
      'sections': [
        {'key': 'identity', 'label': 'Identity', 'fields': ['child_first_name', 'child_gender', 'child_nationality', 'child_nationality_other']},
        {'key': 'labour', 'label': 'Labour', 'fields': ['have_labour', 'labour_hours', 'first_phone_number', 'first_phone_number_confirm', 'registration_date']},
      ],
      'reveals': [
        {'when': {'field': 'have_labour', 'not_in': ['', 'No']}, 'show': ['labour_hours']},
        {'when': {'field': 'child_nationality', 'in': ['6']}, 'show': ['child_nationality_other']},
      ],
    });

void main() {
  test('parses schema, sections and reveals', () {
    final schema = _schema();
    expect(schema.fields.length, 10);
    expect(schema.sections.map((s) => s.key), ['identity', 'labour']);
    expect(schema.reveals.length, 2);
    expect(schema.field('child_gender')!.choices.length, 3);
    expect(schema.field('student_old')!.isHidden, isTrue);
  });

  test('hidden fields follow reveal rules and are not validated', () {
    final controller = SchemaFormController(schema: _schema(), initial: {
      'child_first_name': 'Ali',
      'child_gender': 'Male',
      'have_labour': 'No',
      'child_nationality': 2,
    });
    expect(controller.hiddenFields, {'labour_hours', 'child_nationality_other'});
    expect(controller.validate(), isTrue);

    controller.setValue('have_labour', 'Yes - Morning');
    expect(controller.hiddenFields, {'child_nationality_other'});
    expect(controller.validate(), isFalse);
    expect(controller.errorsFor('labour_hours'), isNotEmpty);

    controller.setValue('labour_hours', '0');
    expect(controller.validate(), isFalse); // below min_value
    controller.setValue('labour_hours', '12');
    expect(controller.validate(), isTrue);

    controller.setValue('child_nationality', 6);
    expect(controller.validate(), isFalse);
    expect(controller.errorsFor('child_nationality_other'), isNotEmpty);
  });

  test('validates required, max length, pattern, date and confirm twins', () {
    final controller = SchemaFormController(schema: _schema(), initial: {
      'child_first_name': 'Mohamad-too-long',
      'child_gender': '',
      'have_labour': 'No',
      'first_phone_number': '03-123456',
      'first_phone_number_confirm': '03-654321',
      'registration_date': '2026/01/01',
    });
    expect(controller.validate(), isFalse);
    expect(controller.errorsFor('child_first_name'), isNotEmpty);
    expect(controller.errorsFor('child_gender'), isNotEmpty);
    expect(controller.errorsFor('first_phone_number_confirm'), isNotEmpty);
    expect(controller.errorsFor('registration_date'), isNotEmpty);

    controller.setValue('first_phone_number', '3-1');
    controller.validate();
    expect(controller.errorsFor('first_phone_number'), isNotEmpty);
  });

  test('collect drops values of hidden conditional fields', () {
    final controller = SchemaFormController(schema: _schema(), initial: {
      'child_first_name': 'Ali',
      'child_gender': 'Male',
      'have_labour': 'No',
      'labour_hours': '8',
      'child_nationality': 2,
      'child_nationality_other': 'stale',
    });
    final values = controller.collect();
    expect(values.containsKey('labour_hours'), isFalse);
    expect(values.containsKey('child_nationality_other'), isFalse);
    expect(values['child_first_name'], 'Ali');
  });

  test('server errors are shown alongside client errors', () {
    final controller = SchemaFormController(
      schema: _schema(),
      initial: {'child_first_name': 'Ali', 'child_gender': 'Male', 'have_labour': 'No'},
      serverErrors: {'child_first_name': ['Only letters are allowed.'], '__all__': 'Something'},
    );
    expect(controller.errorsFor('child_first_name'), ['Only letters are allowed.']);
    expect(controller.generalErrors, ['Something']);
    controller.setValue('child_first_name', 'Omar');
    expect(controller.errorsFor('child_first_name'), isEmpty);
  });
}
