import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/dio_provider.dart';
import '../data/injection_repository.dart';
import '../domain/injection.dart';

final injectionRepositoryProvider = Provider<InjectionRepository>(
    (ref) => InjectionRepository(ref.watch(dioProvider)));

enum InjectionMode { loading, create, edit, error }

class InjectionState {
  const InjectionState(
      {required this.date,
      required this.injectedAt,
      this.mode = InjectionMode.loading,
      this.record,
      this.latest,
      this.busy = false,
      this.message,
      this.formRevision = 0});
  final DateTime date;
  final DateTime injectedAt;
  final InjectionMode mode;
  final InjectionRecord? record;
  final InjectionRecord? latest;
  final bool busy;
  final String? message;
  final int formRevision;
  DateTime? get nextScheduledDate {
    final date = latest?.recordDate;
    return date == null ? null : DateTime(date.year, date.month, date.day + 7);
  }

  InjectionState copy(
          {InjectionMode? mode,
          InjectionRecord? record,
          bool clearRecord = false,
          InjectionRecord? latest,
          bool clearLatest = false,
          DateTime? injectedAt,
          bool? busy,
          String? message,
          bool refreshForm = false}) =>
      InjectionState(
          date: date,
          injectedAt: injectedAt ?? this.injectedAt,
          mode: mode ?? this.mode,
          record: clearRecord ? null : record ?? this.record,
          latest: clearLatest ? null : latest ?? this.latest,
          busy: busy ?? this.busy,
          message: message,
          formRevision: refreshForm ? formRevision + 1 : formRevision);
}

final injectionControllerProvider =
    StateNotifierProvider.autoDispose<InjectionController, InjectionState>(
        (ref) => InjectionController(
            ref.watch(injectionRepositoryProvider), DateTime.now()));

class InjectionController extends StateNotifier<InjectionState> {
  InjectionController(this._repository, DateTime now)
      : super(InjectionState(
            date: DateTime(now.year, now.month, now.day), injectedAt: now));
  final InjectionRepository _repository;
  int _generation = 0;

  void setInjectedAt(DateTime value) => state = state.copy(injectedAt: value);

  Future<void> load(DateTime date) async {
    final selected = DateTime(date.year, date.month, date.day);
    final token = ++_generation;
    state = InjectionState(date: selected, injectedAt: _defaultTime(selected));
    try {
      await _reconcile(token, selected);
    } on ApiException catch (error) {
      if (_isCurrent(token, selected)) {
        state = state.copy(
            mode: InjectionMode.error,
            clearRecord: true,
            clearLatest: true,
            busy: false,
            message: injectionErrorMessage(error));
      }
    }
  }

  Future<bool> save(String dose, InjectionSite? site, String memo,
      DateTime injectedAt, DateTime formDate) async {
    if (state.busy ||
        state.mode == InjectionMode.loading ||
        state.mode == InjectionMode.error ||
        state.date != formDate ||
        !_sameDate(injectedAt, state.date)) {
      return false;
    }
    final doseValue = validateDose(dose);
    if (site == null) {
      throw const InjectionValidationException('注射部位を選択してください。');
    }
    validateInjectionMemo(memo);
    final token = _generation;
    final date = state.date;
    final edit = state.mode == InjectionMode.edit;
    var mutationCompleted = false;
    final cleanMemo = memo.trim().isEmpty ? null : memo;
    state = state.copy(busy: true);
    try {
      if (edit) {
        await _repository.update(date,
            InjectionUpdateRequest(injectedAt, doseValue, site, cleanMemo));
      } else {
        await _repository.create(InjectionCreateRequest(
            date, injectedAt, doseValue, site, cleanMemo));
      }
      mutationCompleted = true;
      if (!_isCurrent(token, date)) return false;
      return await _reconcile(token, date);
    } on ApiException catch (error) {
      if (!_isCurrent(token, date)) return false;
      state = state.copy(
          mode: mutationCompleted ? InjectionMode.error : null,
          clearLatest: mutationCompleted,
          busy: false,
          message: injectionErrorMessage(error));
      return false;
    }
  }

  Future<bool> delete() async {
    if (state.busy || state.mode != InjectionMode.edit) return false;
    final token = _generation;
    final date = state.date;
    var mutationCompleted = false;
    state = state.copy(busy: true);
    try {
      await _repository.delete(date);
      mutationCompleted = true;
      if (!_isCurrent(token, date)) return false;
      return await _reconcile(token, date);
    } on ApiException catch (error) {
      if (!_isCurrent(token, date)) return false;
      state = state.copy(
          mode: mutationCompleted ? InjectionMode.error : null,
          clearLatest: mutationCompleted,
          busy: false,
          message: injectionErrorMessage(error));
      return false;
    }
  }

  Future<bool> _reconcile(int token, DateTime date) async {
    InjectionRecord? selected;
    try {
      selected = await _repository.getByDate(date);
    } on ApiException catch (error) {
      if (error.statusCode != 404 || error.code != 'INJECTION_NOT_FOUND') {
        rethrow;
      }
    }
    if (!_isCurrent(token, date)) return false;
    final latest = await _repository.getLatest();
    if (!_isCurrent(token, date)) return false;
    state = state.copy(
        mode: selected == null ? InjectionMode.create : InjectionMode.edit,
        record: selected,
        clearRecord: selected == null,
        latest: latest,
        clearLatest: latest == null,
        injectedAt: selected?.injectedAt.toLocal() ?? _defaultTime(date),
        busy: false,
        refreshForm: true);
    return true;
  }

  bool _isCurrent(int token, DateTime date) =>
      token == _generation && state.date == date;
}

DateTime _defaultTime(DateTime date) {
  final now = DateTime.now();
  return DateTime(date.year, date.month, date.day, now.hour, now.minute);
}

bool _sameDate(DateTime value, DateTime date) =>
    value.year == date.year &&
    value.month == date.month &&
    value.day == date.day;

String injectionErrorMessage(ApiException error) => switch (error.code) {
      'INJECTION_ALREADY_EXISTS' => 'この日にはすでに注射記録があります。再読み込みしてください。',
      'INJECTION_NOT_FOUND' => 'この注射記録は見つかりませんでした。再読み込みしてください。',
      'INJECTION_DATE_MISMATCH' => '注射日時と記録日が一致していません。',
      _ => switch (error.kind) {
          ApiErrorKind.network => 'サーバーに接続できませんでした。',
          ApiErrorKind.timeout => '通信がタイムアウトしました。',
          _ => '注射記録の処理中にエラーが発生しました。',
        }
    };
