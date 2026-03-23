import 'package:flutter/material.dart';

/// Global theme for Book My Tables
///
/// Colors:
/// - Primary: Deep Red (#7B1E12)
/// - Accent:  Gold (#C78A1A)
/// - Background: Cream (#FFF8F3)
/// - Text: Dark Gray (#1A1A1A)
///
/// Fonts: Roboto (default)

class AppColors {
  static const deepRed = Color(0xFF7B1E12);
  static const gold = Color(0xFFC78A1A);
  static const cream = Color(0xFFFFF8F3);
  static const textDark = Color(0xFF1A1A1A);
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.deepRed,
      brightness: Brightness.light,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.deepRed,
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 2,
    ),
    textTheme: base.textTheme.copyWith(
      headlineLarge: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: AppColors.deepRed,
      ),
      titleLarge: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      ),
      bodyMedium: const TextStyle(
        color: AppColors.textDark,
        fontSize: 15,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.deepRed,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.gold, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.deepRed, width: 1.5),
      ),
      labelStyle: const TextStyle(color: AppColors.textDark),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.deepRed,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    iconTheme: const IconThemeData(color: AppColors.deepRed),
  );
}