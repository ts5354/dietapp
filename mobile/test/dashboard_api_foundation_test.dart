import 'package:dio/dio.dart';
import 'package:dietapp/core/config/api_config.dart';
import 'package:dietapp/core/network/api_error.dart';
import 'package:dietapp/core/network/dio_provider.dart';
import 'package:dietapp/features/dashboard/data/dashboard_api.dart';
import 'package:dietapp/features/dashboard/data/dashboard_repository.dart';
import 'package:dietapp/features/dashboard/domain/dashboard.dart';
import 'package:dietapp/features/dashboard/providers/dashboard_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> dashboardJson() => {
      'date': '2026-09-07',
      'timezone': 'Asia/Tokyo',
      'weight': {
        'status': 'RECORDED',
        'record': {'record_date': '2026-09-05', 'weight_kg': 65.5},
      },
      'nutrition': {
        'status': 'RECORDED',
        'record': {
          'mode': 'NORMAL',
          'total_calories': 1850,
          'total_protein_g': 82.5,
        },
      },
      'symptom': {
        'status': 'RECORDED',
        'record': {
          'recorded_at': '2026-09-07T03:30:00Z',
          'nausea': 2,
          'abdominal_pain': 1,
          'fatigue': 4,
          'appetite': 6,
          'bowel_condition': null,
        },
      },
      'injection': {
        'status': 'RECORDED',
        'record': {'record_date': '2026-09-01'},
        'next_scheduled_date': '2026-09-08',
      },
    };

Map<String, dynamic> unrecordedJson() => {
      'date': '2026-09-07',
      'timezone': 'Asia/Tokyo',
      'weight': {'status': 'UNRECORDED', 'record': null},
      'nutrition': {'status': 'UNRECORDED', 'record': null},
      'symptom': {'status': 'UNRECORDED', 'record': null},
      'injection': {
        'status': 'UNRECORDED',
        'record': null,
        'next_scheduled_date': null,
      },
    };

