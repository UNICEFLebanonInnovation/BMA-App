import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../config/settings_controller.dart';
import 'api_exception.dart';

/// Thin wrapper around `dio` that adds the token header, the API prefix and
/// maps transport/HTTP failures to [ApiException].
class ApiClient {
  ApiClient({required String baseUrl, String? token, Dio? dio}) : _dio = dio ?? Dio() {
    _token = token;
    _dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = AppConfig.connectTimeout
      ..receiveTimeout = AppConfig.receiveTimeout
      ..sendTimeout = AppConfig.receiveTimeout
      ..headers = {'Accept': 'application/json', 'Accept-Language': 'en'}
      ..responseType = ResponseType.json
      ..validateStatus = (_) => true;
  }

  final Dio _dio;
  String? _token;

  String get baseUrl => _dio.options.baseUrl;

  set token(String? value) => _token = value;

  set language(String code) => _dio.options.headers['Accept-Language'] = code;

  Map<String, String> get _authHeaders => _token == null ? const {} : {'Authorization': 'Token $_token'};

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    return _run(() => _dio.get<dynamic>('${AppConfig.apiPrefix}$path',
        queryParameters: query, options: Options(headers: _authHeaders)));
  }

  Future<Map<String, dynamic>> post(String path, Object? body, {bool auth = true}) async {
    return _run(() => _dio.post<dynamic>('${AppConfig.apiPrefix}$path',
        data: body, options: Options(headers: auth ? _authHeaders : const {})));
  }

  Future<Map<String, dynamic>> _run(Future<Response<dynamic>> Function() call) async {
    Response<dynamic> response;
    try {
      response = await call();
    } on DioException catch (e) {
      throw ApiException(ApiErrorKind.network, e.message ?? 'Network error', data: e);
    }
    final status = response.statusCode ?? 0;
    final data = response.data;
    if (status >= 200 && status < 300) {
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'result': data};
    }
    final message = _extractMessage(data, status);
    switch (status) {
      case 401:
        throw ApiException(ApiErrorKind.unauthorized, message, statusCode: status, data: data);
      case 403:
        throw ApiException(ApiErrorKind.forbidden, message, statusCode: status, data: data);
      case 404:
        throw ApiException(ApiErrorKind.notFound, message, statusCode: status, data: data);
      case 400:
        throw ApiException(ApiErrorKind.validation, message, statusCode: status, data: data);
      default:
        throw ApiException(status >= 500 ? ApiErrorKind.server : ApiErrorKind.unknown, message,
            statusCode: status, data: data);
    }
  }

  static String _extractMessage(Object? data, int status) {
    if (data is Map) {
      final detail = data['detail'] ?? data['message'] ?? data['error'];
      if (detail != null) return detail.toString();
    }
    if (data is String && data.isNotEmpty && data.length < 300) return data;
    return 'HTTP $status';
  }
}

/// A client bound to the configured server URL. Token is injected by the
/// auth controller once the user is signed in.
final apiClientProvider = Provider<ApiClient>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  final client = ApiClient(baseUrl: settings.serverUrl);
  client.language = settings.locale.languageCode;
  return client;
});
