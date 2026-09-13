import 'package:dio/dio.dart';
import 'package:dietapp/core/config/api_config.dart';
import 'package:dietapp/core/network/dio_provider.dart';
import 'package:dietapp/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the dashboard home screen', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiConfigProvider.overrideWithValue(
          ApiConfig(baseUrl: 'http://example.test'),
        ),
      ],
      child: const DietApp(),
    ));

    expect(find.text('ホーム'), findsOneWidget);
    expect(find.byKey(const Key('dashboardScroll')), findsOneWidget);
  });

  testWidgets('navigates from record menu and validates the create form',
      (tester) async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.reject(DioException.badResponse(
          statusCode: 404,
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 404, data: {
            'error': {'code': 'WEIGHT_NOT_FOUND', 'message': 'Not found.'},
          }),
        ));
      }));
    await tester.pumpWidget(ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const DietApp(),
    ));

    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('体重'));
    await tester.pumpAndSettle();

    expect(find.text('体重を記録'), findsOneWidget);
    expect(find.byKey(const Key('weightField')), findsOneWidget);
    expect(find.text('メモ（任意）'), findsOneWidget);
    expect(find.text('保存する'), findsOneWidget);
    expect(find.text('記録を削除'), findsNothing);
    await tester.tap(find.text('保存する'));
    await tester.pump();
    expect(find.text('体重を入力してください'), findsOneWidget);
  });

  testWidgets('prefills edit form and confirms deletion', (tester) async {
    var deletes = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        if (options.method == 'DELETE') {
          deletes++;
          handler.resolve(Response(requestOptions: options, statusCode: 204));
        } else {
          handler.resolve(Response(requestOptions: options, data: {
            'id': 1,
            'record_date': '2026-09-07',
            'weight_kg': 65.5,
            'recorded_at': '2026-09-07T03:30:00Z',
            'memo': 'memo',
            'created_at': '2026-09-07T03:30:00Z',
            'updated_at': '2026-09-07T03:30:00Z',
          }));
        }
      }));
    await tester.pumpWidget(ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const DietApp(),
    ));
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('体重'));
    await tester.pumpAndSettle();
    expect(find.text('体重を編集'), findsOneWidget);
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('weightField')))
            .controller!
            .text,
        '65.5');
    expect(find.text('memo'), findsOneWidget);

    await tester.tap(find.text('記録を削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('キャンセル'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    await tester.tap(find.text('記録を削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(find.text('保存する'), findsOneWidget);
  });
}
