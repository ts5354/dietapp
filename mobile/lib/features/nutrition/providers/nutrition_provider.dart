import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/dio_provider.dart';
import '../data/nutrition_repository.dart';
import '../domain/nutrition.dart';

final nutritionRepositoryProvider = Provider<NutritionRepository>(
    (ref) => NutritionRepository(ref.watch(dioProvider)));

enum NutritionViewMode { loading, ready, error }

class NutritionState {
  const NutritionState({
    required this.date,
    this.viewMode = NutritionViewMode.loading,
    this.day,
    this.busy = false,
    this.message,
  });
  final DateTime date;
  final NutritionViewMode viewMode;
  final NutritionDay? day;
  final bool busy;
  final String? message;

  NutritionState copy({
    DateTime? date,
    NutritionViewMode? viewMode,
    NutritionDay? day,
    bool clearDay = false,
    bool? busy,
    String? message,
  }) =>
      NutritionState(
        date: date ?? this.date,
        viewMode: viewMode ?? this.viewMode,
        day: clearDay ? null : day ?? this.day,
        busy: busy ?? this.busy,
        message: message,
      );
}

final nutritionControllerProvider =
    StateNotifierProvider.autoDispose<NutritionController, NutritionState>(
        (ref) => NutritionController(
            ref.watch(nutritionRepositoryProvider), DateTime.now()));

class NutritionController extends StateNotifier<NutritionState> {
  NutritionController(this._repository, DateTime now)
      : super(NutritionState(date: DateTime(now.year, now.month, now.day)));
  final NutritionRepository _repository;
  int _generation = 0;

  Future<void> load(DateTime date) async {
    final selectedDate = DateTime(date.year, date.month, date.day);
    final token = ++_generation;
    state = NutritionState(date: selectedDate);
    try {
      final day = await _repository.getDay(selectedDate);
      if (_isCurrent(token, selectedDate)) {
        state = state.copy(viewMode: NutritionViewMode.ready, day: day);
      }
    } on ApiException catch (error) {
      if (_isCurrent(token, selectedDate)) {
        state = state.copy(
            viewMode: NutritionViewMode.error,
            clearDay: true,
            message: nutritionErrorMessage(error));
      }
    }
  }

  Future<bool> createFood(FoodWriteRequest request) async {
    if (state.busy ||
        state.day?.mode == NutritionMode.freeDay ||
        !_sameDate(request.eatenAt, state.date)) {
      return false;
    }
    return _foodMutation((date) => _repository.createFood(date, request));
  }

  Future<bool> updateFood(int id, FoodWriteRequest request) async {
    if (state.busy ||
        state.day?.mode != NutritionMode.normal ||
        !_sameDate(request.eatenAt, state.date)) {
      return false;
    }
    return _foodMutation((date) => _repository.updateFood(date, id, request));
  }

  Future<bool> deleteFood(int id) async {
    if (state.busy || state.day?.mode != NutritionMode.normal) return false;
    return _foodMutation((date) => _repository.deleteFood(date, id));
  }

  Future<bool> _foodMutation(
      Future<Object?> Function(DateTime date) mutation) async {
    final token = _generation;
    final operationDate = state.date;
    state = state.copy(busy: true);
    try {
      await mutation(operationDate);
      if (!_isCurrent(token, operationDate)) return false;
      return await _reconcile(token, operationDate);
    } on ApiException catch (error) {
      if (!_isCurrent(token, operationDate)) return false;
      state = state.copy(busy: false, message: nutritionErrorMessage(error));
      return false;
    }
  }

  Future<bool> setMode(NutritionMode mode) async {
    if (state.busy || mode == NutritionMode.unrecorded) return false;
    final day = state.day;
    if (mode == NutritionMode.freeDay &&
        day?.mode == NutritionMode.normal &&
        day!.foods.isNotEmpty) {
      state = state.copy(
          message: 'この日には食事記録があります。Free Dayに変更するには、先に食事記録を削除してください。');
      return false;
    }
    final token = _generation;
    final operationDate = state.date;
    state = state.copy(busy: true);
    try {
      await _repository.setDayMode(
          operationDate, NutritionDayUpdateRequest(mode, day?.memo));
      if (!_isCurrent(token, operationDate)) return false;
      return await _reconcile(token, operationDate);
    } on ApiException catch (error) {
      if (!_isCurrent(token, operationDate)) return false;
      state = state.copy(busy: false, message: nutritionErrorMessage(error));
      return false;
    }
  }

  Future<bool> _reconcile(int token, DateTime date) async {
    try {
      final day = await _repository.getDay(date);
      if (!_isCurrent(token, date)) return false;
      state =
          state.copy(viewMode: NutritionViewMode.ready, day: day, busy: false);
      return true;
    } on ApiException catch (error) {
      if (!_isCurrent(token, date)) return false;
      state = state.copy(
          viewMode: NutritionViewMode.error,
          clearDay: true,
          busy: false,
          message: nutritionErrorMessage(error));
      return false;
    }
  }

  bool _isCurrent(int token, DateTime date) =>
      token == _generation && state.date == date;
}

bool _sameDate(DateTime timestamp, DateTime date) =>
    timestamp.year == date.year &&
    timestamp.month == date.month &&
    timestamp.day == date.day;

String nutritionErrorMessage(ApiException error) {
  return switch (error.code) {
    'FOOD_NOT_ALLOWED_ON_FREE_DAY' => 'Free Dayには食事記録を追加できません。',
    'FOOD_DATE_MISMATCH' => '食事の日時と記録日が一致していません。',
    'FOOD_NOT_FOUND' => 'この食事記録は見つかりませんでした。再読み込みしてください。',
    'FREE_DAY_HAS_FOOD_LOGS' =>
      'この日には食事記録があります。Free Dayに変更するには、先に食事記録を削除してください。',
    _ => switch (error.kind) {
        ApiErrorKind.network => 'サーバーに接続できませんでした。',
        ApiErrorKind.timeout => '通信がタイムアウトしました。',
        _ => '食事記録の処理中にエラーが発生しました。',
      }
  };
}
