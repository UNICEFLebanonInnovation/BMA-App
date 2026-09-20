// The form packer. Pure, synchronous, widget-free — it takes the list of
// fields SchemaForm has ALREADY filtered and returns the rows to render.
//
// THE CORRECTNESS BOUNDARY, restated here because this is the file someone
// will edit in a hurry: the packer REARRANGES fields, it never decides which
// fields exist. `SchemaFormController.collect()` drops the values of
// reveal-hidden fields, so a packer that kept a hidden field mounted to avoid
// a reflow would silently change the JSON pushed to the server — a data bug
// with no symptom on the device.

import '../models/form_schema.dart';

/// Packs [fields] into rows of at most [columns] cells, in source order.
///
/// Four rules, in the order they are applied to each field:
///
/// 1. REVEAL RUNS. A row break is forced immediately before and after every
///    contiguous run of [revealTargets] members. This is the reflow guard:
///    `mscc.registration` has 15 reveal rules and the controller notifies on
///    every keystroke, so without it a reveal would re-pair every field below
///    it and fields would jump under the operator's finger with a caregiver
///    waiting. The invariant it buys: the fields before the first reveal
///    target occupy the same (row, column) whether the reveal is on or off.
/// 2. FULL-ROW FIELDS. [FieldSpec.spansFullRow] fields (textarea,
///    multiselect, multiref, file, long help text) always occupy a row alone.
/// 3. CONFIRM TWINS. A `<base>_confirm` field that would start a new row
///    pulls its base field down with it, so the pair always reads as one
///    line — the 22 consecutive X/X_confirm pairs in the caregivers section
///    are the reason this rule exists.
/// 4. Otherwise: append, and flush when the row is full.
///
/// [columns] below 2 returns one row per field, which is what the compact
/// branch of `SchemaForm` uses (and never renders, because it takes the
/// untouched single-Column fast path instead).
List<List<FieldSpec>> packFields(
  List<FieldSpec> fields,
  int columns,
  Set<String> revealTargets,
) {
  final rows = <List<FieldSpec>>[];
  if (fields.isEmpty) return rows;
  if (columns < 2) return [for (final field in fields) [field]];

  var current = <FieldSpec>[];
  // null until the first field: the first field never forces a break.
  bool? previousWasTarget;

  void flush() {
    if (current.isEmpty) return;
    rows.add(current);
    current = <FieldSpec>[];
  }

  for (final field in fields) {
    final isTarget = revealTargets.contains(field.name);

    // (1) Entering or leaving a run of reveal targets.
    if (previousWasTarget != null && previousWasTarget != isTarget) flush();
    previousWasTarget = isTarget;

    // (2) A field that owns its row.
    if (field.spansFullRow) {
      flush();
      rows.add([field]);
      continue;
    }

    // (3) A twin that would start a new row takes its base field with it.
    // Never across a reveal boundary — a base and a twin on opposite sides of
    // one genuinely cannot share a line without breaking rule (1).
    if (field.pairsWithPrevious && current.isEmpty && rows.isNotEmpty) {
      final base = field.confirmBaseName;
      final previousRow = rows.last;
      if (previousRow.length > 1 &&
          previousRow.last.name == base &&
          revealTargets.contains(base) == isTarget) {
        current.add(previousRow.removeLast());
      }
    }

    // (4)
    current.add(field);
    if (current.length >= columns) flush();
  }
  flush();
  return rows;
}
