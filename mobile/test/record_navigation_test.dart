import 'dart:async';

import 'package:dietapp/core/timezone/device_timezone.dart';
import 'package:dietapp/features/dashboard/data/dashboard_repository.dart';
import 'package:dietapp/features/dashboard/domain/dashboard.dart';
import 'package:dietapp/features/dashboard/providers/dashboard_provider.dart';
import 'package:dietapp/features/history/data/history_repository.dart';
import 'package:dietapp/features/history/domain/history.dart';
import 'package:dietapp/features/history/providers/history_provider.dart';
import 'package:dietapp/features/injection/domain/injection.dart';
import 'package:dietapp/features/nutrition/domain/nutrition.dart';
import 'package:dietapp/features/record/presentation/record_screen.dart';
import 'package:dietapp/features/symptom/domain/symptom.dart';
import 'package:dietapp/features/weight/domain/weight.dart';
import 'package:dietapp/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('Home Record destination opens the Record screen',
      (tester) async {
    final fixture = await _pumpApp(tester, '/');

    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();

    expect(fixture.router.routeInformationProvider.value.uri.path, '/record');
    expect(find.byType(RecordScreen), findsOneWidget);
    expect(find.text('記録'), findsOneWidget);
    fixture.dispose();
  });

  testWidgets('Record has selected index 1 and keeps its route when reselected',
      (tester) async {
    final fixture = await _pumpApp(tester, '/record');
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));

    expect(navigation.selectedIndex, 1);
    expect(Navigator.of(tester.element(find.byType(RecordScreen))).canPop(),
        isFalse);

    await tester.tap(find.text('Record'));
    await tester.pump();

    expect(fixture.router.routeInformationProvider.value.uri.path, '/record');
    expect(Navigator.of(tester.element(find.byType(RecordScreen))).canPop(),
        isFalse);
    fixture.dispose();
  });

  testWidgets('Record navigates to Home, History and Settings', (tester) async {
    for (final destination in <String, String>{
      'Home': '/',
      'History': '/history',
      'Settings': '/settings',
    }.entries) {
      final fixture = await _pumpApp(tester, '/record');

      await tester.tap(find.text(destination.key));
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

      await tester.tap(find.text('Record'));
      await tester.pumpAndSettle();

      expect(fixture.router.routeInformationProvider.value.uri.path, '/record');
      expect(find.byType(RecordScreen), findsOneWidget);
      fixture.dispose();
    }
  });

  testWidgets('Record opens every existing record route', (tester) async {
    for (final destination in <String, String>{
      '体重': '/record/weight',
      '食事': '/record/food',
      '体調': '/record/symptom',
      '注射': '/record/injection',
    }.entries) {
      final fixture = await _pumpApp(tester, '/record');

      await tester.tap(find.text(destination.key));

      expect(
        fixture.router.routeInformationProvider.value.uri.path,
        destination.value,
      );
      fixture.dispose();
    }
  });
}

Future<_AppFixture> _pumpApp(WidgetTester tester, String location) async {
  final container = ProviderContainer(overrides: [
    dashboardRepositoryProvider.overrideWithValue(_PendingDashboard()),
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
