import 'package:bma_app/core/layout/app_layout.dart';
import 'package:bma_app/core/models/entity_record.dart';
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:bma_app/core/widgets/common.dart';
import 'package:bma_app/core/widgets/ui.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/viewport.dart';

/// COMMIT 3 — the shared widgets read LayoutScope.
///
/// The load-bearing half of this file is the "compact" group: every one of
/// these widgets has ~20 call sites and none of them passes a new parameter,
/// so a wrong default is a silent phone regression. Each compact expectation
/// below is the literal that was in the file before this commit.

const _trailing = ValueKey('hh-trailing');
const _tileA = ValueKey('tile-a');
const _tileB = ValueKey('tile-b');

/// Pumps [child] with the real theme and localisations. [layout] null means
/// NO LayoutScope above the widget — the production phone situation and the
/// situation every screen is in until it opts in.
Widget host(Widget child, {AppLayout? layout, String lang = 'en'}) {
  final body = layout == null ? child : LayoutScope(layout: layout, child: child);
  return MaterialApp(
    locale: Locale(lang),
    theme: AppTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: body),
  );
}

/// Width of the label box of a FactRow / InfoLine whose label reads [label].
double labelWidthOf(WidgetTester tester, String label) => tester
    .getSize(find.ancestor(of: find.text(label), matching: find.byType(SizedBox)).first)
    .width;

Finder circleOf(Finder tile) => find.descendant(of: tile, matching: find.byType(Container)).first;

