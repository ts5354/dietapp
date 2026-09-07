import 'package:dio/dio.dart';
import 'package:dietapp/core/network/api_error.dart';
import 'package:dietapp/features/weight/data/weight_repository.dart';
import 'package:dietapp/features/weight/domain/weight.dart';
import 'package:dietapp/features/weight/providers/weight_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:async';

Map<String, dynamic> response() => {
      'id': 1,
      'record_date': '2026-09-07',
      'weight_kg': 65.5,
      'recorded_at': '2026-09-07T03:30:00Z',
      'memo': null,
      'created_at': '2026-09-07T03:30:00Z',
      'updated_at': '2026-09-07T03:30:00Z',
    };

void main() {
  test('parses strict response and permits additive fields', () {
    final json = response()..['extra'] = true;
    final record = WeightRecord.fromJson(json);
    expect(record.weightKg, 65.5);
    expect(record.memo, isNull);
    expect(record.recordedAt.isUtc, isTrue);
    for (final change in [
      {'weight_kg': '65.5'},
      {'record_date': 'bad'},
      {'recorded_at': '2026-09-07T03:30:00'}
    ]) {
      final invalid = response()..addAll(change);
      expect(
          () => WeightRecord.fromJson(invalid), throwsA(isA<ApiException>()));
    }
  });
  test('serializes create and update contracts', () {
    final local = DateTime(2026, 9, 7, 15, 30);
    final create =
        CreateWeightRequest(DateTime(2026, 9, 7), 65.5, local, null).toJson();
    final update = UpdateWeightRequest(65.5, local, null).toJson();
    expect(create['record_date'], '2026-09-07');
    expect(create['weight_kg'], isA<num>());
    expect(create['recorded_at'], matches(RegExp(r'(Z|[+-]\d\d:\d\d)$')));
    expect(create['memo'], isNull);
    expect(update.containsKey('record_date'), isFalse);
    expect(update['memo'], isNull);
  });
  test('validates weight and memo without rounding', () {
    expect(validateWeightInput('65'), 65);
    expect(validateWeightInput('65.5'), 65.5);
    for (final value in ['', 'abc', '0', '-1', '65.55', 'NaN', 'Infinity']) {
      expect(() => validateWeightInput(value),
          throwsA(isA<WeightValidationException>()));
    }
    expect(() => validateMemo(List.filled(501, 'x').join()),
        throwsA(isA<WeightValidationException>()));
  });
  test('uses all CRUD paths and numeric bodies', () async {
    final seen = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        seen.add(o);
        if (o.method == 'DELETE') {
          h.resolve(Response(requestOptions: o, statusCode: 204));
        } else {
          h.resolve(Response(requestOptions: o, data: response()));
        }
      }));
    final repository = WeightRepository(dio);
    final date = DateTime(2026, 9, 7);
    final at = DateTime.utc(2026, 9, 7, 3, 30);
    await repository.get(date);
    await repository.create(CreateWeightRequest(date, 65.5, at, null));
    await repository.update(date, UpdateWeightRequest(65.4, at, null));
    await repository.delete(date);
    expect(seen.map((e) => e.method), ['GET', 'POST', 'PUT', 'DELETE']);
    expect(seen[0].path, '/api/v1/weights/2026-09-07');
    expect(seen[1].data['record_date'], '2026-09-07');
    expect(seen[2].data.containsKey('record_date'), isFalse);
  });
  test('normalizes Dio errors', () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (o, h) => h.reject(DioException.connectionError(
              requestOptions: o, reason: 'refused'))));
    expect(
        WeightRepository(dio).get(DateTime(2026)),
        throwsA(isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.network)));
  });

  group('controller transitions and stale responses', () {
    test('found, not found, and network map to edit, create, and error',
        () async {
      final fake = FakeWeightRepository();
      final controller = WeightController(fake, DateTime(2026, 9, 7, 10));
      fake.getResult = Future.value(record(DateTime(2026, 9, 7), memo: 'memo'));
      await controller.load(DateTime(2026, 9, 7));
      expect(controller.state.mode, WeightMode.edit);
      fake.getResult = Future.error(apiError(404, 'WEIGHT_NOT_FOUND'));
      await controller.load(DateTime(2026, 9, 8));
      expect(controller.state.mode, WeightMode.create);
      expect(controller.state.record, isNull);
      expect(controller.state.recordedAt.day, 8);
      fake.getResult = Future.error(
          const ApiException(kind: ApiErrorKind.network, message: 'network'));
      await controller.load(DateTime(2026, 9, 9));
      expect(controller.state.mode, WeightMode.error);
    });

    test('create, update, delete and duplicate mutation transitions', () async {
      final fake = FakeWeightRepository();
      final controller = WeightController(fake, DateTime(2026, 9, 7, 10));
      fake.getResult = Future.error(apiError(404, 'WEIGHT_NOT_FOUND'));
      await controller.load(DateTime(2026, 9, 7));
      fake.writeResult = Future.value(record(DateTime(2026, 9, 7)));
      expect(await controller.save('65.5', '', controller.state.recordedAt),
          isTrue);
      expect(controller.state.mode, WeightMode.edit);
      fake.writeResult =
          Future.value(record(DateTime(2026, 9, 7), weight: 65.4));
      expect(await controller.save('65.4', 'm', controller.state.recordedAt),
          isTrue);
      final pending = Completer<void>();
      fake.deleteResult = pending.future;
      final first = controller.delete();
      expect(await controller.delete(), isFalse);
      pending.complete();
      expect(await first, isTrue);
      expect(controller.state.mode, WeightMode.create);
      expect(controller.state.record, isNull);
    });

    test('old get, save, and delete results cannot overwrite a new date',
        () async {
      final fake = FakeWeightRepository();
      final controller = WeightController(fake, DateTime(2026, 9, 7));
      final oldGet = Completer<WeightRecord>();
      fake.getResult = oldGet.future;
      final loadingA = controller.load(DateTime(2026, 9, 7));
      fake.getResult = Future.error(apiError(404, 'WEIGHT_NOT_FOUND'));
      await controller.load(DateTime(2026, 9, 8));
      oldGet.complete(record(DateTime(2026, 9, 7)));
      await loadingA;
      expect(controller.state.date.day, 8);
      expect(controller.state.mode, WeightMode.create);

      final oldSave = Completer<WeightRecord>();
      fake.writeResult = oldSave.future;
      final saving = controller.save('65.5', 'A', controller.state.recordedAt);
      fake.getResult = Future.error(apiError(404, 'WEIGHT_NOT_FOUND'));
      await controller.load(DateTime(2026, 9, 9));
      oldSave.complete(record(DateTime(2026, 9, 8)));
      await saving;
      expect(controller.state.date.day, 9);
      expect(controller.state.record, isNull);

      fake.writeResult = Future.value(record(DateTime(2026, 9, 9)));
      await controller.save('65.5', '', controller.state.recordedAt);
      final oldDelete = Completer<void>();
      fake.deleteResult = oldDelete.future;
      final deleting = controller.delete();
      fake.getResult = Future.error(apiError(404, 'WEIGHT_NOT_FOUND'));
      await controller.load(DateTime(2026, 9, 10));
      oldDelete.complete();
      await deleting;
      expect(controller.state.date.day, 10);
      expect(controller.state.mode, WeightMode.create);
    });
  });
}

WeightRecord record(DateTime date, {double weight = 65.5, String? memo}) =>
    WeightRecord(
        id: 1,
        recordDate: date,
        weightKg: weight,
        recordedAt: DateTime(date.year, date.month, date.day, 10),
        memo: memo,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026));
ApiException apiError(int status, String code) => ApiException(
    kind: ApiErrorKind.server, statusCode: status, code: code, message: code);

class FakeWeightRepository implements WeightRepository {
  Future<WeightRecord> getResult = Completer<WeightRecord>().future;
  Future<WeightRecord> writeResult = Completer<WeightRecord>().future;
  Future<void> deleteResult = Future.value();
  int mutations = 0;
  @override
  Future<WeightRecord> get(DateTime date) => getResult;
  @override
  Future<WeightRecord> create(CreateWeightRequest request) {
    mutations++;
    return writeResult;
  }

  @override
  Future<WeightRecord> update(DateTime date, UpdateWeightRequest request) {
    mutations++;
    return writeResult;
  }

  @override
  Future<void> delete(DateTime date) {
    mutations++;
    return deleteResult;
  }
}
