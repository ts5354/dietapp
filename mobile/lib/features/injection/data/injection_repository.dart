import 'package:dio/dio.dart';

import '../../../core/network/api_error.dart';
import '../../dashboard/domain/dashboard.dart';
import '../domain/injection.dart';

class InjectionRepository {
  const InjectionRepository(this._dio);
  final Dio _dio;

  Future<InjectionRecord> getByDate(DateTime date) =>
      _request('GET', '/api/v1/injections/${formatApiDate(date)}');

  Future<InjectionRecord?> getLatest() async {
    try {
      final response = await _dio.get<Object?>('/api/v1/injections',
          queryParameters: {'limit': 1, 'offset': 0});
      final body = requireInjectionMap(response.data);
      if (body['items'] is! List ||
          body['total'] is! int ||
          body['limit'] != 1 ||
          body['offset'] != 0) {
        throw ApiException.contract('Invalid latest injection page.');
      }
      final items = body['items'] as List;
      final total = body['total'] as int;
      if (total < 0 ||
          items.length > 1 ||
          (total == 0 && items.isNotEmpty) ||
          (total > 0 && items.length != 1)) {
        throw ApiException.contract('Invalid latest injection page.');
      }
      return items.isEmpty
          ? null
          : InjectionRecord.fromJson(requireInjectionMap(items.single));
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw normalizeDioException(error);
    } catch (error) {
      throw ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Unexpected injection error.',
          cause: error);
    }
  }

  Future<InjectionRecord> create(InjectionCreateRequest request) =>
      _request('POST', '/api/v1/injections', data: request.toJson());
  Future<InjectionRecord> update(
          DateTime date, InjectionUpdateRequest request) =>
      _request('PUT', '/api/v1/injections/${formatApiDate(date)}',
          data: request.toJson());
  Future<void> delete(DateTime date) async {
    try {
      await _dio.delete<void>('/api/v1/injections/${formatApiDate(date)}');
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw normalizeDioException(error);
    } catch (error) {
      throw ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Unexpected injection error.',
          cause: error);
    }
  }

  Future<InjectionRecord> _request(String method, String path,
      {Object? data}) async {
    try {
      final response = await _dio.request<Object?>(path,
          data: data, options: Options(method: method));
      return InjectionRecord.fromJson(requireInjectionMap(response.data));
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw normalizeDioException(error);
    } catch (error) {
      throw ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Unexpected injection error.',
          cause: error);
    }
  }
}
