import 'package:flutter/material.dart';

abstract final class AppColors {
  static const mint = Color(0xFF2A9D8F);
  static const background = Color(0xFFF9FCFB);
  static const divider = Color(0xFFE4ECE9);
  static const weight = Color(0xFFDDF3FA);
  static const food = Color(0xFFFFE9D2);
  static const symptom = Color(0xFFFFE1E7);
  static const injection = Color(0xFFECE3FA);
}

ThemeData buildAppTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: AppColors.mint,
    brightness: Brightness.light,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colors,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Hiragino Maru Gothic ProN',
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: Color(0xFF24332F),
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.divider, space: 1),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.mint.withValues(alpha: 0.16),
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? AppColors.mint
                : const Color(0xFF697571),
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            fontSize: 12,
          )),
    ),
  );
}
