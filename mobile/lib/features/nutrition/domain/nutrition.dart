import '../../../core/network/api_error.dart';
import '../../dashboard/domain/dashboard.dart';
import '../../weight/domain/weight.dart';

enum NutritionMode { normal, freeDay, unrecorded }

class NutritionDaySummary {
  const NutritionDaySummary({
    required this.date,
    required this.mode,
    required this.memo,
    required this.totalCalories,
    required this.totalProteinG,
  });

  factory NutritionDaySummary.fromJson(Map<String, dynamic> json) {
    for (final field in [
      'date',
      'mode',
      'memo',
      'total_calories',
      'total_protein_g'
    ]) {
      if (!json.containsKey(field)) {
        throw ApiException.contract('Missing $field.');
      }
    }
    final mode = switch (json['mode']) {
      'NORMAL' => NutritionMode.normal,
      'FREE_DAY' => NutritionMode.freeDay,
      _ => throw ApiException.contract('Unknown nutrition mode.'),
    };
    final calories = json['total_calories'];
    final protein = json['total_protein_g'];
    if (mode == NutritionMode.normal) {
      if (calories is! int ||
          calories < 0 ||
          protein is! num ||
          !protein.isFinite ||
          protein < 0) {
        throw ApiException.contract('NORMAL totals are invalid.');
      }
    } else if (calories != null || protein != null) {
      throw ApiException.contract('FREE_DAY totals must be null.');
    }
    return NutritionDaySummary(
      date: _date(json['date']),
      mode: mode,
      memo: _requiredNullableString(json, 'memo'),
      totalCalories: calories as int?,
      totalProteinG: (protein as num?)?.toDouble(),
    );
  }

  final DateTime date;
  final NutritionMode mode;
  final String? memo;
  final int? totalCalories;
  final double? totalProteinG;
}

