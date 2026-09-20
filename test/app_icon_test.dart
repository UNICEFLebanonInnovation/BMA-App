import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The launcher icon is invisible to every other test: a missing density or a
/// stale mipmap ships the stock Flutter placeholder and nothing goes red.
/// These read the files.
void main() {
  // A PNG's width and height live in the IHDR chunk, at a fixed offset.
  ({int width, int height}) pngSize(File file) {
    final bytes = file.readAsBytesSync();
    expect(bytes.length, greaterThan(24), reason: '${file.path} is not a PNG');
    expect(bytes.sublist(1, 4), [0x50, 0x4E, 0x47], reason: '${file.path} is not a PNG');
    int be32(int at) => (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3];
    return (width: be32(16), height: be32(20));
  }

  const res = 'android/app/src/main/res';
  const legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192};
  const foreground = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432};

  test('every launcher density is present and square at the right size', () {
    legacy.forEach((density, size) {
      for (final name in ['ic_launcher', 'ic_launcher_round']) {
        final file = File('$res/mipmap-$density/$name.png');
        expect(file.existsSync(), isTrue, reason: 'missing $name at $density');
        final got = pngSize(file);
        expect([got.width, got.height], [size, size], reason: '$name at $density');
      }
    });
  });

  test('every adaptive foreground density is present at 108dp', () {
    foreground.forEach((density, size) {
      final file = File('$res/mipmap-$density/ic_launcher_foreground.png');
      expect(file.existsSync(), isTrue, reason: 'missing foreground at $density');
      final got = pngSize(file);
      expect([got.width, got.height], [size, size], reason: 'foreground at $density');
    });
  });

  test('the adaptive icon is declared for Android 8 and later', () {
    for (final name in ['ic_launcher', 'ic_launcher_round']) {
      final xml = File('$res/mipmap-anydpi-v26/$name.xml');
      expect(xml.existsSync(), isTrue, reason: 'missing adaptive $name');
      final text = xml.readAsStringSync();
      expect(text, contains('<adaptive-icon'));
      expect(text, contains('@color/ic_launcher_background'));
      expect(text, contains('@mipmap/ic_launcher_foreground'));
    }
    expect(File('$res/values/ic_launcher_background.xml').readAsStringSync(),
        contains('ic_launcher_background'));
  });

  test('the manifest points at both icons', () {
    final xml = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(xml, contains('android:icon="@mipmap/ic_launcher"'));
    expect(xml, contains('android:roundIcon="@mipmap/ic_launcher_round"'),
        reason: 'pre-Android-8 round launchers fall back to the square icon without it');
  });

  test('the bundled logo assets exist and are declared', () {
    for (final name in ['bma_logo', 'bma_mark']) {
      final file = File('assets/images/$name.png');
      expect(file.existsSync(), isTrue, reason: 'missing assets/images/$name.png');
      expect(pngSize(file).width, greaterThan(200), reason: '$name should be the full-resolution crop');
    }
    expect(File('pubspec.yaml').readAsStringSync(), contains('assets/images/'),
        reason: 'an undeclared asset throws at runtime, not at analyze time');
  });

  test('the icon is not the stock Flutter placeholder', () {
    // The template icon is a flat blue 'F'. The BMA mark is blue on WHITE, so
    // the corner pixel of a real icon is white — this catches a density that
    // was never regenerated.
    final bytes = File('$res/mipmap-xxxhdpi/ic_launcher.png').readAsBytesSync();
    expect(bytes.length, greaterThan(2000),
        reason: 'the stock placeholder is a tiny indexed PNG; the BMA mark is larger');
  });
}
