import 'dart:async';

import 'package:dietapp/core/network/api_error.dart';
import 'package:dietapp/core/config/api_config.dart';
import 'package:dietapp/core/network/dio_provider.dart';
import 'package:dietapp/core/timezone/device_timezone.dart';
import 'package:dietapp/features/dashboard/data/dashboard_repository.dart';
import 'package:dietapp/features/dashboard/domain/dashboard.dart';
import 'package:dietapp/features/dashboard/providers/dashboard_provider.dart';
import 'package:dietapp/features/history/data/history_repository.dart';
import 'package:dietapp/features/history/domain/history.dart';
import 'package:dietapp/features/history/providers/history_provider.dart';
import 'package:dietapp/features/injection/domain/injection.dart';
import 'package:dietapp/features/injection/presentation/injection_screen.dart';
import 'package:dietapp/features/nutrition/domain/nutrition.dart';
import 'package:dietapp/features/nutrition/presentation/nutrition_screen.dart';
import 'package:dietapp/features/record/presentation/record_screen.dart';
import 'package:dietapp/features/symptom/domain/symptom.dart';
import 'package:dietapp/features/symptom/presentation/symptom_screen.dart';
import 'package:dietapp/features/weight/domain/weight.dart';
import 'package:dietapp/features/weight/presentation/weight_screen.dart';
import 'package:dietapp/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('Home round trips keep data visible and refresh from every tab',
      (tester) async {
    for (final destination in ['履歴', '記録', '設定']) {
      final repository = _LifecycleDashboard();
      final fixture = await _pumpApp(tester, '/', dashboard: repository);
      await tester.pumpAndSettle();
      expect(find.text('62.3 kg'), findsOneWidget);

      await _tapDestination(tester, destination);
      await _finishRouteTransition(tester);
      await _tapDestination(tester, 'ホーム');
      await _finishRouteTransition(tester);

      expect(repository.calls, 2);
      expect(find.text('62.3 kg'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '体重'), findsNothing);

      repository.refresh.complete(_dashboard(64.1));
      await tester.pumpAndSettle();
      expect(find.text('64.1 kg'), findsOneWidget);
      fixture.dispose();
    }
  });

  testWidgets('failed refresh keeps the existing Dashboard visible',
      (tester) async {
    final repository = _LifecycleDashboard();
    final fixture = await _pumpApp(tester, '/', dashboard: repository);
    await tester.pumpAndSettle();

    await _tapDestination(tester, '設定');
    await _finishRouteTransition(tester);
    await _tapDestination(tester, 'ホーム');
    await _finishRouteTransition(tester);
    repository.refresh.completeError(const ApiException(
      kind: ApiErrorKind.network,
      message: 'offline',
    ));
    await tester.pumpAndSettle();

    expect(find.text('62.3 kg'), findsOneWidget);
    expect(find.text('サーバーに接続できませんでした。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '体重'), findsNothing);
    fixture.dispose();
  });

  testWidgets('Home Record destination opens the Record screen',
      (tester) async {
    final fixture = await _pumpApp(tester, '/');

    await _tapDestination(tester, '記録');
    await tester.pumpAndSettle();

    expect(fixture.router.routeInformationProvider.value.uri.path, '/record');
    expect(find.byType(RecordScreen), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('記録')),
        findsOneWidget);
    fixture.dispose();
  });

  testWidgets('Home primary record button opens the Record screen',
      (tester) async {
    final repository = _LifecycleDashboard();
    final fixture = await _pumpApp(tester, '/', dashboard: repository);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
        find.byKey(const Key('homeRecordButton')), 300);
    await tester.tap(find.byKey(const Key('homeRecordButton')));
    await _finishRouteTransition(tester);

    expect(fixture.router.routeInformationProvider.value.uri.path, '/record');
    expect(find.byType(RecordScreen), findsOneWidget);
    fixture.dispose();
  });

  testWidgets('the shell keeps one NavigationBar and updates its selection',
      (tester) async {
    final fixture = await _pumpApp(tester, '/');
    final navigationElement = tester.element(find.byType(NavigationBar));

    for (final destination in <String, int>{
      'ホーム': 0,
      '記録': 1,
      '履歴': 2,
      '設定': 3,
    }.entries) {
      await _tapDestination(tester, destination.key);
      await _finishRouteTransition(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          destination.value);
      expect(
          identical(
              tester.element(find.byType(NavigationBar)), navigationElement),
          isTrue);
    }
    fixture.dispose();
  });

  testWidgets('Record has selected index 1 and keeps its route when reselected',
      (tester) async {
    final fixture = await _pumpApp(tester, '/record');
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));

    expect(navigation.selectedIndex, 1);
    expect(Navigator.of(tester.element(find.byType(RecordScreen))).canPop(),
        isFalse);

    await _tapDestination(tester, '記録');
    await tester.pump();

    expect(fixture.router.routeInformationProvider.value.uri.path, '/record');
    expect(Navigator.of(tester.element(find.byType(RecordScreen))).canPop(),
        isFalse);
    fixture.dispose();
  });

  testWidgets('Record navigates to Home, History and Settings', (tester) async {
    for (final destination in <String, String>{
      'ホーム': '/',
      '履歴': '/history',
      '設定': '/settings',
    }.entries) {
      final fixture = await _pumpApp(tester, '/record');

      await _tapDestination(tester, destination.key);
      await tester.pump();

      expect(
        fixture.router.routeInformationProvider.value.uri.path,
        destination.value,
      );
      fixture.dispose();
    }
  });

  testWidgets('History and Settings navigate to the Record screen',
      (tester) async {
    for (final start in ['/history', '/settings']) {
      final fixture = await _pumpApp(tester, start);

      await _tapDestination(tester, '記録');
      await tester.pumpAndSettle();

      expect(fixture.router.routeInformationProvider.value.uri.path, '/record');
      expect(find.byType(RecordScreen), findsOneWidget);
      fixture.dispose();
    }
  });

  testWidgets('Record opens every existing record route', (tester) async {
    for (final destination in <String, Type>{
      '体重': WeightScreen,
      '食事': NutritionScreen,
      '体調': SymptomScreen,
      '注射': InjectionScreen,
    }.entries) {
      final fixture = await _pumpApp(tester, '/record');

      await tester.tap(find.widgetWithText(ListTile, destination.key));
      await _finishRouteTransition(tester);

      expect(find.byType(destination.value), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      fixture.router.pop();
      await _finishRouteTransition(tester);
      expect(fixture.router.routeInformationProvider.value.uri.path, '/record');
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          1);
      await tester.pumpWidget(const SizedBox());
      fixture.dispose();
      await tester.pump();
    }
  });
}

