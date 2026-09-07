import 'package:dio/dio.dart';

import '../../../core/network/api_error.dart';
import '../../dashboard/domain/dashboard.dart';
import '../domain/nutrition.dart';

class NutritionRepository {
  const NutritionRepository(this._dio);
  final Dio _dio;

  String _dayPath(DateTime date) =>
      '/api/v1/nutrition/days/${formatApiDate(date)}';

  Future<NutritionDay> getDay(DateTime date) =>
      _dayRequest('GET', _dayPath(date));

  Future<NutritionDay> setDayMode(
          DateTime date, NutritionDayUpdateRequest request) =>
      _dayRequest('PUT', _dayPath(date), data: request.toJson());

  Future<FoodLog> createFood(DateTime date, FoodWriteRequest request) =>
      _foodRequest('POST', '${_dayPath(date)}/foods', data: request.toJson());

  Future<FoodLog> updateFood(DateTime date, int id, FoodWriteRequest request) =>
      _foodRequest('PUT', '${_dayPath(date)}/foods/$id',
          data: request.toJson());

  Future<void> deleteFood(DateTime date, int id) async {
    try {
      await _dio.delete<void>('${_dayPath(date)}/foods/$id');
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw normalizeDioException(error);
    } catch (error) {
      throw ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Unexpected nutrition error.',
          cause: error);
    }
  }

  Future<NutritionDay> _dayRequest(String method, String path,
      {Object? data}) async {
    try {
      final response = await _dio.request<Object?>(path,
          data: data, options: Options(method: method));
      return NutritionDay.fromJson(requireNutritionMap(response.data));
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw normalizeDioException(error);
    } catch (error) {
      throw ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Unexpected nutrition error.',
          cause: error);
    }
  }

  Future<FoodLog> _foodRequest(String method, String path,
      {Object? data}) async {
    try {
      final response = await _dio.request<Object?>(path,
          data: data, options: Options(method: method));
      return FoodLog.fromJson(requireNutritionMap(response.data));
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw normalizeDioException(error);
    } catch (error) {
      throw ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Unexpected nutrition error.',
          cause: error);
    }
  }
}
