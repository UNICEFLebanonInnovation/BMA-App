import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  static ThemeData light() {
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
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(48, 48),
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
          side: const BorderSide(color: AppColors.border),
          shape: const RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.controlRadius),
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
    final buttonLabel = base.textTheme.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600);
    return base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: base.textTheme.titleLarge?.copyWith(color: AppColors.primary, fontSize: 20),
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
        labelStyle: base.textTheme.labelLarge?.copyWith(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        side: const BorderSide(color: AppColors.border),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(999))),
      ),
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
