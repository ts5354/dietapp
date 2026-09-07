import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_error.dart';
import '../../../core/network/dio_provider.dart';
import '../data/weight_repository.dart';
import '../domain/weight.dart';

final weightRepositoryProvider = Provider<WeightRepository>(
    (ref) => WeightRepository(ref.watch(dioProvider)));

enum WeightMode { loading, create, edit, error }

class WeightState {
  const WeightState(
      {required this.date,
      required this.recordedAt,
      this.mode = WeightMode.loading,
      this.record,
      this.message,
      this.busy = false,
      this.formRevision = 0});
  final DateTime date;
  final DateTime recordedAt;
  final WeightMode mode;
  final WeightRecord? record;
  final String? message;
  final bool busy;
  final int formRevision;
  WeightState copy(
          {DateTime? date,
          DateTime? recordedAt,
          WeightMode? mode,
          WeightRecord? record,
          bool clearRecord = false,
          String? message,
          bool? busy,
          bool refreshForm = false}) =>
      WeightState(
          date: date ?? this.date,
          recordedAt: recordedAt ?? this.recordedAt,
          mode: mode ?? this.mode,
          record: clearRecord ? null : record ?? this.record,
          message: message,
          busy: busy ?? this.busy,
          formRevision: refreshForm ? formRevision + 1 : formRevision);
}

final weightControllerProvider =
    StateNotifierProvider.autoDispose<WeightController, WeightState>((ref) =>
        WeightController(ref.watch(weightRepositoryProvider), DateTime.now()));

class WeightController extends StateNotifier<WeightState> {
  WeightController(this._repository, DateTime now)
      : super(WeightState(
            date: DateTime(now.year, now.month, now.day), recordedAt: now));
  final WeightRepository _repository;
  int _generation = 0;
  void setRecordedAt(DateTime value) {
    state = state.copy(recordedAt: value);
  }

  Future<void> load(DateTime date) async {
    final token = ++_generation;
    final selectedDate = DateTime(date.year, date.month, date.day);
    state = state.copy(
        date: selectedDate,
        mode: WeightMode.loading,
        clearRecord: true,
        busy: false);
    try {
      final record = await _repository.get(date);
      if (token == _generation) {
        state = state.copy(
            mode: WeightMode.edit,
            record: record,
            recordedAt: record.recordedAt.toLocal(),
            refreshForm: true);
      }
    } on ApiException catch (e) {
      if (token != _generation) return;
      if (e.code == 'WEIGHT_NOT_FOUND' && e.statusCode == 404) {
        state = state.copy(
            mode: WeightMode.create,
            clearRecord: true,
            recordedAt: _createRecordedAt(selectedDate),
            refreshForm: true);
      } else {
        state = state.copy(
            mode: WeightMode.error,
            clearRecord: true,
            message: weightErrorMessage(e));
      }
    }
  }

  Future<bool> save(String weight, String memo, DateTime recordedAt) async {
    if (state.busy) return false;
    final value = validateWeightInput(weight);
    validateMemo(memo);
    final token = _generation;
    final operationDate = state.date;
    final edit = state.mode == WeightMode.edit;
    state = state.copy(busy: true);
    try {
      final cleanMemo = memo.trim().isEmpty ? null : memo;
      final record = edit
          ? await _repository.update(
              state.date, UpdateWeightRequest(value, recordedAt, cleanMemo))
          : await _repository.create(
              CreateWeightRequest(state.date, value, recordedAt, cleanMemo));
      if (!_isCurrent(token, operationDate)) return false;
      state = state.copy(
          mode: WeightMode.edit,
          record: record,
          recordedAt: record.recordedAt.toLocal(),
          busy: false,
          refreshForm: true);
      return true;
    } on ApiException catch (e) {
      if (!_isCurrent(token, operationDate)) return false;
      state = state.copy(busy: false, message: weightErrorMessage(e));
      return false;
    }
  }

  Future<bool> delete() async {
    if (state.busy) return false;
    final token = _generation;
    final operationDate = state.date;
    state = state.copy(busy: true);
    try {
      await _repository.delete(state.date);
      if (!_isCurrent(token, operationDate)) return false;
      state = state.copy(
          mode: WeightMode.create,
          clearRecord: true,
          recordedAt: _createRecordedAt(operationDate),
          busy: false,
          refreshForm: true);
      return true;
    } on ApiException catch (e) {
      if (!_isCurrent(token, operationDate)) return false;
      state = state.copy(busy: false, message: weightErrorMessage(e));
      return false;
    }
  }

  bool _isCurrent(int token, DateTime date) =>
      token == _generation && state.date == date;
}

DateTime _createRecordedAt(DateTime date) {
  final now = DateTime.now();
  return DateTime(date.year, date.month, date.day, now.hour, now.minute);
}

String weightErrorMessage(ApiException e) {
  if (e.code == 'WEIGHT_ALREADY_EXISTS') return 'この日付にはすでに体重記録があります。';
  if (e.code == 'WEIGHT_NOT_FOUND') return 'この体重記録は見つかりませんでした。再読み込みしてください。';
  return switch (e.kind) {
    ApiErrorKind.network => 'サーバーに接続できませんでした。',
    ApiErrorKind.timeout => '通信がタイムアウトしました。',
    _ => '体重記録の処理中にエラーが発生しました。'
  };
}
