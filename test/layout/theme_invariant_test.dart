// Turns the phone-theme claim from stated into proven. ThemeData implements
// ==, so the whole "nothing changes on the phone" argument for commit 2 is one
// expect() away from being mechanical.
import 'package:bma_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    // fontFamilyFallback is a mutable static that the screenshot harness
    // writes; restore it so ordering between tests cannot matter.
    final saved = AppTheme.fontFamilyFallback;
    addTearDown(() => AppTheme.fontFamilyFallback = saved);
  });

  group('the phone theme is unchanged', () {
    test('light(tablet: false) == light()', () {
      expect(AppTheme.light(tablet: false), equals(AppTheme.light()));
    });

    test('cached(tablet: false) == light()', () {
      expect(AppTheme.cached(tablet: false), equals(AppTheme.light()));
    });

    test('the phone keeps every density literal it shipped with', () {
      final phone = AppTheme.light();
      expect(phone.inputDecorationTheme.isDense, isTrue);
      expect(
        phone.inputDecorationTheme.contentPadding,
        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );
      expect(
        phone.filledButtonTheme.style?.minimumSize?.resolve({}),
        const Size(48, 48),
      );
      expect(
        phone.outlinedButtonTheme.style?.minimumSize?.resolve({}),
        const Size(48, 48),
      );
      expect(
        phone.filledButtonTheme.style?.padding?.resolve({}),
        const EdgeInsets.symmetric(horizontal: 20),
      );
      expect(phone.segmentedButtonTheme.style?.minimumSize, isNull);
      expect(phone.listTileTheme.minVerticalPadding, isNull);
      expect(phone.appBarTheme.titleTextStyle?.fontSize, 20);
      expect(phone.chipTheme.labelStyle?.fontSize, 12);
      expect(phone.chipTheme.padding, const EdgeInsets.symmetric(horizontal: 6));
      // Null, not 14/16: ThemeData leaves body sizes unset and the localized
      // text geometry supplies them at render time (14 / 16 for englishLike).
      // The tablet branch sets them explicitly, which is what overrides the
      // geometry; the phone must stay unset so the geometry still wins.
      expect(phone.textTheme.bodyMedium?.fontSize, isNull);
      expect(phone.textTheme.bodyLarge?.fontSize, isNull);
      expect(phone.textTheme.titleMedium?.fontSize, isNull);
      expect(phone.textTheme.titleSmall?.fontSize, isNull);
      expect(phone.textTheme.labelLarge?.fontSize, isNull);
    });

    test('cardTheme.margin is deliberately identical on both densities', () {
      // The highest-leverage line in the file: every Card in the app is as wide
      // as the page because of it. Changing it would move every phone screen
      // and every tablet screen at once, with no way to bisect a regression.
      const margin = EdgeInsets.symmetric(horizontal: 12, vertical: 6);
      expect(AppTheme.light().cardTheme.margin, margin);
      expect(AppTheme.light(tablet: true).cardTheme.margin, margin);
    });

    test('AppColors and AppRadius are size-neutral and shared', () {
      final phone = AppTheme.light();
      final tablet = AppTheme.light(tablet: true);
      expect(tablet.colorScheme, phone.colorScheme);
      expect(tablet.scaffoldBackgroundColor, AppColors.background);
      expect(tablet.scaffoldBackgroundColor, phone.scaffoldBackgroundColor);
      expect(tablet.cardTheme.shape, phone.cardTheme.shape);
    });
  });

  group('the tablet density branch', () {
    test('differs from the phone theme at all', () {
      expect(AppTheme.light(tablet: true), isNot(equals(AppTheme.light())));
    });

    test('applies exactly the documented table', () {
      final tablet = AppTheme.light(tablet: true);
      expect(tablet.inputDecorationTheme.isDense, isFalse);
      expect(
        tablet.inputDecorationTheme.contentPadding,
        const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      );
      expect(
        tablet.filledButtonTheme.style?.minimumSize?.resolve({}),
        const Size(48, 56),
      );
      expect(
        tablet.outlinedButtonTheme.style?.minimumSize?.resolve({}),
        const Size(48, 56),
      );
      expect(
        tablet.filledButtonTheme.style?.padding?.resolve({}),
        const EdgeInsets.symmetric(horizontal: 24),
      );
      expect(
        tablet.segmentedButtonTheme.style?.minimumSize?.resolve({}),
        const Size(0, 56),
      );
      expect(tablet.listTileTheme.minVerticalPadding, 8);
      expect(tablet.appBarTheme.titleTextStyle?.fontSize, 22);
      expect(tablet.chipTheme.labelStyle?.fontSize, 13);
      expect(tablet.chipTheme.padding, const EdgeInsets.symmetric(horizontal: 8));
      expect(tablet.textTheme.bodyMedium?.fontSize, 15);
      expect(tablet.textTheme.bodyLarge?.fontSize, 17);
      expect(tablet.textTheme.titleMedium?.fontSize, 17);
      expect(tablet.textTheme.titleSmall?.fontSize, 15);
      expect(tablet.textTheme.labelLarge?.fontSize, 15);
      expect(
        tablet.filledButtonTheme.style?.textStyle?.resolve({})?.fontSize,
        16,
      );
    });

    test('adds a navigation rail theme the phone does not have', () {
      final rail = AppTheme.light(tablet: true).navigationRailTheme;
      expect(rail.backgroundColor, AppColors.surface);
      expect(rail.indicatorColor, AppColors.surfaceAlt);
      expect(rail.elevation, 0);
      expect(rail.selectedIconTheme?.color, AppColors.primary);
      expect(rail.unselectedIconTheme?.color, AppColors.muted);
      expect(rail.selectedLabelTextStyle?.color, AppColors.primary);
      expect(rail.unselectedLabelTextStyle?.color, AppColors.muted);
      expect(AppTheme.light().navigationRailTheme, const NavigationRailThemeData());
    });

    test('text styles are derived from the text theme, never replaced', () {
      // A bare TextStyle replaces rather than merges and would drop the Arabic
      // font fallback, which is invisible until an Arabic capture is rendered.
      AppTheme.fontFamilyFallback = const ['NotoSansArabic'];
      for (final theme in [AppTheme.light(), AppTheme.light(tablet: true)]) {
        for (final style in <TextStyle?>[
          theme.appBarTheme.titleTextStyle,
          theme.chipTheme.labelStyle,
          theme.filledButtonTheme.style?.textStyle?.resolve({}),
          theme.inputDecorationTheme.labelStyle,
          theme.navigationRailTheme.selectedLabelTextStyle,
          theme.navigationRailTheme.unselectedLabelTextStyle,
        ]) {
          if (style == null) continue;
          expect(style.fontFamilyFallback, contains('NotoSansArabic'));
        }
      }
    });
  });

  group('cached', () {
    test('memoises per density', () {
      expect(identical(AppTheme.cached(tablet: false), AppTheme.cached(tablet: false)), isTrue);
      expect(identical(AppTheme.cached(tablet: true), AppTheme.cached(tablet: true)), isTrue);
      expect(identical(AppTheme.cached(tablet: false), AppTheme.cached(tablet: true)), isFalse);
      // Both densities stay live, so rotating between them is not a rebuild.
      final phone = AppTheme.cached(tablet: false);
      AppTheme.cached(tablet: true);
      expect(identical(AppTheme.cached(tablet: false), phone), isTrue);
    });

    test('picks up a change to fontFamilyFallback', () {
      // The screenshot harness writes this static before pumping; a bool-only
      // memo key would freeze the wrong fonts into every Arabic capture.
      AppTheme.fontFamilyFallback = const [];
      final withoutArabic = AppTheme.cached(tablet: false);
      expect(withoutArabic.textTheme.bodyMedium?.fontFamilyFallback ?? const [],
          isNot(contains('NotoSansArabic')));

      AppTheme.fontFamilyFallback = const ['NotoSansArabic'];
      final withArabic = AppTheme.cached(tablet: false);
      expect(identical(withArabic, withoutArabic), isFalse);
      expect(withArabic.textTheme.bodyMedium?.fontFamilyFallback, contains('NotoSansArabic'));
      expect(identical(AppTheme.cached(tablet: false), withArabic), isTrue);
    });
  });
}
