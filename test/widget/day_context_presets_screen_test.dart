import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/day_context/domain/day_context_presets.dart';
import 'package:personal_planner/features/day_context/providers/day_context_presets_provider.dart';
import 'package:personal_planner/features/day_context/providers/day_context_providers.dart';

import '../helpers/test_container.dart';

void main() {
  Future<void> flush(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await settle(tester);
  }

  Future<ProviderContainer> pumpScreen(WidgetTester tester) async {
    final c = await buildTestContainer(tester);
    appRouter.go('/settings/day-contexts');
    await pumpApp(tester, c, surface: const Size(1200, 900));
    await flush(tester);
    return c;
  }

  List<DayContextPreset> presetsOf(ProviderContainer c) =>
      c.read(dayContextPresetsProvider).value!;

  testWidgets('Reset to defaults asks first; Cancel changes nothing', (
    tester,
  ) async {
    final c = await pumpScreen(tester);
    await tester.tap(find.byKey(const ValueKey('day-context-preset-delete-0')));
    await flush(tester);
    final afterDelete = presetsOf(c);
    expect(afterDelete.length, defaultDayContextPresets.length - 1);

    await tester.tap(find.byKey(const ValueKey('day-context-preset-reset')));
    await settle(tester);
    expect(find.text('Reset to defaults?'), findsOneWidget);
    expect(find.textContaining('stop counting as break days'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('day-context-preset-reset-cancel')),
    );
    await flush(tester);
    expect(find.text('Reset to defaults?'), findsNothing);
    expect(presetsOf(c), afterDelete);

    await tester.tap(find.byKey(const ValueKey('day-context-preset-reset')));
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('day-context-preset-reset-confirm')),
    );
    await flush(tester);
    expect(presetsOf(c), defaultDayContextPresets);
    await finish(tester, c);
  });

  testWidgets('Delete is instant with an Undo that restores the exact list', (
    tester,
  ) async {
    final c = await pumpScreen(tester);
    // Switch the second preset's Break on so the order and switches matter.
    await tester.tap(find.byKey(const ValueKey('day-context-preset-break-1')));
    await flush(tester);
    final before = presetsOf(c);
    expect(before[1].isBreak, isTrue);

    await tester.tap(find.byKey(const ValueKey('day-context-preset-delete-1')));
    await flush(tester);
    expect(presetsOf(c).length, before.length - 1);
    expect(find.text('Deleted ${before[1].name}'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await flush(tester);
    expect(presetsOf(c), before);
    await finish(tester, c);
  });

  testWidgets('the Undo bar goes away on its own after its duration', (
    tester,
  ) async {
    final c = await pumpScreen(tester);
    final name = presetsOf(c)[1].name;
    await tester.tap(find.byKey(const ValueKey('day-context-preset-delete-1')));
    await flush(tester);
    expect(find.text('Deleted $name'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Deleted $name'), findsNothing);
    expect(find.text('Undo'), findsNothing);
    await finish(tester, c);
  });

  testWidgets('Undo does nothing once the list changed since the delete', (
    tester,
  ) async {
    final c = await pumpScreen(tester);
    final before = presetsOf(c);
    await tester.tap(find.byKey(const ValueKey('day-context-preset-delete-1')));
    await flush(tester);
    await tester.tap(find.byKey(const ValueKey('day-context-preset-break-0')));
    await flush(tester);
    final changed = presetsOf(c);

    await tester.tap(find.text('Undo'));
    await flush(tester);
    expect(presetsOf(c), changed);
    expect(changed.length, before.length - 1);
    await finish(tester, c);
  });

  testWidgets('every row labels its Break switch', (tester) async {
    final c = await pumpScreen(tester);
    final presets = presetsOf(c);
    for (var i = 0; i < presets.length; i++) {
      final tile = find.byKey(ValueKey('day-context-preset-$i'));
      expect(
        find.descendant(of: tile, matching: find.text('Break day')),
        findsOneWidget,
        reason: presets[i].name,
      );
    }
    expect(find.bySemanticsLabel('Break day: Leave'), findsOneWidget);
    await finish(tester, c);
  });

  group('changes that reclassify past days ask first', () {
    // Defaults: 3 Leave (break), 4 Travel (not a break), 5 Rest Day (break).
    Future<ProviderContainer> pumpWithDays(
      WidgetTester tester,
      DayContextKind kind,
      int days,
    ) async {
      final c = await buildTestContainer(tester);
      await runDb(tester, () async {
        for (var i = 1; i <= days; i++) {
          await c
              .read(dayContextRepositoryProvider)
              .save('2026-09-0$i', kind, null);
        }
      });
      appRouter.go('/settings/day-contexts');
      await pumpApp(tester, c, surface: const Size(1200, 900));
      await flush(tester);
      return c;
    }

    Finder dialogButton(String label) => find.descendant(
      of: find.byType(AlertDialog).last,
      matching: find.text(label),
    );

    testWidgets('the Break switch shows the count; Cancel writes nothing', (
      tester,
    ) async {
      final c = await pumpWithDays(tester, DayContextKind.travel, 3);
      final before = presetsOf(c);
      await tester.tap(
        find.byKey(const ValueKey('day-context-preset-break-4')),
      );
      await flush(tester);
      expect(
        find.text('3 past days will count as break days.'),
        findsOneWidget,
      );

      await tester.tap(dialogButton('Cancel'));
      await flush(tester);
      expect(presetsOf(c), before);

      await tester.tap(
        find.byKey(const ValueKey('day-context-preset-break-4')),
      );
      await flush(tester);
      await tester.tap(dialogButton('Continue'));
      await flush(tester);
      expect(presetsOf(c)[4].isBreak, isTrue);
      await finish(tester, c);
    });

    testWidgets('switching a break preset off says the days stop counting', (
      tester,
    ) async {
      final c = await pumpWithDays(tester, DayContextKind.leave, 2);
      await tester.tap(
        find.byKey(const ValueKey('day-context-preset-break-3')),
      );
      await flush(tester);
      expect(
        find.text('2 past days will no longer count as break days.'),
        findsOneWidget,
      );
      await tester.tap(dialogButton('Continue'));
      await flush(tester);
      expect(presetsOf(c)[3].isBreak, isFalse);
      await finish(tester, c);
    });

    Future<void> rename(WidgetTester tester, int index, String name) async {
      await tester.tap(
        find.byKey(ValueKey('day-context-preset-rename-$index')),
      );
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey('day-context-preset-name')),
        name,
      );
      await tester.tap(find.byKey(const ValueKey('day-context-preset-save')));
      await flush(tester);
    }

    testWidgets('renaming a break preset asks; Cancel writes nothing', (
      tester,
    ) async {
      final c = await pumpWithDays(tester, DayContextKind.leave, 2);
      final before = presetsOf(c);
      await rename(tester, 3, 'Time off');
      expect(
        find.text('2 past days will no longer count as break days.'),
        findsOneWidget,
      );
      await tester.tap(dialogButton('Cancel'));
      await flush(tester);
      expect(presetsOf(c), before);
      await finish(tester, c);
    });

    testWidgets('renaming a non-break preset that days use does not ask', (
      tester,
    ) async {
      final c = await pumpWithDays(tester, DayContextKind.travel, 2);
      await rename(tester, 4, 'Trip');
      expect(find.byType(AlertDialog), findsNothing);
      expect(presetsOf(c)[4].name, 'Trip');
      await finish(tester, c);
    });

    testWidgets('deleting a break preset asks before it deletes', (
      tester,
    ) async {
      final c = await pumpWithDays(tester, DayContextKind.leave, 2);
      final before = presetsOf(c);
      await tester.tap(
        find.byKey(const ValueKey('day-context-preset-delete-3')),
      );
      await flush(tester);
      expect(
        find.text('2 past days will no longer count as break days.'),
        findsOneWidget,
      );
      await tester.tap(dialogButton('Cancel'));
      await flush(tester);
      expect(presetsOf(c), before);
      expect(find.text('Undo'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('day-context-preset-delete-3')),
      );
      await flush(tester);
      await tester.tap(dialogButton('Continue'));
      await flush(tester);
      expect(presetsOf(c).length, before.length - 1);
      expect(find.text('Undo'), findsOneWidget);
      await finish(tester, c);
    });
  });
}
