import 'package:dio/dio.dart';

import '../../../core/network/api_error.dart';
import '../domain/dashboard.dart';

class DashboardApi {
  const DashboardApi(this._dio);
  final Dio _dio;

  Future<Object?> getDashboard({
    required DateTime date,
    required String timezone,
  }) async {
    try {
      final response = await _dio.get<Object?>(
        '/api/v1/dashboard',
        queryParameters: {
          'date': formatApiDate(date),
          'timezone': timezone,
        },
      );
      return response.data;
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw normalizeDioException(error);
    } catch (error) {
      throw ApiException(
        kind: ApiErrorKind.unknown,
        message: 'An unexpected API error occurred.',
        cause: error,
      );
    }
  }
}
