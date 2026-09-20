import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Viewport helpers for widget tests.
///
/// WHY THIS FILE EXISTS: Flutter's default test surface is 800x600. 800 px
/// resolves to [WidthClass.medium], so from the tablet work onwards a widget
/// test that forgets `tester.view.physicalSize` silently exercises the TABLET
/// layout while reading like a phone test. Every widget test picks one of
/// these three, and each resets the view on tear-down.

/// Pixel 7-class phone portrait. The fallback device this work must not move.
void phone(WidgetTester tester) => _set(tester, 412, 915, 2.625);

/// 9-inch tablet portrait — the registration posture.
void tabletPortrait(WidgetTester tester) => _set(tester, 800, 1280, 2.0);

/// 9-inch tablet landscape — the desk posture this work targets.
void tabletLandscape(WidgetTester tester) => _set(tester, 1280, 800, 2.0);

/// Phone landscape. Wide (915) but only 412 tall, which is what the rail's
/// height gate exists for.
void phoneLandscape(WidgetTester tester) => _set(tester, 915, 412, 2.625);

/// An arbitrary logical window at the tablet's pixel ratio, for the sizes the
/// four presets do not name: `android:resizeableActivity="true"` means the app
/// can be handed a freeform/desktop window of any size on the target tablet,
/// and the navigation rail's own thresholds (1000, 1200) and height gate live
/// between the presets.
void freeformWindow(WidgetTester tester, double w, double h) => _set(tester, w, h, 2.0);

void _set(WidgetTester tester, double w, double h, double dpr) {
  tester.view.physicalSize = Size(w * dpr, h * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
}
