import 'package:dio/dio.dart';

import '../../../core/network/api_error.dart';
import '../../dashboard/domain/dashboard.dart';
import '../../injection/domain/injection.dart';
import '../../nutrition/domain/nutrition.dart';
import '../../symptom/domain/symptom.dart';
import '../../weight/domain/weight.dart';
import '../domain/history.dart';

class HistoryRepository {
  const HistoryRepository(this._dio);
  final Dio _dio;

  Future<HistoryPage<WeightRecord>> weights(
          DateTime from, DateTime to, int limit, int offset) =>
      _get('/api/v1/weights', limit, offset, WeightRecord.fromJson,
          from: from, to: to);

  Future<HistoryPage<NutritionDaySummary>> nutrition(int limit, int offset) =>
      _get('/api/v1/nutrition/days', limit, offset,
          NutritionDaySummary.fromJson);

  Future<HistoryPage<SymptomRecord>> symptoms(int limit, int offset) =>
      _get('/api/v1/symptoms', limit, offset, SymptomRecord.fromJson);

  Future<HistoryPage<InjectionRecord>> injections(int limit, int offset) =>
      _get('/api/v1/injections', limit, offset, InjectionRecord.fromJson);

  Future<HistoryPage<T>> _get<T>(String path, int limit, int offset,
      T Function(Map<String, dynamic>) parse,
      {DateTime? from, DateTime? to}) async {
    try {
      final response = await _dio.get<Object?>(path, queryParameters: {
        if (from != null) 'from': formatApiDate(from),
        if (to != null) 'to': formatApiDate(to),
        'limit': limit,
        'offset': offset,
      });
      return parseHistoryPage(response.data, limit, offset, parse);
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw normalizeDioException(error);
    } catch (error) {
      throw ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Unexpected history error.',
          cause: error);
    }
  }
}
