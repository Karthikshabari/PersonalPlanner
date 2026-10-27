import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/core/theme/app_theme_tokens.dart';
import 'package:personal_planner/core/widgets/status_badge.dart';

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

  for (final (name, theme) in [
    ('dark', AppTheme.darkTheme),
    ('light', AppTheme.lightTheme),
  ]) {
    group('B34 primary and selected navigation ($name)', () {
      test('filled button and New task button labels reach 4.5:1', () {
        final style = theme.filledButtonTheme.style!;
        final fill = style.backgroundColor!.resolve({})!;
        expect(
          contrast(style.foregroundColor!.resolve({})!, fill),
          greaterThanOrEqualTo(4.5),
        );
        final fab = theme.floatingActionButtonTheme;
        expect(
          contrast(fab.foregroundColor!, fab.backgroundColor!),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('selected rail label and icon on the indicator', () {
        final rail = theme.navigationRailTheme;
        final indicator = Color.alphaBlend(
          rail.indicatorColor!,
          rail.backgroundColor!,
        );
        expect(
          contrast(rail.selectedLabelTextStyle!.color!, indicator),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(rail.selectedIconTheme!.color!, indicator),
          greaterThanOrEqualTo(3),
        );
      });

      test('selected bottom bar label and icon on the indicator', () {
        final bar = theme.navigationBarTheme;
        final indicator = Color.alphaBlend(
          bar.indicatorColor!,
          bar.backgroundColor!,
        );
        const selected = {WidgetState.selected};
        expect(
          contrast(bar.labelTextStyle!.resolve(selected)!.color!, indicator),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(bar.iconTheme!.resolve(selected)!.color!, indicator),
          greaterThanOrEqualTo(3),
        );
      });
    });

    test(
      'UX-37 input borders reach 3:1 on the field and the surface ($name)',
      () {
        final input = theme.inputDecorationTheme;
        for (final border in [input.border, input.enabledBorder]) {
          final color = (border! as OutlineInputBorder).borderSide.color;
          expect(contrast(color, input.fillColor!), greaterThanOrEqualTo(3));
          expect(
            contrast(color, theme.colorScheme.surface),
            greaterThanOrEqualTo(3),
          );
        }
      },
    );

    testWidgets('B35 status badge text reaches 4.5:1 and 12 sp ($name)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                for (final status in TaskStatus.values)
                  StatusBadge(status: status),
              ],
            ),
          ),
        ),
      );
      final tokens = AppThemeTokens.of(tester.element(find.byType(Scaffold)));
      for (final status in TaskStatus.values) {
        final badge = find.byWidgetPredicate(
          (w) => w is StatusBadge && w.status == status,
        );
        final text = tester.widget<Text>(
          find.descendant(of: badge, matching: find.text(status.label)),
        );
        final tint =
            (tester
                        .widget<AnimatedContainer>(
                          find.descendant(
                            of: badge,
                            matching: find.byType(AnimatedContainer),
                          ),
                        )
                        .decoration!
                    as BoxDecoration)
                .color!;
        expect(text.style!.fontSize, 12, reason: status.name);
        for (final surface in [
          tokens.canvas,
          tokens.surface,
          tokens.surfaceRaised,
          tokens.surfaceSubtle,
        ]) {
          expect(
            contrast(text.style!.color!, Color.alphaBlend(tint, surface)),
            greaterThanOrEqualTo(4.5),
            reason: '${status.name} on $surface',
          );
        }
      }
    });
  }
}
