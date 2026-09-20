import 'package:bma_app/core/forms/field_layout.dart';
import 'package:bma_app/core/forms/schema_form_controller.dart';
import 'package:bma_app/core/models/form_schema.dart';
import 'package:flutter_test/flutter_test.dart';

/// COMMIT 4 — the form packer, as a pure unit.
///
/// `packFields` is the only new logic that all 25 server-driven schemas run
/// through, and it runs on every keystroke. Everything here is synchronous
/// and widget-free on purpose: the widget test next door proves the tree, and
/// this file proves the arithmetic that decides it.

FieldSpec f(String name, {String type = 'text', String help = '', bool required = false}) =>
    FieldSpec(name: name, label: name, type: type, helpText: help, required: required);

/// Flattened row/column index of every field, for position comparisons.
Map<String, (int, int)> positions(List<List<FieldSpec>> rows) {
  final result = <String, (int, int)>{};
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      result[rows[r][c].name] = (r, c);
    }
  }
  return result;
}

/// Column index of [name], or -1 when it is not packed at all.
int columnOf(List<List<FieldSpec>> rows, String name) {
  for (final row in rows) {
    final i = row.indexWhere((f) => f.name == name);
    if (i >= 0) return i;
  }
  return -1;
}

/// The names sharing a row with [name], including it.
List<String> rowMates(List<List<FieldSpec>> rows, String name) =>
    rows.firstWhere((r) => r.any((f) => f.name == name)).map((f) => f.name).toList();

List<String> flat(List<List<FieldSpec>> rows) => [for (final row in rows) ...row.map((f) => f.name)];

/// A registration-shaped schema: an always-visible identity section, then a
/// select that reveals a run of fields, then more always-visible fields, then
/// a second reveal. This is the shape that made the reflow guard necessary.
EntitySchema revealSchema() => EntitySchema.fromJson({
      'key': 'test.registration',
      'module': 'mscc',
      'label': 'Registration',
      'kind': 'identity',
      'fields': [
        {'name': 'first_name', 'label': 'First name', 'type': 'text'},
        {'name': 'last_name', 'label': 'Last name', 'type': 'text'},
        {'name': 'gender', 'label': 'Gender', 'type': 'select', 'choices': [
          {'value': 'M', 'label': 'M'}, {'value': 'F', 'label': 'F'}]},
        {'name': 'birth_date', 'label': 'Birth date', 'type': 'date'},
        {'name': 'id_type', 'label': 'ID type', 'type': 'select', 'choices': [
          {'value': 'none', 'label': 'None'}, {'value': 'unhcr', 'label': 'UNHCR'}]},
        {'name': 'id_number', 'label': 'ID number', 'type': 'text'},
        {'name': 'id_number_confirm', 'label': 'Confirm ID number', 'type': 'text'},
        {'name': 'id_issued', 'label': 'Issued', 'type': 'date'},
        {'name': 'phone', 'label': 'Phone', 'type': 'text'},
        {'name': 'phone_confirm', 'label': 'Confirm phone', 'type': 'text'},
        {'name': 'have_labour', 'label': 'Labour', 'type': 'select', 'choices': [
          {'value': 'no', 'label': 'No'}, {'value': 'yes', 'label': 'Yes'}]},
        {'name': 'labour_hours', 'label': 'Hours', 'type': 'number'},
        {'name': 'labour_kind', 'label': 'Kind', 'type': 'text'},
        {'name': 'notes', 'label': 'Notes', 'type': 'textarea'},
      ],
      'sections': [
        {
          'key': 'all',
          'label': 'All',
          'fields': [
            'first_name', 'last_name', 'gender', 'birth_date', 'id_type', 'id_number',
            'id_number_confirm', 'id_issued', 'phone', 'phone_confirm', 'have_labour',
            'labour_hours', 'labour_kind', 'notes',
          ],
        },
      ],
      'reveals': [
        {'when': {'field': 'id_type', 'not_in': ['', 'none']}, 'show': ['id_number', 'id_number_confirm', 'id_issued']},
        {'when': {'field': 'have_labour', 'in': ['yes']}, 'show': ['labour_hours', 'labour_kind']},
      ],
    });

/// The fields a real [SchemaForm] would hand the packer for [values].
List<FieldSpec> visible(EntitySchema schema, Map<String, dynamic> values) {
  final controller = SchemaFormController(schema: schema, initial: values);
  return schema.sections.single.fields
      .map(schema.field)
      .whereType<FieldSpec>()
      .where(controller.isVisible)
      .toList();
}

