import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Semantic presentation values shared by screens and feature widgets.
///
/// This is intentionally a ThemeExtension rather than a second styling
/// system: the active Material color scheme remains the source for framework
/// controls, while these tokens cover the app-specific surfaces and states.
@immutable
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  final Color canvas;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSubtle;
  final Color outline;
  final Color outlineStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color focus;
  final Color hover;
  final Color selected;
  final Color disabled;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color pending;
  final Color offline;
  final Color plannedTaskFill;
  final Color actualTaskFill;
  final Color onTaskFill;
  final double radiusSmall;
  final double radiusMedium;
  final double radiusLarge;
  final double controlHeight;

  const AppThemeTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSubtle,
    required this.outline,
    required this.outlineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.focus,
    required this.hover,
    required this.selected,
    required this.disabled,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.pending,
    required this.offline,
    required this.plannedTaskFill,
    required this.actualTaskFill,
    required this.onTaskFill,
    required this.radiusSmall,
    required this.radiusMedium,
    required this.radiusLarge,
    required this.controlHeight,
  });

  factory AppThemeTokens.dark() => const AppThemeTokens(
    canvas: AppColors.backgroundDark,
    surface: AppColors.surfaceDark,
    surfaceRaised: Color(0xFF252631),
    surfaceSubtle: Color(0xFF18191F),
    outline: Color(0xFF3A3C48),
    outlineStrong: Color(0xFF5A5D6B),
    textPrimary: AppColors.textPrimaryDark,
    textSecondary: AppColors.textSecondaryDark,
    // Secondary text is intentionally shared here: the muted token is used
    // for readable time/navigation labels, not decorative chrome.
    textMuted: AppColors.textSecondaryDark,
    focus: Color(0xFFB5A8FF),
    hover: Color(0x147C5CFC),
    selected: Color(0x267C5CFC),
    disabled: Color(0x615F6270),
    success: AppColors.completed,
    warning: AppColors.warning,
    error: Color(0xFFFF8A80),
    info: AppColors.low,
    pending: Color(0xFFFDD663),
    offline: Color(0xFF9AA0A6),
    plannedTaskFill: Color(0xFF3A3564),
    actualTaskFill: Color(0xFF2D6A43),
    onTaskFill: Color(0xFFF6F2FF),
    radiusSmall: 8,
    radiusMedium: 12,
    radiusLarge: 16,
    controlHeight: 44,
  );

  factory AppThemeTokens.light() => const AppThemeTokens(
    canvas: AppColors.backgroundLight,
    surface: AppColors.surfaceLight,
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSubtle: Color(0xFFF3F2F8),
    outline: Color(0xFFD7D5E0),
    outlineStrong: Color(0xFF9995A8),
    textPrimary: AppColors.textPrimaryLight,
    textSecondary: AppColors.textSecondaryLight,
    textMuted: AppColors.textSecondaryLight,
    focus: Color(0xFF5540CC),
    hover: Color(0x107C5CFC),
    selected: Color(0x187C5CFC),
    disabled: Color(0x61777777),
    success: Color(0xFF287C4A),
    warning: Color(0xFF9A6500),
    error: Color(0xFFB3261E),
    info: Color(0xFF315F9E),
    pending: Color(0xFF8A6400),
    offline: Color(0xFF696969),
    plannedTaskFill: Color(0xFFE8E2FF),
    actualTaskFill: Color(0xFFD5EEDC),
    onTaskFill: Color(0xFF211A47),
    radiusSmall: 8,
    radiusMedium: 12,
    radiusLarge: 16,
    controlHeight: 44,
  );

  static AppThemeTokens of(BuildContext context) =>
      Theme.of(context).extension<AppThemeTokens>() ?? AppThemeTokens.dark();

  @override
  AppThemeTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSubtle,
    Color? outline,
    Color? outlineStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? focus,
    Color? hover,
    Color? selected,
    Color? disabled,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? pending,
    Color? offline,
    Color? plannedTaskFill,
    Color? actualTaskFill,
    Color? onTaskFill,
    double? radiusSmall,
    double? radiusMedium,
    double? radiusLarge,
    double? controlHeight,
  }) => AppThemeTokens(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
    outline: outline ?? this.outline,
    outlineStrong: outlineStrong ?? this.outlineStrong,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    focus: focus ?? this.focus,
    hover: hover ?? this.hover,
    selected: selected ?? this.selected,
    disabled: disabled ?? this.disabled,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    info: info ?? this.info,
    pending: pending ?? this.pending,
    offline: offline ?? this.offline,
    plannedTaskFill: plannedTaskFill ?? this.plannedTaskFill,
    actualTaskFill: actualTaskFill ?? this.actualTaskFill,
    onTaskFill: onTaskFill ?? this.onTaskFill,
    radiusSmall: radiusSmall ?? this.radiusSmall,
    radiusMedium: radiusMedium ?? this.radiusMedium,
    radiusLarge: radiusLarge ?? this.radiusLarge,
    controlHeight: controlHeight ?? this.controlHeight,
  );

  @override
  AppThemeTokens lerp(covariant AppThemeTokens? other, double t) {
    if (other == null) return this;
    return AppThemeTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineStrong: Color.lerp(outlineStrong, other.outlineStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
      plannedTaskFill: Color.lerp(plannedTaskFill, other.plannedTaskFill, t)!,
      actualTaskFill: Color.lerp(actualTaskFill, other.actualTaskFill, t)!,
      onTaskFill: Color.lerp(onTaskFill, other.onTaskFill, t)!,
      radiusSmall: lerpDouble(radiusSmall, other.radiusSmall, t),
      radiusMedium: lerpDouble(radiusMedium, other.radiusMedium, t),
      radiusLarge: lerpDouble(radiusLarge, other.radiusLarge, t),
      controlHeight: lerpDouble(controlHeight, other.controlHeight, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
