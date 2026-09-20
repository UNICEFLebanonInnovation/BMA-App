import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout/breakpoints.dart';

/// Palette taken from the BMA-NFE redesign specification: UNICEF-inspired deep
/// blue primary, light blue secondary, green success, on a soft neutral ground.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF003366);
  static const Color primaryBright = Color(0xFF0B4F8A);
  static const Color secondary = Color(0xFF00ADEF);
  static const Color success = Color(0xFF28A745);
  static const Color warning = Color(0xFFF0AD4E);
  static const Color danger = Color(0xFFDC3545);

  /// Page ground. Slightly cool so white cards lift off it without shadows.
  static const Color background = Color(0xFFF4F7FA);
  static const Color surface = Colors.white;

  /// Tinted surface for headers, tonal tiles and selected rows.
  static const Color surfaceAlt = Color(0xFFEAF1F8);

  /// Hairline that replaces heavy card elevation.
  static const Color border = Color(0xFFDCE4EC);

  /// Secondary text. Meets AA on [background] and on white.
  static const Color muted = Color(0xFF5B6976);
}

/// Shared shape tokens, so cards, fields and buttons agree.
class AppRadius {
  AppRadius._();

  static const double card = 16;
  static const double control = 12;
  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(card));
  static const BorderRadius controlRadius = BorderRadius.all(Radius.circular(control));
}

class AppTheme {
  AppTheme._();

  /// Extra font families tried when a glyph is missing from the default
  /// font (used by the screenshot harness to render Arabic on the host).
  static List<String> fontFamilyFallback = const [];

  /// At most two live entries — one per density — for the CURRENT
  /// [fontFamilyFallback]. The fallback list has to take part in the key
  /// because it is a mutable static that the screenshot harness writes before
  /// pumping; a bool-only cache would freeze the wrong fonts into the captures.
  static final Map<String, ThemeData> _cache = <String, ThemeData>{};

  /// Memoised [light]. Called from a `MaterialApp.router` builder on every
  /// frame (including every keystroke, because `adjustResize` moves
  /// `viewInsets` continuously), so it must not rebuild a ThemeData each time.
  static ThemeData cached({required bool tablet}) {
    final fonts = fontFamilyFallback.join(',');
    final key = '$tablet|$fonts';
    final hit = _cache[key];
    if (hit != null) return hit;
    _cache.removeWhere((k, _) => !k.endsWith('|$fonts'));
    final theme = light(tablet: tablet);
    _cache[key] = theme;
    return theme;
  }

