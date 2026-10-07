import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme_tokens.dart';

/// Mood and outcome colours for the Review screens. Kept apart from
/// [AppThemeTokens] so no existing token changes (D24).
@immutable
class ReviewColors extends ThemeExtension<ReviewColors> {
  final Color mood1;
  final Color mood2;
  final Color mood3;
  final Color mood4;
  final Color success;
  final Color amber;
  final Color blue;

  const ReviewColors({
    required this.mood1,
    required this.mood2,
    required this.mood3,
    required this.mood4,
    required this.success,
    required this.amber,
    required this.blue,
  });

  static const dark = ReviewColors(
    mood1: Color(0xFF45C1B6),
    mood2: Color(0xFF6C9BF0),
    mood3: Color(0xFFC58CF0),
    mood4: Color(0xFFE8B640),
    success: Color(0xFF45C1B6),
    amber: Color(0xFFE2B043),
    blue: Color(0xFF6C9BF0),
  );

  static const light = ReviewColors(
    mood1: Color(0xFF1F8A80),
    mood2: Color(0xFF3A72D4),
    mood3: Color(0xFF9A4FCF),
    mood4: Color(0xFFB87C0A),
    success: Color(0xFF1F8A80),
    amber: Color(0xFFB27A0D),
    blue: Color(0xFF3A72D4),
  );

  static ReviewColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ReviewColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  Color mood(int level) => switch (level) {
    1 => mood1,
    2 => mood2,
    3 => mood3,
    _ => mood4,
  };

  @override
  ReviewColors copyWith({
    Color? mood1,
    Color? mood2,
    Color? mood3,
    Color? mood4,
    Color? success,
    Color? amber,
    Color? blue,
  }) => ReviewColors(
    mood1: mood1 ?? this.mood1,
    mood2: mood2 ?? this.mood2,
    mood3: mood3 ?? this.mood3,
    mood4: mood4 ?? this.mood4,
    success: success ?? this.success,
    amber: amber ?? this.amber,
    blue: blue ?? this.blue,
  );

  @override
  ReviewColors lerp(covariant ReviewColors? other, double t) {
    if (other == null) return this;
    return ReviewColors(
      mood1: Color.lerp(mood1, other.mood1, t)!,
      mood2: Color.lerp(mood2, other.mood2, t)!,
      mood3: Color.lerp(mood3, other.mood3, t)!,
      mood4: Color.lerp(mood4, other.mood4, t)!,
      success: Color.lerp(success, other.success, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      blue: Color.lerp(blue, other.blue, t)!,
    );
  }
}

TextStyle reviewMonoStyle(BuildContext context, {double fontSize = 11}) =>
    TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['DejaVu Sans Mono', 'Roboto Mono'],
      fontSize: fontSize,
      letterSpacing: 0.6,
      color: AppThemeTokens.of(context).textMuted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
