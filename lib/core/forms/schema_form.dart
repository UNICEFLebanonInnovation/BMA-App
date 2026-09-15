// Renders every server-driven form in the app. All 25 schemas funnel through
// the two `Column`s below, so read this header before changing either.
//
// THE PACKER CONTRACT
//
// * The packer REARRANGES fields; it never filters them. The visible list is
//   decided by `controller.isVisible` a few lines below, and
//   `SchemaFormController.collect()` drops the values of reveal-hidden fields
//   before they are stored. A packer that kept a hidden field mounted to
//   avoid a reflow would silently change the JSON pushed to the server — a
//   data bug with no symptom on the device and no failing test.
// * `ValueKey('field-<name>')` is load-bearing at runtime, not just in tests.
//   `_SchemaFieldWidgetState` owns a live `TextEditingController`; re-parenting
//   a field into a `Row`/`Expanded` cell is only safe because the key keeps
//   the `Element` matched. The rows and cells carry keys for the same reason:
//   inserting the general-error `Card` shifts every row by one, and keyless
//   rows would match by position and throw away the typing in them.
// * `packFields` forces a row break around every run of reveal targets so
//   that flipping a reveal can never move a field above it. See
//   `field_layout.dart`.
// * At one column the returned tree is the exact `Column` expression this
//   file had before the tablet work, so the phone cannot regress.

import 'package:flutter/material.dart';

import '../layout/app_layout.dart';
import '../models/form_schema.dart';
import 'field_layout.dart';
import 'field_widgets.dart';
import 'schema_form_controller.dart';

/// One item of the form's vertical flow: something that always spans the full
/// width, or a run of fields that the packer may put side by side.
sealed class _Block {
  const _Block();
}

class _WidgetBlock extends _Block {
  const _WidgetBlock(this.child);

  final Widget child;
}

class _TitleBlock extends _Block {
  const _TitleBlock(this.label);

  final String label;
}

class _FieldsBlock extends _Block {
  const _FieldsBlock(this.fields);

  final List<FieldSpec> fields;
}

/// Renders the fields of an [EntitySchema] (optionally only some sections)
/// bound to a [SchemaFormController]. Conditional fields are hidden
/// according to the schema's reveal rules.
class SchemaForm extends StatelessWidget {
  const SchemaForm({
    super.key,
    required this.controller,
    required this.languageCode,
    this.sectionKeys,
    this.readOnly = false,
    this.showSectionTitles = true,
    this.excludeFields = const {},
  });