  /// The app theme.
  ///
  /// [tablet] turns on the density branch — larger controls, non-dense fields
  /// and a ~1.07x type ramp. It follows the DEVICE (`shortestSide >= 640`, see
  /// [Breakpoints.tabletShortestSide]), never the box a widget is drawing into:
  /// a 16 px button label must not shrink because the button happens to sit in
  /// a 360 px pane, and it must not change when the tablet rotates. Columns and
  /// panes are the opposite — they read the measured box via `LayoutScope`.
  ///
  /// INVARIANT, asserted by test/layout/theme_invariant_test.dart:
  /// `AppTheme.light(tablet: false) == AppTheme.light()`. Every branch below
  /// must therefore fall back to the exact value that shipped on the phone.
  static ThemeData light({bool tablet = false}) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      error: AppColors.danger,
    ).copyWith(
      surfaceContainerLowest: AppColors.surface,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surfaceAlt,
      outlineVariant: AppColors.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamilyFallback: fontFamilyFallback.isEmpty ? null : fontFamilyFallback,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        // Dropping isDense is the single biggest "this is not a phone" cue,
        // and it fixes touch in four places that are not buttons: the schema
        // date and reference fields and the attendance centre and date pickers
        // are bare InputDecorators whose whole tap height is this padding.
        // Dense 14/14 is ~46 px; non-dense 16/18 is ~58 px.
        isDense: !tablet,
        contentPadding: tablet
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 18)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.controlRadius,
          borderSide: BorderSide(color: AppColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          // Physical-size arithmetic, written down so nobody "simplifies" it
          // back to 48: at 1280 logical px across the ~7.6 inch long edge of a
          // 9 inch 16:10 panel one logical pixel is 1/168 inch = 0.151 mm, so
          // 48dp is 7.3 mm here against ~8.2 mm on the 412 px Pixel 7 this
          // replaces. Keeping 48 would ship physically SMALLER buttons to the
          // bigger device; 56dp is 8.5 mm.
          minimumSize: Size(48, tablet ? 56 : 48),
          padding: EdgeInsets.symmetric(horizontal: tablet ? 24 : 20),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: Size(48, tablet ? 56 : 48),
          side: const BorderSide(color: AppColors.border),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryBright,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.surfaceAlt,
          selectedForegroundColor: AppColors.primary,
          // Attendance Present/Absent is tapped ~25 times per class by someone
          // standing up; the tips wizard already hand-rolls Size(0, 52) locally.
          minimumSize: tablet ? const Size(0, 56) : null,
          side: const BorderSide(color: AppColors.border),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
        minVerticalPadding: tablet ? 8 : null,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.surfaceAlt,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(space: 1, thickness: 1, color: AppColors.border),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
      ),
      dialogTheme: const DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.cardRadius),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.border,
      ),
    );

    // The chip label style replaces (rather than merges with) the Material
    // default, so derive it from the text theme to keep the font family and
    // fallback fonts.
    final buttonLabel =
        base.textTheme.labelLarge?.copyWith(fontSize: tablet ? 16 : 15, fontWeight: FontWeight.w600);
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle:
            base.textTheme.titleLarge?.copyWith(color: AppColors.primary, fontSize: tablet ? 22 : 20),
      ),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        labelStyle: base.textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        floatingLabelStyle:
            base.textTheme.bodyMedium?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: base.filledButtonTheme.style?.copyWith(textStyle: WidgetStatePropertyAll(buttonLabel)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: base.outlinedButtonTheme.style?.copyWith(textStyle: WidgetStatePropertyAll(buttonLabel)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: base.textButtonTheme.style?.copyWith(textStyle: WidgetStatePropertyAll(buttonLabel)),
      ),
      chipTheme: ChipThemeData(
        labelStyle: base.textTheme.labelLarge?.copyWith(fontSize: tablet ? 13 : 12),
        padding: EdgeInsets.symmetric(horizontal: tablet ? 8 : 6),
        side: const BorderSide(color: AppColors.border),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(999))),
      ),
      // Absent on the phone: passing null to copyWith keeps ThemeData's own
      // default instance, so light(tablet: false) stays equal to light().
      navigationRailTheme: tablet
          ? NavigationRailThemeData(
              backgroundColor: AppColors.surface,
              indicatorColor: AppColors.surfaceAlt,
              elevation: 0,
              selectedIconTheme: const IconThemeData(color: AppColors.primary),
              unselectedIconTheme: const IconThemeData(color: AppColors.muted),
              selectedLabelTextStyle: base.textTheme.labelMedium
                  ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
              unselectedLabelTextStyle: base.textTheme.labelMedium?.copyWith(color: AppColors.muted),
            )
          : null,
      // A deliberately modest ~1.07x ramp. Bigger is tempting at 168 px/in, but
      // the suite pins "no overflow at TextScaler.linear(1.3)" in two places
      // and halving field widths spends the same budget. Every tablet-only size
      // is expressed as `tablet ? x : null` because copyWith(null) is a no-op,
      // which is what keeps the phone text theme byte-identical.
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: base.textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600, fontSize: tablet ? 17 : null),
        titleSmall: tablet ? base.textTheme.titleSmall?.copyWith(fontSize: 15) : null,
        bodyLarge: tablet ? base.textTheme.bodyLarge?.copyWith(fontSize: 17) : null,
        bodyMedium: tablet ? base.textTheme.bodyMedium?.copyWith(fontSize: 15) : null,
        labelLarge: tablet ? base.textTheme.labelLarge?.copyWith(fontSize: 15) : null,
      ),
    );
  }
}
