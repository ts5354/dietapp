import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/api_config.dart';

final apiConfigProvider =
    Provider<ApiConfig>((ref) => ApiConfig.fromEnvironment());

final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(apiConfigProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: config.baseUrl,
      responseType: ResponseType.json,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 10),
    ),
  );
  ref.onDispose(() => dio.close());
  return dio;
});
