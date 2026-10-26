import 'package:flutter/material.dart';

abstract final class AppColors {
  static const Color primary = Color(0xFF7C5CFC);
  static const Color primaryDim = Color(0xFF5A3FE0);

  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color surfaceVariantDark = Color(0xFF2A2A2A);

  static const Color backgroundLight = Color(0xFFFAFAFA);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFEFEFEF);

  static const Color textPrimaryDark = Color(0xFFEAEAEA);
  static const Color textSecondaryDark = Color(0xFFA0A0A0);
  static const Color textPrimaryLight = Color(0xFF1B1B1B);
  static const Color textSecondaryLight = Color(0xFF5F5F5F);

  static const Color gridLine = Color(0x2FFFFFFF);
  static const Color currentTimeIndicator = Color(0xFFFF5252);
  static const Color selectionHighlight = Color(0xFF7C5CFC);

  static const Color planned = Color(0xFF8AB4F8);
  static const Color inProgress = Color(0xFFFDD663);
  static const Color completed = Color(0xFF81C995);
  static const Color skipped = Color(0xFF9AA0A6);
  static const Color cancelled = Color(0xFF6E6E6E);
  static const Color rescheduled = Color(0xFFF28B82);

  static const Color urgent = Color(0xFFEA4335);
  static const Color high = Color(0xFFFBBC04);
  static const Color medium = Color(0xFF7C5CFC);
  static const Color low = Color(0xFF8AB4F8);
  static const Color warning = Color(0xFFFFB300);

  static Color statusColor(String dbValue) => switch (dbValue) {
        'planned' => planned,
        'in_progress' => inProgress,
        'completed' => completed,
        'skipped' => skipped,
        'cancelled' => cancelled,
        'rescheduled' => rescheduled,
        _ => planned,
      };

  /// 3:1 against white needs a relative luminance of at most 1.05 / 3 - 0.05.
  static const double _maxLuminanceOnWhite = 1.05 / 3 - 0.05;

  /// A category's colour for stripes and dots. In the light theme a colour
  /// that is under 3:1 against white is darkened, keeping its hue, until it
  /// reaches it; the dark theme shows the stored colour.
  static Color categoryColor(String hex, Brightness brightness) {
    final color = parseHex(hex);
    if (brightness == Brightness.dark ||
        color.computeLuminance() <= _maxLuminanceOnWhite) {
      return color;
    }
    final hsl = HSLColor.fromColor(color);
    // Lightness 0 always passes; find the lightest value that still does.
    var passing = 0.0;
    var failing = hsl.lightness;
    for (var i = 0; i < 8; i++) {
      final middle = (passing + failing) / 2;
      if (hsl.withLightness(middle).toColor().computeLuminance() <=
          _maxLuminanceOnWhite) {
        passing = middle;
      } else {
        failing = middle;
      }
    }
    return hsl.withLightness(passing).toColor();
  }

  static Color parseHex(String hex) {
    final normalized = hex.replaceFirst('#', '');
    final value = int.parse(normalized, radix: 16);
    return Color(0xFF000000 | value);
  }
}
