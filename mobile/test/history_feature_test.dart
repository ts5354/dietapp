import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dietapp/core/network/api_error.dart';
import 'package:dietapp/features/history/data/history_repository.dart';
import 'package:dietapp/features/history/domain/history.dart';
import 'package:dietapp/features/history/presentation/history_screen.dart';
import 'package:dietapp/features/history/providers/history_provider.dart';
import 'package:dietapp/features/injection/domain/injection.dart';
import 'package:dietapp/features/nutrition/domain/nutrition.dart';
import 'package:dietapp/features/symptom/domain/symptom.dart';
import 'package:dietapp/features/weight/domain/weight.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strict page rejects malformed metadata and parses object items', () {
    final valid = parseHistoryPage({
      'items': [
        {'value': 2},
        {'value': 1}
      ],
      'total': 2,
      'limit': 50,
      'offset': 0
    }, 50, 0, (j) => j['value'] as int);
    expect(valid.items, [2, 1]);
    for (final body in [
      {'items': [], 'total': -1, 'limit': 50, 'offset': 0},
      {'items': [], 'total': 1, 'limit': 50, 'offset': 0},
      {'items': [], 'total': 0, 'limit': 49, 'offset': 0},
      {'items': [], 'total': 0, 'limit': 50, 'offset': 1},
    ]) {
      expect(() => parseHistoryPage(body, 50, 0, (_) => 1),
          throwsA(isA<ApiException>()));
    }
  });

  test('weight range uses inclusive days and calendar month semantics', () {
    expect(weightRangeStart(DateTime(2026, 9, 9), WeightRange.sevenDays),
        DateTime(2026, 9, 3));
    expect(weightRangeStart(DateTime(2026, 9, 9), WeightRange.thirtyDays),
        DateTime(2026, 8, 11));
    expect(weightRangeStart(DateTime(2026, 5, 31), WeightRange.threeMonths),
        DateTime(2026, 3, 1));
  });

  test('chart ordering is oldest first without synthesizing missing dates', () {
    final newestFirst = [
      weight(DateTime(2026, 9, 9)),
      weight(DateTime(2026, 9, 7)),
    ];
    final chart = oldestFirst(newestFirst);
    expect(chart.map((item) => item.recordDate.day), [7, 9]);
    expect(chart, hasLength(2));
    expect(newestFirst.first.recordDate.day, 9);
  });

  test('chart axis intervals and rounded weight range remain readable', () {
    expect(weightXAxisInterval(WeightRange.sevenDays), 1);
    expect(weightXAxisInterval(WeightRange.thirtyDays), 7);
    expect(weightXAxisInterval(WeightRange.threeMonths), 14);

    final varied = weightYAxis(79.1, 83.4);
    expect(varied.min, lessThanOrEqualTo(79.1));
    expect(varied.max, greaterThanOrEqualTo(83.4));
    expect(varied.interval, 2);

    final single = weightYAxis(80.2, 80.2);
    expect(single.min, lessThan(80.2));
    expect(single.max, greaterThan(80.2));
    expect(single.max - single.min, greaterThanOrEqualTo(4));
  });

  test('repository sends authoritative paths, filters and pagination',
      () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        requests.add(o);
        h.resolve(Response(
            requestOptions: o,
            data: {'items': <Object>[], 'total': 0, 'limit': 50, 'offset': 0}));
      }));
    final repository = HistoryRepository(dio);
    await repository.weights(DateTime(2026, 9, 3), DateTime(2026, 9, 9), 50, 0);
    await repository.nutrition(50, 0);
    await repository.symptoms(50, 0);
    await repository.injections(50, 0);
    expect(requests.map((r) => r.path), [
      '/api/v1/weights',
      '/api/v1/nutrition/days',
      '/api/v1/symptoms',
      '/api/v1/injections'
    ]);
    expect(requests.first.queryParameters['from'], '2026-09-03');
    expect(requests[2].queryParameters.containsKey('timezone'), isFalse);
  });

  test('range change and stale response reset weight pagination', () async {
    final fake = FakeHistoryRepository();
    final controller = HistoryController(fake, DateTime(2026, 9, 9));
    final old = Completer<HistoryPage<WeightRecord>>();
    fake.weightResults.add(old.future);
    final pending = controller.loadWeight();
    await Future<void>.delayed(Duration.zero);
    fake.weightResults.add(
        Future.value(HistoryPage([weight(DateTime(2026, 9, 9))], 1, 50, 0)));
    await controller.loadWeight(range: WeightRange.thirtyDays);
    old.complete(HistoryPage([weight(DateTime(2026, 9, 3))], 1, 50, 0));
    await pending;
    expect(controller.state.range, WeightRange.thirtyDays);
    expect(
        controller.state.weights.items.single.recordDate, DateTime(2026, 9, 9));
  });

  test('duplicate load more is prevented and pages append once', () async {
    final fake = FakeHistoryRepository();
    final controller = HistoryController(fake, DateTime(2026, 9, 9));
    fake.weightResults.add(
        Future.value(HistoryPage([weight(DateTime(2026, 9, 9))], 2, 50, 0)));
    await controller.loadWeight();
    final more = Completer<HistoryPage<WeightRecord>>();
    fake.weightResults.add(more.future);
    final first = controller.loadMoreWeight();
    await controller.loadMoreWeight();
    expect(fake.weightCalls, 2);
    more.complete(HistoryPage([weight(DateTime(2026, 9, 8))], 2, 50, 1));
    await first;
    expect(controller.state.weights.items.length, 2);
  });

  test('nutrition, symptom and injection stale responses are ignored',
      () async {
    final fake = FakeHistoryRepository();
    final controller = HistoryController(fake, DateTime(2026, 9, 9));

    final oldNutrition = Completer<HistoryPage<NutritionDaySummary>>();
    fake.nutritionResults.add(oldNutrition.future);
    final nutritionPending = controller.loadNutrition();
    await Future<void>.delayed(Duration.zero);
    fake.nutritionResults.add(Future.value(HistoryPage(
        [nutrition(DateTime(2026, 9, 9), NutritionMode.normal)], 1, 50, 0)));
    await controller.loadNutrition();
    oldNutrition.complete(HistoryPage(
        [nutrition(DateTime(2026, 9, 8), NutritionMode.freeDay)], 1, 50, 0));
    await nutritionPending;
    expect(controller.state.nutrition.items.single.date.day, 9);

    final oldSymptoms = Completer<HistoryPage<SymptomRecord>>();
    fake.symptomResults.add(oldSymptoms.future);
    final symptomPending = controller.loadSymptoms();
    await Future<void>.delayed(Duration.zero);
    fake.symptomResults
        .add(Future.value(HistoryPage([symptom(id: 2)], 1, 50, 0)));
    await controller.loadSymptoms();
    oldSymptoms.complete(HistoryPage([symptom(id: 1)], 1, 50, 0));
    await symptomPending;
    expect(controller.state.symptoms.items.single.id, 2);

    final oldInjections = Completer<HistoryPage<InjectionRecord>>();
    fake.injectionResults.add(oldInjections.future);
    final injectionPending = controller.loadInjections();
    await Future<void>.delayed(Duration.zero);
    fake.injectionResults
        .add(Future.value(HistoryPage([injection(id: 2)], 1, 50, 0)));
    await controller.loadInjections();
    oldInjections.complete(HistoryPage([injection(id: 1)], 1, 50, 0));
    await injectionPending;
    expect(controller.state.injections.items.single.id, 2);
  });

  test('refresh invalidates an older load-more response', () async {
    final fake = FakeHistoryRepository();
    final controller = HistoryController(fake, DateTime(2026, 9, 9));
    fake.weightResults.add(
        Future.value(HistoryPage([weight(DateTime(2026, 9, 9))], 2, 50, 0)));
    await controller.loadWeight();
    final oldPage = Completer<HistoryPage<WeightRecord>>();
    fake.weightResults.add(oldPage.future);
    final loadingMore = controller.loadMoreWeight();
    await Future<void>.delayed(Duration.zero);
    fake.weightResults.add(
        Future.value(HistoryPage([weight(DateTime(2026, 9, 8))], 1, 50, 0)));
    await controller.loadWeight();
    oldPage.complete(HistoryPage([weight(DateTime(2026, 9, 7))], 2, 50, 1));
    await loadingMore;
    expect(controller.state.weights.items.single.recordDate.day, 8);
  });

  test('history contracts cover nutrition modes and injection sites', () {
    final normal = NutritionDaySummary.fromJson(nutritionJson());
    final free = NutritionDaySummary.fromJson(
        nutritionJson(mode: 'FREE_DAY', calories: null, protein: null));
    expect(normal.mode, NutritionMode.normal);
    expect(normal.totalCalories, 1800);
    expect(free.mode, NutritionMode.freeDay);
    expect(free.totalCalories, isNull);
    for (final malformed in [
      nutritionJson(mode: 'UNRECORDED'),
      nutritionJson(mode: 'FREE_DAY', calories: 0, protein: 0),
    ]) {
      expect(() => NutritionDaySummary.fromJson(malformed),
          throwsA(isA<ApiException>()));
    }
    for (final site in InjectionSite.values) {
      expect(
          InjectionRecord.fromJson(injectionJson(site.apiValue)).injectionSite,
          site);
    }
    expect(() => InjectionRecord.fromJson(injectionJson('UNKNOWN')),
        throwsA(isA<ApiException>()));
  });

  test('symptom duplicate timestamps and backend ordering are preserved',
      () async {
    final fake = FakeHistoryRepository()
      ..symptomResults.add(Future.value(
          HistoryPage([symptom(id: 2), symptom(id: 1)], 2, 50, 0)));
    final controller = HistoryController(fake, DateTime(2026, 9, 9));
    await controller.loadSymptoms();
    expect(controller.state.symptoms.items.map((item) => item.id), [2, 1]);
    expect(
        controller.state.symptoms.items.map((item) => item.recordedAt).toSet(),
        hasLength(1));
  });

  testWidgets('Weight supports one point and empty states', (tester) async {
    final fake = FakeHistoryRepository()
      ..weightResults.add(
          Future.value(HistoryPage([weight(DateTime(2026, 9, 9))], 1, 50, 0)));
    await pumpHistory(tester, fake);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('62.3 kg'), findsOneWidget);
    final chartWidget = tester.widget<LineChart>(find.byType(LineChart));
    final chartData = chartWidget.data;
    final bar = chartData.lineBarsData.single;
    final tooltipItems = chartData.lineTouchData.touchTooltipData
        .getTooltipItems([LineBarSpot(bar, 0, bar.spots.single)]);
    expect(chartData.lineTouchData.touchSpotThreshold, 24);
    expect(tooltipItems.single!.text, contains('9月9日'));
    expect(tooltipItems.single!.text, contains('62.3 kg'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final empty = FakeHistoryRepository()
      ..weightResults.add(Future.value(
          const HistoryPage<WeightRecord>(<WeightRecord>[], 0, 50, 0)));
    await pumpHistory(tester, empty);
    expect(find.text('この期間の体重記録はありません。'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
  });

  testWidgets('History distinguishes loading, error and retry', (tester) async {
    final pending = Completer<HistoryPage<WeightRecord>>();
    final fake = FakeHistoryRepository()..weightResults.add(pending.future);
    await pumpHistory(tester, fake, settle: false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(
        const ApiException(kind: ApiErrorKind.network, message: 'offline'));
    await tester.pumpAndSettle();
    expect(find.text('サーバーに接続できませんでした。'), findsOneWidget);
    fake.weightResults.add(
        Future.value(HistoryPage([weight(DateTime(2026, 9, 9))], 1, 50, 0)));
    await tester.tap(find.text('再読み込み'));
    await tester.pumpAndSettle();
    expect(find.text('62.3 kg'), findsOneWidget);
  });

  testWidgets('History shows tabs, ranges, graph/list and safety wording',
      (tester) async {
    final fake = FakeHistoryRepository()
      ..weightResults.add(Future.value(HistoryPage([
        weight(DateTime(2026, 9, 9)),
        weight(DateTime(2026, 9, 7), value: 63)
      ], 2, 50, 0)))
      ..nutritionResults.add(Future.value(HistoryPage([
        NutritionDaySummary(
            date: DateTime(2026, 9, 8),
            mode: NutritionMode.freeDay,
            memo: null,
            totalCalories: null,
            totalProteinG: null)
      ], 1, 50, 0)))
      ..symptomResults.add(Future.value(HistoryPage([symptom()], 1, 50, 0)))
      ..injectionResults
          .add(Future.value(HistoryPage([injection()], 1, 50, 0)));
    await tester.pumpWidget(ProviderScope(overrides: [
      historyRepositoryProvider.overrideWithValue(fake),
    ], child: const MaterialApp(home: HistoryScreen())));
    await tester.pumpAndSettle();
    expect(find.text('履歴'), findsWidgets);
    for (final label in ['体重', '食事', '体調', '注射', '7日', '30日', '3か月']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('62.3 kg'), findsOneWidget);
    await tester.tap(find.text('食事').first);
    await tester.pumpAndSettle();
    expect(find.text('Free Day'), findsOneWidget);
    expect(find.text('0 kcal'), findsNothing);
    await tester.tap(find.text('体調').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('吐き気 2'), findsOneWidget);
    await tester.tap(find.text('注射').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('2.5 mg'), findsOneWidget);
    expect(find.textContaining('医療者の指示'), findsOneWidget);
    for (final prohibited in ['BMI', '順調', '食べすぎ', '重症', '適正dose', '増量']) {
      expect(find.textContaining(prohibited), findsNothing);
    }
  });
}

WeightRecord weight(DateTime date, {double value = 62.3}) => WeightRecord(
    id: 1,
    recordDate: date,
    weightKg: value,
    recordedAt: date,
    memo: null,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026));
SymptomRecord symptom({int id = 1}) => SymptomRecord(
    id: id,
    recordedAt: DateTime.utc(2026, 9, 8, 3),
    nausea: 2,
    abdominalPain: 1,
    fatigue: 4,
    appetite: 6,
    bowelCondition: BowelCondition.normal,
    memo: null,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026));
InjectionRecord injection({int id = 1}) => InjectionRecord(
    id: id,
    recordDate: DateTime(2026, 9, 8),
    injectedAt: DateTime.utc(2026, 9, 8, 1),
    doseMg: 2.5,
    injectionSite: InjectionSite.abdomenUpperRight,
    memo: null,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026));

