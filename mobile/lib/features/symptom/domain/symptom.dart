import '../../../core/network/api_error.dart';
import '../../weight/domain/weight.dart';

enum BowelCondition { normal, constipation, diarrhea, other }

class SymptomRecord {
  const SymptomRecord({
    required this.id,
    required this.recordedAt,
    required this.nausea,
    required this.abdominalPain,
    required this.fatigue,
    required this.appetite,
    required this.bowelCondition,
    required this.memo,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SymptomRecord.fromJson(Map<String, dynamic> json) {
    for (final field in [
      'id',
      'recorded_at',
      'nausea',
      'abdominal_pain',
      'fatigue',
      'appetite',
      'bowel_condition',
      'memo',
      'created_at',
      'updated_at'
    ]) {
      if (!json.containsKey(field)) {
        throw ApiException.contract('Missing $field.');
      }
    }
    return SymptomRecord(
      id: _integer(json['id'], 'id'),
      recordedAt: _timestamp(json['recorded_at'], 'recorded_at'),
      nausea: _scale(json['nausea'], 'nausea'),
      abdominalPain: _scale(json['abdominal_pain'], 'abdominal_pain'),
      fatigue: _scale(json['fatigue'], 'fatigue'),
      appetite: _scale(json['appetite'], 'appetite'),
      bowelCondition: _bowel(json['bowel_condition']),
      memo: _nullableString(json['memo'], 'memo'),
      createdAt: _timestamp(json['created_at'], 'created_at'),
      updatedAt: _timestamp(json['updated_at'], 'updated_at'),
    );
  }

  final int id;
  final DateTime recordedAt;
  final int nausea;
  final int abdominalPain;
  final int fatigue;
  final int appetite;
  final BowelCondition? bowelCondition;
  final String? memo;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class SymptomPage {
  const SymptomPage(
      {required this.items,
      required this.total,
      required this.limit,
      required this.offset});

  factory SymptomPage.fromJson(Map<String, dynamic> json) {
    for (final field in ['items', 'total', 'limit', 'offset']) {
      if (!json.containsKey(field)) {
        throw ApiException.contract('Missing $field.');
      }
    }
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw ApiException.contract('items must be an array.');
    }
    final total = _integer(json['total'], 'total');
    final limit = _integer(json['limit'], 'limit');
    final offset = _integer(json['offset'], 'offset');
    if (total < 0) {
      throw ApiException.contract('total must be greater than or equal to 0.');
    }
    if (limit <= 0) {
      throw ApiException.contract('limit must be greater than 0.');
    }
    if (offset < 0) {
      throw ApiException.contract('offset must be greater than or equal to 0.');
    }
    return SymptomPage(
      items: rawItems
          .map((item) => SymptomRecord.fromJson(requireSymptomMap(item)))
          .toList(growable: false),
      total: total,
      limit: limit,
      offset: offset,
    );
  }

  final List<SymptomRecord> items;
  final int total;
  final int limit;
  final int offset;
}

class SymptomWriteRequest {
  const SymptomWriteRequest({
    required this.recordedAt,
    required this.nausea,
    required this.abdominalPain,
    required this.fatigue,
    required this.appetite,
    required this.bowelCondition,
    required this.memo,
  });

  final DateTime recordedAt;
  final int nausea;
  final int abdominalPain;
  final int fatigue;
  final int appetite;
  final BowelCondition? bowelCondition;
  final String? memo;

  Map<String, dynamic> toJson() => {
        'recorded_at': formatOffsetTimestamp(recordedAt),
        'nausea': nausea,
        'abdominal_pain': abdominalPain,
        'fatigue': fatigue,
        'appetite': appetite,
        'bowel_condition': bowelCondition?.apiValue,
        'memo': memo == null || memo!.trim().isEmpty ? null : memo,
      };
}

class SymptomFormValues {
  const SymptomFormValues({
    required this.recordedAt,
    required this.nausea,
    required this.abdominalPain,
    required this.fatigue,
    required this.appetite,
    required this.bowelCondition,
    required this.memo,
  });
  final DateTime recordedAt;
  final int nausea;
  final int abdominalPain;
  final int fatigue;
  final int appetite;
  final BowelCondition? bowelCondition;
  final String memo;

  SymptomWriteRequest requestFor(DateTime date) {
    for (final entry in {
      '吐き気': nausea,
      '腹痛': abdominalPain,
      'だるさ': fatigue,
      '食欲': appetite,
    }.entries) {
      if (entry.value < 1 || entry.value > 10) {
        throw SymptomValidationException('${entry.key}は1〜10で入力してください。');
      }
    }
    if (memo.length > 500) {
      throw const SymptomValidationException('メモは500文字以内で入力してください。');
    }
    return SymptomWriteRequest(
      recordedAt: DateTime(date.year, date.month, date.day, recordedAt.hour,
          recordedAt.minute, recordedAt.second),
      nausea: nausea,
      abdominalPain: abdominalPain,
      fatigue: fatigue,
      appetite: appetite,
      bowelCondition: bowelCondition,
      memo: memo.trim().isEmpty ? null : memo,
    );
  }
}

class SymptomValidationException implements Exception {
  const SymptomValidationException(this.message);
  final String message;
}

extension BowelConditionValue on BowelCondition {
  String get apiValue => switch (this) {
        BowelCondition.normal => 'NORMAL',
        BowelCondition.constipation => 'CONSTIPATION',
        BowelCondition.diarrhea => 'DIARRHEA',
        BowelCondition.other => 'OTHER',
      };

  String get label => switch (this) {
        BowelCondition.normal => '通常',
        BowelCondition.constipation => '便秘',
        BowelCondition.diarrhea => '下痢',
        BowelCondition.other => 'その他',
      };
}

Map<String, dynamic> requireSymptomMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw ApiException.contract('Symptom response must be an object.');
  }
  return value;
}

int _integer(Object? value, String name) {
  if (value is! int) throw ApiException.contract('$name must be an integer.');
  return value;
}

int _scale(Object? value, String name) {
  final scale = _integer(value, name);
  if (scale < 1 || scale > 10) {
    throw ApiException.contract('$name must be between 1 and 10.');
  }
  return scale;
}

BowelCondition? _bowel(Object? value) => switch (value) {
      null => null,
      'NORMAL' => BowelCondition.normal,
      'CONSTIPATION' => BowelCondition.constipation,
      'DIARRHEA' => BowelCondition.diarrhea,
      'OTHER' => BowelCondition.other,
      _ => throw ApiException.contract('Unknown bowel_condition.'),
    };

String? _nullableString(Object? value, String name) {
  if (value == null) return null;
  if (value is! String) throw ApiException.contract('$name must be a string.');
  return value;
}

DateTime _timestamp(Object? value, String name) {
  final hasTimezone =
      value is String && RegExp(r'(?:Z|[+-]\d{2}:\d{2})$').hasMatch(value);
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (!hasTimezone || parsed == null) {
    throw ApiException.contract('$name must be a timezone-aware timestamp.');
  }
  return parsed;
}
