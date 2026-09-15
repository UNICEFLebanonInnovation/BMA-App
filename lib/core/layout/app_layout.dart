// The token bundle + the InheritedWidget that distributes it.
import 'package:flutter/widgets.dart';

import 'breakpoints.dart';

/// Immutable bundle of layout tokens derived from one [WidthClass].
///
/// RULE: every `compact` value below is the literal that is in the codebase
/// today. A widget that reads these tokens and finds no [LayoutScope] above it
/// gets [AppLayout.compact] and therefore renders exactly as it does now.
/// That fallback is what lets this work land screen by screen.
@immutable
class AppLayout {
  const AppLayout({
    required this.width,
    required this.gutter,
    required this.contentMaxWidth,
    required this.formMaxWidth,
    required this.readingMaxWidth,
    required this.maxFormColumns,
    required this.fieldMinWidth,
    required this.listPaneWidth,
    required this.sessionPaneWidth,
    required this.identityPaneWidth,
    required this.stepRailWidth,
    required this.touchTarget,
    required this.actionTileExtent,
    required this.actionTileHeight,
    required this.labelColumnWidth,
    required this.statTileWidth,
    required this.searchMaxWidth,
    required this.avatarRadius,
    required this.emptyStateIcon,
    required this.dialogPickers,
  });

  final WidthClass width;

  /// Page side padding.
  final double gutter;

  /// Centred caps. NONE of these may ever be 720: test/tips_wizard_test.dart
  /// asserts exactly one ConstrainedBox with maxWidth == 720 exists in the tips
  /// subtree, and a shared 720 token would fail a test that looks unrelated.
  final double contentMaxWidth;
  final double formMaxWidth;
  final double readingMaxWidth;

  /// Upper bound on form columns; [formColumns] clamps down by real width.
  final int maxFormColumns;
  final double fieldMinWidth;

  /// Fixed pane widths (0 below expanded — panes do not exist there).
  final double listPaneWidth;
  final double sessionPaneWidth;
  final double identityPaneWidth;
  final double stepRailWidth;

  /// Minimum height for a primary action. 48dp is 7.3 mm on this 168 px/in
  /// panel versus ~8.2 mm on the Pixel 7 it replaces, so the tablet floor is
  /// higher, not equal.
  final double touchTarget;

  /// maxCrossAxisExtent / mainAxisExtent for the home action grid. 0 at
  /// compact, where GridView.count(3 or 4) is kept verbatim.
  final double actionTileExtent;
  final double actionTileHeight;

  /// FactRow / InfoLine label column (today: 132 and 140 respectively).
  final double labelColumnWidth;

  /// Caps a StatTile so two tiles stop being 610 px wide for a two-digit number.
  final double statTileWidth;

  final double searchMaxWidth;
  final double avatarRadius;
  final double emptyStateIcon;

  /// Reference / service pickers become a centred dialog instead of a
  /// full-bleed bottom sheet.
  final bool dialogPickers;

  bool get twoPane => width.isExpanded;

  static const AppLayout compact = AppLayout(
    width: WidthClass.compact,
    gutter: 16,
    contentMaxWidth: double.infinity,
    formMaxWidth: double.infinity,
    readingMaxWidth: double.infinity,
    maxFormColumns: 1,
    fieldMinWidth: 320,
    listPaneWidth: 0,
    sessionPaneWidth: 0,
    identityPaneWidth: 0,
    stepRailWidth: 0,
    touchTarget: 48,
    actionTileExtent: 0,
    actionTileHeight: 0,
    labelColumnWidth: 132,
    statTileWidth: double.infinity,
    searchMaxWidth: double.infinity,
    avatarRadius: 20,
    emptyStateIcon: 56,
    dialogPickers: false,
  );

