import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/home_screen.dart';
import '../features/nutrition/presentation/nutrition_screen.dart';
import '../features/symptom/presentation/symptom_screen.dart';
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
      GoRoute(
          path: '/record/food',
          builder: (context, state) => const NutritionScreen()),
      GoRoute(
          path: '/record/symptom',
          builder: (context, state) => const SymptomScreen()),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