NutritionDaySummary nutrition(DateTime date, NutritionMode mode) =>
    NutritionDaySummary(
        date: date,
        mode: mode,
        memo: null,
        totalCalories: mode == NutritionMode.normal ? 1800 : null,
        totalProteinG: mode == NutritionMode.normal ? 75.5 : null);

Map<String, dynamic> nutritionJson(
        {String mode = 'NORMAL',
        Object? calories = 1800,
        Object? protein = 75.5}) =>
    {
      'date': '2026-09-08',
      'mode': mode,
      'memo': null,
      'total_calories': calories,
      'total_protein_g': protein,
    };

Map<String, dynamic> injectionJson(String site) => {
      'id': 1,
      'record_date': '2026-09-08',
      'injected_at': '2026-09-08T03:30:00Z',
      'dose_mg': 2.5,
      'injection_site': site,
      'memo': null,
      'created_at': '2026-09-08T03:30:00Z',
      'updated_at': '2026-09-08T03:30:00Z',
    };

Future<void> pumpHistory(WidgetTester tester, FakeHistoryRepository repository,
    {bool settle = true}) async {
  await tester.pumpWidget(ProviderScope(overrides: [
    historyRepositoryProvider.overrideWithValue(repository),
  ], child: const MaterialApp(home: HistoryScreen())));
  if (settle) await tester.pumpAndSettle();
}

class FakeHistoryRepository implements HistoryRepository {
  final weightResults = <Future<HistoryPage<WeightRecord>>>[];
  final nutritionResults = <Future<HistoryPage<NutritionDaySummary>>>[];
  final symptomResults = <Future<HistoryPage<SymptomRecord>>>[];
  final injectionResults = <Future<HistoryPage<InjectionRecord>>>[];
  int weightCalls = 0;
  @override
  Future<HistoryPage<WeightRecord>> weights(
      DateTime from, DateTime to, int limit, int offset) {
    weightCalls++;
    return weightResults.removeAt(0);
  }

  @override
  Future<HistoryPage<NutritionDaySummary>> nutrition(int limit, int offset) =>
      nutritionResults.removeAt(0);
  @override
  Future<HistoryPage<SymptomRecord>> symptoms(int limit, int offset) =>
      symptomResults.removeAt(0);
  @override
  Future<HistoryPage<InjectionRecord>> injections(int limit, int offset) =>
      injectionResults.removeAt(0);
}
