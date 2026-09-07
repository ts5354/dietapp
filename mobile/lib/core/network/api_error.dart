import 'package:dio/dio.dart';

enum ApiErrorKind { server, network, timeout, contract, configuration, unknown }

class ApiErrorDetail {
  const ApiErrorDetail({required this.field, required this.message});
  final String field;
  final String message;
}

class ApiException implements Exception {
  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
    this.code,
    this.details = const [],
    this.cause,
  });

  factory ApiException.contract(String message, [Object? cause]) =>
      ApiException(kind: ApiErrorKind.contract, message: message, cause: cause);
  factory ApiException.configuration(String message) =>
      ApiException(kind: ApiErrorKind.configuration, message: message);

  final ApiErrorKind kind;
  final int? statusCode;
  final String? code;
  final String message;
  final List<ApiErrorDetail> details;
  final Object? cause;
}

ApiException normalizeDioException(DioException error) {
  if (error.error case final ApiException existing) {
    return existing;
  }
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
      return ApiException(
        kind: ApiErrorKind.timeout,
        message: 'The request timed out.',
        cause: error,
      );
    case DioExceptionType.connectionError:
      return ApiException(
        kind: ApiErrorKind.network,
        message: 'The server could not be reached.',
        cause: error,
      );
    case DioExceptionType.badResponse:
      return _normalizeHttpError(error);
    case DioExceptionType.badCertificate:
    case DioExceptionType.cancel:
      return ApiException(
        kind: ApiErrorKind.unknown,
        message: 'An unexpected network error occurred.',
        cause: error,
      );
    case DioExceptionType.unknown:
      if (error.error is FormatException) {
        return ApiException.contract(
          'The server returned malformed JSON.',
          error,
        );
      }
      return ApiException(
        kind: ApiErrorKind.unknown,
        message: 'An unexpected network error occurred.',
        cause: error,
      );
  }
}

ApiException _normalizeHttpError(DioException error) {
  final statusCode = error.response?.statusCode;
  final data = error.response?.data;
  if (data is! Map ||
      data['error'] is! Map ||
      (data['error'] as Map)['code'] is! String ||
      (data['error'] as Map)['message'] is! String) {
    return ApiException(
      kind: ApiErrorKind.contract,
      statusCode: statusCode,
      message: 'The server returned an invalid error response.',
      cause: error,
    );
  }
  final envelope = data['error'] as Map;
  final rawDetails = envelope['details'];
  if (rawDetails != null && rawDetails is! List) {
    return ApiException.contract(
        'The server returned invalid error details.', error);
  }
  final details = <ApiErrorDetail>[];
  for (final detail in rawDetails as List? ?? const []) {
    if (detail is! Map ||
        detail['field'] is! String ||
        detail['message'] is! String) {
      return ApiException.contract(
        'The server returned invalid error details.',
        error,
      );
    }
    details.add(
      ApiErrorDetail(
        field: detail['field'] as String,
        message: detail['message'] as String,
      ),
    );
  }
  return ApiException(
    kind: ApiErrorKind.server,
    statusCode: statusCode,
    code: envelope['code'] as String,
    message: envelope['message'] as String,
    details: details,
    cause: error,
  );
}
