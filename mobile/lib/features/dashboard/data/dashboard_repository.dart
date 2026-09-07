import '../../../core/network/api_error.dart';
import '../domain/dashboard.dart';
import 'dashboard_api.dart';

class DashboardRepository {
  const DashboardRepository(this._api);
  final DashboardApi _api;

  Future<Dashboard> getDashboard({
    required DateTime date,
    required String timezone,
  }) async {
    try {
      final body = await _api.getDashboard(date: date, timezone: timezone);
      if (body is! Map<String, dynamic>) {
        throw ApiException.contract('Dashboard response must be an object.');
      }
      return Dashboard.fromJson(body);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException.contract('Dashboard response is invalid.', error);
    }
  }
}