void main() {
  group('the layout members on the schema', () {
    test('spansFullRow is true for the four wide types and for a long help text', () {
      for (final type in ['textarea', 'multiselect', 'multiref', 'file']) {
        expect(f('x', type: type).spansFullRow, isTrue, reason: type);
      }
      for (final type in ['text', 'email', 'number', 'decimal', 'date', 'boolean', 'select', 'ref']) {
        expect(f('x', type: type).spansFullRow, isFalse, reason: type);
      }
      expect(f('x', help: 'a' * 60).spansFullRow, isFalse);
      expect(f('x', help: 'a' * 61).spansFullRow, isTrue);
    });

    test('pairsWithPrevious is the _confirm suffix rule the controller already uses', () {
      expect(f('phone_confirm').pairsWithPrevious, isTrue);
      expect(f('phone_confirm').confirmBaseName, 'phone');
      expect(f('phone').pairsWithPrevious, isFalse);
      expect(f('phone').confirmBaseName, isNull);
      expect(f('confirmation').pairsWithPrevious, isFalse);
    });

    test('revealTargets is the union of every rule and is cached and unmodifiable', () {
      final schema = revealSchema();
      expect(
        schema.revealTargets,
        {'id_number', 'id_number_confirm', 'id_issued', 'labour_hours', 'labour_kind'},
      );
      // Cached: the packer asks once per build, per section, on every keystroke.
      expect(identical(schema.revealTargets, schema.revealTargets), isTrue);
      expect(() => schema.revealTargets.add('x'), throwsUnsupportedError);
      // A schema without reveal rules answers with an empty set, not null.
      expect(EntitySchema.fromJson({'key': 'k', 'label': 'l'}).revealTargets, isEmpty);
    });
  });

  group('packFields basics', () {
    test('one column gives one row per field, in source order', () {
      final fields = [f('a'), f('b'), f('c')];
      expect(packFields(fields, 1, const {}).map((r) => r.single.name), ['a', 'b', 'c']);
      // 0 and negatives are defensive, not reachable: formColumns clamps at 1.
      expect(packFields(fields, 0, const {}).length, 3);
    });

    test('an empty field list packs to no rows at all', () {
      expect(packFields(const [], 3, const {}), isEmpty);
    });

    test('source order is preserved for every column count and reveal set', () {
      final schema = revealSchema();
      final fields = visible(schema, {'id_type': 'unhcr', 'have_labour': 'yes'});
      final names = fields.map((f) => f.name).toList();
      for (final columns in [1, 2, 3, 4]) {
        for (final targets in [<String>{}, schema.revealTargets]) {
          expect(flat(packFields(fields, columns, targets)), names,
              reason: 'columns=$columns targets=${targets.length}');
        }
      }
    });

    test('no row is ever wider than the column count', () {
      final fields = [for (var i = 0; i < 20; i++) f('f$i')];
      for (final columns in [2, 3, 4]) {
        for (final row in packFields(fields, columns, const {})) {
          expect(row.length, lessThanOrEqualTo(columns));
        }
      }
    });

    test('a plain run fills rows left to right and leaves the last one short', () {
      final rows = packFields([f('a'), f('b'), f('c'), f('d'), f('e')], 3, const {});
      expect(rows.map((r) => r.map((f) => f.name).toList()), [
        ['a', 'b', 'c'],
        ['d', 'e'],
      ]);
    });
  });

  group('full-row fields', () {
    test('a wide field occupies a row alone and does not disturb its neighbours', () {
      final rows = packFields(
        [f('a'), f('notes', type: 'textarea'), f('b'), f('c')],
        2,
        const {},
      );
      expect(rows.map((r) => r.map((f) => f.name).toList()), [
        ['a'],
        ['notes'],
        ['b', 'c'],
      ]);
    });

    test('a long help text is enough to claim the row', () {
      final rows = packFields([f('a'), f('b', help: 'x' * 80), f('c')], 2, const {});
      expect(rows.map((r) => r.map((f) => f.name).toList()), [
        ['a'],
        ['b'],
        ['c'],
      ]);
    });

    test('consecutive wide fields each get their own row', () {
      final rows = packFields(
        [f('m', type: 'multiselect'), f('n', type: 'multiref'), f('o', type: 'file')],
        3,
        const {},
      );
      expect(rows.length, 3);
    });
  });

  group('confirm twins', () {
    test('a twin that would start a new row pulls its base down with it', () {
      // Without the rule this packs as [a, phone] / [phone_confirm].
      final rows = packFields([f('a'), f('phone'), f('phone_confirm')], 2, const {});
      expect(rows.map((r) => r.map((f) => f.name).toList()), [
        ['a'],
        ['phone', 'phone_confirm'],
      ]);
    });

    test('a twin already in the same row is left where it is', () {
      final rows = packFields([f('phone'), f('phone_confirm'), f('a')], 2, const {});
      expect(rows.map((r) => r.map((f) => f.name).toList()), [
        ['phone', 'phone_confirm'],
        ['a'],
      ]);
    });

    test('the caregivers shape: 22 consecutive pairs land as 22 clean rows at two columns', () {
      final fields = [
        for (var i = 0; i < 22; i++) ...[f('c$i'), f('c${i}_confirm')],
      ];
      final rows = packFields(fields, 2, const {});
      expect(rows.length, 22);
      for (var i = 0; i < 22; i++) {
        expect(rows[i].map((f) => f.name).toList(), ['c$i', 'c${i}_confirm']);
      }
    });

    test('a twin whose base is not the preceding field is packed normally', () {
      // `other_confirm` has no `other` above it, so there is nothing to pull.
      final rows = packFields([f('a'), f('b'), f('other_confirm')], 2, const {});
      expect(rows.map((r) => r.map((f) => f.name).toList()), [
        ['a', 'b'],
        ['other_confirm'],
      ]);
    });

    test('a twin never drags its base across a reveal boundary', () {
      // `id_number` is revealed, `phone` is not: pulling would put a revealed
      // field and an always-visible one in one row and break the guard below.
      final rows = packFields(
        [f('phone'), f('phone_confirm')],
        2,
        const {'phone_confirm'},
      );
      expect(rows.map((r) => r.map((f) => f.name).toList()), [
        ['phone'],
        ['phone_confirm'],
      ]);
    });
  });

  group('THE REVEAL INVARIANT — nothing above a reveal point may move', () {
    final schema = revealSchema();
    final off = visible(schema, {'id_type': 'none', 'have_labour': 'no'});
    final on = visible(schema, {'id_type': 'unhcr', 'have_labour': 'yes'});
    // Source index of the first field any rule can reveal. Computed from the
    // SCHEMA, not from `off`, where the targets are exactly what is missing.
    final firstTarget = schema.sections.single.fields.indexWhere(schema.revealTargets.contains);
    final aboveTheReveal = schema.sections.single.fields.take(firstTarget).toList();

    test('the fixture really does reveal five fields', () {
      expect(on.length - off.length, 5);
      expect(off.map((f) => f.name), isNot(contains('id_number')));
      expect(on.map((f) => f.name), contains('id_number'));
      expect(aboveTheReveal, ['first_name', 'last_name', 'gender', 'birth_date', 'id_type']);
    });

    for (final columns in [2, 3]) {
      test('at $columns columns every field above the first reveal target keeps its exact (row, column)', () {
        final before = positions(packFields(off, columns, schema.revealTargets));
        final after = positions(packFields(on, columns, schema.revealTargets));
        for (final name in aboveTheReveal) {
          expect(after[name], before[name], reason: '$name moved when the reveal flipped');
        }
      });

      test('at $columns columns the fields BELOW a reveal keep their column and their row-mates', () {
        // They cannot keep their row INDEX — revealing five fields inserts
        // rows above them, and pushing the rest of the form down is the whole
        // point of a reveal. What must not happen is re-pairing: a field
        // changing column, or landing beside a different field, is what makes
        // the form jump sideways under the operator's finger.
        final before = packFields(off, columns, schema.revealTargets);
        final after = packFields(on, columns, schema.revealTargets);
        for (final name in ['phone', 'phone_confirm', 'have_labour', 'notes']) {
          expect(columnOf(after, name), columnOf(before, name), reason: '$name changed column');
          expect(rowMates(after, name), rowMates(before, name), reason: '$name changed neighbours');
        }
      });
    }

    test('the guard is doing work: without it, a one-field reveal re-pairs everything below', () {
      final fields = [f('a'), f('b'), f('target'), f('c'), f('d')];
      final without = [f('a'), f('b'), f('c'), f('d')];
      // Reveal off, both ways: [a, b] / [c, d].
      expect(columnOf(packFields(without, 2, const {'target'}), 'c'), 0);
      // Reveal on, WITH the guard: [a, b] / [target] / [c, d] — c stays first.
      expect(columnOf(packFields(fields, 2, const {'target'}), 'c'), 0);
      // Reveal on, WITHOUT it: [a, b] / [target, c] / [d] — c slides into the
      // second column and sits next to a field it has nothing to do with.
      expect(columnOf(packFields(fields, 2, const {}), 'c'), 1);
      expect(rowMates(packFields(fields, 2, const {}), 'c'), ['target', 'c']);
    });

    test('a reveal run is separated from its neighbours by a row break', () {
      final rows = packFields(on, 3, schema.revealTargets);
      for (final row in rows) {
        final targets = row.where((f) => schema.revealTargets.contains(f.name)).length;
        expect(targets == 0 || targets == row.length, isTrue,
            reason: 'row ${row.map((f) => f.name)} mixes revealed and always-visible fields');
      }
    });

    test('within a run the revealed fields still pack among themselves', () {
      final rows = packFields(on, 3, schema.revealTargets);
      final idRow = rows.firstWhere((r) => r.first.name == 'id_number');
      // id_number / id_number_confirm / id_issued are one run of three.
      expect(idRow.map((f) => f.name).toList(), ['id_number', 'id_number_confirm', 'id_issued']);
    });
  });
}
