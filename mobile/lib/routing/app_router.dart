import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../screens/home_screen.dart';
import '../features/nutrition/presentation/nutrition_screen.dart';
import '../features/record/presentation/record_screen.dart';
import '../features/history/presentation/history_screen.dart';
import '../features/injection/presentation/injection_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/symptom/presentation/symptom_screen.dart';
import '../features/weight/presentation/weight_screen.dart';
import '../shared/presentation/app_bottom_navigation.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    routes: [
      GoRoute(
          path: '/record/weight',
          builder: (context, state) => const WeightScreen()),
      GoRoute(
          path: '/record/food',
          builder: (context, state) => const NutritionScreen()),
      GoRoute(
          path: '/record/symptom',
          builder: (context, state) => const SymptomScreen()),
      GoRoute(
          path: '/record/injection',
          builder: (context, state) => const InjectionScreen()),
      ShellRoute(
        builder: (context, state, child) => Scaffold(
          body: child,
          bottomNavigationBar: AppBottomNavigation(
            selectedIndex: _tabIndex(state.uri.path),
          ),
        ),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const HomeScreen(),
          ),
          GoRoute(
            path: '/record',
            builder: (context, state) => const RecordScreen(),
          ),
          GoRoute(
            path: '/history',
            builder: (context, state) => const HistoryScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

int _tabIndex(String path) => switch (path) {
      '/record' => 1,
      '/history' => 2,
      '/settings' => 3,
      _ => 0,
    };
