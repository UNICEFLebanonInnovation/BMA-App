import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A missing INTERNET permission only breaks release builds, which no widget
/// test and no debug run can catch: every request fails at the transport layer
/// and the app just reports "cannot reach the server". Guard the manifest.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');

  test('the release manifest grants the permissions the app needs', () {
    expect(manifest.existsSync(), isTrue, reason: 'run tests from the project root');
    final xml = manifest.readAsStringSync();
    expect(
      xml,
      contains('android.permission.INTERNET'),
      reason: 'without it a release APK cannot reach the BMA-NFE server',
    );
    expect(
      xml,
      contains('android.permission.ACCESS_NETWORK_STATE'),
      reason: 'the offline banner reads the connectivity state',
    );
  });

  test('the launcher shows a human app name', () {
    final xml = manifest.readAsStringSync();
    expect(xml, contains('android:label="BMA Mobile"'));
    expect(xml, isNot(contains('android:label="bma_app"')));
  });

  // The app is tablet-first for a 9-inch device in BOTH orientations. Any of
  // these three declarations would pin or letterbox it on a real tablet, and
  // none of them is visible from a widget test: the manifest is the only place
  // where "portrait only" can be switched on by accident.
  test('nothing in the manifest locks the orientation or the size', () {
    // Comments are stripped first: this very file's manifest explains WHY the
    // attributes are absent, and a substring match would find the explanation.
    final xml = _withoutComments(manifest.readAsStringSync());
    expect(
      xml,
      isNot(contains('android:screenOrientation')),
      reason: 'an orientation lock silently defeats the tablet layout',
    );
    expect(
      xml,
      isNot(contains('android:maxAspectRatio')),
      reason: 'a capped aspect ratio letterboxes the app on a 16:10 tablet',
    );
    expect(
      xml,
      isNot(contains('<supports-screens')),
      reason: 'legacy screen filtering can hide the app from large-screen devices',
    );
  });

  test('the activity declares itself resizeable and handles size changes itself', () {
    final xml = _withoutComments(manifest.readAsStringSync());
    expect(
      xml,
      contains('android:resizeableActivity="true"'),
      reason: 'older OEM 9-inch tablets still read it, and it states the intent in review',
    );
    // Without these, rotating a tablet recreates the activity instead of just
    // handing Flutter a new view size.
    for (final change in ['orientation', 'screenSize', 'smallestScreenSize', 'density', 'layoutDirection']) {
      expect(
        RegExp('android:configChanges="[^"]*\\b$change\\b').hasMatch(xml),
        isTrue,
        reason: 'configChanges must cover "$change" so rotation never recreates the activity',
      );
    }
    expect(
      xml,
      contains('android:windowSoftInputMode="adjustResize"'),
      reason: 'the form screens scroll the field into view instead of being covered',
    );
  });

  test('the debug and profile manifests add nothing size-related', () {
    for (final flavour in ['debug', 'profile']) {
      final file = File('android/app/src/$flavour/AndroidManifest.xml');
      if (!file.existsSync()) continue;
      final xml = file.readAsStringSync();
      expect(xml, isNot(contains('android:screenOrientation')), reason: '$flavour manifest');
      expect(xml, isNot(contains('android:maxAspectRatio')), reason: '$flavour manifest');
    }
  });
}

String _withoutComments(String xml) => xml.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
