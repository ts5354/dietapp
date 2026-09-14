import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'routing/app_router.dart';

void main() {
  runApp(const ProviderScope(child: DietApp()));
}

class DietApp extends ConsumerWidget {
  const DietApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ダイエット男',
      theme: buildAppTheme(),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