void main() {
  group('API config', () {
    test('normalizes a valid trailing slash and can be overridden', () {
      final container = ProviderContainer(overrides: [
        apiConfigProvider
            .overrideWithValue(ApiConfig(baseUrl: ' http://api:8000/ ')),
      ]);
      addTearDown(container.dispose);
      expect(container.read(dioProvider).options.baseUrl, 'http://api:8000');
      expect(container.read(dioProvider).options.sendTimeout,
          const Duration(seconds: 10));
    });

    test('does not silently fallback for missing or invalid configuration', () {
      for (final value in ['', '   ', 'localhost:8000']) {
        expect(
          () => ApiConfig(baseUrl: value),
          throwsA(isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiErrorKind.configuration,
          )),
        );
      }
    });
  });

  group('dashboard model', () {
    test('parses complete response and ignores additive fields', () {
      final json = dashboardJson()..['future_field'] = true;
      final dashboard = Dashboard.fromJson(json);
      expect(dashboard.date, DateTime(2026, 9, 7));
      expect(dashboard.weight.record!.weightKg, 65.5);
      expect(dashboard.nutrition.record!.mode, DashboardNutritionMode.normal);
      expect(dashboard.nutrition.record!.totalProteinG, 82.5);
      expect(dashboard.symptom.record!.recordedAt.isUtc, isTrue);
      expect(dashboard.symptom.record!.bowelCondition, isNull);
      expect(dashboard.injection.record!.recordDate, DateTime(2026, 9, 1));
      expect(dashboard.injection.nextScheduledDate, DateTime(2026, 9, 8));
    });

    test('parses unrecorded and free day without inventing zero totals', () {
      final empty = Dashboard.fromJson(unrecordedJson());
      expect(empty.weight.record, isNull);
      expect(empty.injection.nextScheduledDate, isNull);

      final json = dashboardJson();
      json['nutrition'] = {
        'status': 'RECORDED',
        'record': {
          'mode': 'FREE_DAY',
          'total_calories': null,
          'total_protein_g': null,
        },
      };
      final freeDay = Dashboard.fromJson(json).nutrition.record!;
      expect(freeDay.mode, DashboardNutritionMode.freeDay);
      expect(freeDay.totalCalories, isNull);
      expect(freeDay.totalProteinG, isNull);
    });

    test('rejects section status and record invariant violations', () {
      for (final section in ['weight', 'nutrition', 'symptom', 'injection']) {
        final recordedNull = unrecordedJson();
        (recordedNull[section] as Map)['status'] = 'RECORDED';
        expect(() => Dashboard.fromJson(recordedNull),
            throwsA(isA<ApiException>()));

        final unknown = unrecordedJson();
        (unknown[section] as Map)['status'] = 'UNKNOWN';
        expect(() => Dashboard.fromJson(unknown), throwsA(isA<ApiException>()));
      }
      final unrecordedValue = dashboardJson();
      (unrecordedValue['weight'] as Map)['status'] = 'UNRECORDED';
      expect(() => Dashboard.fromJson(unrecordedValue),
          throwsA(isA<ApiException>()));
    });

    test('rejects nutrition invariant and enum violations', () {
      for (final record in [
        {'mode': 'UNKNOWN', 'total_calories': 1, 'total_protein_g': 1},
        {'mode': 'NORMAL', 'total_calories': null, 'total_protein_g': 1},
        {'mode': 'NORMAL', 'total_calories': 1, 'total_protein_g': null},
        {'mode': 'FREE_DAY', 'total_calories': 1, 'total_protein_g': null},
        {'mode': 'FREE_DAY', 'total_calories': null, 'total_protein_g': 1},
      ]) {
        final json = dashboardJson();
        json['nutrition'] = {'status': 'RECORDED', 'record': record};
        expect(() => Dashboard.fromJson(json), throwsA(isA<ApiException>()));
      }
    });

    test('rejects symptom, injection, date, and primitive contract violations',
        () {
      final cases = <Map<String, dynamic>>[];
      var json = dashboardJson();
      (json['symptom'] as Map)['record']['recorded_at'] = 'invalid';
      cases.add(json);
      json = dashboardJson();
      (json['symptom'] as Map)['record']['bowel_condition'] = 'UNKNOWN';
      cases.add(json);
      json = dashboardJson();
      json['injection'] = <String, dynamic>{
        'status': 'RECORDED',
        'record': {'record_date': '2026-09-01'},
        'next_scheduled_date': null,
      };
      cases.add(json);
      json = unrecordedJson();
      json['injection'] = <String, dynamic>{
        'status': 'UNRECORDED',
        'record': null,
        'next_scheduled_date': '2026-09-08',
      };
      cases.add(json);
      json = dashboardJson()..['date'] = '2026-02-30';
      cases.add(json);
      json = dashboardJson()..['timezone'] = 9;
      cases.add(json);
      for (final value in cases) {
        expect(() => Dashboard.fromJson(value), throwsA(isA<ApiException>()));
      }
    });
  });

  group('API and repository', () {
    test('does not replace an existing contract exception with unknown',
        () async {
      final original = ApiException.contract('Existing contract violation.');
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          throw original;
        }));

      await expectLater(
        DashboardApi(dio).getDashboard(
          date: DateTime(2026, 9, 7),
          timezone: 'Asia/Tokyo',
        ),
        throwsA(same(original)),
      );
    });

    test('formats date without timezone conversion and sends timezone',
        () async {
      late RequestOptions captured;
      final dio = Dio(BaseOptions(baseUrl: 'http://example.test'))
        ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          captured = options;
          handler.resolve(
              Response(requestOptions: options, data: dashboardJson()));
        }));
      final result = await DashboardRepository(DashboardApi(dio)).getDashboard(
        date: DateTime(2026, 1, 2, 23, 30),
        timezone: 'America/New_York',
      );
      expect(captured.path, '/api/v1/dashboard');
      expect(captured.queryParameters, {
        'date': '2026-01-02',
        'timezone': 'America/New_York',
      });
      expect(result.timezone, 'Asia/Tokyo');
    });

    test('classifies malformed success bodies as contract errors', () async {
      for (final body in [
        'not json',
        <Object?>[],
        {'date': '2026-09-07'}
      ]) {
        final dio = Dio()
          ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
            handler.resolve(Response(requestOptions: options, data: body));
          }));
        expect(
          DashboardRepository(DashboardApi(dio)).getDashboard(
            date: DateTime(2026),
            timezone: 'UTC',
          ),
          throwsA(isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiErrorKind.contract,
          )),
        );
      }
    });
  });

  group('error normalization', () {
    test('preserves backend status, code, message, and details', () {
      final request = RequestOptions();
      final exception = normalizeDioException(DioException.badResponse(
        statusCode: 422,
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 422, data: {
          'error': {
            'code': 'VALIDATION_ERROR',
            'message': 'Invalid values.',
            'details': [
              {'field': 'timezone', 'message': 'Invalid timezone.'},
            ],
          },
        }),
      ));
      expect(exception.kind, ApiErrorKind.server);
      expect(exception.statusCode, 422);
      expect(exception.code, 'VALIDATION_ERROR');
      expect(exception.message, 'Invalid values.');
      expect(exception.details.single.field, 'timezone');
    });

    test('accepts omitted details and rejects malformed HTTP envelopes', () {
      final request = RequestOptions();
      final valid = normalizeDioException(DioException.badResponse(
        statusCode: 500,
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 500, data: {
          'error': {'code': 'SERVER_ERROR', 'message': 'Failed.'},
        }),
      ));
      expect(valid.details, isEmpty);
      final malformed = normalizeDioException(DioException.badResponse(
        statusCode: 500,
        requestOptions: request,
        response:
            Response(requestOptions: request, statusCode: 500, data: '<html>'),
      ));
      expect(malformed.kind, ApiErrorKind.contract);
    });

    test('classifies timeout, network, and unexpected errors', () {
      final request = RequestOptions();
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
        DioExceptionType.transformTimeout,
      ]) {
        expect(
          normalizeDioException(
                  DioException(requestOptions: request, type: type))
              .kind,
          ApiErrorKind.timeout,
        );
      }
      expect(
        normalizeDioException(DioException.connectionError(
          requestOptions: request,
          reason: 'refused',
        )).kind,
        ApiErrorKind.network,
      );
      expect(
        normalizeDioException(DioException(requestOptions: request)).kind,
        ApiErrorKind.unknown,
      );
      expect(
        normalizeDioException(DioException(
          requestOptions: request,
          error: const FormatException('malformed JSON'),
        )).kind,
        ApiErrorKind.contract,
      );
    });
  });

  test('dashboard provider exposes data and normalized error states', () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler
            .resolve(Response(requestOptions: options, data: dashboardJson()));
      }));
    final container =
        ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);
    final query =
        DashboardQuery(date: DateTime(2026, 9, 7), timezone: 'Asia/Tokyo');
    expect(await container.read(dashboardProvider(query).future),
        isA<Dashboard>());

    final failing = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.reject(DioException.connectionError(
          requestOptions: options,
          reason: 'refused',
        ));
      }));
    final failedContainer = ProviderContainer(
      overrides: [dioProvider.overrideWithValue(failing)],
    );
    addTearDown(failedContainer.dispose);
    await expectLater(
      failedContainer.read(dashboardProvider(query).future),
      throwsA(isA<ApiException>().having(
        (error) => error.kind,
        'kind',
        ApiErrorKind.network,
      )),
    );
  });
}
