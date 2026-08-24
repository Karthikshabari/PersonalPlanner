import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTypography {
  static const String fontFamily = 'Inter';

  static TextTheme get dark => _base(
        displayColor: AppColors.textPrimaryDark,
        bodyColor: AppColors.textPrimaryDark,
      );

  static TextTheme get light => _base(
        displayColor: AppColors.textPrimaryLight,
        bodyColor: AppColors.textPrimaryLight,
      );

  static TextTheme _base({
    required Color displayColor,
    required Color bodyColor,
  }) {
    return TextTheme(
      displaySmall: TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w600,
          color: displayColor,
          letterSpacing: -0.5),
      headlineMedium: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: displayColor,
          letterSpacing: -0.25),
      titleLarge: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600, color: displayColor),
      titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: displayColor,
          letterSpacing: 0.15),
      titleSmall: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: displayColor,
          letterSpacing: 0.1),
      bodyLarge: TextStyle(fontSize: 16, color: bodyColor),
      bodyMedium: TextStyle(fontSize: 14, color: bodyColor),
      bodySmall:
          TextStyle(fontSize: 12, color: bodyColor.withValues(alpha: 0.85)),
      labelLarge: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: displayColor),
      labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: displayColor,
          letterSpacing: 0.4),
      labelSmall: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: displayColor,
          letterSpacing: 0.4),
    );
  }
}
