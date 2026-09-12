import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits `true` while the device has some network interface up. It does not
/// guarantee the server is reachable; the sync engine handles that.
final connectivityProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  final controller = StreamController<bool>();

  bool isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  connectivity.checkConnectivity().then((results) {
    if (!controller.isClosed) controller.add(isOnline(results));
  }).catchError((_) {
    if (!controller.isClosed) controller.add(true);
  });
  final sub = connectivity.onConnectivityChanged.listen(
    (results) => controller.add(isOnline(results)),
    onError: (_) => controller.add(true),
  );
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
});

final isOnlineProvider = Provider<bool>((ref) => ref.watch(connectivityProvider).value ?? true);
