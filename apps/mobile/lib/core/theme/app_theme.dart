import 'package:flutter/material.dart';
import 'package:rotary_shared/shared.dart';

/// 8 px tabanlı boşluk sistemi.
abstract final class Gaps {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

abstract final class AppTheme {
  static const Color navy = Color(BrandColors.navy);
  static const Color gold = Color(BrandColors.gold);
  static const Color lightGray = Color(BrandColors.lightGray);
  static const Color success = Color(BrandColors.success);
  static const Color danger = Color(BrandColors.error);
  static const Color warning = Color(BrandColors.warning);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: navy,
      brightness: Brightness.light,
    ).copyWith(
      primary: navy,
      onPrimary: Colors.white,
      secondary: gold,
      surface: Colors.white,
      error: danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: lightGray,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          backgroundColor: navy,
          foregroundColor: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: gold.withValues(alpha: 0.25),
      ),
    );
  }
}
