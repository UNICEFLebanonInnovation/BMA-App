// The shared chart widgets at the boxes and text scales that broke them.
// Every case here painted overflow stripes, scrolled to the wrong end or
// grew a phantom band before the fix it names.
import 'package:bma_app/core/layout/app_layout.dart';
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:bma_app/features/analytics/analytics_models.dart';
import 'package:bma_app/features/analytics/charts/chart_card.dart';
import 'package:bma_app/features/analytics/charts/chart_palette.dart';
import 'package:bma_app/features/analytics/charts/crosstab_table.dart';
import 'package:bma_app/features/analytics/charts/heatmap_calendar.dart';
import 'package:bma_app/features/analytics/charts/trend_line_chart.dart';
import 'package:bma_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/viewport.dart';

/// Pumps [child] in a box of [width], in [lang], at [scale].
Future<void> pumpBox(
  WidgetTester tester,
  Widget child, {
  double width = 348,
  String lang = 'en',
  double scale = 1.0,
  EdgeInsets viewPadding = EdgeInsets.zero,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    locale: Locale(lang),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: viewPadding,
          viewPadding: viewPadding,
        ),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void expectClean(WidgetTester tester) => expect(tester.takeException(), isNull);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChartLegend', () {
    testWidgets('a long series name ellipsizes instead of overflowing the card', (tester) async {
      phone(tester);
      await pumpBox(
        tester,
        const ChartLegend(entries: [
          ('Moved from an earlier round', Color(0xFFE87BA4)),
          ('New in this round', Color(0xFF1BAF7A)),
        ]),
        scale: 1.3,
      );
      expectClean(tester);
      final label = tester.getRect(find.text('Moved from an earlier round'));
      expect(label.width, lessThanOrEqualTo(348));
    });

    testWidgets('and in Arabic at 1.3x', (tester) async {
      phone(tester);
      await pumpBox(
        tester,
        const ChartLegend(entries: [
          ('منتقلون من جولة سابقة إلى الجولة الحالية', Color(0xFFE87BA4)),
          ('جدد في هذه الجولة', Color(0xFF1BAF7A)),
        ]),
        lang: 'ar',
        scale: 1.3,
      );
      expectClean(tester);
    });
  });

  group('TrendLineChart', () {
    testWidgets('the date axis gives way at 1.3x rather than overflowing', (tester) async {
      phone(tester);
      final points = [
        for (var i = 0; i < 30; i++) TrendPoint(DateTime(2026, 9, 1).add(Duration(days: i)), i % 4),
      ];
      await pumpBox(tester, TrendLineChart(points: points), scale: 1.3);
      expectClean(tester);
    });

    testWidgets('and in Arabic at 1.3x, where the dates are longest', (tester) async {
      phone(tester);
      final points = [
        for (var i = 0; i < 30; i++) TrendPoint(DateTime(2026, 9, 1).add(Duration(days: i)), i % 4),
      ];
      await pumpBox(tester, TrendLineChart(points: points), lang: 'ar', scale: 1.3, width: 348);
      expectClean(tester);
    });

    testWidgets('a single day still draws, and the plot runs left to right in Arabic', (tester) async {
      phone(tester);
      await pumpBox(
        tester,
        TrendLineChart(points: [TrendPoint(DateTime(2026, 9, 20), 3)]),
        lang: 'ar',
      );
      expectClean(tester);
      // The plot is pinned LTR so the newest day is never drawn under the
      // oldest; only the caption below follows the page direction.
      final plot = find.descendant(of: find.byType(TrendLineChart), matching: find.byType(Directionality));
      expect(tester.widget<Directionality>(plot.first).textDirection, TextDirection.ltr);
    });
  });

  group('AttendanceHeatmap', () {
    Widget heatmap() => AttendanceHeatmap(
          year: 2026,
          cells: {
            for (var d = 1; d <= 28; d++)
              DateTime(2026, 3, d): HeatCell(date: DateTime(2026, 3, d), total: 10, absent: d % 4),
          },
          rateLabel: 'Attendance rate',
          detailText: (cell) => '${cell.present} of ${cell.total}',
        );

    testWidgets('in Arabic the month gutter is the first thing on screen, not the last', (tester) async {
      phone(tester);
      // 44 px of month labels plus 31 days needs far more than a phone card.
      await pumpBox(tester, heatmap(), lang: 'ar', width: 348);
      expectClean(tester);
      final scroller = find.descendant(of: find.byType(AttendanceHeatmap), matching: find.byType(Scrollable));
      expect(scroller, findsOneWidget);
      final grid = tester.getRect(find.byType(CustomPaint).last);
      final box = tester.getRect(scroller);
      // The grid starts at the scroller's leading edge; it used to be parked
      // ~90 px to the left of it with the labels off screen.
      expect(grid.left, greaterThanOrEqualTo(box.left - 0.5));
    });

    testWidgets('the legend does not overflow a phone card at 1.3x', (tester) async {
      phone(tester);
      await pumpBox(tester, heatmap(), width: 348, scale: 1.3);
      expectClean(tester);
    });

    testWidgets('a wide box draws the grid without a scroller', (tester) async {
      tabletLandscape(tester);
      await pumpBox(tester, heatmap(), width: 1000);
      expectClean(tester);
      expect(
        find.descendant(of: find.byType(AttendanceHeatmap), matching: find.byType(Scrollable)),
        findsNothing,
      );
    });
  });

  group('CrosstabTable', () {
    Crosstab table(int columns) => Crosstab(
          rows: const ['BLN Level 1', 'BLN Level 2'],
          columns: [for (var i = 0; i < columns; i++) 'G$i'],
          counts: {
            for (final r in const ['BLN Level 1', 'BLN Level 2'])
              r: {for (var i = 0; i < columns; i++) 'G$i': i},
          },
        );

    testWidgets('counts its cell margins when deciding it fits', (tester) async {
      // Six age groups plus the total column is seven cells: 150 + 7 * 64 is
      // 598, but the real width is 150 + 7 * 66 = 612. At a 599 px box the
      // table used to claim it fitted and overflow by 13 px.
      freeformWindow(tester, 660, 800);
      await pumpBox(
        tester,
        CrosstabTable(crosstab: table(6), rowHeader: 'Programme', columnHeader: 'Age group', totalLabel: 'Total'),
        width: 599,
      );
      expectClean(tester);
      expect(find.byType(Scrollable), findsWidgets);
    });

    testWidgets('a box with real room still skips the scroller', (tester) async {
      tabletLandscape(tester);
      await pumpBox(
        tester,
        CrosstabTable(crosstab: table(6), rowHeader: 'Programme', columnHeader: 'Age group', totalLabel: 'Total'),
        width: 900,
      );
      expectClean(tester);
      expect(
        find.descendant(of: find.byType(CrosstabTable), matching: find.byType(Scrollable)),
        findsNothing,
      );
    });
  });

  group('KpiGrid', () {
    testWidgets('does not adopt the system bottom inset as padding', (tester) async {
      phone(tester);
      Widget grid() => KpiGrid(
            key: const ValueKey('kpis'),
            tiles: [
              for (var i = 0; i < 4; i++) KpiTile(label: 'Label $i', value: '$i', color: ChartPalette.single),
            ],
          );

      await pumpBox(tester, grid(), width: 396);
      final without = tester.getRect(find.byKey(const ValueKey('kpis'))).height;

      await pumpBox(tester, grid(), width: 396, viewPadding: const EdgeInsets.only(bottom: 48));
      final with48 = tester.getRect(find.byKey(const ValueKey('kpis'))).height;

      // A nested GridView with a null padding takes the ambient MediaQuery
      // padding and grows a band of empty space under the tiles.
      expect(with48, without);
      expectClean(tester);
    });
  });

  group('the fail-safe still holds', () {
    testWidgets('every chart renders with no LayoutScope above it', (tester) async {
      phone(tester);
      expect(AppLayout.compact.width.atLeastMedium, isFalse);
      await pumpBox(
        tester,
        Column(
          children: [
            const ChartLegend(entries: [('A', Color(0xFF2A78D6))]),
            TrendLineChart(points: [TrendPoint(DateTime(2026, 9, 20), 1)]),
            KpiGrid(tiles: [KpiTile(label: 'L', value: '1')]),
          ],
        ),
      );
      expectClean(tester);
    });
  });
}
