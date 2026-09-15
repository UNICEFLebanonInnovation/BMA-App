import 'package:bma_app/core/layout/app_layout.dart';
import 'package:bma_app/core/models/entity_record.dart';
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:bma_app/core/widgets/common.dart';
import 'package:bma_app/core/widgets/ui.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/viewport.dart';

/// THE PHONE-FALLBACK SMOKE TEST.
///
/// Everything in this file is pumped at 412x915 with NO LayoutScope above it —
/// the exact tree the phone builds in production — and asserts that nothing
/// throws and that the pre-tablet literals are still the ones rendered.
///
/// SCOPE AT THIS COMMIT: the shared widgets of ui.dart and common.dart, which
/// are the only things the tablet work has touched so far. As each commit-5
/// lane converts a screen, that screen is APPENDED here (pumped with the
/// lane's fixture container, asserting takeException() is null and that the
/// lane's protected ValueKeys resolve) — the existing suite covers none of the
/// beneficiaries list, attendance, the teacher list, the child profile, the
/// dashboard, the sync centre or any form, so without this file a phone
/// regression in those screens ships green.

/// One page using every shared widget at once, the way a real screen does.
class _KitchenSink extends StatelessWidget {
  const _KitchenSink();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          const HeroHeader(
            title: 'Bar Elias Makani Centre',
            subtitle: 'Bekaa — Zahle',
            leading: InitialsAvatar('Bar Elias'),
            trailing: Icon(Icons.edit, color: Colors.white),
            footer: StatusPill(label: 'Open', color: Colors.white),
          ),
          SearchField(onChanged: (_) {}),
          const StatRow(tiles: [
            StatTile(label: 'Registered children', value: '412'),
            StatTile(label: 'Pending', value: '7'),
          ]),
          const SectionHeader('Details'),
          const AppCard(
            child: Column(children: [
              FactRow(label: 'Partner', value: 'Partner NGO', icon: Icons.handshake_outlined),
              FactRow(label: 'Registration level', value: 'Centre'),
              InfoLine('School', 'Bar Elias Public School'),
              InfoLine('Shift', null),
            ]),
          ),
          const Wrap(spacing: 8, runSpacing: 8, children: [
            SyncStateChip(SyncState.pending),
            SyncStateChip(SyncState.conflict, compact: true),
            StatusPill(label: 'Absent', color: Colors.red, icon: Icons.close),
            StatusPill(label: 'Present', color: Colors.green, icon: Icons.check, large: true),
          ]),
          SizedBox(
            height: 140,
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 0.95,
              children: [
                ActionTile(icon: Icons.person_add, label: 'Register beneficiary', onTap: () {}),
                const ActionTile(icon: Icons.fact_check_outlined, label: 'Attendance'),
                ActionTile(icon: Icons.sync, label: 'Sync centre', onTap: () {}),
              ],
            ),
          ),
          const SizedBox(height: 240, child: EmptyState(message: 'No beneficiaries match this search')),
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showMessage(context, 'Saved'),
              child: const Text('snack'),
            ),
          ),
        ],
      ),
    );
  }
}

Widget app({String lang = 'en', TextScaler? scaler}) => MaterialApp(
      locale: Locale(lang),
      theme: AppTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const _KitchenSink(),
      // Applied below the View's MediaQuery so the window size is kept and
      // only the scale changes.
      builder: scaler == null
          ? null
          : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: scaler),
                child: child!,
              ),
    );

void main() {
  testWidgets('every shared widget renders clean at 412x915 in English', (tester) async {
    phone(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('and in Arabic at TextScaler 1.3', (tester) async {
    phone(tester);
    await tester.pumpWidget(app(lang: 'ar', scaler: const TextScaler.linear(1.3)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone literals are the ones actually rendered', (tester) async {
    phone(tester);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // No scope is installed anywhere in this tree, and LayoutScope.of must
    // keep answering compact for that. If this ever fails, the fallback in
    // LayoutScope.of has been turned into an assert or a lookup.
    final ctx = tester.element(find.byType(SectionHeader));
    expect(LayoutScope.of(ctx), same(AppLayout.compact));

    // FactRow 132, InfoLine 140 — two different literals, one token.
    expect(tester.getSize(find.ancestor(of: find.text('Partner'), matching: find.byType(SizedBox)).first).width, 132);
    expect(tester.getSize(find.ancestor(of: find.text('School'), matching: find.byType(SizedBox)).first).width, 140);

    // Hero: 16 px gutter, 20 px title, no content cap.
    expect(tester.widget<Text>(find.text('Bar Elias Makani Centre')).style!.fontSize, 20);
    expect(tester.getSize(find.byType(HeroHeader)).width, 412);

    // SearchField full bleed; StatRow stretched; ActionTile 44/22/12.5.
    expect(tester.getSize(find.byType(TextField)).width, 412 - 24);
    expect(find.descendant(of: find.byType(StatRow), matching: find.byType(Expanded)), findsNWidgets(2));
    expect(tester.widget<Icon>(find.byIcon(Icons.person_add)).size, 22);
    expect(tester.widget<Text>(find.text('Register beneficiary')).style!.fontSize, 12.5);

    // StatTile 22; EmptyState 56; compact SyncStateChip still an icon.
    expect(tester.widget<Text>(find.text('412')).style!.fontSize, 22);
    expect(tester.widget<Icon>(find.byIcon(Icons.inbox_outlined)).size, 56);
    expect(find.byIcon(Icons.call_split), findsOneWidget);
    expect(find.text('Conflict'), findsNothing);

    // Snackbars keep spanning the phone. (Scroll last: every assertion above
    // is positional and must run against the unscrolled page.)
    await tester.scrollUntilVisible(find.text('snack'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('snack'));
    await tester.pump();
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).width, isNull);
  });
}
