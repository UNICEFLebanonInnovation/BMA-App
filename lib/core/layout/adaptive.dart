// The three primitives every screen uses.
import 'package:flutter/material.dart';

import 'app_layout.dart';

/// Measures its own box, installs a [LayoutScope], centres the content at a
/// cap and applies a directional gutter.
///
/// `heightFactor: 1` on the Align is deliberate: it lets this be used inside a
/// ListView (unbounded height) as well as as a screen body.
class AdaptiveBody extends StatelessWidget {
  const AdaptiveBody({
    super.key,
    required this.child,
    this.maxWidth,
    this.gutter = true,
  });

  final Widget child;

  /// Defaults to `layout.contentMaxWidth`. Pass `layout.formMaxWidth` or
  /// `layout.readingMaxWidth` for forms and reading pages.
  final double? maxWidth;
  final bool gutter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = AppLayout.forWidth(constraints.maxWidth);
        final g = gutter ? layout.gutter : 0.0;
        return LayoutScope(
          layout: layout,
          child: Align(
            alignment: AlignmentDirectional.topCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth ?? layout.contentMaxWidth,
              ),
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(g, 0, g, 0),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Fixed leading pane + flexible trailing pane at `expanded`, and nothing at
/// all below it — [pane] is returned verbatim, so the phone tree gains no
/// wrapper. A plain [Row] mirrors under Directionality.rtl, so in Arabic the
/// list pane lands on the right with no extra code.
class TwoPane extends StatelessWidget {
  const TwoPane({
    super.key,
    required this.pane,
    required this.detail,
    this.paneWidth,
    this.placeholder,
  });

  final Widget pane;
  final Widget? detail;
  final double? paneWidth;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    final layout = LayoutScope.of(context);
    if (!layout.twoPane) return pane;
    final w = paneWidth ?? layout.listPaneWidth;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: w, child: _Scoped(width: w, child: pane)),
        const VerticalDivider(width: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => LayoutScope(
              layout: AppLayout.forWidth(c.maxWidth),
              child: detail ?? placeholder ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
  }
}

class _Scoped extends StatelessWidget {
  const _Scoped({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      LayoutScope(layout: AppLayout.forWidth(width), child: child);
}
