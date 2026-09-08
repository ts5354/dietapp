import '../../../core/network/api_error.dart';
import '../../dashboard/domain/dashboard.dart';
import '../../weight/domain/weight.dart';

enum InjectionSite {
  abdomenUpperRight,
  abdomenLowerRight,
  abdomenUpperLeft,
  abdomenLowerLeft,
  thighRight,
  thighLeft,
}

extension InjectionSiteValue on InjectionSite {
  String get apiValue => switch (this) {
        InjectionSite.abdomenUpperRight => 'ABDOMEN_UPPER_RIGHT',
        InjectionSite.abdomenLowerRight => 'ABDOMEN_LOWER_RIGHT',
        InjectionSite.abdomenUpperLeft => 'ABDOMEN_UPPER_LEFT',
        InjectionSite.abdomenLowerLeft => 'ABDOMEN_LOWER_LEFT',
        InjectionSite.thighRight => 'THIGH_RIGHT',
        InjectionSite.thighLeft => 'THIGH_LEFT',
      };
  String get label => switch (this) {
        InjectionSite.abdomenUpperRight => '腹部 右上',
        InjectionSite.abdomenLowerRight => '腹部 右下',
        InjectionSite.abdomenUpperLeft => '腹部 左上',
        InjectionSite.abdomenLowerLeft => '腹部 左下',
        InjectionSite.thighRight => '右太もも',
        InjectionSite.thighLeft => '左太もも',
      };
}

class InjectionRecord {
  const InjectionRecord({
    required this.id,
    required this.recordDate,
    required this.injectedAt,
    required this.doseMg,
    required this.injectionSite,
    required this.memo,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InjectionRecord.fromJson(Map<String, dynamic> json) {
    for (final field in [
      'id',
      'record_date',
      'injected_at',
      'dose_mg',
      'injection_site',
      'memo',
      'created_at',
      'updated_at'
    ]) {
      if (!json.containsKey(field)) {
        throw ApiException.contract('Missing $field.');
      }
    }
    return InjectionRecord(
      id: _integer(json['id'], 'id'),
      recordDate: _date(json['record_date']),
      injectedAt: _timestamp(json['injected_at'], 'injected_at'),
      doseMg: _dose(json['dose_mg']),
      injectionSite: _site(json['injection_site']),
      memo: _nullableString(json['memo'], 'memo'),
      createdAt: _timestamp(json['created_at'], 'created_at'),
      updatedAt: _timestamp(json['updated_at'], 'updated_at'),
    );
  }

  final int id;
  final DateTime recordDate;
  final DateTime injectedAt;
  final double doseMg;
  final InjectionSite injectionSite;
  final String? memo;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class InjectionCreateRequest {
  const InjectionCreateRequest(this.recordDate, this.injectedAt, this.doseMg,
      this.injectionSite, this.memo);
  final DateTime recordDate;
  final DateTime injectedAt;
  final double doseMg;
  final InjectionSite injectionSite;
  final String? memo;
  Map<String, dynamic> toJson() => {
        'record_date': formatApiDate(recordDate),
        'injected_at': formatOffsetTimestamp(injectedAt),
        'dose_mg': doseMg,
        'injection_site': injectionSite.apiValue,
        'memo': memo,
      };
}

class InjectionUpdateRequest {
  const InjectionUpdateRequest(
      this.injectedAt, this.doseMg, this.injectionSite, this.memo);
  final DateTime injectedAt;
  final double doseMg;
  final InjectionSite injectionSite;
  final String? memo;
  Map<String, dynamic> toJson() => {
        'injected_at': formatOffsetTimestamp(injectedAt),
        'dose_mg': doseMg,
        'injection_site': injectionSite.apiValue,
        'memo': memo,
      };
}

double validateDose(String input) {
  final value = input.trim();
  if (value.isEmpty) throw const InjectionValidationException('doseを入力してください。');
  if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) {
    throw const InjectionValidationException('doseは小数第2位までの数値で入力してください。');
  }
  final parsed = double.tryParse(value);
  if (parsed == null || !parsed.isFinite || parsed <= 0 || parsed > 999.99) {
    throw const InjectionValidationException('doseは0より大きく999.99以下で入力してください。');
  }
  return parsed;
}

void validateInjectionMemo(String memo) {
  if (memo.length > 500) {
    throw const InjectionValidationException('メモは500文字以内で入力してください。');
  }
}

class InjectionValidationException implements Exception {
  const InjectionValidationException(this.message);
  final String message;
}

String formatDose(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

Map<String, dynamic> requireInjectionMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw ApiException.contract('Injection response must be an object.');
  }
  return value;
}

int _integer(Object? value, String name) {
  if (value is! int) throw ApiException.contract('$name must be an integer.');
  return value;
}

double _dose(Object? value) {
  if (value is! num) throw ApiException.contract('dose_mg must be a number.');
  final dose = value.toDouble();
  if (!dose.isFinite ||
      dose <= 0 ||
      dose > 999.99 ||
      ((dose * 100) - (dose * 100).round()).abs() > 1e-9) {
    throw ApiException.contract('dose_mg is invalid.');
  }
  return dose;
}

InjectionSite _site(Object? value) => switch (value) {
      'ABDOMEN_UPPER_RIGHT' => InjectionSite.abdomenUpperRight,
      'ABDOMEN_LOWER_RIGHT' => InjectionSite.abdomenLowerRight,
      'ABDOMEN_UPPER_LEFT' => InjectionSite.abdomenUpperLeft,
      'ABDOMEN_LOWER_LEFT' => InjectionSite.abdomenLowerLeft,
      'THIGH_RIGHT' => InjectionSite.thighRight,
      'THIGH_LEFT' => InjectionSite.thighLeft,
      _ => throw ApiException.contract('Unknown injection_site.'),
    };

String? _nullableString(Object? value, String name) {
  if (value == null) return null;
  if (value is! String) throw ApiException.contract('$name must be a string.');
  return value;
}

DateTime _date(Object? value) {
  if (value is! String) {
    throw ApiException.contract('record_date must be a string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
      formatApiDate(parsed) != value) {
    throw ApiException.contract('Invalid record_date.');
  }
  return parsed;
}

DateTime _timestamp(Object? value, String name) {
  final aware =
      value is String && RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value);
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (!aware || parsed == null) {
    throw ApiException.contract('$name must be a timezone-aware timestamp.');
  }
  return parsed;
}
