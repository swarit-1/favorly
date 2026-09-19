import 'package:flutter/material.dart';

/// Palette lifted from the Favorly design comps.
class AppColors {
  const AppColors._();

  static const cream = Color(0xFFFCFAF6);
  static const surface = Color(0xFFFFFFFF);
  static const green = Color(0xFF1C4B3C);
  static const greenTint = Color(0xFFE7EFE8);
  static const greenTintDeep = Color(0xFFD2E1D4);
  static const orange = Color(0xFFE79463);
  static const peach = Color(0xFFF9E1CD);
  static const ink = Color(0xFF15211C);
  static const muted = Color(0xFF6C7A73);
  static const border = Color(0xFFEDE7DE);
}

ThemeData buildFavorlyTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.green,
      primary: AppColors.green,
      surface: AppColors.cream,
    ),
    scaffoldBackgroundColor: AppColors.cream,
  );

  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: AppColors.ink, displayColor: AppColors.ink)
        .copyWith(
          headlineMedium: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: AppColors.ink,
          ),
          titleLarge: const TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: AppColors.ink,
          ),
          titleMedium: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
          bodyMedium: const TextStyle(
            fontSize: 15,
            height: 1.45,
            color: AppColors.muted,
          ),
          labelLarge: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
  );
}
