/// Normalised error thrown by the API layer.
enum ApiErrorKind { network, unauthorized, forbidden, notFound, validation, server, unknown }

class ApiException implements Exception {
  ApiException(this.kind, this.message, {this.statusCode, this.data});

  final ApiErrorKind kind;
  final String message;
  final int? statusCode;
  final Object? data;

  bool get isNetwork => kind == ApiErrorKind.network;
  bool get isUnauthorized => kind == ApiErrorKind.unauthorized;

  @override
  String toString() => 'ApiException($kind, $statusCode): $message';
}
