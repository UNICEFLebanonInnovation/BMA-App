import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../analytics_models.dart';

/// Colours the charts draw with. Three jobs, three rules:
///
/// * [categorical] — identity. Eight hues in a FIXED order that passes the
///   colour-vision-deficiency separation checks (adjacent ΔE ≥ 8 in OKLab,
///   validated with the data-viz palette validator against a white card);
///   series keep their slot when a filter removes their neighbours, and a
///   ninth series is never invented — the data layer folds the tail into
///   "Other" first ([foldTail] in analytics_models.dart).
/// * [sequentialBlue] / [sequentialGreen] — magnitude. One hue, light to
///   dark, for the cross-tab and the attendance heatmaps.
/// * status — meaning. The app's own success / warning / danger tokens, only
///   where a colour MEANS good or bad (the learning-outcome bands and
///   progress), never for a plain series.
class ChartPalette {
  ChartPalette._();

  static const List<Color> categorical = [
    Color(0xFF2A78D6), // blue
    Color(0xFFEB6834), // orange
    Color(0xFF1BAF7A), // aqua
    Color(0xFFEDA100), // yellow
    Color(0xFFE87BA4), // magenta
    Color(0xFF008300), // green
    Color(0xFF4A3AA7), // violet
    Color(0xFFE34948), // red
  ];

  /// Slot [index] of the categorical order. Callers fold to at most eight
  /// entries before asking, so the modulo only guards against a bad index.
  static Color series(int index) => categorical[index % categorical.length];

  /// A single-series chart uses slot 1 for every bar: colouring bars by size
  /// would double-encode the length the reader already sees.
  static const Color single = Color(0xFF2A78D6);

  /// The de-emphasis grey for context marks and the "Other" fold.
  static const Color muted = Color(0xFFB4BEC8);

  /// Track behind a bar and the "no data" cell of a heatmap.
  static const Color track = AppColors.background;

  static const Color gridline = Color(0xFFE3E9EF);

  /// Status colours for the ordered learning-outcome bands.
  static const Color good = AppColors.success;
  static const Color middling = AppColors.warning;
  static const Color poor = AppColors.danger;

  static const Color _blueLight = Color(0xFFDCEBFB);
  static const Color _blueMid = Color(0xFF5598E7);
  static const Color _blueDark = Color(0xFF0D366B);

  static const Color _greenLight = Color(0xFFDDF1E3);
  static const Color _greenMid = Color(0xFF5CBF70);
  static const Color _greenDark = Color(0xFF1A6E2E);

  /// Light → dark blue for a value in 0..1.
  static Color sequentialBlue(double t) => _ramp(t, _blueLight, _blueMid, _blueDark);

  /// Light → dark green for a rate in 0..1 (attendance: more present is darker).
  static Color sequentialGreen(double t) => _ramp(t, _greenLight, _greenMid, _greenDark);

  /// Ink that stays readable on a sequential cell: white on the dark half.
  static Color inkOn(double t) => t > 0.55 ? Colors.white : AppColors.primary;

  static Color _ramp(double t, Color light, Color mid, Color dark) {
    final v = t.isNaN ? 0.0 : t.clamp(0.0, 1.0);
    return v < 0.5 ? Color.lerp(light, mid, v * 2)! : Color.lerp(mid, dark, (v - 0.5) * 2)!;
  }
}

/// Gender keeps ONE slot per value across every chart in the app: male blue,
/// female orange, unknown and the folded tail grey. Colour follows the
/// entity, so filtering one gender out never repaints the other.
Color genderColor(int index, ChartItem item) => switch (item.key) {
      'Male' => ChartPalette.categorical[0],
      'Female' => ChartPalette.categorical[1],
      'Unknown' || '' || '__other__' => ChartPalette.muted,
      _ => ChartPalette.series(index + 2),
    };