  final SchemaFormController controller;
  final String languageCode;
  final List<String>? sectionKeys;
  final bool readOnly;
  final bool showSectionTitles;
  final Set<String> excludeFields;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final schema = controller.schema;
        final sections = schema.sections.where((s) => sectionKeys == null || sectionKeys!.contains(s.key)).toList();
        final blocks = <_Block>[];
        final general = controller.generalErrors;
        if (general.isNotEmpty) {
          blocks.add(_WidgetBlock(Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(general.join('\n'), style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
            ),
          )));
        }
        for (final section in sections) {
          final fields = section.fields
              .map(schema.field)
              .whereType<FieldSpec>()
              .where((f) => !excludeFields.contains(f.name) && controller.isVisible(f))
              .toList();
          if (fields.isEmpty) continue;
          if (showSectionTitles && sections.length > 1) {
            blocks.add(_TitleBlock(section.labelFor(languageCode)));
          }
          blocks.add(_FieldsBlock(fields));
        }
        // The column count comes from the BOX, never the window: a form
        // inside the 400 px list pane or the 360 px attendance session panel
        // correctly collapses to one column on a 1280 px tablet.
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = LayoutScope.of(context).formColumns(
              constraints.maxWidth,
              MediaQuery.textScalerOf(context),
            );
            if (columns == 1) {
              // THE ESCAPE HATCH: this is the expression that was here before
              // the tablet work, fed by the same flat children list. Compact
              // renders byte-identically, so every phone test keeps passing
              // for the right reason rather than by luck.
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _flat(context, blocks));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _packed(context, blocks, columns, schema.revealTargets),
            );
          },
        );
      },
    );
  }

  /// One field, wrapped exactly as it has always been wrapped.
  Widget _field(FieldSpec field) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SchemaFieldWidget(
          key: ValueKey('field-${field.name}'),
          field: field,
          controller: controller,
          languageCode: languageCode,
          readOnly: readOnly,
        ),
      );

  /// Today's flat list: titles and fields interleaved, one per row.
  List<Widget> _flat(BuildContext context, List<_Block> blocks) {
    final children = <Widget>[];
    for (final block in blocks) {
      switch (block) {
        case _WidgetBlock(:final child):
          children.add(child);
        case _TitleBlock(:final label):
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ));
        case _FieldsBlock(:final fields):
          for (final field in fields) {
            children.add(_field(field));
          }
      }
    }
    return children;
  }

  List<Widget> _packed(BuildContext context, List<_Block> blocks, int columns, Set<String> revealTargets) {
    final children = <Widget>[];
    for (final block in blocks) {
      switch (block) {
        case _WidgetBlock(:final child):
          children.add(child);
        case _TitleBlock(:final label):
          children.add(Padding(
            // 16 -> 24: once fields sit side by side the sections need more
            // air to still read as groups.
            padding: const EdgeInsets.fromLTRB(4, 24, 4, 4),
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ));
        case _FieldsBlock(:final fields):
          for (final row in packFields(fields, columns, revealTargets)) {
            children.add(_row(row, columns));
          }
      }
    }
    return children;
  }

  /// A `Row` of `Expanded` cells — NOT a `Wrap` of fixed-width boxes (a hard
  /// pixel width is exactly what breaks at 1.3x Arabic) and NOT a `GridView`
  /// (`helperMaxLines: 3` / `errorMaxLines: 3` make cell heights genuinely
  /// differ, and a fixed `childAspectRatio` would clip error text).
  /// `Row` honours `Directionality`, so RTL puts the first field on the right
  /// with no extra code.
  Widget _row(List<FieldSpec> row, int columns) {
    final key = ValueKey('form-row-${row.first.name}');
    if (row.length == 1 && row.first.spansFullRow) {
      return KeyedSubtree(key: key, child: _field(row.first));
    }
    final cells = <Widget>[];
    for (var i = 0; i < columns; i++) {
      if (i > 0) cells.add(const SizedBox(width: AppLayout.formGap));
      cells.add(i < row.length
          // Short rows are padded so that columns stay aligned down the page.
          ? Expanded(key: ValueKey('form-cell-${row[i].name}'), child: _field(row[i]))
          : const Expanded(child: SizedBox.shrink()));
    }
    return Row(key: key, crossAxisAlignment: CrossAxisAlignment.start, children: cells);
  }
}

/// Read-only summary of a form's values (review step, profile tab).
class SchemaReview extends StatelessWidget {
  const SchemaReview({
    super.key,
    required this.schema,
    required this.values,
    required this.languageCode,
    this.labelResolver,
    this.sectionKeys,
    this.dense = false,
  });

  final EntitySchema schema;
  final Map<String, dynamic> values;
  final String languageCode;
  final String? Function(FieldSpec field, Object? value)? labelResolver;
  final List<String>? sectionKeys;
  final bool dense;

  String _display(FieldSpec field, Object? value) {
    if (value == null || (value is String && value.isEmpty) || (value is List && value.isEmpty)) return '—';
    if (value is List) {
      return value.map((v) => _display(field, v)).join(', ');
    }
    if (labelResolver != null) {
      final resolved = labelResolver!(field, value);
      if (resolved != null) return resolved;
    }
    for (final c in field.choices) {
      if (c.value == value.toString()) return c.labelFor(languageCode);
    }
    if (value is bool) return value ? '✓' : '✗';
    return value.toString();
  }

