import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// Outcome of checking a server address before the user signs in.
enum ServerCheck {
  /// The address answers and speaks the BMA-NFE mobile API.
  ok,

  /// Something answered, but the mobile API is not installed there.
  notBmaServer,

  /// Nothing answered: wrong address, no network or the server is down.
  unreachable,
}

/// Verifies a server address from the first-run setup screen.
///
/// The login endpoint only accepts POST, so an unauthenticated GET is a cheap
/// probe: a deployment running the mobile API answers 405 (or 401/403/200),
/// while a host without it answers 404.
class ServerProbe {
  const ServerProbe();

  static const _path = '${AppConfig.apiPrefix}/auth/login/';

  Future<ServerCheck> check(String baseUrl, {Dio? dio}) async {
    final client = dio ?? Dio();
    client.options
      ..connectTimeout = AppConfig.connectTimeout
      ..receiveTimeout = AppConfig.connectTimeout
      ..followRedirects = true
      ..headers = {'Accept': 'application/json'}
      // Assigned last: a cascade after an arrow function parses as part of it.
      ..validateStatus = (_) => true;
    try {
      final response = await client.get<dynamic>('$baseUrl$_path');
      final status = response.statusCode ?? 0;
      if (status == 404 || status == 0) return ServerCheck.notBmaServer;
      if (status >= 500) return ServerCheck.unreachable;
      // 405 is the expected answer, 401/403/200 also prove the API is there.
      return ServerCheck.ok;
    } on DioException {
      return ServerCheck.unreachable;
    } finally {
      if (dio == null) client.close(force: true);
    }
  }
}

/// Overridden in tests with a stub that never touches the network.
final serverProbeProvider = Provider<ServerProbe>((ref) => const ServerProbe());
