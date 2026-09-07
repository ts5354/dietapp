import 'package:dio/dio.dart';
import '../../../core/network/api_error.dart';
import '../../dashboard/domain/dashboard.dart';
import '../domain/weight.dart';

class WeightRepository {
  const WeightRepository(this._dio);
  final Dio _dio;
  Future<WeightRecord> get(DateTime date) =>
      _request('GET', '/api/v1/weights/${formatApiDate(date)}');
  Future<WeightRecord> create(CreateWeightRequest request) =>
      _request('POST', '/api/v1/weights', data: request.toJson());
  Future<WeightRecord> update(DateTime date, UpdateWeightRequest request) =>
      _request('PUT', '/api/v1/weights/${formatApiDate(date)}',
          data: request.toJson());
  Future<void> delete(DateTime date) async {
    try {
      await _dio.delete<void>('/api/v1/weights/${formatApiDate(date)}');
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw normalizeDioException(e);
    } catch (e) {
      throw ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Unexpected weight error.',
          cause: e);
    }
  }

  Future<WeightRecord> _request(String method, String path,
      {Object? data}) async {
    try {
      final response = await _dio.request<Object?>(path,
          data: data, options: Options(method: method));
      return WeightRecord.fromJson(requireMap(response.data));
    } on ApiException {
      rethrow;
    } on DioException catch (e) {
      throw normalizeDioException(e);
    } catch (e) {
      throw ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Unexpected weight error.',
          cause: e);
    }
  }
}
