import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/home_screen.dart';
import '../features/weight/presentation/weight_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
          path: '/record/weight',
          builder: (context, state) => const WeightScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
