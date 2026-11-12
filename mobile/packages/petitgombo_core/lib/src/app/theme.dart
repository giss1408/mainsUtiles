import 'package:flutter/material.dart';

import 'spacing.dart';

/// Brand colours. Green is the single accent for actions; orange is kept for
/// the logo and warnings, never for buttons.
abstract final class AppColors {
  static const Color primary = Color(0xFF1B5E20);
  static const Color warning = Color(0xFFB45309);
  static const Color warningSurface = Color(0xFFFFF4E5);
  static const Color danger = Color(0xFFB3261E);
  static const Color text = Color(0xFF1A1C19);
  static const Color textMuted = Color(0xFF5B6157);
  static const Color border = Color(0xFFD9DDD5);
  static const Color surface = Colors.white;
}

/// Light theme only. System font, so nothing is downloaded or bundled.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
  );

  const textTheme = TextTheme(
    headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25, color: AppColors.text),
    titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3, color: AppColors.text),
    bodyLarge: TextStyle(fontSize: 16, height: 1.45, color: AppColors.text),
    bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: AppColors.text),
    bodySmall: TextStyle(fontSize: 12, height: 1.4, color: AppColors.textMuted),
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  );

  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.field),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.surface,
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.md),
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.field)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(minTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.md),
        textStyle: textTheme.labelLarge,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.field)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(minTouchTarget, minTouchTarget),
        textStyle: textTheme.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.lg),
      border: border(AppColors.border),
      enabledBorder: border(AppColors.border),
      focusedBorder: border(AppColors.primary, 2),
      errorBorder: border(AppColors.danger),
      focusedErrorBorder: border(AppColors.danger, 2),
      errorMaxLines: 4,
      hintStyle: const TextStyle(fontSize: 16, color: AppColors.textMuted),
    ),
  );
}
