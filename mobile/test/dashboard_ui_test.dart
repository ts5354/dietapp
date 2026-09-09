import 'dart:async';

import 'package:dietapp/core/network/api_error.dart';
import 'package:dietapp/core/timezone/device_timezone.dart';
import 'package:dietapp/features/dashboard/data/dashboard_repository.dart';
import 'package:dietapp/features/dashboard/domain/dashboard.dart';
import 'package:dietapp/features/dashboard/providers/dashboard_provider.dart';
import 'package:dietapp/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> snapshot({
  String date = '2026-09-08',
  String timezone = 'America/New_York',
  bool recorded = true,
  String nutritionMode = 'NORMAL',
  bool nextDate = true,
}) =>
    {
      'date': date,
      'timezone': timezone,
      'weight': recorded
          ? {
              'status': 'RECORDED',
              'record': {'record_date': date, 'weight_kg': 62.3},
            }
          : {'status': 'UNRECORDED', 'record': null},
      'nutrition': recorded
          ? {
              'status': 'RECORDED',
              'record': {
                'mode': nutritionMode,
                'total_calories': nutritionMode == 'NORMAL' ? 1800 : null,
                'total_protein_g': nutritionMode == 'NORMAL' ? 75.5 : null,
              },
            }
          : {'status': 'UNRECORDED', 'record': null},
      'symptom': recorded
          ? {
              'status': 'RECORDED',
              'record': {
                'recorded_at': '${date}T16:30:00Z',
                'nausea': 2,
                'abdominal_pain': 3,
                'fatigue': 4,
                'appetite': 5,
                'bowel_condition': 'NORMAL',
              },
            }
          : {'status': 'UNRECORDED', 'record': null},
      'injection': recorded
          ? {
              'status': 'RECORDED',
              'record': {'record_date': date},
              'next_scheduled_date': nextDate ? '2026-09-15' : null,
            }
          : {
              'status': 'UNRECORDED',
              'record': null,
              'next_scheduled_date': null,
            },
    };

Dashboard dashboard({String date = '2026-09-08', bool recorded = true}) =>
    Dashboard.fromJson(snapshot(date: date, recorded: recorded));

Future<Dashboard> dashboardFailure(ApiException error) =>
    Future<Dashboard>.delayed(Duration.zero, () => throw error);

