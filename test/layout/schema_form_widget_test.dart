import 'package:bma_app/core/forms/schema_form.dart';
import 'package:bma_app/core/forms/schema_form_controller.dart';
import 'package:bma_app/core/layout/app_layout.dart';
import 'package:bma_app/core/models/form_schema.dart';
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/viewport.dart';

/// COMMIT 4 — the first widget test of the form engine in this repo.
///
/// One widget renders all 25 server-driven schemas, and until this file
/// existed nothing rendered it at all. The load-bearing assertions are:
///
///  * the SET of fields is identical at every width (the packer rearranges,
///    it never filters — `collect()` drops reveal-hidden values, so a packer
///    that changed visibility would silently change the JSON pushed to the
///    server, with no symptom on the device);
///  * live `TextEditingController` state survives being re-parented into a
///    `Row`/`Expanded` cell and being pushed down by a reveal or by the
///    general-error card;
///  * at compact the tree is the one that was there before this commit.

EntitySchema schema() => EntitySchema.fromJson({
      'key': 'test.registration',
      'module': 'mscc',
      'label': 'Registration',
      'kind': 'identity',
      'fields': [
        {'name': 'first_name', 'label': 'First name', 'type': 'text'},
        {'name': 'last_name', 'label': 'Last name', 'type': 'text'},
        {'name': 'gender', 'label': 'Gender', 'type': 'select', 'choices': [
          {'value': 'M', 'label': 'Male'}, {'value': 'F', 'label': 'Female'}]},
        {'name': 'id_type', 'label': 'ID type', 'type': 'select', 'choices': [
          {'value': 'none', 'label': 'None'}, {'value': 'unhcr', 'label': 'UNHCR'}]},
        {'name': 'id_number', 'label': 'ID number', 'type': 'text'},
        {'name': 'id_number_confirm', 'label': 'Confirm ID number', 'type': 'text'},
        {'name': 'id_issued', 'label': 'Issued on', 'type': 'date'},
        {'name': 'phone', 'label': 'Phone', 'type': 'text'},
        {'name': 'phone_confirm', 'label': 'Confirm phone', 'type': 'text'},
        {'name': 'consent', 'label': 'Consent given', 'type': 'boolean'},
        {'name': 'notes', 'label': 'Notes', 'type': 'textarea'},
      ],
      'sections': [
        {
          'key': 'identity',
          'label': 'Identity',
          'fields': ['first_name', 'last_name', 'gender', 'id_type', 'id_number', 'id_number_confirm', 'id_issued'],
        },
        {
          'key': 'contact',
          'label': 'Contact',
          'fields': ['phone', 'phone_confirm', 'consent', 'notes'],
        },
      ],
      'reveals': [
        {'when': {'field': 'id_type', 'not_in': ['', 'none']}, 'show': ['id_number', 'id_number_confirm', 'id_issued']},
      ],
    });

/// 22 X / X_confirm pairs in one section: the caregivers shape, and the
/// worst case for Arabic at 1.3x.
EntitySchema caregiversSchema() {
  final names = [for (var i = 0; i < 22; i++) 'care_$i'];
  return EntitySchema.fromJson({
    'key': 'test.caregivers',
    'label': 'Caregivers',
    'fields': [
      for (final n in names) ...[
        {'name': n, 'label': 'اسم مقدم الرعاية $n', 'type': 'text', 'required': true},
        {'name': '${n}_confirm', 'label': 'تأكيد اسم مقدم الرعاية $n', 'type': 'text'},
      ],
    ],
    'sections': [
      {
        'key': 'caregivers',
        'label': 'مقدمو الرعاية',
        'fields': [for (final n in names) ...[n, '${n}_confirm']],
      },
    ],
  });
}

/// Pumps [child] in a [box]-wide column with the [AppLayout] that box would
/// resolve to — the situation a converted screen creates with `AdaptiveBody`.
/// `scope: false` leaves no LayoutScope above it, which is every screen until
/// commit 5 converts it.
Widget host(
  Widget child, {
  required double box,
  String lang = 'en',
  double scale = 1.0,
  bool scope = true,
}) {
  final body = Align(
    alignment: AlignmentDirectional.topStart,
    heightFactor: 1,
    child: SizedBox(width: box, child: child),
  );
  return ProviderScope(
    child: MaterialApp(
      locale: Locale(lang),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: inner!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: scope ? LayoutScope(layout: AppLayout.forWidth(box), child: body) : body,
        ),
      ),
    ),
  );
}

Finder fieldKeys() => find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('field-'),
    );

Finder rowKeys() => find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('form-row-'),
    );

/// Names of every field currently mounted, in tree order.
List<String> mountedFields(WidgetTester tester) => tester
    .widgetList(fieldKeys())
    .map((w) => (w.key as ValueKey<String>).value.substring('field-'.length))
    .toList();

