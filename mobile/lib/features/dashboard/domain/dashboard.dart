import '../../../core/network/api_error.dart';

enum DashboardSectionStatus { recorded, unrecorded }

enum DashboardNutritionMode { normal, freeDay }

enum DashboardBowelCondition { normal, constipation, diarrhea, other }

class Dashboard {
  const Dashboard(this.date, this.timezone, this.weight, this.nutrition,
      this.symptom, this.injection);
  factory Dashboard.fromJson(Map<String, dynamic> json) => Dashboard(
        _date(json['date'], 'date'),
        _nonEmptyString(json['timezone'], 'timezone'),
        DashboardWeightSection.fromJson(_map(json['weight'], 'weight')),
        DashboardNutritionSection.fromJson(
            _map(json['nutrition'], 'nutrition')),
        DashboardSymptomSection.fromJson(_map(json['symptom'], 'symptom')),
        DashboardInjectionSection.fromJson(
            _map(json['injection'], 'injection')),
      );
  final DateTime date;
  final String timezone;
  final DashboardWeightSection weight;
  final DashboardNutritionSection nutrition;
  final DashboardSymptomSection symptom;
  final DashboardInjectionSection injection;
}

class DashboardWeightSection {
  const DashboardWeightSection(this.status, this.record);
  factory DashboardWeightSection.fromJson(Map<String, dynamic> json) {
    final status = _status(json['status']);
    final record = _record(json, status, 'weight');
    return DashboardWeightSection(
      status,
      record == null ? null : DashboardWeightRecord.fromJson(record),
    );
  }
  final DashboardSectionStatus status;
  final DashboardWeightRecord? record;
}

class DashboardWeightRecord {
  const DashboardWeightRecord(this.recordDate, this.weightKg);
  factory DashboardWeightRecord.fromJson(Map<String, dynamic> json) {
    final weight = _number(json['weight_kg'], 'weight_kg');
    if (weight <= 0) throw ApiException.contract('weight_kg must be positive.');
    return DashboardWeightRecord(
      _date(json['record_date'], 'record_date'),
      weight.toDouble(),
    );
  }
  final DateTime recordDate;
  final double weightKg;
}

class DashboardNutritionSection {
  const DashboardNutritionSection(this.status, this.record);
  factory DashboardNutritionSection.fromJson(Map<String, dynamic> json) {
    final status = _status(json['status']);
    final record = _record(json, status, 'nutrition');
    return DashboardNutritionSection(
      status,
      record == null ? null : DashboardNutritionRecord.fromJson(record),
    );
  }
  final DashboardSectionStatus status;
  final DashboardNutritionRecord? record;
}

class DashboardNutritionRecord {
  const DashboardNutritionRecord(
      this.mode, this.totalCalories, this.totalProteinG);
  factory DashboardNutritionRecord.fromJson(Map<String, dynamic> json) {
    final mode = switch (_string(json['mode'], 'mode')) {
      'NORMAL' => DashboardNutritionMode.normal,
      'FREE_DAY' => DashboardNutritionMode.freeDay,
      _ => throw ApiException.contract('Unknown nutrition mode.'),
    };
    final calories = _nullableInteger(json, 'total_calories');
    final protein = _nullableNumber(json, 'total_protein_g');
    if (mode == DashboardNutritionMode.normal &&
        (calories == null || protein == null)) {
      throw ApiException.contract('NORMAL totals must be present.');
    }
    if (mode == DashboardNutritionMode.freeDay &&
        (calories != null || protein != null)) {
      throw ApiException.contract('FREE_DAY totals must be null.');
    }
    if ((calories != null && calories < 0) ||
        (protein != null && protein < 0)) {
      throw ApiException.contract('Nutrition totals must not be negative.');
    }
    return DashboardNutritionRecord(
      mode,
      calories,
      protein?.toDouble(),
    );
  }
  final DashboardNutritionMode mode;
  final int? totalCalories;
  final double? totalProteinG;
}

class DashboardSymptomSection {
  const DashboardSymptomSection(this.status, this.record);
  factory DashboardSymptomSection.fromJson(Map<String, dynamic> json) {
    final status = _status(json['status']);
    final record = _record(json, status, 'symptom');
    return DashboardSymptomSection(
      status,
      record == null ? null : DashboardSymptomRecord.fromJson(record),
    );
  }
  final DashboardSectionStatus status;
  final DashboardSymptomRecord? record;
}

