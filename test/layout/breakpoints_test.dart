// Pure unit tests over the token layer. No widgets are pumped, so nothing here
// depends on the 800x600 default test surface.
import 'package:bma_app/core/layout/app_layout.dart';
import 'package:bma_app/core/layout/breakpoints.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every numeric token of one bundle, for the mechanical guards below.
List<double> _doubleTokens(AppLayout l) => [
      l.gutter,
      l.contentMaxWidth,
      l.formMaxWidth,
      l.readingMaxWidth,
      l.fieldMinWidth,
      l.listPaneWidth,
      l.sessionPaneWidth,
      l.identityPaneWidth,
      l.stepRailWidth,
      l.touchTarget,
      l.actionTileExtent,
      l.actionTileHeight,
      l.labelColumnWidth,
      l.statTileWidth,
      l.searchMaxWidth,
      l.avatarRadius,
      l.emptyStateIcon,
    ];

const _all = [AppLayout.compact, AppLayout.medium, AppLayout.expanded];

void main() {
  group('widthClassOf', () {
    test('classifies the exact boundaries', () {
      expect(widthClassOf(411), WidthClass.compact);
      expect(widthClassOf(412), WidthClass.compact);
      expect(widthClassOf(599), WidthClass.compact);
      expect(widthClassOf(599.99), WidthClass.compact);
      expect(widthClassOf(600), WidthClass.medium);
      expect(widthClassOf(999), WidthClass.medium);
      expect(widthClassOf(999.99), WidthClass.medium);
      expect(widthClassOf(1000), WidthClass.expanded);
    });

    test('classifies the real device widths', () {
      expect(widthClassOf(412), WidthClass.compact); // phone portrait
      expect(widthClassOf(800), WidthClass.medium); //  9" tablet portrait
      expect(widthClassOf(915), WidthClass.medium); //  phone landscape
      expect(widthClassOf(1280), WidthClass.expanded); // 9" tablet landscape
    });

    test('a pane is classified by its own width, not the window', () {
      // A 400 px master list pane on a 1280 px tablet is compact, and that is
      // the correct answer — it is what keeps forms inside it single-column.
      expect(widthClassOf(400), WidthClass.compact);
      expect(AppLayout.forWidth(400).maxFormColumns, 1);
    });

    test('atLeastMedium / isExpanded', () {
      expect(WidthClass.compact.atLeastMedium, isFalse);
      expect(WidthClass.medium.atLeastMedium, isTrue);
      expect(WidthClass.expanded.atLeastMedium, isTrue);
      expect(WidthClass.compact.isExpanded, isFalse);
      expect(WidthClass.medium.isExpanded, isFalse);
      expect(WidthClass.expanded.isExpanded, isTrue);
    });
  });

  group('AppLayout.forWidth', () {
    test('maps each class to its bundle', () {
      expect(AppLayout.forWidth(412), same(AppLayout.compact));
      expect(AppLayout.forWidth(800), same(AppLayout.medium));
      expect(AppLayout.forWidth(1280), same(AppLayout.expanded));
    });

    test('only expanded unlocks panes', () {
      expect(AppLayout.compact.twoPane, isFalse);
      expect(AppLayout.medium.twoPane, isFalse);
      expect(AppLayout.expanded.twoPane, isTrue);
      expect(AppLayout.compact.listPaneWidth, 0);
      expect(AppLayout.medium.listPaneWidth, 0);
    });
  });

  group('the compact bundle is today\'s phone', () {
    // If any of these drift, every screen that reads a token without a
    // LayoutScope above it silently changes on the phone.
    test('holds the literals that are in the codebase today', () {
      expect(AppLayout.compact.gutter, 16);
      expect(AppLayout.compact.contentMaxWidth, double.infinity);
      expect(AppLayout.compact.formMaxWidth, double.infinity);
      expect(AppLayout.compact.readingMaxWidth, double.infinity);
      expect(AppLayout.compact.maxFormColumns, 1);
      expect(AppLayout.compact.touchTarget, 48);
      expect(AppLayout.compact.labelColumnWidth, 132);
      expect(AppLayout.compact.statTileWidth, double.infinity);
      expect(AppLayout.compact.searchMaxWidth, double.infinity);
      expect(AppLayout.compact.avatarRadius, 20);
      expect(AppLayout.compact.emptyStateIcon, 56);
      expect(AppLayout.compact.dialogPickers, isFalse);
      expect(AppLayout.compact.actionTileExtent, 0);
      expect(AppLayout.compact.actionTileHeight, 0);
    });
  });

  group('mechanical guards', () {
    test('no token anywhere equals 720', () {
      // test/tips_wizard_test.dart asserts that EXACTLY ONE ConstrainedBox with
      // maxWidth == 720 exists in the tips subtree. A shared 720 token would
      // fail a test that looks completely unrelated, months later. This is that
      // comment made executable.
      for (final layout in _all) {
        for (final token in _doubleTokens(layout)) {
          expect(token, isNot(720), reason: '${layout.width} has a 720 token');
        }
      }
    });

    test('gutter, maxFormColumns and touchTarget never decrease', () {
      for (var i = 1; i < _all.length; i++) {
        final narrow = _all[i - 1];
        final wide = _all[i];
        expect(wide.gutter, greaterThanOrEqualTo(narrow.gutter));
        expect(wide.maxFormColumns, greaterThanOrEqualTo(narrow.maxFormColumns));
        expect(wide.touchTarget, greaterThanOrEqualTo(narrow.touchTarget));
      }
    });

    test('touch targets grow because a logical pixel here is physically smaller', () {
      // 48dp is 7.3 mm at 168 px/in against ~8.2 mm on the 412 px phone this
      // replaces, so keeping 48 would ship physically smaller buttons.
      expect(AppLayout.compact.touchTarget, 48);
      expect(AppLayout.expanded.touchTarget, 56);
    });
  });

  group('formColumns', () {
    const noScale = TextScaler.noScaling;

    test('compact is always one column', () {
      expect(AppLayout.compact.formColumns(412, noScale), 1);
      expect(AppLayout.compact.formColumns(double.infinity, noScale), 1);
      expect(AppLayout.compact.formColumns(1280, noScale), 1);
    });

    test('an unbounded box falls back to one column', () {
      expect(AppLayout.expanded.formColumns(double.infinity, noScale), 1);
    });

    test('medium: 760 -> 2, 380 -> 1', () {
      expect(AppLayout.medium.formColumns(760, noScale), 2);
      expect(AppLayout.medium.formColumns(380, noScale), 1);
    });

    test('a 400 px list pane resolves to one column', () {
      expect(AppLayout.forWidth(400).formColumns(400, noScale), 1);
    });

    test('expanded at 1040 px — the spec conflict commit 2 flagged, now resolved', () {
      // Commit 2 copied the expanded bundle verbatim with fieldMinWidth 340 and
      // recorded that it made the spec's own two stated expectations impossible:
      // (1040 + 24) ~/ (340 + 24) == 2, and three columns first fit at 1116 px,
      // which the expanded formMaxWidth of 1040 can never reach -- so
      // maxFormColumns: 3 was dead. Commit 4 (the form engine, where the column
      // count becomes visible) took the decision the spec deferred and changed
      // ONE number: expanded fieldMinWidth 340 -> 330. The alternative,
      // formMaxWidth 1040 -> 1120, would have widened every form on the device.
      //
      // 3 * 330 + 2 * 24 == 1038, so 1040 fits three columns with 2 px to spare.
      expect(AppLayout.expanded.formColumns(1040, noScale), 3);
      expect(AppLayout.expanded.formColumns(1038, noScale), 3);
      // One pixel under the exact fit is two columns, not three.
      expect(AppLayout.expanded.formColumns(1037, noScale), 2);
      expect(AppLayout.expanded.formColumns(1120, noScale), 3);
      // NOTE FOR THE SCREEN COMMITS: reaching 1038 px of AVAILABLE width is a
      // separate question from the token. AdaptiveBody(maxWidth: formMaxWidth)
      // spends 2 * gutter (64 px at expanded) on padding, so a 1280 px window
      // hands the packer 976 px and gets two columns; the 240 px wizard step
      // rail takes it further down. Three columns need either gutter: false or
      // a window wider than the target device. That is a screen decision, not
      // a token one.
      expect(AppLayout.expanded.formColumns(1040 - 64, noScale), 2);
    });

    test('never exceeds maxFormColumns however wide the box', () {
      expect(AppLayout.medium.formColumns(4000, noScale), 2);
      expect(AppLayout.expanded.formColumns(4000, noScale), 3);
    });

    test('a large text scale spends the width on one fewer, wider column', () {
      // Nothing shrinks a label when the box is fixed, so above ~1.25x we drop
      // a column instead of overflowing. This is the Arabic-at-1.3x valve.
      expect(AppLayout.expanded.formColumns(1120, TextScaler.linear(1.3)), 2);
      // The spec's stated case: 1.3x at 1040 is two columns, not three.
      expect(AppLayout.expanded.formColumns(1040, TextScaler.linear(1.3)), 2);
      expect(AppLayout.medium.formColumns(760, TextScaler.linear(1.3)), 1);
      // 1.25x is 17.5 px on a 14 px body, which is the boundary and NOT a drop.
      expect(AppLayout.expanded.formColumns(1120, TextScaler.linear(1.25)), 3);
      expect(AppLayout.medium.formColumns(760, TextScaler.linear(1.25)), 2);
    });

    test('never drops below one column', () {
      expect(AppLayout.expanded.formColumns(10, noScale), 1);
      expect(AppLayout.expanded.formColumns(10, TextScaler.linear(2)), 1);
      expect(AppLayout.medium.formColumns(0, noScale), 1);
    });
  });

  group('formCellWidth', () {
    test('subtracts the gaps and divides', () {
      expect(AppLayout.formGap, 24);
      expect(AppLayout.expanded.formCellWidth(1040, 1), 1040);
      expect(AppLayout.expanded.formCellWidth(1040, 2), (1040 - 24) / 2);
      expect(AppLayout.expanded.formCellWidth(1120, 3), (1120 - 48) / 3);
    });

    test('a cell is never narrower than fieldMinWidth at the column count formColumns chose', () {
      for (final layout in _all) {
        for (final available in [400.0, 600.0, 760.0, 840.0, 1040.0, 1120.0, 1216.0]) {
          final n = layout.formColumns(available, TextScaler.noScaling);
          if (n > 1) {
            expect(layout.formCellWidth(available, n),
                greaterThanOrEqualTo(layout.fieldMinWidth),
                reason: '${layout.width} at $available px chose $n columns');
          }
        }
      }
    });
  });

  group('Breakpoints', () {
    test('content thresholds match widthClassOf', () {
      expect(Breakpoints.medium, 600);
      expect(Breakpoints.expanded, 1000);
      expect(widthClassOf(Breakpoints.medium), WidthClass.medium);
      expect(widthClassOf(Breakpoints.expanded), WidthClass.expanded);
    });

    test('tabletShortestSide clears the default 800x600 test surface', () {
      // 640, not 600: a widget test that forgets tester.view.physicalSize runs
      // at 800x600, where shortestSide >= 600 would silently be true. A 9"
      // tablet is 800 on its short side in both orientations, so 640 leaves
      // 160 px of margin on the real device.
      expect(Breakpoints.tabletShortestSide, 640);
      expect(600 >= Breakpoints.tabletShortestSide, isFalse);
      expect(412 >= Breakpoints.tabletShortestSide, isFalse);
      expect(800 >= Breakpoints.tabletShortestSide, isTrue);
    });

    test('window thresholds for the rail are ordered and above the content ones', () {
      // railModeFor and its gate-route table land with the shell in commit 6;
      // only the constants exist yet, so only the constants are asserted here.
      expect(Breakpoints.railWindowMin, 1000);
      expect(Breakpoints.railExtendedMin, 1200);
      expect(Breakpoints.railMinHeight, 560);
      expect(Breakpoints.railExtendedMin, greaterThan(Breakpoints.railWindowMin));
      expect(Breakpoints.railWindowMin, greaterThanOrEqualTo(Breakpoints.expanded));
      // A 915x412 phone landscape window fails the height gate.
      expect(412 >= Breakpoints.railMinHeight, isFalse);
      expect(800 >= Breakpoints.railMinHeight, isTrue);
    });
  });
}
