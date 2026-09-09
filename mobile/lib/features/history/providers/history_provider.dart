import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/dio_provider.dart';
import '../../injection/domain/injection.dart';
import '../../nutrition/domain/nutrition.dart';
import '../../symptom/domain/symptom.dart';
import '../../weight/domain/weight.dart';
import '../data/history_repository.dart';
import '../domain/history.dart';

final historyRepositoryProvider = Provider<HistoryRepository>(
    (ref) => HistoryRepository(ref.watch(dioProvider)));

enum HistoryLoadMode { loading, ready, error }

class HistoryListState<T> {
  const HistoryListState({
    this.items = const [],
    this.total = 0,
    this.mode = HistoryLoadMode.loading,
    this.loadingMore = false,
    this.message,
  });
  final List<T> items;
  final int total;
  final HistoryLoadMode mode;
  final bool loadingMore;
  final String? message;
  bool get hasMore => items.length < total;
  HistoryListState<T> copy(
          {List<T>? items,
          int? total,
          HistoryLoadMode? mode,
          bool? loadingMore,
          String? message}) =>
      HistoryListState(
          items: items ?? this.items,
          total: total ?? this.total,
          mode: mode ?? this.mode,
          loadingMore: loadingMore ?? this.loadingMore,
          message: message);
}

class HistoryState {
  const HistoryState({
    this.range = WeightRange.sevenDays,
    this.weights = const HistoryListState<WeightRecord>(),
    this.nutrition = const HistoryListState<NutritionDaySummary>(),
    this.symptoms = const HistoryListState<SymptomRecord>(),
    this.injections = const HistoryListState<InjectionRecord>(),
  });
  final WeightRange range;
  final HistoryListState<WeightRecord> weights;
  final HistoryListState<NutritionDaySummary> nutrition;
  final HistoryListState<SymptomRecord> symptoms;
  final HistoryListState<InjectionRecord> injections;
  HistoryState copy(
          {WeightRange? range,
          HistoryListState<WeightRecord>? weights,
          HistoryListState<NutritionDaySummary>? nutrition,
          HistoryListState<SymptomRecord>? symptoms,
          HistoryListState<InjectionRecord>? injections}) =>
      HistoryState(
        range: range ?? this.range,
        weights: weights ?? this.weights,
        nutrition: nutrition ?? this.nutrition,
        symptoms: symptoms ?? this.symptoms,
        injections: injections ?? this.injections,
      );
}

final historyControllerProvider =
    StateNotifierProvider.autoDispose<HistoryController, HistoryState>((ref) =>
        HistoryController(
            ref.watch(historyRepositoryProvider), DateTime.now()));

class HistoryController extends StateNotifier<HistoryState> {
  HistoryController(this._repository, DateTime now)
      : today = DateTime(now.year, now.month, now.day),
        super(const HistoryState());
  static const pageSize = 50;
  final HistoryRepository _repository;
  final DateTime today;
  final _generation = <int>[0, 0, 0, 0];

  Future<void> loadWeight({WeightRange? range}) async {
    final selected = range ?? state.range;
    final token = ++_generation[0];
    state = state.copy(
        range: selected, weights: const HistoryListState<WeightRecord>());
    await _weightPage(token, selected, 0, false);
  }

  Future<void> loadMoreWeight() async {
    if (state.weights.loadingMore || !state.weights.hasMore) return;
    final token = _generation[0];
    state = state.copy(weights: state.weights.copy(loadingMore: true));
    await _weightPage(token, state.range, state.weights.items.length, true);
  }

  Future<void> _weightPage(
      int token, WeightRange range, int offset, bool append) async {
    try {
      final page = await _repository.weights(
          weightRangeStart(today, range), today, pageSize, offset);
      if (token != _generation[0] || range != state.range) return;
      state = state.copy(
          weights: HistoryListState(
              items:
                  append ? [...state.weights.items, ...page.items] : page.items,
              total: page.total,
              mode: HistoryLoadMode.ready));
    } on ApiException catch (error) {
      if (token != _generation[0] || range != state.range) return;
      state = state.copy(
          weights: append
              ? state.weights.copy(loadingMore: false, message: _message(error))
              : HistoryListState(
                  mode: HistoryLoadMode.error, message: _message(error)));
    }
  }

