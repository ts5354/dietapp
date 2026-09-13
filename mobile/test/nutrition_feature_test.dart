import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dietapp/core/config/api_config.dart';
import 'package:dietapp/core/network/api_error.dart';
import 'package:dietapp/core/network/dio_provider.dart';
import 'package:dietapp/core/timezone/device_timezone.dart';
import 'package:dietapp/features/dashboard/data/dashboard_repository.dart';
import 'package:dietapp/features/dashboard/domain/dashboard.dart';
import 'package:dietapp/features/dashboard/providers/dashboard_provider.dart';
import 'package:dietapp/features/nutrition/data/nutrition_repository.dart';
import 'package:dietapp/features/nutrition/domain/nutrition.dart';
import 'package:dietapp/features/nutrition/presentation/nutrition_screen.dart';
import 'package:dietapp/features/nutrition/providers/nutrition_provider.dart';
import 'package:dietapp/features/weight/data/weight_repository.dart';
import 'package:dietapp/features/weight/domain/weight.dart';
import 'package:dietapp/features/weight/providers/weight_provider.dart';
import 'package:dietapp/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> foodJson({int id = 1}) => {
      'id': id,
      'name': '昼食',
      'calories': 600,
      'protein_g': 25.5,
      'eaten_at': '2026-09-07T03:30:00Z',
      'memo': 'memo',
      'created_at': '2026-09-07T03:30:00Z',
      'updated_at': '2026-09-07T03:30:00Z',
    };

Map<String, dynamic> dayJson(String mode,
        {List<Map<String, dynamic>> foods = const [], String? memo}) =>
    {
      'date': '2026-09-07',
      'mode': mode,
      'memo': memo,
      'total_calories': mode == 'NORMAL' ? 600 : null,
      'total_protein_g': mode == 'NORMAL' ? 25.5 : null,
      'foods': foods,
    };

NutritionDay day(NutritionMode mode,
        {DateTime? date, List<FoodLog> foods = const [], String? memo}) =>
    NutritionDay(
      date: date ?? DateTime(2026, 9, 7),
      mode: mode,
      memo: memo,
      totalCalories: mode == NutritionMode.normal
          ? foods.fold<int>(0, (sum, food) => sum + food.calories)
          : null,
      totalProteinG: mode == NutritionMode.normal
          ? foods.fold<double>(0, (sum, food) => sum + food.proteinG)
          : null,
      foods: foods,
    );

