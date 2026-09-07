import 'package:dio/dio.dart';

import '../../../core/network/api_error.dart';
import '../../dashboard/domain/dashboard.dart';
import '../domain/symptom.dart';

class SymptomRepository {
  const SymptomRepository(this._dio);
  final Dio _dio;

  Future<List<SymptomRecord>> listByDate(DateTime date, String timezone) async {
    const limit = 100;
    final items = <SymptomRecord>[];
    var offset = 0;
    while (true) {
      final page = await _page(date, timezone, limit, offset);
      if (page.offset != offset) {
        throw ApiException.contract(
            'Symptom page offset does not match the request.');
      }
      if (page.limit != limit) {
        throw ApiException.contract(
            'Symptom page limit does not match the request.');
      }
      if (page.items.length > page.limit ||
          page.offset + page.items.length > page.total) {
        throw ApiException.contract(
            'Symptom page items are inconsistent with its metadata.');
      }
      if (page.items.isEmpty && page.offset < page.total) {
        throw ApiException.contract(
            'Symptom pagination ended before reaching total.');
      }
      items.addAll(page.items);
      if (items.length == page.total) return items;
      offset += page.items.length;
    }
  }

  Future<SymptomRecord> create(SymptomWriteRequest request) =>
      _recordRequest('POST', '/api/v1/symptoms', data: request.toJson());

  Future<SymptomRecord> update(int id, SymptomWriteRequest request) =>
      _recordRequest('PUT', '/api/v1/symptoms/$id', data: request.toJson());

  Future<void> delete(int id) async {
    try {
      await _dio.delete<void>('/api/v1/symptoms/$id');
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw normalizeDioException(error);
    } catch (error) {
      throw ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Unexpected symptom error.',
          cause: error);
    }
  }

  Future<SymptomPage> _page(
      DateTime date, String timezone, int limit, int offset) async {
    try {
      final response = await _dio.get<Object?>(
        '/api/v1/symptoms',
        queryParameters: {
          'from': formatApiDate(date),
          'to': formatApiDate(date),
          'timezone': timezone,
          'limit': limit,
          'offset': offset,
        },
      );
      return SymptomPage.fromJson(requireSymptomMap(response.data));
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw normalizeDioException(error);
    } catch (error) {
      throw ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Unexpected symptom error.',
          cause: error);
    }
  }

  Future<SymptomRecord> _recordRequest(String method, String path,
      {Object? data}) async {
    try {
      final response = await _dio.request<Object?>(path,
          data: data, options: Options(method: method));
      return SymptomRecord.fromJson(requireSymptomMap(response.data));
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw normalizeDioException(error);
    } catch (error) {
      throw ApiException(
          kind: ApiErrorKind.unknown,
          message: 'Unexpected symptom error.',
          cause: error);
    }
  }
}
