import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dietapp/core/config/api_config.dart';
import 'package:dietapp/core/network/api_error.dart';
import 'package:dietapp/core/network/dio_provider.dart';
import 'package:dietapp/features/injection/data/injection_repository.dart';
import 'package:dietapp/features/injection/domain/injection.dart';
import 'package:dietapp/features/injection/presentation/injection_screen.dart';
import 'package:dietapp/features/injection/providers/injection_provider.dart';
import 'package:dietapp/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> injectionJson({
  int id = 1,
  String date = '2026-09-08',
  Object dose = 2.5,
  String site = 'ABDOMEN_UPPER_RIGHT',
  String timestamp = '2026-09-08T03:30:00Z',
}) =>
    {
      'id': id,
      'record_date': date,
      'injected_at': timestamp,
      'dose_mg': dose,
      'injection_site': site,
      'memo': 'memo',
      'created_at': timestamp,
      'updated_at': timestamp,
    };

InjectionRecord record(DateTime date, {int id = 1, double dose = 2.5}) =>
    InjectionRecord(
      id: id,
      recordDate: DateTime(date.year, date.month, date.day),
      injectedAt: DateTime(date.year, date.month, date.day, 12, 30),
      doseMg: dose,
      injectionSite: InjectionSite.abdomenUpperRight,
      memo: 'memo',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

ApiException notFound() => const ApiException(
      kind: ApiErrorKind.server,
      statusCode: 404,
      code: 'INJECTION_NOT_FOUND',
      message: 'not found',
    );

Future<InjectionRecord> missingRecord() =>
    Future<InjectionRecord>.delayed(Duration.zero, () => throw notFound());

void main() {
  group('domain contract', () {
    test('parses all sites and timezone-aware timestamps', () {
      final timestamps = [
        '2026-09-08T03:30:00Z',
        '2026-09-08T12:30:00+09:00',
        '2026-09-07T23:30:00-04:00',
      ];
      for (final site in InjectionSite.values) {
        final parsed = InjectionRecord.fromJson(injectionJson(
          site: site.apiValue,
          timestamp: timestamps[site.index % timestamps.length],
        ));
        expect(parsed.injectionSite, site);
        expect(parsed.injectedAt.isUtc, isTrue);
      }
      expect(
        () => InjectionRecord.fromJson(
          injectionJson(timestamp: '2026-09-08T12:30:00'),
        ),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => InjectionRecord.fromJson(injectionJson(site: 'OTHER')),
        throwsA(isA<ApiException>()),
      );
      final additive = injectionJson()..['future_field'] = true;
      expect(InjectionRecord.fromJson(additive).memo, 'memo');
      final nullable = injectionJson()..['memo'] = null;
      expect(InjectionRecord.fromJson(nullable).memo, isNull);
      final missing = injectionJson()..remove('memo');
      expect(() => InjectionRecord.fromJson(missing),
          throwsA(isA<ApiException>()));
    });

    test('dose is a strict positive JSON number with two decimals', () {
      for (final invalid in <Object>['2.5', true, 0, -1, 2.555, 1000]) {
        expect(
          () => InjectionRecord.fromJson(injectionJson(dose: invalid)),
          throwsA(isA<ApiException>()),
        );
      }
      expect(validateDose('0.01'), 0.01);
      expect(validateDose('999.99'), 999.99);
      for (final invalid in ['', '0', '-1', '2.555', '1000', 'NaN']) {
        expect(
          () => validateDose(invalid),
          throwsA(isA<InjectionValidationException>()),
        );
      }
    });

    test('serializes exact create/update contracts with shared timestamp', () {
      final at = DateTime(2026, 9, 8, 12, 30);
      final create = InjectionCreateRequest(
        DateTime(2026, 9, 8),
        at,
        2.5,
        InjectionSite.thighLeft,
        null,
      ).toJson();
      final update = InjectionUpdateRequest(
        at,
        2.5,
        InjectionSite.thighLeft,
        null,
      ).toJson();
      expect(create['record_date'], '2026-09-08');
      expect(create['dose_mg'], isA<num>());
      expect(create['injected_at'], matches(RegExp(r'(Z|[+-]\d\d:\d\d)$')));
      expect(update.containsKey('record_date'), isFalse);
      expect(update['injection_site'], 'THIGH_LEFT');
    });
  });

  group('repository', () {
    test('uses CRUD paths and authoritative latest query', () async {
      final seen = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          seen.add(options);
          if (options.method == 'DELETE') {
            handler.resolve(Response(requestOptions: options, statusCode: 204));
          } else if (options.method == 'GET' &&
              options.path == '/api/v1/injections') {
            handler.resolve(Response(requestOptions: options, data: {
              'items': [injectionJson()],
              'total': 1,
              'limit': 1,
              'offset': 0,
            }));
          } else {
            handler.resolve(
              Response(requestOptions: options, data: injectionJson()),
            );
          }
        }));
      final repository = InjectionRepository(dio);
      final date = DateTime(2026, 9, 8);
      final request = InjectionUpdateRequest(
        DateTime(2026, 9, 8, 12),
        2.5,
        InjectionSite.abdomenUpperRight,
        null,
      );
      await repository.getByDate(date);
      await repository.create(InjectionCreateRequest(
        date,
        request.injectedAt,
        request.doseMg,
        request.injectionSite,
        null,
      ));
      await repository.update(date, request);
      await repository.delete(date);
      await repository.getLatest();
      expect(seen.map((value) => value.method),
          ['GET', 'POST', 'PUT', 'DELETE', 'GET']);
      expect(seen.last.queryParameters, {'limit': 1, 'offset': 0});
      expect(seen[1].data['dose_mg'], isA<num>());
      expect(seen[2].data.containsKey('record_date'), isFalse);
    });

    test('rejects malformed latest metadata', () async {
      for (final body in [
        {'items': <Object>[], 'total': -1, 'limit': 1, 'offset': 0},
        {'items': <Object>[], 'total': 0, 'limit': 2, 'offset': 0},
        {'items': <Object>[], 'total': 0, 'limit': 1, 'offset': 1},
        {'items': <Object>[], 'total': 1, 'limit': 1, 'offset': 0},
      ]) {
        final dio = Dio()
          ..interceptors.add(InterceptorsWrapper(
            onRequest: (options, handler) => handler.resolve(
              Response(requestOptions: options, data: body),
            ),
          ));
        expect(
          InjectionRepository(dio).getLatest(),
          throwsA(isA<ApiException>().having(
            (error) => error.kind,
            'kind',
            ApiErrorKind.contract,
          )),
        );
      }
    });

    test('normalizes network failures', () async {
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(
          onRequest: (options, handler) => handler.reject(
            DioException.connectionError(
              requestOptions: options,
              reason: 'offline',
            ),
          ),
        ));
      expect(
        InjectionRepository(dio).getLatest(),
        throwsA(isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiErrorKind.network,
        )),
      );
    });
  });

  group('controller', () {
    test('found/not found/network and latest next-date transitions', () async {
      final fake = FakeInjectionRepository();
      final controller = InjectionController(fake, DateTime(2026, 9, 8, 10));
      fake
        ..gets.add(Future.value(record(DateTime(2026, 9, 8))))
        ..latest.add(Future.value(record(DateTime(2026, 9, 6))));
      await controller.load(DateTime(2026, 9, 8));
      expect(controller.state.mode, InjectionMode.edit);
      expect(controller.state.nextScheduledDate, DateTime(2026, 9, 13));

      fake
        ..gets.add(missingRecord())
        ..latest.add(Future.value(record(DateTime(2026, 9, 8))));
      await controller.load(DateTime(2026, 9, 9));
      expect(controller.state.mode, InjectionMode.create);
      expect(controller.state.record, isNull);

      fake.gets.add(Future.error(const ApiException(
        kind: ApiErrorKind.network,
        message: 'offline',
      )));
      await controller.load(DateTime(2026, 9, 10));
      expect(controller.state.mode, InjectionMode.error);
      expect(controller.state.nextScheduledDate, isNull);
    });

    test('create, update and delete reconcile with backend', () async {
      final fake = FakeInjectionRepository();
      final date = DateTime(2026, 9, 8);
      final controller = InjectionController(fake, DateTime(2026, 9, 8, 10));
      fake
        ..gets.add(missingRecord())
        ..latest.add(Future.value(null))
        ..write = Future.value(record(date));
      await controller.load(date);

      fake
        ..gets.add(Future.value(record(date)))
        ..latest.add(Future.value(record(date)));
      expect(
        await controller.save('2.5', InjectionSite.thighRight, '',
            controller.state.injectedAt, date),
        isTrue,
      );
      expect(controller.state.mode, InjectionMode.edit);

      fake
        ..gets.add(Future.value(record(date, dose: 3)))
        ..latest.add(Future.value(record(date, dose: 3)));
      expect(
        await controller.save('3', InjectionSite.thighLeft, 'm',
            controller.state.injectedAt, date),
        isTrue,
      );
      expect(controller.state.record!.doseMg, 3);

      fake
        ..gets.add(missingRecord())
        ..latest.add(Future.value(null));
      expect(await controller.delete(), isTrue);
      expect(controller.state.mode, InjectionMode.create);
      expect(controller.state.record, isNull);
    });

    test('old GET, mutation and reconciliation cannot overwrite new date',
        () async {
      final fake = FakeInjectionRepository();
      final controller = InjectionController(fake, DateTime(2026, 9, 8));
      final oldGet = Completer<InjectionRecord>();
      fake.gets.add(oldGet.future);
      final loading = controller.load(DateTime(2026, 9, 8));
      fake
        ..gets.add(missingRecord())
        ..latest.add(Future.value(null));
      await controller.load(DateTime(2026, 9, 9));
      oldGet.complete(record(DateTime(2026, 9, 8)));
      await loading;
      expect(controller.state.date, DateTime(2026, 9, 9));

      final mutation = Completer<InjectionRecord>();
      fake.write = mutation.future;
      final saving = controller.save('2.5', InjectionSite.thighRight, '',
          controller.state.injectedAt, controller.state.date);
      fake
        ..gets.add(missingRecord())
        ..latest.add(Future.value(null));
      await controller.load(DateTime(2026, 9, 10));
      mutation.complete(record(DateTime(2026, 9, 9)));
      expect(await saving, isFalse);
      expect(controller.state.date, DateTime(2026, 9, 10));

      fake.write = Future.value(record(DateTime(2026, 9, 10)));
      final reconcile = Completer<InjectionRecord>();
      fake.gets.add(reconcile.future);
      final reconciling = controller.save('2.5', InjectionSite.thighRight, '',
          controller.state.injectedAt, controller.state.date);
      await Future<void>.delayed(Duration.zero);
      fake
        ..gets.add(missingRecord())
        ..latest.add(Future.value(null));
      await controller.load(DateTime(2026, 9, 11));
      reconcile.complete(record(DateTime(2026, 9, 10)));
      expect(await reconciling, isFalse);
      expect(controller.state.date, DateTime(2026, 9, 11));
    });

    test('blocks old form and duplicate mutation; latest failure clears date',
        () async {
      final fake = FakeInjectionRepository();
      final date = DateTime(2026, 9, 8);
      final controller = InjectionController(fake, date);
      fake
        ..gets.add(missingRecord())
        ..latest.add(Future.value(record(DateTime(2026, 9, 7))));
      await controller.load(date);
      expect(
        await controller.save('2.5', InjectionSite.thighRight, '',
            controller.state.injectedAt, DateTime(2026, 9, 7)),
        isFalse,
      );
      final write = Completer<InjectionRecord>();
      fake.write = write.future;
      final first = controller.save('2.5', InjectionSite.thighRight, '',
          controller.state.injectedAt, date);
      expect(
        await controller.save('2.5', InjectionSite.thighRight, '',
            controller.state.injectedAt, date),
        isFalse,
      );
      write.complete(record(date));
      fake
        ..gets.add(Future.value(record(date)))
        ..latest.add(Future.error(const ApiException(
          kind: ApiErrorKind.network,
          message: 'offline',
        )));
      expect(await first, isFalse);
      expect(controller.state.mode, InjectionMode.error);
      expect(controller.state.nextScheduledDate, isNull);
      expect(fake.mutations, 1);
    });

    test('failed and stale delete retain the current record safely', () async {
      final fake = FakeInjectionRepository();
      final date = DateTime(2026, 9, 8);
      final controller = InjectionController(fake, date);
      fake
        ..gets.add(Future.value(record(date)))
        ..latest.add(Future.value(record(date)));
      await controller.load(date);
      fake.deleteResult = Future.error(const ApiException(
        kind: ApiErrorKind.network,
        message: 'offline',
      ));
      expect(await controller.delete(), isFalse);
      expect(controller.state.mode, InjectionMode.edit);
      expect(controller.state.record, isNotNull);

      final oldDelete = Completer<void>();
      fake.deleteResult = oldDelete.future;
      final deleting = controller.delete();
      fake
        ..gets.add(missingRecord())
        ..latest.add(Future.value(null));
      await controller.load(DateTime(2026, 9, 9));
      oldDelete.complete();
      expect(await deleting, isFalse);
      expect(controller.state.date, DateTime(2026, 9, 9));
      expect(controller.state.mode, InjectionMode.create);
    });
  });

  group('widgets', () {
    testWidgets('create form has all sites and neutral guidance',
        (tester) async {
      final fake = FakeInjectionRepository()
        ..gets.add(missingRecord())
        ..latest.add(Future.value(null));
      await pumpInjection(tester, fake);
      expect(find.text('この日の注射記録はまだありません。'), findsOneWidget);
      expect(find.textContaining('医療者の指示'), findsWidgets);
      await tester.tap(find.byKey(const Key('injectionSiteField')));
      await tester.pumpAndSettle();
      for (final site in InjectionSite.values) {
        expect(find.text(site.label), findsOneWidget);
      }
    });

    testWidgets('edit prefills and delete confirmation cancels and accepts',
        (tester) async {
      final today = DateTime.now();
      final fake = FakeInjectionRepository()
        ..gets.add(Future.value(record(today)))
        ..latest.add(Future.value(record(today)));
      await pumpInjection(tester, fake);
      expect(find.text('2.5'), findsOneWidget);
      expect(find.text('memo'), findsOneWidget);
      await tester.tap(find.byKey(const Key('deleteInjectionButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(fake.deletes, 0);
      await tester.tap(find.byKey(const Key('deleteInjectionButton')));
      await tester.pumpAndSettle();
      fake
        ..gets.add(missingRecord())
        ..latest.add(Future.value(null));
      await tester.tap(find.text('削除'));
      await tester.pumpAndSettle();
      expect(fake.deletes, 1);
      expect(find.text('この日の注射記録はまだありません。'), findsOneWidget);
    });

    testWidgets(
        'invalid form sends nothing; valid create reconciles and is busy',
        (tester) async {
      final today = DateTime.now();
      final fake = FakeInjectionRepository()
        ..gets.add(missingRecord())
        ..latest.add(Future.value(null));
      await pumpInjection(tester, fake);
      await tester.tap(find.byKey(const Key('saveInjectionButton')));
      await tester.pump();
      expect(find.byKey(const Key('injectionValidation')), findsOneWidget);
      expect(fake.mutations, 0);

      await tester.enterText(find.byKey(const Key('doseField')), '2.5');
      await tester.tap(find.byKey(const Key('injectionSiteField')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(InjectionSite.thighLeft.label).last);
      await tester.pumpAndSettle();
      final pending = Completer<InjectionRecord>();
      fake.write = pending.future;
      final saveButton = find.byKey(const Key('saveInjectionButton')).last;
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pump();
      expect(
        tester.widget<FilledButton>(saveButton).onPressed,
        isNull,
      );
      pending.complete(record(today));
      fake
        ..gets.add(Future.value(record(today)))
        ..latest.add(Future.value(record(today)));
      await tester.pumpAndSettle();
      expect(fake.mutations, 1);
      expect(find.text('更新'), findsOneWidget);
      expect(find.byKey(const Key('nextInjectionDate')), findsOneWidget);
    });

    testWidgets('record menu preserves routes and reaches Injection',
        (tester) async {
      final fake = FakeInjectionRepository();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          apiConfigProvider.overrideWithValue(
            ApiConfig(baseUrl: 'http://example.test'),
          ),
          injectionRepositoryProvider.overrideWithValue(fake),
        ],
        child: const _RouterApp(),
      ));
      expect(find.text('体重'), findsOneWidget);
      expect(find.text('食事'), findsOneWidget);
      expect(find.text('体調'), findsOneWidget);
      final missing = Completer<InjectionRecord>();
      fake.gets.add(missing.future);
      await tester.tap(find.text('注射'));
      await tester.pump();
      missing.completeError(notFound());
      fake.latest.add(Future.value(null));
      await tester.pumpAndSettle();
      expect(find.byType(InjectionScreen), findsOneWidget);
    });
  });
}

class _RouterApp extends ConsumerWidget {
  const _RouterApp();
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MaterialApp.router(routerConfig: ref.watch(appRouterProvider));
}

class FakeInjectionRepository implements InjectionRepository {
  final List<Future<InjectionRecord>> gets = [];
  final List<Future<InjectionRecord?>> latest = [];
  Future<InjectionRecord> write = Completer<InjectionRecord>().future;
  Future<void> deleteResult = Future.value();
  int mutations = 0;
  int deletes = 0;

  @override
  Future<InjectionRecord> getByDate(DateTime date) => gets.removeAt(0);
  @override
  Future<InjectionRecord?> getLatest() => latest.removeAt(0);
  @override
  Future<InjectionRecord> create(InjectionCreateRequest request) {
    mutations++;
    return write;
  }

  @override
  Future<InjectionRecord> update(
      DateTime date, InjectionUpdateRequest request) {
    mutations++;
    return write;
  }

  @override
  Future<void> delete(DateTime date) {
    deletes++;
    return deleteResult;
  }
}

Future<void> pumpInjection(
    WidgetTester tester, FakeInjectionRepository repository) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [injectionRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: InjectionScreen()),
  ));
  await tester.pumpAndSettle();
}