class FoodLog {
  const FoodLog({
    required this.id,
    required this.name,
    required this.calories,
    required this.proteinG,
    required this.eatenAt,
    required this.memo,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FoodLog.fromJson(Map<String, dynamic> json) => FoodLog(
        id: _integer(json['id'], 'id'),
        name: _string(json['name'], 'name'),
        calories: _integer(json['calories'], 'calories'),
        proteinG: _number(json['protein_g'], 'protein_g').toDouble(),
        eatenAt: _timestamp(json['eaten_at'], 'eaten_at'),
        memo: _requiredNullableString(json, 'memo'),
        createdAt: _timestamp(json['created_at'], 'created_at'),
        updatedAt: _timestamp(json['updated_at'], 'updated_at'),
      );

  final int id;
  final String name;
  final int calories;
  final double proteinG;
  final DateTime eatenAt;
  final String? memo;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class NutritionDay {
  const NutritionDay({
    required this.date,
    required this.mode,
    required this.memo,
    required this.totalCalories,
    required this.totalProteinG,
    required this.foods,
  });

  factory NutritionDay.fromJson(Map<String, dynamic> json) {
    for (final field in [
      'date',
      'mode',
      'memo',
      'total_calories',
      'total_protein_g',
      'foods'
    ]) {
      if (!json.containsKey(field)) {
        throw ApiException.contract('Missing $field.');
      }
    }
    final date = _date(json['date']);
    final mode = switch (json['mode']) {
      'NORMAL' => NutritionMode.normal,
      'FREE_DAY' => NutritionMode.freeDay,
      'UNRECORDED' => NutritionMode.unrecorded,
      _ => throw ApiException.contract('Unknown nutrition mode.'),
    };
    final rawFoods = json['foods'];
    if (rawFoods is! List) {
      throw ApiException.contract('foods must be an array.');
    }
    final foods = rawFoods
        .map((value) => FoodLog.fromJson(_map(value, 'food')))
        .toList(growable: false);
    final calories = json['total_calories'];
    final protein = json['total_protein_g'];
    if (mode == NutritionMode.normal) {
      if (calories is! int || protein is! num) {
        throw ApiException.contract('NORMAL totals must be numbers.');
      }
      return NutritionDay(
        date: date,
        mode: mode,
        memo: _requiredNullableString(json, 'memo'),
        totalCalories: calories,
        totalProteinG: protein.toDouble(),
        foods: foods,
      );
    }
    if (calories != null || protein != null || foods.isNotEmpty) {
      throw ApiException.contract(
          'FREE_DAY and UNRECORDED must have null totals and no foods.');
    }
    return NutritionDay(
      date: date,
      mode: mode,
      memo: _requiredNullableString(json, 'memo'),
      totalCalories: null,
      totalProteinG: null,
      foods: foods,
    );
  }

  final DateTime date;
  final NutritionMode mode;
  final String? memo;
  final int? totalCalories;
  final double? totalProteinG;
  final List<FoodLog> foods;
}

class FoodWriteRequest {
  const FoodWriteRequest({
    required this.name,
    required this.calories,
    required this.proteinG,
    required this.eatenAt,
    required this.memo,
  });

  final String name;
  final int calories;
  final double proteinG;
  final DateTime eatenAt;
  final String? memo;

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'calories': calories,
        'protein_g': proteinG,
        'eaten_at': formatOffsetTimestamp(eatenAt),
        'memo': memo == null || memo!.trim().isEmpty ? null : memo,
      };
}

class NutritionDayUpdateRequest {
  const NutritionDayUpdateRequest(this.mode, this.memo)
      : assert(mode != NutritionMode.unrecorded);
  final NutritionMode mode;
  final String? memo;
  Map<String, dynamic> toJson() => {
        'mode': mode == NutritionMode.normal ? 'NORMAL' : 'FREE_DAY',
        'memo': memo,
      };
}

class FoodFormValues {
  const FoodFormValues({
    required this.name,
    required this.calories,
    required this.protein,
    required this.time,
    required this.memo,
  });
  final String name;
  final String calories;
  final String protein;
  final DateTime time;
  final String memo;

  FoodWriteRequest requestFor(DateTime date) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      throw const FoodValidationException('名前を入力してください。');
    }
    if (cleanName.length > 100) {
      throw const FoodValidationException('名前は100文字以内で入力してください。');
    }
    final cleanCalories = calories.trim();
    if (cleanCalories.isEmpty) {
      throw const FoodValidationException('カロリーを入力してください。');
    }
    if (!RegExp(r'^\d+$').hasMatch(cleanCalories)) {
      throw const FoodValidationException('カロリーは0以上の整数で入力してください。');
    }
    final calorieValue = int.tryParse(cleanCalories);
    if (calorieValue == null) {
      throw const FoodValidationException('正しいカロリーを入力してください。');
    }
    final cleanProtein = protein.trim();
    if (cleanProtein.isEmpty) {
      throw const FoodValidationException('たんぱく質を入力してください。');
    }
    if (!RegExp(r'^\d{1,4}(?:\.\d{1,2})?$').hasMatch(cleanProtein)) {
      throw const FoodValidationException('たんぱく質は9999.99以下、小数第2位までで入力してください。');
    }
    final proteinValue = double.tryParse(cleanProtein);
    if (proteinValue == null || !proteinValue.isFinite) {
      throw const FoodValidationException('正しいたんぱく質を入力してください。');
    }
    if (memo.length > 500) {
      throw const FoodValidationException('メモは500文字以内で入力してください。');
    }
    return FoodWriteRequest(
      name: cleanName,
      calories: calorieValue,
      proteinG: proteinValue,
      eatenAt: DateTime(
          date.year, date.month, date.day, time.hour, time.minute, time.second),
      memo: memo.trim().isEmpty ? null : memo,
    );
  }
}

class FoodValidationException implements Exception {
  const FoodValidationException(this.message);
  final String message;
}

String formatNutritionNumber(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
}

Map<String, dynamic> requireNutritionMap(Object? value) =>
    _map(value, 'nutrition response');

Map<String, dynamic> _map(Object? value, String name) {
  if (value is! Map<String, dynamic>) {
    throw ApiException.contract('$name must be an object.');
  }
  return value;
}

int _integer(Object? value, String name) {
  if (value is! int) throw ApiException.contract('$name must be an integer.');
  return value;
}

num _number(Object? value, String name) {
  if (value is! num) throw ApiException.contract('$name must be a number.');
  return value;
}

String _string(Object? value, String name) {
  if (value is! String) throw ApiException.contract('$name must be a string.');
  return value;
}

String? _nullableString(Object? value, String name) {
  if (value == null) return null;
  return _string(value, name);
}

String? _requiredNullableString(Map<String, dynamic> json, String name) {
  if (!json.containsKey(name)) {
    throw ApiException.contract('Missing $name.');
  }
  return _nullableString(json[name], name);
}

DateTime _date(Object? value) {
  final text = _string(value, 'date');
  final parsed = DateTime.tryParse(text);
  if (parsed == null ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
      formatApiDate(parsed) != text) {
    throw ApiException.contract('Invalid nutrition date.');
  }
  return parsed;
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