  Future<void> loadNutrition() => _loadNutrition(++_generation[1], 0, false);
  Future<void> loadMoreNutrition() async {
    if (state.nutrition.loadingMore || !state.nutrition.hasMore) return;
    state = state.copy(nutrition: state.nutrition.copy(loadingMore: true));
    await _loadNutrition(_generation[1], state.nutrition.items.length, true);
  }

  Future<void> _loadNutrition(int token, int offset, bool append) async {
    if (!append) {
      state =
          state.copy(nutrition: const HistoryListState<NutritionDaySummary>());
    }
    try {
      final page = await _repository.nutrition(pageSize, offset);
      if (token != _generation[1]) return;
      state = state.copy(
          nutrition: HistoryListState(
              items: append
                  ? [...state.nutrition.items, ...page.items]
                  : page.items,
              total: page.total,
              mode: HistoryLoadMode.ready));
    } on ApiException catch (e) {
      if (token == _generation[1]) {
        state = state.copy(
            nutrition: append
                ? state.nutrition.copy(loadingMore: false, message: _message(e))
                : HistoryListState(
                    mode: HistoryLoadMode.error, message: _message(e)));
      }
    }
  }

  Future<void> loadSymptoms() => _loadSymptoms(++_generation[2], 0, false);
  Future<void> loadMoreSymptoms() async {
    if (state.symptoms.loadingMore || !state.symptoms.hasMore) return;
    state = state.copy(symptoms: state.symptoms.copy(loadingMore: true));
    await _loadSymptoms(_generation[2], state.symptoms.items.length, true);
  }

  Future<void> _loadSymptoms(int token, int offset, bool append) async {
    if (!append) {
      state = state.copy(symptoms: const HistoryListState<SymptomRecord>());
    }
    try {
      final page = await _repository.symptoms(pageSize, offset);
      if (token != _generation[2]) return;
      state = state.copy(
          symptoms: HistoryListState(
              items: append
                  ? [...state.symptoms.items, ...page.items]
                  : page.items,
              total: page.total,
              mode: HistoryLoadMode.ready));
    } catch (e) {
      if (token == _generation[2]) {
        final message = e is ApiException ? _message(e) : '履歴を取得できませんでした。';
        state = state.copy(
            symptoms: append
                ? state.symptoms.copy(loadingMore: false, message: message)
                : HistoryListState(
                    mode: HistoryLoadMode.error, message: message));
      }
    }
  }

  Future<void> loadInjections() => _loadInjections(++_generation[3], 0, false);
  Future<void> loadMoreInjections() async {
    if (state.injections.loadingMore || !state.injections.hasMore) return;
    state = state.copy(injections: state.injections.copy(loadingMore: true));
    await _loadInjections(_generation[3], state.injections.items.length, true);
  }

  Future<void> _loadInjections(int token, int offset, bool append) async {
    if (!append) {
      state = state.copy(injections: const HistoryListState<InjectionRecord>());
    }
    try {
      final page = await _repository.injections(pageSize, offset);
      if (token != _generation[3]) return;
      state = state.copy(
          injections: HistoryListState(
              items: append
                  ? [...state.injections.items, ...page.items]
                  : page.items,
              total: page.total,
              mode: HistoryLoadMode.ready));
    } on ApiException catch (e) {
      if (token == _generation[3]) {
        state = state.copy(
            injections: append
                ? state.injections
                    .copy(loadingMore: false, message: _message(e))
                : HistoryListState(
                    mode: HistoryLoadMode.error, message: _message(e)));
      }
    }
  }
}

String _message(ApiException error) => switch (error.kind) {
      ApiErrorKind.network => 'サーバーに接続できませんでした。',
      ApiErrorKind.timeout => '通信がタイムアウトしました。',
      _ => '履歴を取得できませんでした。',
    };