Future<void> _finishRouteTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tapDestination(WidgetTester tester, String label) => tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );

Future<_AppFixture> _pumpApp(
  WidgetTester tester,
  String location, {
  DashboardRepository? dashboard,
}) async {
  final container = ProviderContainer(overrides: [
    apiConfigProvider
        .overrideWithValue(ApiConfig(baseUrl: 'http://127.0.0.1:1')),
    dashboardRepositoryProvider
        .overrideWithValue(dashboard ?? _PendingDashboard()),
    historyRepositoryProvider.overrideWithValue(_PendingHistory()),
    deviceTimezoneProvider.overrideWithValue(_FakeTimezone()),
  ]);
  final router = container.read(appRouterProvider)..go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  return _AppFixture(container, router);
}

class _LifecycleDashboard implements DashboardRepository {
  final refresh = Completer<Dashboard>();
  int calls = 0;

  @override
  Future<Dashboard> getDashboard({
    required DateTime date,
    required String timezone,
  }) {
    calls++;
    if (calls == 1) return Future.value(_dashboard(62.3, date, timezone));
    return refresh.future;
  }
}

Dashboard _dashboard(
  double weight, [
  DateTime? requestedDate,
  String timezone = 'America/New_York',
]) {
  final date = requestedDate ?? DateTime.now();
  final day =
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  return Dashboard.fromJson({
    'date': day,
    'timezone': timezone,
    'weight': {
      'status': 'RECORDED',
      'record': {'record_date': day, 'weight_kg': weight},
    },
    'nutrition': {'status': 'UNRECORDED', 'record': null},
    'symptom': {'status': 'UNRECORDED', 'record': null},
    'injection': {
      'status': 'UNRECORDED',
      'record': null,
      'next_scheduled_date': null,
    },
  });
}

class _AppFixture {
  const _AppFixture(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;

  void dispose() => container.dispose();
}

class _FakeTimezone implements DeviceTimezone {
  @override
  Future<String> currentIdentifier() async => 'America/New_York';
}

class _PendingDashboard implements DashboardRepository {
  @override
  Future<Dashboard> getDashboard({
    required DateTime date,
    required String timezone,
  }) =>
      Completer<Dashboard>().future;
}

class _PendingHistory implements HistoryRepository {
  @override
  Future<HistoryPage<WeightRecord>> weights(
    DateTime from,
    DateTime to,
    int limit,
    int offset,
  ) =>
      Completer<HistoryPage<WeightRecord>>().future;

  @override
  Future<HistoryPage<NutritionDaySummary>> nutrition(int limit, int offset) =>
      Completer<HistoryPage<NutritionDaySummary>>().future;

  @override
  Future<HistoryPage<SymptomRecord>> symptoms(int limit, int offset) =>
      Completer<HistoryPage<SymptomRecord>>().future;

  @override
  Future<HistoryPage<InjectionRecord>> injections(int limit, int offset) =>
      Completer<HistoryPage<InjectionRecord>>().future;
}
