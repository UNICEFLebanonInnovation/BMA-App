import '../../core/forms/schema_form_controller.dart';
import '../../core/models/form_schema.dart';

/// Validation for an attendance sheet, using the same engine as every other
/// form in the app.
///
/// The sheet is not rendered by the schema engine -- a roster of 30 children
/// is a table, not a column of fields -- but there is no reason for it to be
/// validated by different rules, which is how it came to enforce three of the
/// server's five and, on the teacher sheet, none of them.
class AttendanceErrors {
  const AttendanceErrors({this.header = const {}, this.rows = const {}});

  /// Header field name -> messages.
  final Map<String, List<String>> header;

  /// Row index -> field name -> messages.
  final Map<int, Map<String, List<String>>> rows;

  bool get isEmpty => header.isEmpty && rows.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// How many ROWS have a problem. Used for "3 children need a reason",
  /// which is more useful than a count of messages.
  int get rowCount => rows.length;

  List<String> forHeader(String field) => header[field] ?? const [];

  /// The single message a compact control has room for.
  String? headerMessage(String field) {
    final messages = header[field];
    return (messages == null || messages.isEmpty) ? null : messages.first;
  }

  /// Drop a header field's errors, so fixing a value clears its complaint
  /// instead of leaving it red until the next save.
  AttendanceErrors withoutHeader(String field) {
    if (!header.containsKey(field)) return this;
    return AttendanceErrors(header: {...header}..remove(field), rows: rows);
  }

  /// Drop one row's errors, for the same reason.
  AttendanceErrors withoutRow(int index) {
    if (!rows.containsKey(index)) return this;
    return AttendanceErrors(header: header, rows: {...rows}..remove(index));
  }
  List<String> forRow(int index, String field) => rows[index]?[field] ?? const [];
  bool rowHasError(int index) => rows.containsKey(index);

  /// The first header message, for a screen that has room for only one line.
  String? get firstHeaderMessage {
    for (final messages in header.values) {
      if (messages.isNotEmpty) return messages.first;
    }
    return null;
  }
}

/// The one message a compact control has room for.
extension AttendanceMessageList on List<String> {
  String? get firstOrNullMessage => isEmpty ? null : first;
}

/// Validate a sheet. [rows] are the per-child (or per-teacher) maps exactly as
/// they are stored in the record, so what is checked is what is pushed.
AttendanceErrors validateAttendance({
  required EntitySchema schema,
  required Map<String, dynamic> header,
  required List<Map<String, dynamic>> rows,
  ValidationMessages messages = const ValidationMessages(),
  AllowedValuesResolver? allowedValues,
  DateTime Function()? clock,
}) {
  final headerController = SchemaFormController(
    schema: schema,
    initial: header,
    allowedValues: allowedValues,
    messages: messages,
    clock: clock,
  )..validate();

  final rowSchema = schema.rowSchema;
  final rowErrors = <int, Map<String, List<String>>>{};
  if (rowSchema.fields.isNotEmpty) {
    for (var i = 0; i < rows.length; i++) {
      final controller = SchemaFormController(
        schema: rowSchema,
        initial: rows[i],
        allowedValues: allowedValues,
        messages: messages,
        clock: clock,
      )..validate();
      if (controller.errors.isNotEmpty) {
        rowErrors[i] = Map<String, List<String>>.from(controller.errors);
      }
    }
  }
  return AttendanceErrors(header: Map<String, List<String>>.from(headerController.errors), rows: rowErrors);
}

/// The attendance rules, expressed client-side.
///
/// A device pulls its schemas from whatever server it is pointed at, and a
/// server that predates `row_fields` sends `fields: []` -- which would mean an
/// upgraded app silently validating nothing, a regression on the sheet that
/// used to check three rules by hand. So when the schema arrives empty the app
/// supplies the same description the server now sends, and there stays exactly
/// one set of rules rather than a schema path and a legacy path.
EntitySchema attendanceSchemaOrFallback(EntitySchema schema) {
  if (schema.fields.isNotEmpty || schema.rowFields.isNotEmpty) return schema;
  final teacher = schema.kind == 'teacher_attendance';
  final module = schema.module;
  return EntitySchema(
    key: schema.key,
    module: module,
    label: schema.label,
    kind: schema.kind,
    description: schema.description,
    sections: const [],
    fields: [
      const FieldSpec(
        name: 'attendance_date',
        label: 'Date',
        type: 'date',
        required: true,
        maxDate: 'today',
      ),
      if (!teacher) const FieldSpec(name: 'attendance_day_off', label: 'Day off', type: 'boolean'),
      if (!teacher)
        FieldSpec(
          name: 'close_reason',
          label: 'Reason for closing',
          type: 'select',
          choicesRef: '$module.attendance.close_reason',
        ),
    ],
    reveals: teacher
        ? const []
        : const [
            RevealRule(
              field: 'attendance_day_off',
              show: ['close_reason'],
              inValues: ['true', 'Yes', 'yes'],
              require: true,
            ),
          ],
    rowFields: [
      // A child row says attended Yes/No; a TEACHER row says status
      // Present/Absent. Different names and different values, because they are
      // different tables on the server -- and `create_teacher_attendance`
      // applies no required check, so neither does this.
      if (teacher)
        const FieldSpec(
          name: 'status',
          label: 'Status',
          type: 'select',
          choices: [
            ChoiceOption(value: 'Present', label: 'Present'),
            ChoiceOption(value: 'Absent', label: 'Absent'),
          ],
        ),
      if (!teacher)
        const FieldSpec(
          name: 'attended',
          label: 'Attendance',
          type: 'select',
          required: true,
          choices: [
            ChoiceOption(value: 'Yes', label: 'Present'),
            ChoiceOption(value: 'No', label: 'Absent'),
          ],
        ),
      if (!teacher)
        FieldSpec(
          name: 'absence_reason',
          label: 'Reason for absence',
          type: 'select',
          choicesRef: '$module.attendance.absence_reason',
        ),
      if (!teacher) const FieldSpec(name: 'absence_reason_other', label: 'Please specify', type: 'text'),
    ],
    rowReveals: teacher
        ? const []
        : const [
            RevealRule(field: 'attended', show: ['absence_reason'], inValues: ['No'], require: true),
            RevealRule(field: 'absence_reason', show: ['absence_reason_other'], inValues: ['Other'], require: true),
          ],
    rowKey: teacher ? 'teachers_attendance' : 'children_attendance',
  );
}