  /// Review columns are decided by real width, not by the width class: the
  /// cells are a label and a value, far narrower than an input, so they fit
  /// 2-up from 1000 px and 3-up from 1400.
  static int reviewColumns(double available) {
    if (!available.isFinite) return 1;
    if (available >= 1400) return 3;
    if (available >= 1000) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final controller = SchemaFormController(schema: schema, initial: values, labelResolver: labelResolver);
    final hidden = controller.hiddenFields;
    final sections = schema.sections.where((s) => sectionKeys == null || sectionKeys!.contains(s.key)).toList();
    final blocks = <_Block>[];
    for (final section in sections) {
      final fields = section.fields
          .map(schema.field)
          .whereType<FieldSpec>()
          .where((f) => !f.isHidden && !hidden.contains(f.name))
          .toList();
      if (fields.isEmpty) continue;
      if (sections.length > 1) {
        blocks.add(_TitleBlock(section.labelFor(languageCode)));
      }
      blocks.add(_FieldsBlock(fields));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!LayoutScope.of(context).width.atLeastMedium) {
          // Unchanged tree: the same ListTiles in the same single Column.
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _flat(context, blocks));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _packed(context, blocks, reviewColumns(constraints.maxWidth)),
        );
      },
    );
  }

  Widget _tile(BuildContext context, FieldSpec field) => ListTile(
        dense: dense,
        contentPadding: EdgeInsets.zero,
        title: Text(field.labelFor(languageCode), style: Theme.of(context).textTheme.bodySmall),
        subtitle: Text(_display(field, values[field.name]), style: Theme.of(context).textTheme.bodyMedium),
      );

  List<Widget> _flat(BuildContext context, List<_Block> blocks) {
    final children = <Widget>[];
    for (final block in blocks) {
      switch (block) {
        case _WidgetBlock(:final child):
          children.add(child);
        case _TitleBlock(:final label):
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ));
        case _FieldsBlock(:final fields):
          for (final field in fields) {
            children.add(_tile(context, field));
          }
      }
    }
    return children;
  }

  /// A label/value pair instead of a `ListTile`: the label column is fixed so
  /// the values line up down the page, which is what turns the child-profile
  /// Info tab (~81 fields) from six screenfuls into about one and a half.
  Widget _cell(BuildContext context, FieldSpec field, double labelWidth) => Padding(
        // `dense` still means something here: the child-profile Info tab passes
        // it and renders ~81 of these.
        padding: EdgeInsets.symmetric(vertical: dense ? 4 : 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(field.labelFor(languageCode), style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_display(field, values[field.name]), style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
      );

  List<Widget> _packed(BuildContext context, List<_Block> blocks, int columns) {
    final labelWidth = LayoutScope.of(context).labelColumnWidth;
    final children = <Widget>[];
    for (final block in blocks) {
      switch (block) {
        case _WidgetBlock(:final child):
          children.add(child);
        case _TitleBlock(:final label):
          children.add(Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
            child: Text(label, style: Theme.of(context).textTheme.titleSmall),
          ));
        case _FieldsBlock(:final fields):
          // No reveal targets: a review is read-only, so there is no finger to
          // protect from reflow and the run breaks would only cost density.
          for (final row in packFields(fields, columns, const {})) {
            if (row.length == 1 && row.first.spansFullRow) {
              children.add(_cell(context, row.first, labelWidth));
              continue;
            }
            final cells = <Widget>[];
            for (var i = 0; i < columns; i++) {
              if (i > 0) cells.add(const SizedBox(width: AppLayout.formGap));
              cells.add(i < row.length
                  ? Expanded(child: _cell(context, row[i], labelWidth))
                  : const Expanded(child: SizedBox.shrink()));
            }
            children.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells));
          }
      }
    }
    return children;
  }
}
