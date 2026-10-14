import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/core/theme/app_theme_tokens.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/timeline_hour_grid.dart';

import 'theme_accessibility_test.dart' show contrast;

void main() {
  test('token colours: ruler text reaches 4.5:1 on the canvas', () {
    expect(
      contrast(
        AppThemeTokens.dark().textSecondary,
        AppThemeTokens.dark().canvas,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(
        AppThemeTokens.light().textSecondary,
        AppThemeTokens.light().canvas,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  for (final (name, theme) in [
    ('dark', AppTheme.darkTheme),
    ('light', AppTheme.lightTheme),
  ]) {
    testWidgets('the ruler label painted by the grid reaches 4.5:1 ($name)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: TimelineHourGrid(date: DateTime(2026, 3, 10)),
            ),
          ),
        ),
      );
      final tokens = AppThemeTokens.of(tester.element(find.byType(Scaffold)));
      final label = tester.widget<Text>(find.text('01:00'));
      final color = label.style!.color!;
      expect(label.style!.fontSize, 12);
      expect(color.a, 1.0, reason: 'the label must not be translucent');
      expect(contrast(color, tokens.canvas), greaterThanOrEqualTo(4.5));
      // And on the other surfaces the grid can sit on.
      expect(contrast(color, tokens.surface), greaterThanOrEqualTo(4.5));
    });
  }
}