void main() {
  group('compact — no LayoutScope, the production phone tree', () {
    testWidgets('FactRow keeps a 132 px label column', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(const FactRow(label: 'Centre', value: 'Bar Elias')));
      expect(labelWidthOf(tester, 'Centre'), 132);
    });

    testWidgets('InfoLine keeps a 140 px label column, NOT the 132 token', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(const InfoLine('Centre', 'Bar Elias')));
      // labelColumnWidth is 132 at compact because that is FactRow's literal.
      // InfoLine's own literal is 140 and must survive.
      expect(labelWidthOf(tester, 'Centre'), 140);
    });

    testWidgets('StatRow stretches its tiles with Expanded', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(const StatRow(tiles: [
        SizedBox(key: _tileA, height: 40),
        SizedBox(key: _tileB, height: 40),
      ])));
      expect(find.descendant(of: find.byType(StatRow), matching: find.byType(Expanded)), findsNWidgets(2));
      // 412 - 24 of padding - 8 of gap, halved.
      expect(tester.getSize(find.byKey(_tileA)).width, 190);
    });

    testWidgets('ActionTile is a 44 px circle, a 22 px glyph and a 12.5 px label', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(ActionTile(icon: Icons.person_add, label: 'Register', onTap: () {})));
      expect(tester.getSize(circleOf(find.byType(ActionTile))), const Size(44, 44));
      expect(tester.widget<Icon>(find.byIcon(Icons.person_add)).size, 22);
      expect(tester.widget<Text>(find.text('Register')).style!.fontSize, 12.5);
    });

    testWidgets('StatusPill defaults to the small variant', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(const StatusPill(label: 'Open', color: Colors.green, icon: Icons.check)));
      expect(tester.widget<Text>(find.text('Open')).style!.fontSize, 12);
      expect(tester.widget<Container>(find.byType(Container).first).padding,
          const EdgeInsets.symmetric(horizontal: 10, vertical: 5));
      expect(tester.widget<Icon>(find.byIcon(Icons.check)).size, 13);
    });

    testWidgets('StatTile keeps a 22 px value and 12 px padding', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(const SizedBox(width: 200, child: StatTile(label: 'Children', value: '41'))));
      expect(tester.widget<Text>(find.text('41')).style!.fontSize, 22);
      expect(
        find.descendant(
          of: find.byType(StatTile),
          matching: find.byWidgetPredicate((w) => w is Padding && w.padding == const EdgeInsets.all(12)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('EmptyState keeps a 56 px icon and no text cap', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(const EmptyState(message: 'Nothing here')));
      expect(tester.widget<Icon>(find.byType(Icon)).size, 56);
      expect(find.descendant(of: find.byType(EmptyState), matching: find.byType(ConstrainedBox)), findsNothing);
    });

    testWidgets('SearchField spans the phone', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(SearchField(onChanged: (_) {})));
      expect(tester.getSize(find.byType(TextField)).width, 412 - 24);
      // No Align/ConstrainedBox wrapper is inserted at compact — the Padding's
      // child is the field itself, exactly as before this commit. (TextField
      // has ConstrainedBoxes of its own, so byType is not the way to ask.)
      expect(
        tester.widget<Padding>(find.descendant(of: find.byType(SearchField), matching: find.byType(Padding)).first).child,
        isA<TextField>(),
      );
    });

    testWidgets('SyncStateChip(compact) is still the bare icon', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(const SyncStateChip(SyncState.pending, compact: true)));
      expect(find.byType(Chip), findsNothing);
      expect(find.byType(Tooltip), findsOneWidget);
      expect(tester.widget<Icon>(find.byType(Icon)).size, 18);
    });

    testWidgets('HeroHeader: 16 px gutter, 20 px title, trailing on its own line', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(const HeroHeader(
        title: 'Bar Elias',
        subtitle: 'Centre',
        trailing: Icon(Icons.edit, key: _trailing),
      )));
      expect(tester.getTopLeft(find.text('Bar Elias')).dx, 16);
      expect(tester.widget<Text>(find.text('Bar Elias')).style!.fontSize, 20);
      // Strictly above the title: that is the phone-only stacking.
      expect(tester.getRect(find.byKey(_trailing)).bottom,
          lessThanOrEqualTo(tester.getRect(find.text('Bar Elias')).top));
    });

    testWidgets('showMessage leaves the snackbar full width', (tester) async {
      phone(tester);
      await tester.pumpWidget(host(Builder(
        builder: (context) => TextButton(onPressed: () => showMessage(context, 'Saved'), child: const Text('go')),
      )));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).width, isNull);
    });
  });

  group('medium — 800 px tablet portrait', () {
    testWidgets('label columns widen to 180', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        const Column(children: [FactRow(label: 'Centre', value: 'x'), InfoLine('School', 'y')]),
        layout: AppLayout.medium,
      ));
      expect(labelWidthOf(tester, 'Centre'), 180);
      expect(labelWidthOf(tester, 'School'), 180);
    });

    testWidgets('StatRow caps each tile at 260 and packs from the start', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        const StatRow(tiles: [SizedBox(key: _tileA, height: 40), SizedBox(key: _tileB, height: 40)]),
        layout: AppLayout.medium,
      ));
      expect(find.descendant(of: find.byType(StatRow), matching: find.byType(Expanded)), findsNothing);
      expect(tester.getSize(find.byKey(_tileA)).width, 260);
      expect(tester.getTopLeft(find.byKey(_tileA)).dx, 12);
      // IntrinsicHeight is what bounds the cross axis; removing it reintroduces
      // an unbounded-height error inside a ListView.
      expect(find.descendant(of: find.byType(StatRow), matching: find.byType(IntrinsicHeight)), findsOneWidget);
    });

    testWidgets('ActionTile grows to 52/26/13.5', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        ActionTile(icon: Icons.person_add, label: 'Register', onTap: () {}),
        layout: AppLayout.medium,
      ));
      expect(tester.getSize(circleOf(find.byType(ActionTile))), const Size(52, 52));
      expect(tester.widget<Icon>(find.byIcon(Icons.person_add)).size, 26);
      expect(tester.widget<Text>(find.text('Register')).style!.fontSize, 13.5);
    });

    testWidgets('StatTile grows to 26/14', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        const SizedBox(width: 260, child: StatTile(label: 'Children', value: '41')),
        layout: AppLayout.medium,
      ));
      expect(tester.widget<Text>(find.text('41')).style!.fontSize, 26);
      expect(
        find.descendant(
          of: find.byType(StatTile),
          matching: find.byWidgetPredicate((w) => w is Padding && w.padding == const EdgeInsets.all(14)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('EmptyState gets a 72 px icon and a 420 px text cap', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        const EmptyState(message: 'Select a beneficiary from the list to see their record here'),
        layout: AppLayout.medium,
      ));
      expect(tester.widget<Icon>(find.byType(Icon)).size, 72);
      expect(tester.getSize(find.byType(Text)).width, lessThanOrEqualTo(420));
    });

    // TAB-005. Fixed once here rather than at each of the ~15 call sites: this
    // is the placeholder of every detail pane, and a pane's Expanded is what
    // is left after the toolbar, filter and tip card above it.
    testWidgets('a box too short for the placeholder scrolls instead of overflowing', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        // 81 px is what the 400 px beneficiaries list pane leaves at a 1.3
        // text scale on a 760 px window; the content wants ~96.
        const SizedBox(
          height: 81,
          width: 400,
          child: EmptyState(message: 'No results', icon: Icons.people_outline),
        ),
        layout: AppLayout.medium,
      ));

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(EmptyState)).height, 81);
      expect(find.descendant(of: find.byType(EmptyState), matching: find.byType(SingleChildScrollView)),
          findsOneWidget);
      // The message is reachable rather than clipped away.
      expect(find.text('No results'), findsOneWidget);
    });

    testWidgets('a box with room still CENTRES it — no scroll offset, no stretch', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        const SizedBox(
          height: 600,
          width: 400,
          child: EmptyState(message: 'Select a beneficiary'),
        ),
        layout: AppLayout.medium,
      ));

      final box = tester.getRect(find.byType(EmptyState));
      final content = tester.getRect(
          find.descendant(of: find.byType(EmptyState), matching: find.byType(Column)));
      // Equal slack above and below is the proof that the scroll view
      // shrink-wrapped to the content instead of filling the box and pinning
      // it to the top.
      expect(content.top - box.top, closeTo(box.bottom - content.bottom, 1));
      expect(content.height, lessThan(box.height));
      expect(tester.takeException(), isNull);
    });

    testWidgets('SearchField caps at 420 and hugs the start edge', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(SearchField(onChanged: (_) {}), layout: AppLayout.medium));
      expect(tester.getSize(find.byType(TextField)).width, 420);
      expect(tester.getTopLeft(find.byType(TextField)).dx, 12);
    });

    testWidgets('SyncStateChip(compact) is promoted to the labelled Chip', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(const SyncStateChip(SyncState.pending, compact: true), layout: AppLayout.medium));
      expect(find.byType(Chip), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('forceIcon survives the promotion', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        const SyncStateChip(SyncState.pending, compact: true, forceIcon: true),
        layout: AppLayout.expanded,
      ));
      expect(find.byType(Chip), findsNothing);
      expect(tester.widget<Icon>(find.byType(Icon)).size, 18);
    });

    testWidgets('HeroHeader: 24 px gutter, 24 px title, trailing inline', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        const HeroHeader(title: 'Bar Elias', subtitle: 'Centre', trailing: Icon(Icons.edit, key: _trailing)),
        layout: AppLayout.medium,
      ));
      expect(tester.getTopLeft(find.text('Bar Elias')).dx, 24);
      expect(tester.widget<Text>(find.text('Bar Elias')).style!.fontSize, 24);
      final title = tester.getRect(find.text('Bar Elias'));
      final trailing = tester.getRect(find.byKey(_trailing));
      // Overlaps the title vertically and sits after it.
      expect(trailing.bottom, greaterThan(title.top));
      expect(trailing.left, greaterThan(title.right));
    });

    testWidgets('showMessage caps the snackbar at 520', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        Builder(builder: (context) => TextButton(onPressed: () => showMessage(context, 'Saved'), child: const Text('go'))),
        layout: AppLayout.medium,
      ));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).width, 520);
    });
  });

  group('expanded — 1280 px tablet landscape', () {
    testWidgets('FactRow label column reaches 200', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(const FactRow(label: 'Centre', value: 'x'), layout: AppLayout.expanded));
      expect(labelWidthOf(tester, 'Centre'), 200);
    });

    testWidgets('StatRow tile reaches 280', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        const StatRow(tiles: [SizedBox(key: _tileA, height: 40), SizedBox(key: _tileB, height: 40)]),
        layout: AppLayout.expanded,
      ));
      expect(tester.getSize(find.byKey(_tileA)).width, 280);
    });

    testWidgets('ActionTile reaches 56/28/14 and StatTile 30/16', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        Column(children: [
          ActionTile(icon: Icons.person_add, label: 'Register', onTap: () {}),
          const SizedBox(width: 280, child: StatTile(label: 'Children', value: '41')),
        ]),
        layout: AppLayout.expanded,
      ));
      expect(tester.getSize(circleOf(find.byType(ActionTile))), const Size(56, 56));
      expect(tester.widget<Icon>(find.byIcon(Icons.person_add)).size, 28);
      expect(tester.widget<Text>(find.text('Register')).style!.fontSize, 14);
      expect(tester.widget<Text>(find.text('41')).style!.fontSize, 30);
      expect(
        find.descendant(
          of: find.byType(StatTile),
          matching: find.byWidgetPredicate((w) => w is Padding && w.padding == const EdgeInsets.all(16)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('HeroHeader centres its content inside contentMaxWidth', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(const HeroHeader(title: 'Bar Elias'), layout: AppLayout.expanded));
      expect(tester.widget<Text>(find.text('Bar Elias')).style!.fontSize, 26);
      // 1280 - 2*32 of gutter = 1216 available, capped at 1120, so 48 px of
      // slack on each side on top of the gutter.
      expect(tester.getTopLeft(find.text('Bar Elias')).dx, 32 + 48);
      // The gradient band itself stays full bleed.
      expect(tester.getSize(find.byType(HeroHeader)).width, 1280);
    });
  });

  group('the fail-safe', () {
    testWidgets('a 1280 px window with NO scope still renders compact', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(const Column(children: [
        FactRow(label: 'Centre', value: 'x'),
        InfoLine('School', 'y'),
        SyncStateChip(SyncState.pending, compact: true),
      ])));
      expect(labelWidthOf(tester, 'Centre'), 132);
      expect(labelWidthOf(tester, 'School'), 140);
      expect(find.byType(Chip), findsNothing);
    });

    testWidgets('a compact scope nested inside an expanded one wins', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        const LayoutScope(layout: AppLayout.compact, child: FactRow(label: 'Centre', value: 'x')),
        layout: AppLayout.expanded,
      ));
      expect(labelWidthOf(tester, 'Centre'), 132);
    });

    testWidgets('explicit overrides beat the token in both directions', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        const Column(children: [
          FactRow(label: 'Centre', value: 'x', labelWidth: 96),
          InfoLine('School', 'y', labelWidth: 96),
        ]),
        layout: AppLayout.expanded,
      ));
      expect(labelWidthOf(tester, 'Centre'), 96);
      expect(labelWidthOf(tester, 'School'), 96);
    });

    testWidgets('StatusPill(large) is 14 px on 12/7 padding', (tester) async {
      tabletLandscape(tester);
      await tester.pumpWidget(host(
        const StatusPill(label: 'Open', color: Colors.green, icon: Icons.check, large: true),
        layout: AppLayout.expanded,
      ));
      expect(tester.widget<Text>(find.text('Open')).style!.fontSize, 14);
      expect(tester.widget<Container>(find.byType(Container).first).padding,
          const EdgeInsets.symmetric(horizontal: 12, vertical: 7));
      expect(tester.widget<Icon>(find.byIcon(Icons.check)).size, 15);
    });
  });

  group('Arabic RTL mirrors every new inset', () {
    testWidgets('SearchField hugs the RIGHT edge at medium', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(SearchField(onChanged: (_) {}), layout: AppLayout.medium, lang: 'ar'));
      expect(tester.getSize(find.byType(TextField)).width, 420);
      expect(tester.getTopRight(find.byType(TextField)).dx, 800 - 12);
    });

    testWidgets('HeroHeader mirrors gutter and trailing', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        const HeroHeader(title: 'Bar Elias', trailing: Icon(Icons.edit, key: _trailing)),
        layout: AppLayout.medium,
        lang: 'ar',
      ));
      expect(tester.getTopRight(find.text('Bar Elias')).dx, 800 - 24);
      expect(tester.getRect(find.byKey(_trailing)).right, lessThan(tester.getRect(find.text('Bar Elias')).left));
    });

    testWidgets('FactRow puts the label on the right', (tester) async {
      tabletPortrait(tester);
      await tester.pumpWidget(host(
        const FactRow(label: 'Centre', value: 'Bar Elias'),
        layout: AppLayout.medium,
        lang: 'ar',
      ));
      expect(tester.getTopRight(find.text('Centre')).dx, 800);
      expect(tester.getTopRight(find.text('Bar Elias')).dx, 800 - 180 - 8);
    });
  });
}
