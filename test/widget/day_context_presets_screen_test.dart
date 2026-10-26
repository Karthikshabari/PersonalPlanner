import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/day_context/domain/day_context_presets.dart';
import 'package:personal_planner/features/day_context/providers/day_context_presets_provider.dart';

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
}
