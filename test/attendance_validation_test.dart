import 'package:bma_app/core/forms/schema_form_controller.dart';
import 'package:bma_app/core/models/form_schema.dart';
import 'package:bma_app/features/attendance/attendance_validation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The five rules `engine._validate_attendance_common` enforces on the server,
/// checked here so a worker meets them while the children are still in front
/// of them rather than in a push report hours later.
void main() {
  EntitySchema emptyAttendance({String kind = 'attendance', String module = 'mscc'}) => EntitySchema(
        key: '$module.attendance_day',
        module: module,
        label: 'Attendance day',
        kind: kind,
        fields: const [],
        sections: const [],
      );

  final schema = attendanceSchemaOrFallback(emptyAttendance());
  DateTime clock() => DateTime(2026, 3, 12);

  AttendanceErrors run({
    String date = '2026-03-11',
    bool dayOff = false,
    String closeReason = '',
    List<Map<String, dynamic>> rows = const [],
    Set<String>? reasons,
  }) =>
      validateAttendance(
        schema: schema,
        header: {
          'attendance_date': date,
          'attendance_day_off': dayOff,
          'close_reason': closeReason,
        },
        rows: rows,
        clock: clock,
        allowedValues: (field) => field.choicesRef == null ? null : (reasons ?? {'Sick', 'Other'}),
      );

  Map<String, dynamic> row({String attended = 'Yes', String reason = '', String other = ''}) =>
      {'attended': attended, 'absence_reason': reason, 'absence_reason_other': other};

  group('the sheet the server would accept', () {
    test('a plain present-and-absent sheet passes', () {
      final errors = run(rows: [row(), row(attended: 'No', reason: 'Sick')]);
      expect(errors.isEmpty, isTrue, reason: errors.rows.toString());
    });

    test('a day off with a reason passes, and its empty roster is not examined', () {
      expect(run(dayOff: true, closeReason: 'Holiday', reasons: {'Holiday'}).isEmpty, isTrue);
    });
  });

  group('the rules', () {
    test('the date cannot be in the future', () {
      expect(run(date: '2026-03-13').forHeader('attendance_date'), isNotEmpty);
      expect(run(date: '2026-03-12').forHeader('attendance_date'), isEmpty, reason: 'today is allowed');
    });

    test('a malformed date is rejected', () {
      expect(run(date: '12/03/2026').forHeader('attendance_date'), isNotEmpty);
    });

    test('the date is required', () {
      expect(run(date: '').forHeader('attendance_date'), isNotEmpty);
    });

    test('a day off needs a reason for closing', () {
      expect(run(dayOff: true).forHeader('close_reason'), isNotEmpty);
    });

    test('a reason for closing is NOT required when it is not a day off', () {
      expect(run(dayOff: false).forHeader('close_reason'), isEmpty);
    });

    test('an absent child needs a reason', () {
      final errors = run(rows: [row(), row(attended: 'No')]);
      expect(errors.forRow(1, 'absence_reason'), isNotEmpty);
      expect(errors.rowHasError(0), isFalse, reason: 'the present child is fine');
      expect(errors.rowCount, 1);
    });

    test('"Other" needs the free-text detail', () {
      expect(run(rows: [row(attended: 'No', reason: 'Other')]).forRow(0, 'absence_reason_other'), isNotEmpty);
      expect(run(rows: [row(attended: 'No', reason: 'Other', other: 'Moved away')]).isEmpty, isTrue);
    });

    test('a reason the server does not offer is rejected', () {
      expect(run(rows: [row(attended: 'No', reason: 'Raining')]).forRow(0, 'absence_reason'), isNotEmpty);
    });

    test('a reason list that has not been pulled yet is NOT treated as invalid', () {
      final errors = validateAttendance(
        schema: schema,
        header: const {'attendance_date': '2026-03-11', 'attendance_day_off': false},
        rows: [row(attended: 'No', reason: 'Sick')],
        clock: clock,
        allowedValues: (field) => null, // nothing cached
      );
      expect(errors.isEmpty, isTrue, reason: 'offline must not mean every row is wrong');
    });
  });

  group('the teacher sheet', () {
    final teacherSchema = attendanceSchemaOrFallback(emptyAttendance(kind: 'teacher_attendance', module: 'alp'));

    test('a full sheet of Present teachers passes, since status is not required', () {
      final errors = validateAttendance(
        schema: teacherSchema,
        header: const {'attendance_date': '2026-03-11'},
        rows: const [{'status': 'Present'}, {'status': 'Absent'}, {}],
        clock: clock,
      );
      expect(errors.isEmpty, isTrue, reason: errors.rows.toString());
    });

    test('a status the model does not offer is rejected', () {
      final errors = validateAttendance(
        schema: teacherSchema,
        header: const {'attendance_date': '2026-03-11'},
        rows: const [{'status': 'Maybe'}],
        clock: clock,
      );
      expect(errors.forRow(0, 'status'), isNotEmpty);
    });

    test('carries the date rule that the screen enforced nowhere', () {
      final errors = validateAttendance(
        schema: teacherSchema,
        header: const {'attendance_date': '2026-03-13'},
        rows: const [],
        clock: clock,
      );
      expect(errors.forHeader('attendance_date'), isNotEmpty);
    });

    test('has no day-off or absence-reason rules, which it does not have on the server either', () {
      expect(teacherSchema.fields.map((f) => f.name), ['attendance_date']);
      // `status`, not `attended`: a teacher row is a different table, and the
      // screen writes Present/Absent under that key.
      expect(teacherSchema.rowFields.map((f) => f.name), ['status']);
      expect(teacherSchema.rowKey, 'teachers_attendance');
    });
  });

  group('the server schema wins when it sends one', () {
    test('a schema with fields is returned untouched', () {
      final fromServer = EntitySchema(
        key: 'mscc.attendance_day',
        module: 'mscc',
        label: 'Attendance day',
        kind: 'attendance',
        fields: const [FieldSpec(name: 'attendance_date', label: 'Date', type: 'date', required: true)],
        sections: const [],
      );
      expect(identical(attendanceSchemaOrFallback(fromServer), fromServer), isTrue);
    });
  });

  group('messages are the localised ones', () {
    test('the future-date message comes from the injected set', () {
      final errors = validateAttendance(
        schema: schema,
        header: const {'attendance_date': '2030-01-01'},
        rows: const [],
        clock: clock,
        messages: const ValidationMessages(dateInFuture: 'لا يمكن أن يكون التاريخ في المستقبل.'),
      );
      expect(errors.forHeader('attendance_date').first, 'لا يمكن أن يكون التاريخ في المستقبل.');
    });
  });
}
