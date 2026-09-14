import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/theme/app_theme_tokens.dart';

double contrast(Color foreground, Color background) {
  final lighter = foreground.computeLuminance();
  final darker = background.computeLuminance();
  final high = lighter > darker ? lighter : darker;
  final low = lighter > darker ? darker : lighter;
  return (high + 0.05) / (low + 0.05);
}

void main() {
  test('meaningful muted text reaches normal-text contrast targets', () {
    final dark = AppThemeTokens.dark();
    final light = AppThemeTokens.light();
    expect(contrast(dark.textMuted, dark.canvas), greaterThanOrEqualTo(4.5));
    expect(contrast(dark.textMuted, dark.surface), greaterThanOrEqualTo(4.5));
    expect(
      contrast(light.textMuted, light.surfaceRaised),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(light.textMuted, light.surfaceSubtle),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(dark.onTaskFill, dark.plannedTaskFill),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(dark.onTaskFill, dark.actualTaskFill),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(light.onTaskFill, light.plannedTaskFill),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(light.onTaskFill, light.actualTaskFill),
      greaterThanOrEqualTo(4.5),
    );
  });
}