FoodLog food({int id = 1}) => FoodLog(
      id: id,
      name: '昼食',
      calories: 600,
      proteinG: 25.5,
      eatenAt: DateTime.utc(2026, 9, 7, 3, 30),
      memo: 'memo',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

FoodWriteRequest request([DateTime? date]) => FoodFormValues(
      name: ' 昼食 ',
      calories: '600',
      protein: '25.50',
      time: DateTime(
          (date ?? DateTime(2026, 9, 7)).year,
          (date ?? DateTime(2026, 9, 7)).month,
          (date ?? DateTime(2026, 9, 7)).day,
          12,
          30),
      memo: ' ',
    ).requestFor(date ?? DateTime(2026, 9, 7));

void main() {
  group('models', () {
    test('accepts Z and positive/negative offset food timestamps', () {
      for (final timestamp in [
        '2026-09-07T03:30:00Z',
        '2026-09-07T12:30:00+09:00',
        '2026-09-06T23:30:00-04:00',
      ]) {
        final json = foodJson()
          ..['eaten_at'] = timestamp
          ..['created_at'] = timestamp
          ..['updated_at'] = timestamp;
        final parsed = FoodLog.fromJson(json);
        expect(parsed.eatenAt.isUtc, isTrue);
        expect(parsed.createdAt.isUtc, isTrue);
        expect(parsed.updatedAt.isUtc, isTrue);
      }
    });

    test('rejects timezone-naive food timestamps', () {
      for (final field in ['eaten_at', 'created_at', 'updated_at']) {
        final json = foodJson()..[field] = '2026-09-07T12:30:00';
        expect(() => FoodLog.fromJson(json), throwsA(isA<ApiException>()));
      }
    });

    test('parses all modes, empty NORMAL, food, and additive fields', () {
      final normalJson = dayJson('NORMAL', foods: [foodJson()])..['extra'] = 1;
      final normal = NutritionDay.fromJson(normalJson);
      expect(normal.mode, NutritionMode.normal);
      expect(normal.foods.single.name, '昼食');
      expect(normal.foods.single.eatenAt.isUtc, isTrue);

      final empty = dayJson('NORMAL')
        ..['total_calories'] = 0
        ..['total_protein_g'] = 0.0;
      expect(NutritionDay.fromJson(empty).totalCalories, 0);
      for (final mode in ['FREE_DAY', 'UNRECORDED']) {
        final parsed = NutritionDay.fromJson(dayJson(mode));
        expect(parsed.totalCalories, isNull);
        expect(parsed.totalProteinG, isNull);
      }
    });

    test('rejects malformed contracts and state invariants', () {
      final cases = <Map<String, dynamic>>[
        dayJson('UNKNOWN'),
        {...dayJson('NORMAL'), 'date': 'bad'},
        {...dayJson('NORMAL'), 'total_calories': null},
        {...dayJson('FREE_DAY'), 'total_calories': 0},
        {
          ...dayJson('FREE_DAY'),
          'foods': [foodJson()]
        },
        {
          ...dayJson('UNRECORDED'),
          'foods': [foodJson()]
        },
        {
          ...dayJson('NORMAL'),
          'foods': [foodJson()..['calories'] = '600']
        },
        {
          ...dayJson('NORMAL'),
          'foods': [foodJson()..['protein_g'] = '25.5']
        },
        {
          ...dayJson('NORMAL'),
          'foods': [foodJson()..['eaten_at'] = '2026-09-07T12:30:00']
        },
        Map<String, dynamic>.from(dayJson('FREE_DAY'))
          ..remove('total_calories'),
        {
          ...dayJson('NORMAL'),
          'foods': [Map<String, dynamic>.from(foodJson())..remove('memo')]
        },
      ];
      for (final value in cases) {
        expect(
            () => NutritionDay.fromJson(value), throwsA(isA<ApiException>()));
      }
    });
  });

  group('serialization and validation', () {
    test('serializes trimmed, typed, timezone-aware food without ids', () {
      final json = request().toJson();
      expect(json['name'], '昼食');
      expect(json['calories'], isA<int>());
      expect(json['protein_g'], isA<double>());
      expect(json['eaten_at'], matches(RegExp(r'(Z|[+-]\d\d:\d\d)$')));
      expect(json['memo'], isNull);
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('nutrition_day_id'), isFalse);
    });

    test('mode serialization excludes UNRECORDED and preserves memo', () {
      expect(
          const NutritionDayUpdateRequest(NutritionMode.normal, 'day memo')
              .toJson(),
          {'mode': 'NORMAL', 'memo': 'day memo'});
      expect(
          const NutritionDayUpdateRequest(NutritionMode.freeDay, null).toJson(),
          {'mode': 'FREE_DAY', 'memo': null});
    });

    test('validates inputs without rounding and accepts zero', () {
      FoodFormValues values(String name, String calories, String protein,
              {String memo = ''}) =>
          FoodFormValues(
              name: name,
              calories: calories,
              protein: protein,
              time: DateTime(2026),
              memo: memo);
      expect(values('x', '0', '0').requestFor(DateTime(2026)).calories, 0);
      for (final invalid in [
        values('', '1', '1'),
        values('   ', '1', '1'),
        values('x' * 101, '1', '1'),
        values('x', '', '1'),
        values('x', 'abc', '1'),
        values('x', '1.2', '1'),
        values('x', '-1', '1'),
        values('x', '1', ''),
        values('x', '1', 'abc'),
        values('x', '1', '-1'),
        values('x', '1', '2.555'),
        values('x', '1', '10000'),
        values('x', '1', '1', memo: 'x' * 501),
      ]) {
        expect(() => invalid.requestFor(DateTime(2026)),
            throwsA(isA<FoodValidationException>()));
      }
    });
  });

  group('repository', () {
    test('uses nested paths, request bodies, shared Dio, and DELETE 204',
        () async {
      final seen = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
          seen.add(options);
          if (options.method == 'DELETE') {
            handler.resolve(Response(requestOptions: options, statusCode: 204));
          } else if (options.path.endsWith('/foods') ||
              options.path.contains('/foods/')) {
            handler
                .resolve(Response(requestOptions: options, data: foodJson()));
          } else {
            handler.resolve(
                Response(requestOptions: options, data: dayJson('UNRECORDED')));
          }
        }));
      final repository = NutritionRepository(dio);
      final date = DateTime(2026, 9, 7);
      await repository.getDay(date);
      await repository.setDayMode(
          date, const NutritionDayUpdateRequest(NutritionMode.normal, 'memo'));
      await repository.createFood(date, request());
      await repository.updateFood(date, 42, request());
      await repository.deleteFood(date, 42);
      expect(seen.map((request) => request.method),
          ['GET', 'PUT', 'POST', 'PUT', 'DELETE']);
      expect(seen[0].path, '/api/v1/nutrition/days/2026-09-07');
      expect(seen[1].data, {'mode': 'NORMAL', 'memo': 'memo'});
      expect(seen[2].path, '/api/v1/nutrition/days/2026-09-07/foods');
      expect(seen[3].path, '/api/v1/nutrition/days/2026-09-07/foods/42');
      expect(seen[4].path, '/api/v1/nutrition/days/2026-09-07/foods/42');
    });

    test('normalizes network/server errors and malformed success', () async {
      final networkDio = Dio()
        ..interceptors.add(InterceptorsWrapper(
            onRequest: (options, handler) => handler.reject(
                DioException.connectionError(
                    requestOptions: options, reason: 'offline'))));
      expect(
          NutritionRepository(networkDio).getDay(DateTime(2026)),
          throwsA(isA<ApiException>()
              .having((error) => error.kind, 'kind', ApiErrorKind.network)));

      final serverDio = Dio()
        ..interceptors.add(InterceptorsWrapper(
            onRequest: (options, handler) => handler.reject(
                DioException.badResponse(
                    requestOptions: options,
                    statusCode: 409,
                    response: Response(
                        requestOptions: options,
                        statusCode: 409,
                        data: {
                          'error': {
                            'code': 'FOOD_NOT_ALLOWED_ON_FREE_DAY',
                            'message': 'conflict'
                          }
                        })))));
      expect(
          NutritionRepository(serverDio).createFood(DateTime(2026), request()),
          throwsA(isA<ApiException>().having(
              (error) => error.code, 'code', 'FOOD_NOT_ALLOWED_ON_FREE_DAY')));

      final malformedDio = Dio()
        ..interceptors.add(InterceptorsWrapper(
            onRequest: (options, handler) =>
                handler.resolve(Response(requestOptions: options, data: []))));
      expect(
          NutritionRepository(malformedDio).getDay(DateTime(2026)),
          throwsA(isA<ApiException>()
              .having((error) => error.kind, 'kind', ApiErrorKind.contract)));
    });
  });

  group('controller', () {
    test('loads three states and keeps GET failure as error', () async {
      final fake = FakeNutritionRepository();
      final controller = NutritionController(fake, DateTime(2026, 9, 7));
      for (final mode in NutritionMode.values) {
        fake.getResults.add(Future.value(day(mode)));
        await controller.load(DateTime(2026, 9, 7));
        expect(controller.state.viewMode, NutritionViewMode.ready);
        expect(controller.state.day!.mode, mode);
      }
      fake.getResults.add(Future.error(
          const ApiException(kind: ApiErrorKind.network, message: 'offline')));
      await controller.load(DateTime(2026, 9, 8));
      expect(controller.state.viewMode, NutritionViewMode.error);
      expect(controller.state.day, isNull);
    });

    test('food mutations reconcile, including last delete as empty NORMAL',
        () async {
      final fake = FakeNutritionRepository();
      final controller = NutritionController(fake, DateTime(2026, 9, 7));
      fake.getResults.add(Future.value(day(NutritionMode.unrecorded)));
      await controller.load(DateTime(2026, 9, 7));

      fake.foodResult = Future.value(food());
      fake.getResults
          .add(Future.value(day(NutritionMode.normal, foods: [food()])));
      expect(await controller.createFood(request()), isTrue);
      expect(fake.modeWrites, 0);
      expect(controller.state.day!.foods, hasLength(1));

      fake.getResults
          .add(Future.value(day(NutritionMode.normal, foods: [food()])));
      expect(await controller.updateFood(1, request()), isTrue);
      fake.getResults.add(Future.value(day(NutritionMode.normal)));
      expect(await controller.deleteFood(1), isTrue);
      expect(controller.state.day!.mode, NutritionMode.normal);
      expect(controller.state.day!.totalCalories, 0);
      expect(fake.getCalls, 4);
    });

    test('old GET, mutation, and reconciliation never overwrite a new date',
        () async {
      final fake = FakeNutritionRepository();
      final controller = NutritionController(fake, DateTime(2026, 9, 7));
      final oldGet = Completer<NutritionDay>();
      fake.getResults.add(oldGet.future);
      final loading = controller.load(DateTime(2026, 9, 7));
      fake.getResults.add(Future.value(
          day(NutritionMode.unrecorded, date: DateTime(2026, 9, 8))));
      await controller.load(DateTime(2026, 9, 8));
      oldGet.complete(day(NutritionMode.normal));
      await loading;
      expect(controller.state.date.day, 8);

      final oldMutation = Completer<FoodLog>();
      fake.foodResult = oldMutation.future;
      final creating = controller.createFood(request(DateTime(2026, 9, 8)));
      fake.getResults.add(Future.value(
          day(NutritionMode.unrecorded, date: DateTime(2026, 9, 9))));
      await controller.load(DateTime(2026, 9, 9));
      oldMutation.complete(food());
      await creating;
      expect(controller.state.date.day, 9);

      fake.foodResult = Future.value(food());
      final oldReconcile = Completer<NutritionDay>();
      fake.getResults.add(oldReconcile.future);
      final updatingSetup =
          controller.createFood(request(DateTime(2026, 9, 9)));
      await Future<void>.delayed(Duration.zero);
      fake.getResults.add(Future.value(
          day(NutritionMode.unrecorded, date: DateTime(2026, 9, 10))));
      await controller.load(DateTime(2026, 9, 10));
      oldReconcile.complete(day(NutritionMode.normal));
      await updatingSetup;
      expect(controller.state.date.day, 10);
    });

    test('old update/delete responses and duplicate mutations are ignored',
        () async {
      final fake = FakeNutritionRepository();
      final controller = NutritionController(fake, DateTime(2026, 9, 7));
      fake.getResults
          .add(Future.value(day(NutritionMode.normal, foods: [food()])));
      await controller.load(DateTime(2026, 9, 7));
      final update = Completer<FoodLog>();
      fake.foodResult = update.future;
      final first = controller.updateFood(1, request());
      expect(await controller.updateFood(1, request()), isFalse);
      fake.getResults.add(Future.value(
          day(NutritionMode.unrecorded, date: DateTime(2026, 9, 8))));
      await controller.load(DateTime(2026, 9, 8));
      update.complete(food());
      await first;
      expect(controller.state.date.day, 8);

      fake.getResults.add(Future.value(day(NutritionMode.normal,
          date: DateTime(2026, 9, 9), foods: [food()])));
      await controller.load(DateTime(2026, 9, 9));
      final deletion = Completer<void>();
      fake.deleteResult = deletion.future;
      final deleting = controller.deleteFood(1);
      fake.getResults.add(Future.value(
          day(NutritionMode.unrecorded, date: DateTime(2026, 9, 10))));
      await controller.load(DateTime(2026, 9, 10));
      deletion.complete();
      await deleting;
      expect(controller.state.date.day, 10);
    });

    test('mode transitions preserve memo, block foods, and reconcile',
        () async {
      final fake = FakeNutritionRepository();
      final controller = NutritionController(fake, DateTime(2026, 9, 7));
      fake.getResults.add(Future.value(day(NutritionMode.unrecorded)));
      await controller.load(DateTime(2026, 9, 7));
      fake.getResults.add(Future.value(day(NutritionMode.freeDay)));
      expect(await controller.setMode(NutritionMode.freeDay), isTrue);
      fake.getResults
          .add(Future.value(day(NutritionMode.normal, memo: 'keep me')));
      await controller.load(DateTime(2026, 9, 7));
      fake.getResults
          .add(Future.value(day(NutritionMode.freeDay, memo: 'keep me')));
      expect(await controller.setMode(NutritionMode.freeDay), isTrue);
      expect(fake.lastModeRequest!.memo, 'keep me');
      fake.getResults
          .add(Future.value(day(NutritionMode.normal, memo: 'keep me')));
      expect(await controller.setMode(NutritionMode.normal), isTrue);

      fake.getResults.add(Future.value(
          day(NutritionMode.normal, foods: [food()], memo: 'keep me')));
      await controller.load(DateTime(2026, 9, 7));
      final deletes = fake.deleteCalls;
      expect(await controller.setMode(NutritionMode.freeDay), isFalse);
      expect(fake.deleteCalls, deletes);
      expect(fake.modeWrites, 3);
    });

    test('FREE_DAY blocks create and reconciliation failure is error',
        () async {
      final fake = FakeNutritionRepository();
      final controller = NutritionController(fake, DateTime(2026, 9, 7));
      fake.getResults.add(Future.value(day(NutritionMode.freeDay)));
      await controller.load(DateTime(2026, 9, 7));
      expect(await controller.createFood(request()), isFalse);
      expect(fake.foodWrites, 0);

      fake.getResults.add(Future.value(day(NutritionMode.unrecorded)));
      await controller.load(DateTime(2026, 9, 7));
      fake.foodResult = Future.value(food());
      fake.getResults.add(Future.error(
          const ApiException(kind: ApiErrorKind.network, message: 'offline')));
      expect(await controller.createFood(request()), isFalse);
      expect(controller.state.viewMode, NutritionViewMode.error);
      expect(controller.state.day, isNull);
    });

    test('a form from an old selected date sends no mutation', () async {
      final fake = FakeNutritionRepository();
      final controller = NutritionController(fake, DateTime(2026, 9, 7));
      fake.getResults.add(Future.value(
          day(NutritionMode.unrecorded, date: DateTime(2026, 9, 8))));
      await controller.load(DateTime(2026, 9, 8));

      expect(await controller.createFood(request()), isFalse);
      expect(fake.foodWrites, 0);
    });

    test('stable errors have neutral localized messages', () {
      for (final entry in {
        'FOOD_NOT_ALLOWED_ON_FREE_DAY': 'Free Dayには食事記録を追加できません。',
        'FOOD_DATE_MISMATCH': '食事の日時と記録日が一致していません。',
        'FOOD_NOT_FOUND': 'この食事記録は見つかりませんでした。再読み込みしてください。',
        'FREE_DAY_HAS_FOOD_LOGS':
            'この日には食事記録があります。Free Dayに変更するには、先に食事記録を削除してください。',
      }.entries) {
        expect(nutritionErrorMessage(serverError(entry.key)), entry.value);
      }
    });
  });

  group('widgets', () {
    testWidgets('Food and Weight routes are reachable', (tester) async {
      final fake = FakeNutritionRepository()
        ..getResults.add(Future.value(day(NutritionMode.unrecorded)));
      await tester.pumpWidget(ProviderScope(overrides: [
        apiConfigProvider.overrideWithValue(
          ApiConfig(baseUrl: 'http://example.test'),
        ),
        dashboardRepositoryProvider.overrideWithValue(_DashboardRepository()),
        deviceTimezoneProvider.overrideWithValue(_DeviceTimezone()),
        nutritionRepositoryProvider.overrideWithValue(fake),
        weightRepositoryProvider.overrideWithValue(_MissingWeightRepository()),
      ], child: const TestRouterApp()));
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('食事'));
      await tester.pumpAndSettle();
      expect(find.text('食事記録'), findsOneWidget);
      final context = tester.element(find.byType(NutritionScreen));
      ProviderScope.containerOf(context).read(appRouterProvider).go('/');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('体重'));
      await tester.pumpAndSettle();
      expect(find.textContaining('体重'), findsWidgets);
    });

    testWidgets(
        'renders UNRECORDED, NORMAL totals/list, and FREE_DAY distinctly',
        (tester) async {
      await pumpNutrition(tester, day(NutritionMode.unrecorded));
      expect(find.byKey(const Key('unrecordedState')), findsOneWidget);
      expect(find.textContaining('0 kcal'), findsNothing);
      await pumpNutrition(tester, day(NutritionMode.normal, foods: [food()]));
      expect(find.text('記録合計'), findsOneWidget);
      expect(find.text('600 kcal'), findsWidgets);
      expect(find.textContaining('25.5 g'), findsWidgets);
      expect(find.byKey(const Key('food-1')), findsOneWidget);
      await pumpNutrition(tester, day(NutritionMode.freeDay));
      expect(find.byKey(const Key('freeDayState')), findsOneWidget);
      expect(find.text('この日は栄養計算をしない日として記録されています。'), findsOneWidget);
      expect(find.textContaining('0 kcal'), findsNothing);
    });

    testWidgets('create form validates and starts clean every time',
        (tester) async {
      final fake = FakeNutritionRepository();
      await pumpNutrition(tester, day(NutritionMode.unrecorded), fake: fake);
      await tester.tap(find.byKey(const Key('addFoodButton')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('foodNameField')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('foodNameField')), 'old');
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('addFoodButton')));
      await tester.pumpAndSettle();
      expect(find.text('old'), findsNothing);
      await tester.tap(find.byKey(const Key('saveFoodButton')));
      await tester.pump();
      expect(find.byKey(const Key('foodValidation')), findsOneWidget);
      expect(fake.foodWrites, 0);
    });

    testWidgets('edit prefills and delete confirmation can cancel or accept',
        (tester) async {
      final fake = FakeNutritionRepository();
      await pumpNutrition(tester, day(NutritionMode.normal, foods: [food()]),
          fake: fake);
      await tester.tap(find.byKey(const Key('food-1')));
      await tester.pumpAndSettle();
      expect(find.text('昼食'), findsWidgets);
      expect(find.text('600'), findsOneWidget);
      expect(find.text('25.5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('deleteFoodButton')));
      await tester.pumpAndSettle();
      expect(find.text('この食事記録を削除しますか？'), findsOneWidget);
      await tester.tap(find.text('キャンセル').last);
      await tester.pumpAndSettle();
      expect(fake.deleteCalls, 0);
      await tester.tap(find.byKey(const Key('deleteFoodButton')));
      await tester.pumpAndSettle();
      fake.getResults.add(Future.value(day(NutritionMode.normal)));
      await tester.tap(find.text('削除'));
      await tester.pumpAndSettle();
      expect(fake.deleteCalls, 1);
    });

    testWidgets('create and edit show neutral success feedback',
        (tester) async {
      final fake = FakeNutritionRepository();
      await pumpNutrition(tester, day(NutritionMode.unrecorded), fake: fake);
      await tester.tap(find.byKey(const Key('addFoodButton')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('foodNameField')), '昼食');
      await tester.enterText(find.byKey(const Key('caloriesField')), '600');
      await tester.enterText(find.byKey(const Key('proteinField')), '25.5');
      final today = DateTime.now();
      fake.getResults.add(Future.value(day(NutritionMode.normal,
          date: DateTime(today.year, today.month, today.day),
          foods: [food()])));
      await tester.tap(find.byKey(const Key('saveFoodButton')));
      await tester.pumpAndSettle();
      expect(find.text('食事記録を保存しました。'), findsOneWidget);
      tester
          .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('food-1')));
      await tester.pumpAndSettle();
      fake.getResults.add(Future.value(day(NutritionMode.normal,
          date: DateTime(today.year, today.month, today.day),
          foods: [food()])));
      await tester.tap(find.byKey(const Key('saveFoodButton')));
      await tester.pumpAndSettle();
      expect(fake.foodWrites, 2);
      expect(find.text('食事記録を更新しました。'), findsOneWidget);
    });

    testWidgets('FREE_DAY confirmation cancels/accepts and food day blocks it',
        (tester) async {
      final fake = FakeNutritionRepository();
      await pumpNutrition(tester, day(NutritionMode.unrecorded), fake: fake);
      await tester.tap(find.byKey(const Key('freeDayButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(fake.modeWrites, 0);
      await tester.tap(find.byKey(const Key('freeDayButton')));
      await tester.pumpAndSettle();
      fake.getResults.add(Future.value(day(NutritionMode.freeDay)));
      await tester.tap(find.text('Free Dayにする'));
      await tester.pumpAndSettle();
      expect(fake.modeWrites, 1);
      expect(find.byKey(const Key('normalModeButton')), findsOneWidget);
      fake.getResults.add(Future.value(day(NutritionMode.normal)));
      await tester.tap(find.byKey(const Key('normalModeButton')));
      await tester.pumpAndSettle();
      expect(fake.modeWrites, 2);
      expect(find.byKey(const Key('addFoodButton')), findsOneWidget);

      await pumpNutrition(tester, day(NutritionMode.normal, foods: [food()]));
      await tester.tap(find.byKey(const Key('freeDayButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining('先に食事記録を削除してください'), findsOneWidget);
      expect(find.text('Free Dayにする'), findsNothing);
    });

    testWidgets('busy state disables duplicate actions', (tester) async {
      final fake = FakeNutritionRepository();
      await pumpNutrition(tester, day(NutritionMode.normal), fake: fake);
      final pending = Completer<NutritionDay>();
      fake.getResults.add(pending.future);
      final context = tester.element(find.byType(NutritionScreen));
      final operation = ProviderScope.containerOf(context)
          .read(nutritionControllerProvider.notifier)
          .setMode(NutritionMode.freeDay);
      await tester.pump();
      expect(find.byKey(const Key('nutritionBusy')), findsOneWidget);
      final add =
          tester.widget<FilledButton>(find.byKey(const Key('addFoodButton')));
      expect(add.onPressed, isNull);
      pending.complete(day(NutritionMode.freeDay));
      await operation;
    });
  });
}

class FakeNutritionRepository implements NutritionRepository {
  final List<Future<NutritionDay>> getResults = [];
  Future<FoodLog> foodResult = Future.value(food());
  Future<void> deleteResult = Future.value();
  int getCalls = 0;
  int foodWrites = 0;
  int deleteCalls = 0;
  int modeWrites = 0;
  NutritionDayUpdateRequest? lastModeRequest;

  @override
  Future<NutritionDay> getDay(DateTime date) {
    getCalls++;
    return getResults.removeAt(0);
  }

  @override
  Future<NutritionDay> setDayMode(
      DateTime date, NutritionDayUpdateRequest request) {
    modeWrites++;
    lastModeRequest = request;
    return Future.value(day(request.mode, date: date, memo: request.memo));
  }

  @override
  Future<FoodLog> createFood(DateTime date, FoodWriteRequest request) {
    foodWrites++;
    return foodResult;
  }

  @override
  Future<FoodLog> updateFood(DateTime date, int id, FoodWriteRequest request) {
    foodWrites++;
    return foodResult;
  }

  @override
  Future<void> deleteFood(DateTime date, int id) {
    deleteCalls++;
    return deleteResult;
  }
}

class _MissingWeightRepository implements WeightRepository {
  @override
  Future<WeightRecord> get(DateTime date) => Future.error(const ApiException(
      kind: ApiErrorKind.server,
      statusCode: 404,
      code: 'WEIGHT_NOT_FOUND',
      message: 'missing'));
  @override
  Future<WeightRecord> create(CreateWeightRequest request) =>
      throw UnimplementedError();
  @override
  Future<WeightRecord> update(DateTime date, UpdateWeightRequest request) =>
      throw UnimplementedError();
  @override
  Future<void> delete(DateTime date) => throw UnimplementedError();
}

ApiException serverError(String code) => ApiException(
    kind: ApiErrorKind.server, statusCode: 409, code: code, message: code);

Future<void> pumpNutrition(WidgetTester tester, NutritionDay loaded,
    {FakeNutritionRepository? fake}) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  final repository = fake ?? FakeNutritionRepository();
  final now = DateTime.now();
  repository.getResults.add(Future.value(NutritionDay(
      date: DateTime(now.year, now.month, now.day),
      mode: loaded.mode,
      memo: loaded.memo,
      totalCalories: loaded.totalCalories,
      totalProteinG: loaded.totalProteinG,
      foods: loaded.foods)));
  await tester.pumpWidget(ProviderScope(
    overrides: [nutritionRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: NutritionScreen()),
  ));
  await tester.pumpAndSettle();
}

class TestRouterApp extends ConsumerWidget {
  const TestRouterApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MaterialApp.router(routerConfig: ref.watch(appRouterProvider));
}

class _DeviceTimezone implements DeviceTimezone {
  @override
  Future<String> currentIdentifier() async => 'UTC';
}

class _DashboardRepository implements DashboardRepository {
  @override
  Future<Dashboard> getDashboard({
    required DateTime date,
    required String timezone,
  }) async =>
      Dashboard.fromJson({
        'date': formatApiDate(date),
        'timezone': timezone,
        'weight': {'status': 'UNRECORDED', 'record': null},
        'nutrition': {'status': 'UNRECORDED', 'record': null},
        'symptom': {'status': 'UNRECORDED', 'record': null},
        'injection': {
          'status': 'UNRECORDED',
          'record': null,
          'next_scheduled_date': null,
        },
      });
}