class DashboardSymptomRecord {
  const DashboardSymptomRecord(this.recordedAt, this.nausea, this.abdominalPain,
      this.fatigue, this.appetite, this.bowelCondition);
  factory DashboardSymptomRecord.fromJson(Map<String, dynamic> json) =>
      DashboardSymptomRecord(
        _timestamp(json['recorded_at'], 'recorded_at'),
        _scale(json['nausea'], 'nausea'),
        _scale(json['abdominal_pain'], 'abdominal_pain'),
        _scale(json['fatigue'], 'fatigue'),
        _scale(json['appetite'], 'appetite'),
        _bowel(json['bowel_condition']),
      );
  final DateTime recordedAt;
  final int nausea;
  final int abdominalPain;
  final int fatigue;
  final int appetite;
  final DashboardBowelCondition? bowelCondition;
}

class DashboardInjectionSection {
  const DashboardInjectionSection(
      this.status, this.record, this.nextScheduledDate);
  factory DashboardInjectionSection.fromJson(Map<String, dynamic> json) {
    final status = _status(json['status']);
    final record = _record(json, status, 'injection');
    if (!json.containsKey('next_scheduled_date')) {
      throw ApiException.contract('next_scheduled_date is required.');
    }
    final next = json['next_scheduled_date'];
    if ((status == DashboardSectionStatus.recorded) != (next != null)) {
      throw ApiException.contract('Invalid injection next date.');
    }
    return DashboardInjectionSection(
      status,
      record == null ? null : DashboardInjectionRecord.fromJson(record),
      next == null ? null : _date(next, 'next_scheduled_date'),
    );
  }
  final DashboardSectionStatus status;
  final DashboardInjectionRecord? record;
  final DateTime? nextScheduledDate;
}

class DashboardInjectionRecord {
  const DashboardInjectionRecord(this.recordDate);
  factory DashboardInjectionRecord.fromJson(Map<String, dynamic> json) =>
      DashboardInjectionRecord(_date(json['record_date'], 'record_date'));
  final DateTime recordDate;
}

DashboardSectionStatus _status(Object? value) => switch (value) {
      'RECORDED' => DashboardSectionStatus.recorded,
      'UNRECORDED' => DashboardSectionStatus.unrecorded,
      _ => throw ApiException.contract('Unknown section status.'),
    };

Map<String, dynamic>? _record(
    Map<String, dynamic> json, DashboardSectionStatus status, String name) {
  if (!json.containsKey('record')) {
    throw ApiException.contract('$name record is required.');
  }
  final value = json['record'];
  final present = value != null;
  if ((status == DashboardSectionStatus.recorded) != present) {
    throw ApiException.contract('Invalid $name section state.');
  }
  return present ? _map(value, '$name record') : null;
}

Map<String, dynamic> _map(Object? value, String name) {
  if (value is! Map<String, dynamic>) {
    throw ApiException.contract('$name must be an object.');
  }
  return value;
}

String _string(Object? value, String name) {
  if (value is! String) throw ApiException.contract('$name must be a string.');
  return value;
}

String _nonEmptyString(Object? value, String name) {
  final result = _string(value, name);
  if (result.trim().isEmpty) {
    throw ApiException.contract('$name must not be empty.');
  }
  return result;
}

num _number(Object? value, String name) {
  if (value is! num || !value.isFinite) {
    throw ApiException.contract('$name must be a finite number.');
  }
  return value;
}

num? _nullableNumber(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) throw ApiException.contract('$key is required.');
  final value = json[key];
  return value == null ? null : _number(value, key);
}

int _integer(Object? value, String name) {
  if (value is! int) throw ApiException.contract('$name must be an integer.');
  return value;
}

int _scale(Object? value, String name) {
  final result = _integer(value, name);
  if (result < 1 || result > 10) {
    throw ApiException.contract('$name must be between 1 and 10.');
  }
  return result;
}

int? _nullableInteger(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) throw ApiException.contract('$key is required.');
  final value = json[key];
  return value == null ? null : _integer(value, key);
}

DashboardBowelCondition? _bowel(Object? value) => switch (value) {
      null => null,
      'NORMAL' => DashboardBowelCondition.normal,
      'CONSTIPATION' => DashboardBowelCondition.constipation,
      'DIARRHEA' => DashboardBowelCondition.diarrhea,
      'OTHER' => DashboardBowelCondition.other,
      _ => throw ApiException.contract('Unknown bowel condition.'),
    };

DateTime _date(Object? value, String name) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw ApiException.contract('$name must be an ISO date.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || formatApiDate(parsed) != value) {
    throw ApiException.contract('$name must be a valid ISO date.');
  }
  return parsed;
}

DateTime _timestamp(Object? value, String name) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null || !RegExp(r'Z$').hasMatch(value as String)) {
    throw ApiException.contract('$name must be a UTC timestamp.');
  }
  return parsed;
}

String formatApiDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
