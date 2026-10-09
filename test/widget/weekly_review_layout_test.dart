import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/router/app_router.dart';

import '../helpers/test_container.dart';

void main() {
  const widths = [360.0, 700.0, 1100.0, 1600.0];

  for (final width in widths) {
    testWidgets('Review tab at $width dp: no overflow, feel card last, '
        'chips in 4 or 2 + 2', (tester) async {
      final container = await buildTestContainer(tester);
      appRouter.go('/review/weekly');
      await pumpApp(tester, container, surface: Size(width, 900));
      await settle(tester);

      expect(tester.takeException(), isNull);

      double top(Finder finder) => tester.getTopLeft(finder).dy;
      final feel = top(find.text('How did the week feel?'));
      for (final title in [
        'Week at a glance',
        'What got in the way',
        'Task outcomes',
        'How was the week?',
        'Your week',
      ]) {
        expect(top(find.text(title)), lessThan(feel), reason: title);
      }

      final chips = [
        for (final word in ['Focused', 'Calm', 'Tired', 'Proud'])
          find.byKey(ValueKey('weekly-feeling-word-$word')),
      ];
      for (final chip in chips) {
        await tester.ensureVisible(chip);
      }
      final rows = {for (final chip in chips) tester.getTopLeft(chip).dy};
      expect(rows.length, anyOf(1, 2), reason: 'never 3 + 1');
      final sizes = {for (final chip in chips) tester.getSize(chip).width};
      expect(sizes.length, 1, reason: 'equal-width cells');
      for (final chip in chips) {
        expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
      }

      // The four rating tiles are never clipped: each keeps its full label.
      for (var level = 1; level <= 4; level++) {
        expect(
          tester.getSize(find.byKey(ValueKey('weekly-mood-$level'))).height,
          greaterThanOrEqualTo(44),
        );
      }

      if (width >= 1600) {
        final mood = find.text('How was the week?');
        final left = tester.getTopLeft(find.text('What got in the way')).dx;
        expect(tester.getTopLeft(mood).dx, greaterThan(left));
        expect(
          top(find.text('What got in the way')),
          top(mood),
          reason: 'two columns share a top',
        );
        expect(
          tester.getTopLeft(find.text('Your week')).dx,
          tester.getTopLeft(mood).dx,
          reason: 'Your week sits under the rating',
        );
        expect(top(find.text('Your week')), greaterThan(top(mood)));
      } else if (width <= 700) {
        expect(
          top(find.text('How was the week?')),
          lessThan(top(find.text('Your week'))),
        );
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await settle(tester);
      await finish(tester, container);
    });
  }

  presetEditorTests();
}

void presetEditorTests() {
  for (final width in [360.0, 700.0, 1100.0, 1600.0]) {
    testWidgets('Edit presets opens and closes cleanly at $width dp', (
      tester,
    ) async {
      final container = await buildTestContainer(tester);
      appRouter.go('/review/weekly');
      await pumpApp(tester, container, surface: Size(width, 900));
      await settle(tester);

      final edit = find.byKey(const ValueKey('weekly-feeling-edit-presets'));
      final chip = find.byKey(const ValueKey('weekly-feeling-word-Focused'));
      await tester.ensureVisible(edit);
      await settle(tester);
      await tester.tap(edit);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Done'), findsOneWidget);
      expect(chip, findsOneWidget);

      // Four equal fields: one row, or 2 x 2.
      final fields = [
        for (var i = 0; i < 4; i++)
          find.byKey(ValueKey('weekly-feeling-preset-field-$i')),
      ];
      for (final f in fields) {
        await tester.ensureVisible(f);
      }
      expect(
        {for (final f in fields) tester.getTopLeft(f).dy}.length,
        anyOf(1, 2),
      );
      expect({for (final f in fields) tester.getSize(f).width}.length, 1);

      // An error message in one field must not overflow either.
      await tester.enterText(fields[1], 'focused');
      await settle(tester);
      expect(find.text('Already used.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Edit presets'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('weekly-feeling-preset-field-0')),
        findsNothing,
      );
      expect(chip, findsOneWidget);

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await settle(tester);
      await finish(tester, container);
    });
  }

  testWidgets('renaming a feel preset updates the chips at once', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/review/weekly');
    await pumpApp(tester, container, surface: const Size(1600, 900));
    await settle(tester);

    final edit = find.byKey(const ValueKey('weekly-feeling-edit-presets'));
    await tester.ensureVisible(edit);
    await settle(tester);
    await tester.tap(edit);
    await settle(tester);

    final field = find.byKey(const ValueKey('weekly-feeling-preset-field-1'));
    await tester.enterText(field, '12345678901234');
    await settle(tester);
    expect(
      find.byKey(const ValueKey('weekly-feeling-word-12345678901234')),
      findsOneWidget,
    );
    expect(find.text('Calm'), findsNothing);

    await tester.enterText(field, 'focused');
    await settle(tester);
    expect(find.text('Already used.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('weekly-feeling-word-12345678901234')),
      findsOneWidget,
      reason: 'an invalid edit is not stored',
    );
    expect(tester.takeException(), isNull);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
    await finish(tester, container);
  });
}