  static const AppLayout medium = AppLayout(
    width: WidthClass.medium,
    gutter: 24,
    contentMaxWidth: 840,
    formMaxWidth: 760,
    readingMaxWidth: 700,
    maxFormColumns: 2,
    fieldMinWidth: 320,
    listPaneWidth: 0,
    sessionPaneWidth: 0,
    identityPaneWidth: 0,
    stepRailWidth: 0,
    touchTarget: 52,
    actionTileExtent: 132,
    actionTileHeight: 116,
    labelColumnWidth: 180,
    statTileWidth: 260,
    searchMaxWidth: 420,
    avatarRadius: 24,
    emptyStateIcon: 72,
    dialogPickers: true,
  );

  static const AppLayout expanded = AppLayout(
    width: WidthClass.expanded,
    gutter: 32,
    contentMaxWidth: 1120,
    formMaxWidth: 1040,
    readingMaxWidth: 760,
    maxFormColumns: 3,
    // 330, not the 340 the spec's bundle first gave. Commit 2 flagged the
    // arithmetic: with 340 and a 24 px gap, three columns first fit at 1116 px,
    // which the expanded formMaxWidth of 1040 can never reach, so
    // maxFormColumns: 3 was unreachable and the spec's own two stated tests
    // ("1040 -> 3" and "1040 at 1.3x -> 2, not 3") both failed. 330 makes
    // exactly those two true and is the smaller of the two one-number fixes.
    fieldMinWidth: 330,
    listPaneWidth: 400,
    sessionPaneWidth: 360,
    identityPaneWidth: 340,
    stepRailWidth: 240,
    touchTarget: 56,
    actionTileExtent: 148,
    actionTileHeight: 124,
    labelColumnWidth: 200,
    statTileWidth: 280,
    searchMaxWidth: 420,
    avatarRadius: 26,
    emptyStateIcon: 72,
    dialogPickers: true,
  );

  static AppLayout forWidth(double width) => switch (widthClassOf(width)) {
        WidthClass.compact => AppLayout.compact,
        WidthClass.medium => AppLayout.medium,
        WidthClass.expanded => AppLayout.expanded,
      };

  /// Gap between form columns. Kept here so the packer and the cell width
  /// calculation cannot disagree.
  static const double formGap = 24;

  /// How many columns fit in [available] logical pixels.
  ///
  /// The [scaler] term is the safety valve for Arabic at 1.3x: nothing shrinks
  /// a label when the box is fixed, so above ~1.25x text scale we spend the
  /// width on one fewer, wider column instead of overflowing.
  int formColumns(double available, TextScaler scaler) {
    if (maxFormColumns <= 1 || !available.isFinite) return 1;
    var n = ((available + formGap) ~/ (fieldMinWidth + formGap));
    if (n < 1) n = 1;
    if (n > maxFormColumns) n = maxFormColumns;
    if (scaler.scale(14) > 17.5 && n > 1) n -= 1;
    return n;
  }

  /// Width of one cell in an [n]-column row of [available] pixels.
  double formCellWidth(double available, int n) =>
      (available - formGap * (n - 1)) / n;
}

/// Publishes an [AppLayout] measured from a real box. Installed by
/// [AdaptiveBody] and re-installed by every pane, so nested content
/// re-derives its own class.
class LayoutScope extends InheritedWidget {
  const LayoutScope({super.key, required this.layout, required super.child});

  final AppLayout layout;

  /// Falls back to [AppLayout.compact] when no scope is installed. This is the
  /// property that makes the phone fallback safe by construction — do not
  /// change it to an assert.
  static AppLayout of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LayoutScope>()?.layout ??
      AppLayout.compact;

  @override
  bool updateShouldNotify(LayoutScope oldWidget) =>
      !identical(oldWidget.layout, layout);
}

/// Device-class question. Legitimate uses: bottom sheet vs dialog, the tips
/// wizard's icon size, and the theme's density branch. NEVER for columns,
/// panes or the rail — a tablet can be handed a 400 px window.
bool isTabletDevice(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= Breakpoints.tabletShortestSide;
