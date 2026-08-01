import 'package:attendiqo_shared/attendiqo_shared.dart';
import 'package:flutter/material.dart';

abstract final class AttendiqoTheme {
  static const primary = Color(BrandColors.attendiqoPrimary);
  static const secondary = Color(BrandColors.attendiqoSecondary);
  static const accent = Color(BrandColors.attendiqoAccent);
  static const background = Color(0xFFF8FAFC);
  static const text = Color(0xFF172033);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      surface: const Color(0xFFFFFFFF),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFFFFFFFF),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          backgroundColor: primary,
        ),
      ),
    );
  }
}
