import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/timezone/device_timezone.dart';
import '../data/symptom_repository.dart';
import '../domain/symptom.dart';

final deviceTimezoneProvider =
    Provider<DeviceTimezone>((ref) => const PlatformDeviceTimezone());
final symptomRepositoryProvider = Provider<SymptomRepository>(
    (ref) => SymptomRepository(ref.watch(dioProvider)));

enum SymptomViewMode { loading, ready, error }

class SymptomState {
  const SymptomState({
    required this.date,
    this.viewMode = SymptomViewMode.loading,
    this.records = const [],
    this.timezone,
    this.busy = false,
    this.message,
  });
  final DateTime date;
  final SymptomViewMode viewMode;
  final List<SymptomRecord> records;
  final String? timezone;
  final bool busy;
  final String? message;

  SymptomState copy({
    SymptomViewMode? viewMode,
    List<SymptomRecord>? records,
    String? timezone,
    bool? busy,
    String? message,
  }) =>
      SymptomState(
        date: date,
        viewMode: viewMode ?? this.viewMode,
        records: records ?? this.records,
        timezone: timezone ?? this.timezone,
        busy: busy ?? this.busy,
        message: message,
      );
}

final symptomControllerProvider =
    StateNotifierProvider.autoDispose<SymptomController, SymptomState>((ref) =>
        SymptomController(ref.watch(symptomRepositoryProvider),
            ref.watch(deviceTimezoneProvider), DateTime.now()));

class SymptomController extends StateNotifier<SymptomState> {
  SymptomController(this._repository, this._deviceTimezone, DateTime now)
      : super(SymptomState(date: DateTime(now.year, now.month, now.day)));
  final SymptomRepository _repository;
  final DeviceTimezone _deviceTimezone;
  int _generation = 0;

  Future<void> load(DateTime date) async {
    final selectedDate = DateTime(date.year, date.month, date.day);
    final token = ++_generation;
    state = SymptomState(date: selectedDate);
    try {
      final timezone = await _deviceTimezone.currentIdentifier();
      if (!_isCurrent(token, selectedDate)) return;
      if (timezone.trim().isEmpty) throw const TimezoneLookupException();
      final records = await _repository.listByDate(selectedDate, timezone);
      if (_isCurrent(token, selectedDate)) {
        state = state.copy(
            viewMode: SymptomViewMode.ready,
            records: records,
            timezone: timezone);
      }
    } on ApiException catch (error) {
      if (_isCurrent(token, selectedDate)) {
        state = state.copy(
            viewMode: SymptomViewMode.error,
            records: const [],
            message: symptomErrorMessage(error));
      }
    } catch (_) {
      if (_isCurrent(token, selectedDate)) {
        state = state.copy(
            viewMode: SymptomViewMode.error,
            records: const [],
            message: '端末のタイムゾーンを取得できませんでした。');
      }
    }
  }

  Future<bool> create(SymptomWriteRequest request) async {
    if (state.busy || !_sameDate(request.recordedAt, state.date)) return false;
    return _mutate((_) => _repository.create(request));
  }

  Future<bool> update(int id, SymptomWriteRequest request) async {
    if (state.busy || !_sameDate(request.recordedAt, state.date)) return false;
    return _mutate((_) => _repository.update(id, request));
  }

  Future<bool> delete(int id) async {
    if (state.busy) return false;
    return _mutate((_) => _repository.delete(id));
  }

  Future<bool> _mutate(Future<Object?> Function(DateTime date) mutation) async {
    final token = _generation;
    final date = state.date;
    final timezone = state.timezone;
    if (timezone == null) return false;
    state = state.copy(busy: true);
    try {
      await mutation(date);
      if (!_isCurrent(token, date)) return false;
      return await _reconcile(token, date, timezone);
    } on ApiException catch (error) {
      if (!_isCurrent(token, date)) return false;
      state = state.copy(busy: false, message: symptomErrorMessage(error));
      return false;
    }
  }

  Future<bool> _reconcile(int token, DateTime date, String timezone) async {
    try {
      final records = await _repository.listByDate(date, timezone);
      if (!_isCurrent(token, date)) return false;
      state = state.copy(
          viewMode: SymptomViewMode.ready, records: records, busy: false);
      return true;
    } on ApiException catch (error) {
      if (!_isCurrent(token, date)) return false;
      state = state.copy(
          viewMode: SymptomViewMode.error,
          records: const [],
          busy: false,
          message: symptomErrorMessage(error));
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

String symptomErrorMessage(ApiException error) {
  if (error.code == 'SYMPTOM_NOT_FOUND') {
    return 'この体調記録は見つかりませんでした。再読み込みしてください。';
  }
  return switch (error.kind) {
    ApiErrorKind.network => 'サーバーに接続できませんでした。',
    ApiErrorKind.timeout => '通信がタイムアウトしました。',
    _ => '体調記録の処理中にエラーが発生しました。',
  };
}
