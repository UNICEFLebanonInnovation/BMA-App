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
}
