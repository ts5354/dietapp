import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dietapp/core/network/api_error.dart';
import 'package:dietapp/core/timezone/device_timezone.dart';
import 'package:dietapp/features/symptom/data/symptom_repository.dart';
import 'package:dietapp/features/symptom/domain/symptom.dart';
import 'package:dietapp/features/symptom/presentation/symptom_screen.dart';
import 'package:dietapp/features/symptom/providers/symptom_provider.dart';
import 'package:dietapp/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> symptomJson(
        {int id = 1,
        String timestamp = '2026-09-08T03:30:00Z',
        Object? bowel = 'NORMAL'}) =>
    {
      'id': id,
      'recorded_at': timestamp,
      'nausea': 3,
      'abdominal_pain': 2,
      'fatigue': 5,
      'appetite': 4,
      'bowel_condition': bowel,
      'memo': null,
      'created_at': timestamp,
      'updated_at': timestamp,
    };

SymptomRecord record({int id = 1, DateTime? date}) => SymptomRecord(
      id: id,
      recordedAt: date ?? DateTime(2026, 9, 8, 12, 30),
      nausea: 3,
      abdominalPain: 2,
      fatigue: 5,
      appetite: 4,
      bowelCondition: BowelCondition.normal,
      memo: 'memo',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

SymptomWriteRequest writeRequest([DateTime? date]) {
  final selected = date ?? DateTime(2026, 9, 8);
  return SymptomFormValues(
    recordedAt: DateTime(selected.year, selected.month, selected.day, 12, 30),
    nausea: 3,
    abdominalPain: 2,
    fatigue: 5,
    appetite: 4,
    bowelCondition: null,
    memo: ' ',
  ).requestFor(selected);
}

void main() {
  group('model and validation', () {
    test('parses valid response, additive fields, bowels, and nulls', () {
      for (final bowel in [
        'NORMAL',
        'CONSTIPATION',
        'DIARRHEA',
        'OTHER',
        null
      ]) {
        final json = symptomJson(bowel: bowel)..['extra'] = true;
        final result = SymptomRecord.fromJson(json);
        expect(result.nausea, 3);
        expect(result.memo, isNull);
        expect(result.bowelCondition?.apiValue, bowel);
      }
    });

    test('accepts Z/offset timestamps and rejects naive or invalid', () {
      for (final timestamp in [
        '2026-09-08T03:30:00Z',
        '2026-09-08T12:30:00+09:00',
        '2026-09-07T23:30:00-04:00'
      ]) {
        expect(
            SymptomRecord.fromJson(symptomJson(timestamp: timestamp))
                .recordedAt
                .isUtc,
            isTrue);
      }
      for (final timestamp in ['2026-09-08T12:30:00', 'invalid']) {
        expect(() => SymptomRecord.fromJson(symptomJson(timestamp: timestamp)),
            throwsA(isA<ApiException>()));
      }
    });

    test('rejects missing, wrong scale types/ranges, and unknown bowel', () {
      final cases = <Map<String, dynamic>>[
        Map.of(symptomJson())..remove('memo'),
        {...symptomJson(), 'nausea': '3'},
        {...symptomJson(), 'nausea': 3.0},
        {...symptomJson(), 'nausea': 0},
        {...symptomJson(), 'appetite': 11},
        {...symptomJson(), 'bowel_condition': 'UNKNOWN'},
      ];
      for (final value in cases) {
        expect(
            () => SymptomRecord.fromJson(value), throwsA(isA<ApiException>()));
      }
    });

    test('serializes exact request contract with integers and shared timestamp',
        () {
      final json = writeRequest().toJson();
      expect(json.keys, {
        'recorded_at',
        'nausea',
        'abdominal_pain',
        'fatigue',
        'appetite',
        'bowel_condition',
        'memo'
      });
      expect(json['nausea'], isA<int>());
      expect(json['recorded_at'], matches(RegExp(r'(Z|[+-]\d\d:\d\d)$')));
      expect(json['bowel_condition'], isNull);
      expect(json['memo'], isNull);
    });

    test('accepts scale boundaries and rejects invalid scale/memo', () {
      SymptomFormValues form(int scale, {String memo = ''}) =>
          SymptomFormValues(
              recordedAt: DateTime(2026),
              nausea: scale,
              abdominalPain: scale,
              fatigue: scale,
              appetite: scale,
              bowelCondition: BowelCondition.other,
              memo: memo);
      expect(form(1).requestFor(DateTime(2026)).nausea, 1);
      expect(form(10).requestFor(DateTime(2026)).appetite, 10);
      for (final invalid in [form(0), form(11), form(1, memo: 'x' * 501)]) {
        expect(() => invalid.requestFor(DateTime(2026)),
            throwsA(isA<SymptomValidationException>()));
      }
    });
  });

  group('repository', () {
    test('rejects invalid pagination metadata values', () {
      for (final metadata in [
        {'total': -1, 'limit': 100, 'offset': 0},
        {'total': 0, 'limit': 0, 'offset': 0},
        {'total': 0, 'limit': -1, 'offset': 0},
        {'total': 0, 'limit': 100, 'offset': -1},
      ]) {
        expect(
            () => SymptomPage.fromJson({
                  'items': <Object>[],
                  ...metadata,
                }),
            throwsA(isA<ApiException>()
                .having((error) => error.kind, 'kind', ApiErrorKind.contract)));
      }
    });

    test('rejects response offset or limit that differs from request',
        () async {
      for (final metadata in [
        {'total': 0, 'limit': 100, 'offset': 1},
        {'total': 0, 'limit': 50, 'offset': 0},
      ]) {
        final dio = Dio()
          ..interceptors.add(InterceptorsWrapper(
              onRequest: (options, handler) => handler.resolve(Response(
                  requestOptions: options,
                  data: {'items': <Object>[], ...metadata}))));
        expect(
            SymptomRepository(dio)
                .listByDate(DateTime(2026, 9, 8), 'America/New_York'),
            throwsA(isA<ApiException>()
                .having((error) => error.kind, 'kind', ApiErrorKind.contract)));
      }
    });

    test('rejects item metadata that cannot make valid progress', () async {
      for (final body in [
        {'items': <Object>[], 'total': 1, 'limit': 100, 'offset': 0},
        {
          'items': [symptomJson(), symptomJson(id: 2)],
          'total': 1,
          'limit': 100,
          'offset': 0
        },
      ]) {
        final dio = Dio()
          ..interceptors.add(InterceptorsWrapper(
              onRequest: (options, handler) => handler
                  .resolve(Response(requestOptions: options, data: body))));
        expect(SymptomRepository(dio).listByDate(DateTime(2026, 9, 8), 'UTC'),
            throwsA(isA<ApiException>()));
      }
    });

    test('sends selected date and supplied IANA timezone unchanged', () async {
      final seen = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          seen.add(options);
          handler.resolve(Response(requestOptions: options, data: {
            'items': <Object>[],
            'total': 0,
            'limit': 100,
            'offset': 0,
          }));
        }));
      await SymptomRepository(dio)
          .listByDate(DateTime(2026, 9, 8), 'America/New_York');
      expect(seen.single.path, '/api/v1/symptoms');
      expect(seen.single.queryParameters, {
        'from': '2026-09-08',
        'to': '2026-09-08',
        'timezone': 'America/New_York',
        'limit': 100,
        'offset': 0,
      });
      expect(seen.single.queryParameters['timezone'], isNot('Asia/Tokyo'));
    });

    test('paginates all selected-day records without reordering', () async {
      var calls = 0;
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          final offset = options.queryParameters['offset'] as int;
          calls++;
          handler.resolve(Response(requestOptions: options, data: {
            'items': offset == 0
                ? List.generate(100, (index) => symptomJson(id: 200 - index))
                : [symptomJson(id: 100)],
            'total': 101,
            'limit': 100,
            'offset': offset,
          }));
        }));
      final result =
          await SymptomRepository(dio).listByDate(DateTime(2026, 9, 8), 'UTC');
      expect(calls, 2);
      expect(result, hasLength(101));
      expect(result.first.id, 200);
      expect(result.last.id, 100);
    });

    test('uses CRUD paths, body, and ignores DELETE 204 body', () async {
      final seen = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          seen.add(options);
          handler.resolve(Response(
              requestOptions: options,
              statusCode: options.method == 'DELETE' ? 204 : 200,
              data: options.method == 'DELETE' ? 'not-json' : symptomJson()));
        }));
      final repository = SymptomRepository(dio);
      await repository.create(writeRequest());
      await repository.update(42, writeRequest());
      await repository.delete(42);
      expect(seen.map((value) => '${value.method} ${value.path}'), [
        'POST /api/v1/symptoms',
        'PUT /api/v1/symptoms/42',
        'DELETE /api/v1/symptoms/42'
      ]);
      expect(seen[1].data.containsKey('id'), isFalse);
    });

    test('normalizes network, timeout, stable errors, and malformed success',
        () async {
      Future<void> expectKind(DioException exception, ApiErrorKind kind) async {
        final dio = Dio()
          ..interceptors.add(InterceptorsWrapper(
              onRequest: (options, handler) => handler.reject(exception)));
        expect(SymptomRepository(dio).create(writeRequest()),
            throwsA(isA<ApiException>().having((e) => e.kind, 'kind', kind)));
      }

      final options = RequestOptions();
      await expectKind(
          DioException.connectionError(
              requestOptions: options, reason: 'offline'),
          ApiErrorKind.network);
      await expectKind(
          DioException(
              requestOptions: options, type: DioExceptionType.receiveTimeout),
          ApiErrorKind.timeout);

      final serverDio = Dio()
        ..interceptors.add(InterceptorsWrapper(
            onRequest: (request, handler) => handler.reject(
                DioException.badResponse(
                    requestOptions: request,
                    statusCode: 404,
                    response: Response(
                        requestOptions: request,
                        statusCode: 404,
                        data: {
                          'error': {
                            'code': 'SYMPTOM_NOT_FOUND',
                            'message': 'missing'
                          }
                        })))));
      expect(
          SymptomRepository(serverDio).update(1, writeRequest()),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'SYMPTOM_NOT_FOUND')));

      final malformed = Dio()
        ..interceptors.add(InterceptorsWrapper(
            onRequest: (request, handler) =>
                handler.resolve(Response(requestOptions: request, data: []))));
      expect(
          SymptomRepository(malformed).create(writeRequest()),
          throwsA(isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.contract)));
    });
  });

  group('timezone and controller', () {
    test('timezone service boundary returns an overridable IANA identifier',
        () async {
      final timezone = FakeDeviceTimezone('America/New_York');
      expect(await timezone.currentIdentifier(), 'America/New_York');
    });

    test('timezone failure calls no API and is error, not empty ready',
        () async {
      final repository = FakeSymptomRepository();
      final controller = SymptomController(
          repository, FakeDeviceTimezone.failure(), DateTime(2026, 9, 8));
      await controller.load(DateTime(2026, 9, 8));
      expect(repository.listCalls, 0);
      expect(controller.state.viewMode, SymptomViewMode.error);
      expect(controller.state.message, contains('タイムゾーン'));
    });

    test('load passes another IANA timezone and distinguishes empty/error',
        () async {
      final repository = FakeSymptomRepository()
        ..listResults.add(Future.value([]));
      final controller = SymptomController(repository,
          FakeDeviceTimezone('America/New_York'), DateTime(2026, 9, 8));
      await controller.load(DateTime(2026, 9, 8));
      expect(controller.state.viewMode, SymptomViewMode.ready);
      expect(controller.state.records, isEmpty);
      expect(repository.lastTimezone, 'America/New_York');

      repository.nextListError =
          const ApiException(kind: ApiErrorKind.network, message: 'offline');
      await controller.load(DateTime(2026, 9, 9));
      expect(controller.state.viewMode, SymptomViewMode.error);
    });

    test('old GET is ignored', () async {
      final repository = FakeSymptomRepository();
      final controller = SymptomController(
          repository, FakeDeviceTimezone('UTC'), DateTime(2026, 9, 8));
      final old = Completer<List<SymptomRecord>>();
      repository.listResults.add(old.future);
      final first = controller.load(DateTime(2026, 9, 8));
      while (repository.listCalls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      repository.listResults.add(Future.value([]));
      await controller.load(DateTime(2026, 9, 9));
      old.complete([record()]);
      await first;
      expect(controller.state.date.day, 9);
      expect(controller.state.records, isEmpty);
    });

    test('create/update/delete reconcile and duplicate is prevented', () async {
      final repository = FakeSymptomRepository()
        ..listResults.add(Future.value([]));
      final controller = SymptomController(
          repository, FakeDeviceTimezone('UTC'), DateTime(2026, 9, 8));
      await controller.load(DateTime(2026, 9, 8));
      repository.listResults.add(Future.value([record()]));
      expect(await controller.create(writeRequest()), isTrue);
      repository.listResults.add(Future.value([record()]));
      expect(await controller.update(1, writeRequest()), isTrue);
      final deletion = Completer<void>();
      repository.deleteResult = deletion.future;
      final first = controller.delete(1);
      expect(await controller.delete(1), isFalse);
      repository.listResults.add(Future.value([]));
      deletion.complete();
      expect(await first, isTrue);
      expect(controller.state.records, isEmpty);
      expect(repository.listCalls, 4);
    });

    test('old create/update/delete and reconciliation are ignored', () async {
      final repository = FakeSymptomRepository()
        ..listResults.add(Future.value([]));
      final controller = SymptomController(
          repository, FakeDeviceTimezone('UTC'), DateTime(2026, 9, 8));
      await controller.load(DateTime(2026, 9, 8));

      for (final operation in ['create', 'update', 'delete']) {
        final write = Completer<SymptomRecord>();
        final deletion = Completer<void>();
        repository.writeResult = write.future;
        repository.deleteResult = deletion.future;
        final pending = operation == 'create'
            ? controller.create(writeRequest(controller.state.date))
            : operation == 'update'
                ? controller.update(1, writeRequest(controller.state.date))
                : controller.delete(1);
        final next = controller.state.date.add(const Duration(days: 1));
        repository.listResults.add(Future.value([]));
        await controller.load(next);
        if (operation == 'delete') {
          deletion.complete();
        } else {
          write.complete(record());
        }
        expect(await pending, isFalse);
        expect(controller.state.date, next);
      }

      repository.writeResult = Future.value(record());
      final reconcile = Completer<List<SymptomRecord>>();
      repository.listResults.add(reconcile.future);
      final pending = controller.create(writeRequest(controller.state.date));
      await Future<void>.delayed(Duration.zero);
      final next = controller.state.date.add(const Duration(days: 1));
      repository.listResults.add(Future.value([]));
      await controller.load(next);
      reconcile.complete([record()]);
      expect(await pending, isFalse);
      expect(controller.state.date, next);
    });

    test('old-date form is blocked and reconciliation failure is error',
        () async {
      final repository = FakeSymptomRepository()
        ..listResults.add(Future.value([]));
      final controller = SymptomController(
          repository, FakeDeviceTimezone('UTC'), DateTime(2026, 9, 9));
      await controller.load(DateTime(2026, 9, 9));
      expect(
          await controller.create(writeRequest(DateTime(2026, 9, 8))), isFalse);
      expect(repository.writeCalls, 0);

      repository.nextListError =
          const ApiException(kind: ApiErrorKind.network, message: 'offline');
      expect(
          await controller.create(writeRequest(DateTime(2026, 9, 9))), isFalse);
      expect(controller.state.viewMode, SymptomViewMode.error);
      expect(controller.state.records, isEmpty);
    });
  });

  group('widgets', () {
    testWidgets('Record menu exposes existing routes and reaches Symptom',
        (tester) async {
      final repository = FakeSymptomRepository()
        ..listResults.add(Future.value([]));
      await tester.pumpWidget(ProviderScope(overrides: [
        symptomRepositoryProvider.overrideWithValue(repository),
        deviceTimezoneProvider.overrideWithValue(FakeDeviceTimezone('UTC')),
      ], child: const _RouterApp()));
      expect(find.text('体重'), findsOneWidget);
      expect(find.text('食事'), findsOneWidget);
      await tester.tap(find.text('体調'));
      await tester.pumpAndSettle();
      expect(find.byType(SymptomScreen), findsOneWidget);
      expect(find.text('体調記録'), findsOneWidget);
    });

    testWidgets('renders empty/list and neutral safety text', (tester) async {
      await pumpSymptom(tester, []);
      expect(find.byKey(const Key('emptySymptomState')), findsOneWidget);
      expect(find.textContaining('医療機関へ相談'), findsOneWidget);
      expect(find.textContaining(RegExp('重症|危険|投与量|減量')), findsNothing);

      await pumpSymptom(tester, [record()]);
      expect(find.byKey(const Key('symptom-1')), findsOneWidget);
      expect(find.textContaining('吐き気 3'), findsOneWidget);
      expect(find.textContaining('便通 通常'), findsOneWidget);
    });

    testWidgets('create form has four visible scale defaults and bowel options',
        (tester) async {
      await pumpSymptom(tester, []);
      await tester.tap(find.byKey(const Key('addSymptomButton')));
      await tester.pumpAndSettle();
      for (final label in ['吐き気 1', '腹痛 1', 'だるさ 1', '食欲 1']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byKey(const Key('symptomMemoField')), findsOneWidget);
      await tester.tap(find.byKey(const Key('bowelField')));
      await tester.pumpAndSettle();
      for (final label in ['記録しない', '通常', '便秘', '下痢', 'その他']) {
        expect(find.text(label), findsWidgets);
      }
    });

    testWidgets('edit prefills and delete confirmation cancels/accepts',
        (tester) async {
      final repository = FakeSymptomRepository();
      await pumpSymptom(tester, [record()], repository: repository);
      await tester.tap(find.byKey(const Key('symptom-1')));
      await tester.pumpAndSettle();
      expect(find.text('吐き気 3'), findsOneWidget);
      expect(find.text('腹痛 2'), findsOneWidget);
      expect(find.text('memo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('deleteSymptomButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル').last);
      await tester.pumpAndSettle();
      expect(repository.deleteCalls, 0);
      await tester.tap(find.byKey(const Key('deleteSymptomButton')));
      await tester.pumpAndSettle();
      repository.listResults.add(Future.value([]));
      await tester.tap(find.text('削除'));
      await tester.pumpAndSettle();
      expect(repository.deleteCalls, 1);
    });

    testWidgets('create and edit reconcile with neutral success feedback',
        (tester) async {
      final repository = FakeSymptomRepository();
      await pumpSymptom(tester, [], repository: repository);
      await tester.tap(find.byKey(const Key('addSymptomButton')));
      await tester.pumpAndSettle();
      repository.listResults.add(Future.value([record()]));
      await tester.tap(find.byKey(const Key('saveSymptomButton')));
      await tester.pumpAndSettle();
      expect(repository.writeCalls, 1);
      expect(find.text('体調記録を保存しました。'), findsOneWidget);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('symptom-1')));
      await tester.pumpAndSettle();
      repository.listResults.add(Future.value([record()]));
      await tester.tap(find.byKey(const Key('saveSymptomButton')));
      await tester.pumpAndSettle();
      expect(repository.writeCalls, 2);
      expect(find.text('体調記録を更新しました。'), findsOneWidget);
    });

    testWidgets('invalid memo shows validation and sends no request',
        (tester) async {
      final repository = FakeSymptomRepository();
      await pumpSymptom(tester, [], repository: repository);
      await tester.tap(find.byKey(const Key('addSymptomButton')));
      await tester.pumpAndSettle();
      tester
          .widget<TextField>(find.byKey(const Key('symptomMemoField')))
          .controller!
          .text = 'x' * 501;
      await tester.pump();
      await tester.tap(find.byKey(const Key('saveSymptomButton')));
      await tester.pump();
      expect(find.byKey(const Key('symptomValidation')), findsOneWidget);
      expect(repository.writeCalls, 0);
    });

    testWidgets('timezone failure renders error and performs no API call',
        (tester) async {
      final repository = FakeSymptomRepository();
      await tester.pumpWidget(ProviderScope(overrides: [
        symptomRepositoryProvider.overrideWithValue(repository),
        deviceTimezoneProvider.overrideWithValue(FakeDeviceTimezone.failure()),
      ], child: const MaterialApp(home: SymptomScreen())));
      await tester.pumpAndSettle();
      expect(find.textContaining('タイムゾーン'), findsOneWidget);
      expect(find.byKey(const Key('emptySymptomState')), findsNothing);
      expect(repository.listCalls, 0);
    });

    testWidgets('busy disables create action', (tester) async {
      final repository = FakeSymptomRepository();
      await pumpSymptom(tester, [], repository: repository);
      final context = tester.element(find.byType(SymptomScreen));
      final controller = ProviderScope.containerOf(context)
          .read(symptomControllerProvider.notifier);
      final reconcile = Completer<List<SymptomRecord>>();
      repository.listResults.add(reconcile.future);
      final pending = controller.create(writeRequest(controller.state.date));
      await tester.pump();
      expect(find.byKey(const Key('symptomBusy')), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('addSymptomButton')))
              .onPressed,
          isNull);
      reconcile.complete([]);
      await pending;
    });
  });
}

