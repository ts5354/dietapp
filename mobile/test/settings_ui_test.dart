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
import 'package:dietapp/features/symptom/domain/symptom.dart';
import 'package:dietapp/features/weight/domain/weight.dart';
import 'package:dietapp/routing/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('/settings renders static, neutral settings content',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = container.read(appRouterProvider)..go('/settings');
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();

    for (final text in [
      '表示・単位',
      '体重の単位',
      'kg（固定）',
      '記録データ',
      '体重',
      '食事',
      '体調',
      '注射',
      '医療上の注意',
      'アプリ情報',
      'ダイエット男',
    ]) {
      expect(find.text(text, skipOffstage: false), findsOneWidget);
    }
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('設定')),
        findsOneWidget);
    expect(find.textContaining('医療者の指示', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('診断や治療方針', skipOffstage: false), findsOneWidget);
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.selectedIndex, 3);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(TextField), findsNothing);
    for (final prohibited in [
      '適正dose',
      '増量',
      '減量',
      '理想体重',
      '目標体重',
      '順調',
      '停滞',
      '食べすぎ',
    ]) {
      expect(
          find.textContaining(prohibited, skipOffstage: false), findsNothing);
    }
  });

  testWidgets('Settings navigation reaches Home, Record and History',
      (tester) async {
    for (final destination in <String, String>{
      'ホーム': '/',
      '記録': '/record',
      '履歴': '/history',
    }.entries) {
      final container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(_PendingDashboard()),
        deviceTimezoneProvider.overrideWithValue(_FakeTimezone()),
        historyRepositoryProvider.overrideWithValue(_PendingHistory()),
      ]);
      final router = container.read(appRouterProvider)..go('/settings');
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(destination.key));
      await tester.pump();
      expect(router.routeInformationProvider.value.uri.path, destination.value);
      container.dispose();
    }
  });

  testWidgets('Home and History navigation connect to Settings',
      (tester) async {
    for (final start in ['/', '/history']) {
      final container = ProviderContainer(overrides: [
        dashboardRepositoryProvider.overrideWithValue(_PendingDashboard()),
        deviceTimezoneProvider.overrideWithValue(_FakeTimezone()),
        historyRepositoryProvider.overrideWithValue(_PendingHistory()),
      ]);
      final router = container.read(appRouterProvider)..go(start);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router)));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('設定'));
      await tester.pumpAndSettle();
      expect(
          find.descendant(of: find.byType(AppBar), matching: find.text('設定')),
          findsOneWidget);
      container.dispose();
    }
  });
}

class _FakeTimezone implements DeviceTimezone {
  @override
  Future<String> currentIdentifier() async => 'America/New_York';
}

class _PendingDashboard implements DashboardRepository {
  @override
  Future<Dashboard> getDashboard(
          {required DateTime date, required String timezone}) =>
      Completer<Dashboard>().future;
}

class _PendingHistory implements HistoryRepository {
  @override
  Future<HistoryPage<WeightRecord>> weights(
          DateTime from, DateTime to, int limit, int offset) =>
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