/// How many fields share the topmost row — i.e. the rendered column count.
int renderedColumns(WidgetTester tester) {
  final tops = <double>[];
  for (final name in mountedFields(tester)) {
    tops.add(tester.getTopLeft(find.byKey(ValueKey('field-$name'))).dy);
  }
  final first = tops.first;
  return tops.where((t) => t == first).length;
}

TextField textFieldOf(WidgetTester tester, String name) => tester.widget<TextField>(
      find.descendant(of: find.byKey(ValueKey('field-$name')), matching: find.byType(TextField)),
    );

void main() {
  group('(a) column count follows the box', () {
    testWidgets('412 renders one column', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(
        SchemaForm(controller: SchemaFormController(schema: schema()), languageCode: 'en'),
        box: 412,
      ));
      expect(renderedColumns(tester), 1);
      // And the packer added nothing: no Row wrapper exists at all.
      expect(rowKeys(), findsNothing);
    });

    testWidgets('800 renders two columns', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        SchemaForm(controller: SchemaFormController(schema: schema()), languageCode: 'en'),
        box: 800,
      ));
      expect(renderedColumns(tester), 2);
      expect(rowKeys(), findsWidgets);
      // first_name and last_name are one row: same top, and the second starts
      // after the first plus the 24 px gap.
      final a = tester.getRect(find.byKey(const ValueKey('field-first_name')));
      final b = tester.getRect(find.byKey(const ValueKey('field-last_name')));
      expect(a.top, b.top);
      expect(b.left - a.right, AppLayout.formGap);
    });

    testWidgets('1280 renders three columns', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        SchemaForm(controller: SchemaFormController(schema: schema()), languageCode: 'en'),
        box: 1280,
      ));
      expect(renderedColumns(tester), 3);
    });

    testWidgets('a textarea still owns its row at three columns', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        SchemaForm(controller: SchemaFormController(schema: schema()), languageCode: 'en'),
        box: 1280,
      ));
      final notes = tester.getRect(find.byKey(const ValueKey('field-notes')));
      final phone = tester.getRect(find.byKey(const ValueKey('field-phone')));
      expect(notes.width, greaterThan(phone.width * 2));
    });

    testWidgets('a confirm twin sits beside its base, not under it', (tester) async {
      tabletPortrait(tester);
      final controller = SchemaFormController(schema: schema(), initial: {'id_type': 'unhcr'});
      await tester.pumpWidget(host(
        SchemaForm(controller: controller, languageCode: 'en'),
        box: 800,
      ));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('field-id_number'))).dy,
        tester.getTopLeft(find.byKey(const ValueKey('field-id_number_confirm'))).dy,
      );
    });
  });

  group('(b) THE CORRECTNESS ASSERTION — the packer never changes WHICH fields exist', () {
    for (final (label, size, box) in [
      ('412', phone, 412.0),
      ('800', tabletPortrait, 800.0),
      ('1280', tabletLandscape, 1280.0),
    ]) {
      testWidgets('the mounted field set at $label is the schema\'s visible set', (tester) async {
        size(tester);
        final controller = SchemaFormController(schema: schema(), initial: {'id_type': 'unhcr'});
        await tester.pumpWidget(host(
          SchemaForm(controller: controller, languageCode: 'en'),
          box: box,
        ));
        // Source order is preserved too, at every width.
        expect(mountedFields(tester), [
          'first_name', 'last_name', 'gender', 'id_type', 'id_number', 'id_number_confirm',
          'id_issued', 'phone', 'phone_confirm', 'consent', 'notes',
        ]);
      });

      testWidgets('a reveal turned OFF hides exactly the same three fields at $label', (tester) async {
        size(tester);
        final controller = SchemaFormController(schema: schema(), initial: {'id_type': 'none'});
        await tester.pumpWidget(host(
          SchemaForm(controller: controller, languageCode: 'en'),
          box: box,
        ));
        expect(mountedFields(tester), isNot(contains('id_number')));
        expect(mountedFields(tester).length, 8);
        // What is mounted is what collect() will keep: the two must agree.
        controller.setValue('id_number', 'stale');
        expect(controller.collect().containsKey('id_number'), isFalse);
      });
    }
  });

  group('(c) field state survives re-parenting', () {
    testWidgets('typing survives a reveal that pushes the field down a row', (tester) async {
      tabletLandscape(tester);
      final controller = SchemaFormController(schema: schema(), initial: {'id_type': 'none'});
      await tester.pumpWidget(host(
        SchemaForm(controller: controller, languageCode: 'en'),
        box: 1280,
      ));

      await tester.enterText(find.byKey(const ValueKey('field-phone')), '70-123456');
      await tester.pump();
      final before = tester.state(find.byKey(const ValueKey('field-phone')));
      final beforeTop = tester.getTopLeft(find.byKey(const ValueKey('field-phone'))).dy;
      textFieldOf(tester, 'phone').controller!.selection = const TextSelection.collapsed(offset: 3);
      await tester.pump();

      // The reveal fires: three fields appear ABOVE the phone row.
      controller.setValue('id_type', 'unhcr');
      await tester.pump();

      expect(find.byKey(const ValueKey('field-id_number')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const ValueKey('field-phone'))).dy,
          greaterThan(beforeTop), reason: 'the reveal should have pushed the phone row down');
      // The Element was matched, not rebuilt: same State, same controller,
      // same text, same cursor.
      expect(identical(tester.state(find.byKey(const ValueKey('field-phone'))), before), isTrue);
      expect(textFieldOf(tester, 'phone').controller!.text, '70-123456');
      expect(textFieldOf(tester, 'phone').controller!.selection.baseOffset, 3);
    });

    testWidgets('typing survives the general-error card appearing above everything', (tester) async {
      // This is why the rows carry keys: inserting the card shifts every row
      // by one, and keyless rows would match by position and throw the live
      // TextEditingControllers away.
      tabletLandscape(tester);
      final controller = SchemaFormController(schema: schema());
      await tester.pumpWidget(host(
        SchemaForm(controller: controller, languageCode: 'en'),
        box: 1280,
      ));
      await tester.enterText(find.byKey(const ValueKey('field-phone')), '70-123456');
      await tester.pump();
      final before = tester.state(find.byKey(const ValueKey('field-phone')));

      controller.setServerErrors({'__all__': 'Server says no.'});
      await tester.pump();

      expect(find.text('Server says no.'), findsOneWidget);
      expect(identical(tester.state(find.byKey(const ValueKey('field-phone'))), before), isTrue);
      expect(textFieldOf(tester, 'phone').controller!.text, '70-123456');
    });

    testWidgets('at 412 the text survives, and the Element is recreated exactly as it always was', (tester) async {
      // DOCUMENTING TODAY'S PHONE BEHAVIOUR, not asserting a new one. The flat
      // Column's children are keyless `Padding`s — the ValueKey sits one level
      // down, on the SchemaFieldWidget, which is too deep to help Flutter's
      // multi-child reconciliation. So inserting three revealed fields above
      // `phone` shifts every position by three and the field's State is
      // rebuilt. No data is lost (initState re-reads the controller), but the
      // cursor and focus are.
      //
      // The multi-column path is strictly better here because its rows and
      // cells carry the keys themselves (see the two tests above). The phone
      // path is deliberately NOT "fixed": its tree must stay byte-identical,
      // and this is the kind of one-line improvement that would quietly move
      // 25 screens' worth of pixels.
      phone(tester);
      final controller = SchemaFormController(schema: schema(), initial: {'id_type': 'none'});
      await tester.pumpWidget(host(
        SchemaForm(controller: controller, languageCode: 'en'),
        box: 412,
      ));
      await tester.enterText(find.byKey(const ValueKey('field-phone')), '70-123456');
      await tester.pump();
      final before = tester.state(find.byKey(const ValueKey('field-phone')));
      controller.setValue('id_type', 'unhcr');
      await tester.pump();
      expect(identical(tester.state(find.byKey(const ValueKey('field-phone'))), before), isFalse);
      expect(textFieldOf(tester, 'phone').controller!.text, '70-123456');
    });

    testWidgets('at 412 a reveal BELOW the typed field leaves even the Element alone', (tester) async {
      // Nothing is inserted above `first_name`, so its position in the flat
      // Column is unchanged and the phone keeps its live controller.
      phone(tester);
      final controller = SchemaFormController(schema: schema(), initial: {'id_type': 'none'});
      await tester.pumpWidget(host(
        SchemaForm(controller: controller, languageCode: 'en'),
        box: 412,
      ));
      await tester.enterText(find.byKey(const ValueKey('field-first_name')), 'Rana');
      await tester.pump();
      final before = tester.state(find.byKey(const ValueKey('field-first_name')));
      controller.setValue('id_type', 'unhcr');
      await tester.pump();
      expect(identical(tester.state(find.byKey(const ValueKey('field-first_name'))), before), isTrue);
      expect(textFieldOf(tester, 'first_name').controller!.text, 'Rana');
    });
  });

  group('(d) SchemaReview', () {
    testWidgets('412 keeps today\'s ListTile per field', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(
        SchemaReview(schema: schema(), values: const {'id_type': 'none', 'phone': '70-123456'}, languageCode: 'en'),
        box: 412,
      ));
      // 11 fields minus the three the reveal hides.
      expect(find.byType(ListTile), findsNWidgets(8));
      expect(find.text('70-123456'), findsOneWidget);
    });

    testWidgets('a review with no LayoutScope above it is also the compact tree', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        SchemaReview(schema: schema(), values: const {'id_type': 'none'}, languageCode: 'en'),
        box: 1280,
        scope: false,
      ));
      expect(find.byType(ListTile), findsNWidgets(8));
    });

    testWidgets('1280 drops the ListTile for a label/value pair, packed two up', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        SchemaReview(schema: schema(), values: const {'id_type': 'none', 'phone': '70-123456'}, languageCode: 'en'),
        box: 1280,
      ));
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('70-123456'), findsOneWidget);
      // First name and last name share a line.
      expect(
        tester.getTopLeft(find.text('First name')).dy,
        tester.getTopLeft(find.text('Last name')).dy,
      );
      // The label column is the token, so the values line up.
      expect(
        tester.getTopLeft(find.text('Phone')).dx + AppLayout.expanded.labelColumnWidth + 8,
        tester.getTopLeft(find.text('70-123456')).dx,
      );
    });

    testWidgets('reviewColumns is 1 / 2 / 3 at the stated widths', (tester) async {
      expect(SchemaReview.reviewColumns(999), 1);
      expect(SchemaReview.reviewColumns(1000), 2);
      expect(SchemaReview.reviewColumns(1399), 2);
      expect(SchemaReview.reviewColumns(1400), 3);
      expect(SchemaReview.reviewColumns(double.infinity), 1);
    });
  });

  group('(e) the nested-scope contract — a pane is not a window', () {
    testWidgets('a 400 px box inside a 1280 px window renders one column', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        SchemaForm(controller: SchemaFormController(schema: schema()), languageCode: 'en'),
        box: 400,
      ));
      expect(renderedColumns(tester), 1);
      expect(rowKeys(), findsNothing);
    });

    testWidgets('an expanded scope over a 400 px box still renders one column', (tester) async {
      // The pathological case: a screen forgot to re-scope its pane, so the
      // TOKENS say expanded while the BOX is 400 wide. formColumns reads the
      // box, so the answer is still one column rather than three 125 px cells.
      tabletLandscape(tester);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: LayoutScope(
              layout: AppLayout.expanded,
              child: Align(
                alignment: AlignmentDirectional.topStart,
                heightFactor: 1,
                child: SizedBox(
                  width: 400,
                  child: SingleChildScrollView(
                    child: SchemaForm(
                      controller: SchemaFormController(schema: schema()),
                      languageCode: 'en',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      expect(renderedColumns(tester), 1);
    });

    testWidgets('an unconverted screen on a tablet is unchanged: no scope means one column', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        SchemaForm(controller: SchemaFormController(schema: schema()), languageCode: 'en'),
        box: 1280,
        scope: false,
      ));
      expect(renderedColumns(tester), 1);
      expect(rowKeys(), findsNothing);
    });
  });

  group('(f) the text-scale valve', () {
    testWidgets('1.3x at 1040 renders two columns, not three', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        SchemaForm(controller: SchemaFormController(schema: schema()), languageCode: 'en'),
        box: 1040,
        scale: 1.3,
      ));
      expect(renderedColumns(tester), 2);
    });

    testWidgets('1.0x at 1040 renders three', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        SchemaForm(controller: SchemaFormController(schema: schema()), languageCode: 'en'),
        box: 1040,
      ));
      expect(renderedColumns(tester), 3);
    });
  });

  group('THE GATE — the 44-field caregivers section in Arabic at 1.3x', () {
    testWidgets('1280x800, ar, 1.3x: 22 pairs render without an overflow', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        SchemaForm(controller: SchemaFormController(schema: caregiversSchema()), languageCode: 'ar'),
        box: 1280,
        lang: 'ar',
        scale: 1.3,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(mountedFields(tester).length, 44);
    });

    testWidgets('and in RTL the first field of a row is the RIGHTMOST one', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        SchemaForm(controller: SchemaFormController(schema: caregiversSchema()), languageCode: 'ar'),
        box: 1280,
        lang: 'ar',
      ));
      final base = tester.getRect(find.byKey(const ValueKey('field-care_0')));
      final twin = tester.getRect(find.byKey(const ValueKey('field-care_0_confirm')));
      expect(base.top, twin.top, reason: 'the pair must share a row');
      expect(base.left, greaterThan(twin.left), reason: 'ar: the base field belongs on the right');
      // Mirrored, not merely reversed: the row still spans the full box.
      expect(twin.left, lessThan(base.left));
      expect(base.right, greaterThan(twin.right));
    });

    testWidgets('800x1280 portrait, ar, 1.3x collapses to one column and still renders', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        SchemaForm(controller: SchemaFormController(schema: caregiversSchema()), languageCode: 'ar'),
        box: 800,
        lang: 'ar',
        scale: 1.3,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(renderedColumns(tester), 1);
    });
  });
}
