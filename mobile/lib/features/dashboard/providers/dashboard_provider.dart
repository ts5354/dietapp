import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/timezone/device_timezone.dart';
import '../data/dashboard_api.dart';
import '../data/dashboard_repository.dart';
import '../domain/dashboard.dart';

final dashboardApiProvider = Provider<DashboardApi>(
  (ref) => DashboardApi(ref.watch(dioProvider)),
);

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => DashboardRepository(ref.watch(dashboardApiProvider)),
);

class DashboardQuery {
  const DashboardQuery({required this.date, required this.timezone});
  final DateTime date;
  final String timezone;

  @override
  bool operator ==(Object other) =>
      other is DashboardQuery &&
      other.date == date &&
      other.timezone == timezone;

  @override
  int get hashCode => Object.hash(date, timezone);
}

final dashboardProvider = FutureProvider.family<Dashboard, DashboardQuery>(
  (ref, query) => ref.watch(dashboardRepositoryProvider).getDashboard(
        date: query.date,
        timezone: query.timezone,
      ),
);

enum DashboardViewMode { loading, ready, error }

class DashboardState {
  const DashboardState({
    required this.date,
    this.mode = DashboardViewMode.loading,
    this.dashboard,
    this.message,
  });
  final DateTime date;
  final DashboardViewMode mode;
  final Dashboard? dashboard;
  final String? message;
}

final dashboardControllerProvider =
    StateNotifierProvider<DashboardController, DashboardState>(
        (ref) => DashboardController.withRepositoryResolver(
              () => ref.read(dashboardRepositoryProvider),
              ref.watch(deviceTimezoneProvider),
              DateTime.now(),
            ));

class DashboardController extends StateNotifier<DashboardState> {
  DashboardController(
    DashboardRepository repository,
    DeviceTimezone timezone,
    DateTime now,
  ) : this.withRepositoryResolver(() => repository, timezone, now);

  DashboardController.withRepositoryResolver(
    this._resolveRepository,
    this._timezone,
    DateTime now,
  ) : super(DashboardState(date: DateTime(now.year, now.month, now.day)));
  final DashboardRepository Function() _resolveRepository;
  final DeviceTimezone _timezone;
  int _generation = 0;

  Future<void> load(DateTime date) async {
    final selected = DateTime(date.year, date.month, date.day);
    final token = ++_generation;
    state = DashboardState(date: selected);
    await _fetch(token, selected);
  }

  Future<void> refresh() async {
    final token = ++_generation;
    await _fetch(token, state.date, keepDashboard: true);
  }

  Future<void> _fetch(int token, DateTime date,
      {bool keepDashboard = false}) async {
    try {
      final repository = _resolveRepository();
      final timezone = await _timezone.currentIdentifier();
      if (!_isCurrent(token, date)) return;
      final dashboard =
          await repository.getDashboard(date: date, timezone: timezone);
      if (!_isCurrent(token, date)) return;
      if (dashboard.date != date || dashboard.timezone != timezone) {
        throw ApiException.contract('Dashboard query does not match response.');
      }
      state = DashboardState(
          date: date, mode: DashboardViewMode.ready, dashboard: dashboard);
    } on ApiException catch (error) {
      if (!_isCurrent(token, date)) return;
      state = DashboardState(
        date: date,
        mode: DashboardViewMode.error,
        dashboard: keepDashboard ? state.dashboard : null,
        message: dashboardErrorMessage(error),
      );
    } catch (_) {
      if (!_isCurrent(token, date)) return;
      state = DashboardState(
        date: date,
        mode: DashboardViewMode.error,
        dashboard: keepDashboard ? state.dashboard : null,
        message: 'ホーム情報の取得中にエラーが発生しました。',
      );
    }
  }

  bool _isCurrent(int token, DateTime date) =>
      token == _generation && state.date == date;
}

String dashboardErrorMessage(ApiException error) => switch (error.kind) {
      ApiErrorKind.network => 'サーバーに接続できませんでした。',
      ApiErrorKind.timeout => '通信がタイムアウトしました。',
      _ => 'ホーム情報の取得中にエラーが発生しました。',
    };
