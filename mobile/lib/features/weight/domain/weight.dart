import '../../../core/network/api_error.dart';
import '../../dashboard/domain/dashboard.dart';

class WeightRecord {
  const WeightRecord(
      {required this.id,
      required this.recordDate,
      required this.weightKg,
      required this.recordedAt,
      required this.memo,
      required this.createdAt,
      required this.updatedAt});
  factory WeightRecord.fromJson(Map<String, dynamic> json) => WeightRecord(
      id: _int(json['id'], 'id'),
      recordDate: _date(json['record_date']),
      weightKg: _num(json['weight_kg']).toDouble(),
      recordedAt: _timestamp(json['recorded_at']),
      memo: json['memo'] == null ? null : _string(json['memo'], 'memo'),
      createdAt: _timestamp(json['created_at']),
      updatedAt: _timestamp(json['updated_at']));
  final int id;
  final DateTime recordDate;
  final double weightKg;
  final DateTime recordedAt;
  final String? memo;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class CreateWeightRequest {
  const CreateWeightRequest(
      this.recordDate, this.weightKg, this.recordedAt, this.memo);
  final DateTime recordDate;
  final double weightKg;
  final DateTime recordedAt;
  final String? memo;
  Map<String, dynamic> toJson() => {
        'record_date': formatApiDate(recordDate),
        'weight_kg': weightKg,
        'recorded_at': formatOffsetTimestamp(recordedAt),
        'memo': memo
      };
}

class UpdateWeightRequest {
  const UpdateWeightRequest(this.weightKg, this.recordedAt, this.memo);
  final double weightKg;
  final DateTime recordedAt;
  final String? memo;
  Map<String, dynamic> toJson() => {
        'weight_kg': weightKg,
        'recorded_at': formatOffsetTimestamp(recordedAt),
        'memo': memo
      };
}

String formatOffsetTimestamp(DateTime value) {
  if (value.isUtc) return value.toIso8601String();
  final base = value.toIso8601String();
  final offset = value.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absolute = offset.abs();
  return '$base$sign${absolute.inHours.toString().padLeft(2, '0')}:${(absolute.inMinutes % 60).toString().padLeft(2, '0')}';
}

double validateWeightInput(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) throw const WeightValidationException('体重を入力してください');
  if (!RegExp(r'^\d+(?:\.\d)?$').hasMatch(trimmed)) {
    throw const WeightValidationException('体重は小数第1位まで入力してください');
  }
  final value = double.tryParse(trimmed);
  if (value == null || !value.isFinite) {
    throw const WeightValidationException('正しい体重を入力してください');
  }
  if (value <= 0) throw const WeightValidationException('体重は0より大きい値を入力してください');
  if (value >= 1000) throw const WeightValidationException('正しい体重を入力してください');
  return value;
}

void validateMemo(String value) {
  if (value.length > 500) {
    throw const WeightValidationException('メモは500文字以内で入力してください');
  }
}

class WeightValidationException implements Exception {
  const WeightValidationException(this.message);
  final String message;
}

Map<String, dynamic> requireMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw ApiException.contract('Weight response must be an object.');
  }
  return value;
}

int _int(Object? v, String n) {
  if (v is! int) throw ApiException.contract('$n must be an integer.');
  return v;
}

num _num(Object? v) {
  if (v is! num) throw ApiException.contract('weight_kg must be a number.');
  return v;
}

String _string(Object? v, String n) {
  if (v is! String) throw ApiException.contract('$n must be a string.');
  return v;
}

DateTime _date(Object? v) {
  final s = _string(v, 'record_date');
  final d = DateTime.tryParse(s);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) ||
      d == null ||
      formatApiDate(d) != s) {
    throw ApiException.contract('Invalid record_date.');
  }
  return d;
}

DateTime _timestamp(Object? v) {
  final d = v is String ? DateTime.tryParse(v) : null;
  if (d == null || !d.isUtc) throw ApiException.contract('Invalid timestamp.');
  return d;
}