void main() {
  group('strict dashboard contract', () {
    test('accepts valid/additive states and null next date', () {
      final json = snapshot()..['future_field'] = true;
      expect(Dashboard.fromJson(json).weight.record!.weightKg, 62.3);
      expect(
        Dashboard.fromJson(snapshot(recorded: false))
            .injection
            .nextScheduledDate,
        isNull,
      );
      expect(
        Dashboard.fromJson(snapshot(nutritionMode: 'FREE_DAY'))
            .nutrition
            .record!
            .totalCalories,
        isNull,
      );
    });

    test('rejects missing, invalid date/status and impossible states', () {
      final cases = <Map<String, dynamic>>[
        Map.of(snapshot())..remove('weight'),
        {...snapshot(), 'date': '2026-02-30'},
        {
          ...snapshot(),
          'weight': {'status': 'UNKNOWN', 'record': null},
        },
        {
          ...snapshot(),
          'injection': {
            'status': 'UNRECORDED',
            'record': null,
            'next_scheduled_date': '2026-09-15',
          },
        },
      ];
      for (final value in cases) {
        expect(() => Dashboard.fromJson(value), throwsA(isA<ApiException>()));
      }
    });

    test('rejects malformed numbers, scales and timestamp', () {
      final cases = <Map<String, dynamic>>[];
      for (final weight in ['62.3', double.nan, 0]) {
        final json = snapshot();
        (json['weight'] as Map)['record']['weight_kg'] = weight;
        cases.add(json);
      }
      var json = snapshot();
      (json['nutrition'] as Map)['record']['total_calories'] = 1.5;
      cases.add(json);
      json = snapshot();
      (json['nutrition'] as Map)['record']['total_protein_g'] = -1;
      cases.add(json);
      json = snapshot();
      (json['symptom'] as Map)['record']['nausea'] = 11;
      cases.add(json);
      json = snapshot();
      (json['symptom'] as Map)['record']['recorded_at'] = '2026-09-08T12:30:00';
      cases.add(json);
      for (final value in cases) {
        expect(() => Dashboard.fromJson(value), throwsA(isA<ApiException>()));
      }
    });
  });

  group('dashboard controller', () {
    test('initial load, date change, error and retry', () async {
      final repository = FakeDashboardRepository();
      final controller = DashboardController(
        repository,
        FakeTimezone('America/New_York'),
        DateTime(2026, 9, 8, 22),
      );
      expect(controller.state.date, DateTime(2026, 9, 8));
      repository.responses.add(Future.value(dashboard()));
      await controller.load(DateTime(2026, 9, 8));
      expect(controller.state.mode, DashboardViewMode.ready);
      expect(repository.dates.single, DateTime(2026, 9, 8));
      expect(repository.timezones.single, 'America/New_York');

      repository.responses.add(dashboardFailure(const ApiException(
        kind: ApiErrorKind.network,
        message: 'offline',
      )));
      await controller.load(DateTime(2026, 9, 9));
      expect(controller.state.mode, DashboardViewMode.error);
      expect(controller.state.dashboard, isNull);

      repository.responses.add(Future.value(dashboard(date: '2026-09-09')));
      await controller.refresh();
      expect(controller.state.mode, DashboardViewMode.ready);
      expect(controller.state.date, DateTime(2026, 9, 9));
    });

    test('stale load and refresh responses never overwrite current date',
        () async {
      final repository = FakeDashboardRepository();
      final controller = DashboardController(
        repository,
        FakeTimezone('America/New_York'),
        DateTime(2026, 9, 8),
      );
      final old = Completer<Dashboard>();
      repository.responses.add(old.future);
      final loading = controller.load(DateTime(2026, 9, 8));
      await Future<void>.delayed(Duration.zero);
      repository.responses.add(Future.value(dashboard(date: '2026-09-09')));
      await controller.load(DateTime(2026, 9, 9));
      old.complete(dashboard());
      await loading;
      expect(controller.state.date, DateTime(2026, 9, 9));

      final refresh = Completer<Dashboard>();
      repository.responses.add(refresh.future);
      final refreshing = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      repository.responses.add(Future.value(dashboard(date: '2026-09-10')));
      await controller.load(DateTime(2026, 9, 10));
      refresh.complete(dashboard(date: '2026-09-09'));
      await refreshing;
      expect(controller.state.date, DateTime(2026, 9, 10));
    });

    test('timezone and mismatched response failures become error state',
        () async {
      final repository = FakeDashboardRepository();
      final failed = DashboardController(
        repository,
        FakeTimezone.failure(),
        DateTime(2026, 9, 8),
      );
      await failed.load(DateTime(2026, 9, 8));
      expect(failed.state.mode, DashboardViewMode.error);
      expect(repository.dates, isEmpty);

      final mismatch = DashboardController(
        repository,
        FakeTimezone('America/New_York'),
        DateTime(2026, 9, 8),
      );
      repository.responses.add(Future.value(dashboard(date: '2026-09-09')));
      await mismatch.load(DateTime(2026, 9, 8));
      expect(mismatch.state.mode, DashboardViewMode.error);
    });
  });

  group('dashboard widgets', () {
    testWidgets('renders recorded sections and neutral wording',
        (tester) async {
      await pumpHome(tester, dashboard());
      expect(find.text('ホーム'), findsOneWidget);
      expect(find.text('62.3 kg'), findsOneWidget);
      expect(find.text('1800 kcal'), findsOneWidget);
      expect(find.textContaining('吐き気 2'), findsOneWidget);
      await tester.drag(
          find.byKey(const Key('dashboardScroll')), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('最新の記録日 2026/09/08'), findsOneWidget);
      expect(
          find.byKey(const Key('dashboardNextInjectionDate')), findsOneWidget);
      expect(find.textContaining('医療者の指示'), findsOneWidget);
      for (final prohibited in ['BMI', '食べすぎ', '危険', '適正dose', '増量']) {
        expect(find.textContaining(prohibited), findsNothing);
      }
    });

    testWidgets('renders unrecorded and free day without fabricated totals',
        (tester) async {
      await pumpHome(tester, dashboard(recorded: false));
      expect(find.text('この日の記録はありません。'), findsNWidgets(4));
      expect(find.byKey(const Key('dashboardNextInjectionDate')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await pumpHome(
        tester,
        Dashboard.fromJson(snapshot(nutritionMode: 'FREE_DAY')),
      );
      expect(find.text('Free Day'), findsOneWidget);
      expect(find.text('0 kcal'), findsNothing);
      expect(find.text('0 g'), findsNothing);
    });

    testWidgets('loading, error and retry are distinct from unrecorded',
        (tester) async {
      final repository = FakeDashboardRepository();
      final pending = Completer<Dashboard>();
      repository.responses.add(pending.future);
      await pumpHomeWithRepository(tester, repository, settle: false);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.completeError(const ApiException(
        kind: ApiErrorKind.network,
        message: 'offline',
      ));
      await tester.pumpAndSettle();
      expect(find.text('サーバーに接続できませんでした。'), findsOneWidget);
      expect(find.text('この日の記録はありません。'), findsNothing);
      repository.responses.add(Future.value(dashboard()));
      await tester.tap(find.byKey(const Key('retryDashboardButton')));
      await tester.pumpAndSettle();
      expect(find.text('62.3 kg'), findsOneWidget);
    });
  });
}

class FakeTimezone implements DeviceTimezone {
  FakeTimezone(this.value) : error = null;
  FakeTimezone.failure()
      : value = null,
        error = StateError('unavailable');
  final String? value;
  final Object? error;
  @override
  Future<String> currentIdentifier() =>
      error == null ? Future.value(value) : Future.error(error!);
}

class FakeDashboardRepository implements DashboardRepository {
  final List<Future<Dashboard>> responses = [];
  final List<DateTime> dates = [];
  final List<String> timezones = [];
  @override
  Future<Dashboard> getDashboard({
    required DateTime date,
    required String timezone,
  }) {
    dates.add(date);
    timezones.add(timezone);
    return responses.removeAt(0);
  }
}

Future<void> pumpHome(WidgetTester tester, Dashboard value) async {
  final repository = FakeDashboardRepository()
    ..responses.add(Future.value(value));
  await pumpHomeWithRepository(tester, repository);
}

Future<void> pumpHomeWithRepository(
  WidgetTester tester,
  FakeDashboardRepository repository, {
  bool settle = true,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      dashboardRepositoryProvider.overrideWithValue(repository),
      deviceTimezoneProvider
          .overrideWithValue(FakeTimezone('America/New_York')),
    ],
    child: const MaterialApp(home: HomeScreen()),
  ));
  if (settle) await tester.pumpAndSettle();
}