class FakeDeviceTimezone implements DeviceTimezone {
  FakeDeviceTimezone(this.value) : error = null;
  FakeDeviceTimezone.failure()
      : value = null,
        error = StateError('unavailable');
  final String? value;
  final Object? error;
  @override
  Future<String> currentIdentifier() =>
      error == null ? Future.value(value) : Future.error(error!);
}

class FakeSymptomRepository implements SymptomRepository {
  final List<Future<List<SymptomRecord>>> listResults = [];
  Future<SymptomRecord> writeResult = Future.value(record());
  Future<void> deleteResult = Future.value();
  int listCalls = 0;
  int writeCalls = 0;
  int deleteCalls = 0;
  String? lastTimezone;
  Object? nextListError;

  @override
  Future<List<SymptomRecord>> listByDate(DateTime date, String timezone) {
    listCalls++;
    lastTimezone = timezone;
    if (nextListError case final error?) {
      nextListError = null;
      return Future.error(error);
    }
    return listResults.removeAt(0);
  }

  @override
  Future<SymptomRecord> create(SymptomWriteRequest request) {
    writeCalls++;
    return writeResult;
  }

  @override
  Future<SymptomRecord> update(int id, SymptomWriteRequest request) {
    writeCalls++;
    return writeResult;
  }

  @override
  Future<void> delete(int id) {
    deleteCalls++;
    return deleteResult;
  }
}

Future<void> pumpSymptom(WidgetTester tester, List<SymptomRecord> records,
    {FakeSymptomRepository? repository}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  final fake = repository ?? FakeSymptomRepository();
  fake.listResults.add(Future.value(records));
  await tester.pumpWidget(ProviderScope(overrides: [
    symptomRepositoryProvider.overrideWithValue(fake),
    deviceTimezoneProvider.overrideWithValue(FakeDeviceTimezone('Etc/UTC')),
  ], child: const MaterialApp(home: SymptomScreen())));
  await tester.pumpAndSettle();
}

class _RouterApp extends ConsumerWidget {
  const _RouterApp();
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MaterialApp.router(routerConfig: ref.watch(appRouterProvider));
}
