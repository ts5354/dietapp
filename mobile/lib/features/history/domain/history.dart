import '../../../core/network/api_error.dart';

class HistoryPage<T> {
  const HistoryPage(this.items, this.total, this.limit, this.offset);
  final List<T> items;
  final int total;
  final int limit;
  final int offset;
}

HistoryPage<T> parseHistoryPage<T>(
  Object? value,
  int requestedLimit,
  int requestedOffset,
  T Function(Map<String, dynamic>) parse,
) {
  if (value is! Map<String, dynamic>) {
    throw ApiException.contract('History page must be an object.');
  }
  for (final key in ['items', 'total', 'limit', 'offset']) {
    if (!value.containsKey(key)) throw ApiException.contract('Missing $key.');
  }
  final raw = value['items'];
  final total = value['total'];
  final limit = value['limit'];
  final offset = value['offset'];
  if (raw is! List ||
      total is! int ||
      limit is! int ||
      offset is! int ||
      total < 0 ||
      limit <= 0 ||
      offset < 0 ||
      limit != requestedLimit ||
      offset != requestedOffset ||
      raw.length > limit ||
      offset + raw.length > total ||
      (offset < total && raw.isEmpty)) {
    throw ApiException.contract('Invalid history pagination.');
  }
  return HistoryPage(
    raw.map((item) {
      if (item is! Map<String, dynamic>) {
        throw ApiException.contract('History item must be an object.');
      }
      return parse(item);
    }).toList(growable: false),
    total,
    limit,
    offset,
  );
}

enum WeightRange { sevenDays, thirtyDays, threeMonths }

extension WeightRangeLabel on WeightRange {
  String get label => switch (this) {
        WeightRange.sevenDays => '7日',
        WeightRange.thirtyDays => '30日',
        WeightRange.threeMonths => '3か月',
      };
}

DateTime weightRangeStart(DateTime today, WeightRange range) {
  final day = DateTime(today.year, today.month, today.day);
  if (range == WeightRange.sevenDays) {
    return day.subtract(const Duration(days: 6));
  }
  if (range == WeightRange.thirtyDays) {
    return day.subtract(const Duration(days: 29));
  }
  final targetMonth = DateTime(day.year, day.month - 3, 1);
  final lastDay = DateTime(targetMonth.year, targetMonth.month + 1, 0).day;
  final clamped = DateTime(targetMonth.year, targetMonth.month,
      day.day > lastDay ? lastDay : day.day);
  return clamped.add(const Duration(days: 1));
}

List<T> oldestFirst<T>(List<T> newestFirst) =>
    newestFirst.reversed.toList(growable: false);
