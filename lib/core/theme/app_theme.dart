import 'package:flutter/material.dart';

/// Colours taken from the BMA-NFE redesign specification (DOCS_REDESIGN.md):
/// UNICEF-inspired deep blue primary, light blue secondary, green success and
/// a light grey working background.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF003366);
  static const Color secondary = Color(0xFF00ADEF);
  static const Color success = Color(0xFF28A745);
  static const Color warning = Color(0xFFF0AD4E);
  static const Color danger = Color(0xFFDC3545);
  static const Color background = Color(0xFFF4F7F6);
  static const Color surface = Colors.white;
  static const Color muted = Color(0xFF6C757D);
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
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamilyFallback: fontFamilyFallback.isEmpty ? null : fontFamilyFallback,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        elevation: 1,
        margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 44),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 44)),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        indicatorColor: AppColors.secondary,
      ),
      dividerTheme: const DividerThemeData(space: 1),
    );

    // The chip label style replaces (rather than merges with) the Material
    // default, so derive it from the text theme to keep the font family and
    // fallback fonts.
    return base.copyWith(
      chipTheme: ChipThemeData(
        labelStyle: base.textTheme.labelLarge?.copyWith(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
    );
  }
}
