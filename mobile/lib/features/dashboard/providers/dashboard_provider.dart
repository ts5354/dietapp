import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
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
