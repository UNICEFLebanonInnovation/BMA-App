// Pure width classification. No tokens, no widgets, no Flutter import: this
// file is deliberately dependency-free so a unit test can reason about widths
// without pumping anything.

/// Width class of the BOX a widget is drawing into — never of the window and
/// never of the device. A form inside a 400 px pane on a 1280 px tablet is
/// [WidthClass.compact], and that is the correct answer.
enum WidthClass {
  /// < 600. Phone portrait (412), a master list pane, a narrow split-screen
  /// window. Always one column; always today's layout.
  compact,

  /// 600–999. 9" tablet portrait (800), phone landscape (915), half of a
  /// 1280 landscape window in Android split-screen (640).
  medium,

  /// >= 1000. 9" tablet landscape (1280). The only class that unlocks panes.
  expanded;

  bool get atLeastMedium => index >= WidthClass.medium.index;
  bool get isExpanded => this == WidthClass.expanded;
}

class Breakpoints {
  Breakpoints._();

  /// Content thresholds — read by [AppLayout.forWidth] from a measured box.
  static const double medium = 600;
  static const double expanded = 1000;

  /// Window thresholds — read ONLY by the shell (see lib/core/layout/adaptive_shell.dart).
  /// The rail consumes width, so deciding whether it exists from a pane-derived
  /// class would feed the rail's own presence back into the measurement.
  static const double railWindowMin = 1000;
  static const double railExtendedMin = 1200;

  /// A rail of eight ~56 px destinations does not fit a 412 px-tall phone
  /// landscape window.
  static const double railMinHeight = 560;

  /// Device-class question, used for MODALITY ONLY (bottom sheet vs dialog).
  /// 640, not 600: Flutter's default widget-test surface is 800x600, where
  /// `shortestSide >= 600` silently evaluates true in any test that forgets
  /// `tester.view.physicalSize`. A 9" tablet's shortest side is 800 in both
  /// orientations, so 640 is safe with 160 px of margin.
  static const double tabletShortestSide = 640;
}

WidthClass widthClassOf(double width) => width >= Breakpoints.expanded
    ? WidthClass.expanded
    : width >= Breakpoints.medium
        ? WidthClass.medium
        : WidthClass.compact;
