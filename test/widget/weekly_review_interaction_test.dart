import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';

import '../helpers/test_container.dart';

void main() {
  testWidgets('Tab order follows the reading order', (tester) async {
    final container = await buildTestContainer(tester);
    appRouter.go('/review/weekly');
    await pumpApp(tester, container, surface: const Size(1600, 1100));
    await settle(tester);

    final order = <Finder>[
      find.byKey(const ValueKey('weekly-mood-1')),
      find.byKey(const ValueKey('weekly-feeling-word-Focused')),
      find.byKey(const ValueKey('weekly-feeling-edit-presets')),
      find.byKey(const ValueKey('weekly-feeling')),
      find.byKey(const ValueKey('weekly-save')),
    ];
    // Reading order on the page: tiles, then chips, then the edit button,
    // then the note field, then Save (the bar below the list).
    FocusNode? focused() => FocusManager.instance.primaryFocus;

    // Focus the first tile, then walk Tab and record which target is hit.
    final tile = tester.element(order.first);
    Focus.of(tile).requestFocus();
    await tester.pump();

    final hit = <int>[];
    for (var step = 0; step < 40 && hit.length < order.length; step++) {
      final node = focused();
      if (node?.context != null) {
        for (var i = 0; i < order.length; i++) {
          if (order[i].evaluate().isEmpty) continue;
          final target = order[i].evaluate().first;
          final isInside =
              node!.context == target ||
              _isAncestor(target, node.context! as Element) ||
              _isAncestor(node.context! as Element, target);
          if (isInside && (hit.isEmpty || hit.last != i)) hit.add(i);
        }
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(hit, orderedEquals([...hit]..sort()), reason: 'Tab goes forward');
    expect(hit.toSet().length, greaterThanOrEqualTo(4));

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
    await finish(tester, container);
  });

  testWidgets(
    'Show all expands Task outcomes in place and Show less folds it',
    (tester) async {
      final container = await buildTestContainer(tester);
      final week = startOfWeek(DateTime.now());
      await tester.runAsync(() async {
        for (var i = 0; i < 6; i++) {
          final start = addDays(week, 0).add(Duration(hours: 8 + i));
          await container
              .read(taskRepositoryProvider)
              .insertTask(
                Task(
                  id: '',
                  title: 'Skipped task $i',
                  startTime: start,
                  endTime: start.add(const Duration(minutes: 30)),
                  status: TaskStatus.skipped,
                  createdAt: start,
                  updatedAt: start,
                ),
              );
        }
      });
      appRouter.go('/review/weekly');
      await pumpApp(tester, container, surface: const Size(1600, 1000));
      await settle(tester);

      final button = find.byKey(const ValueKey('weekly-outcomes-show-all'));
      expect(button, findsOneWidget);
      expect(find.textContaining('Skipped task'), findsNWidgets(4));
      await tester.ensureVisible(button);
      await settle(tester);
      await tester.tap(find.text('Show all 6'));
      await settle(tester);
      expect(find.textContaining('Skipped task'), findsNWidgets(6));
      expect(find.text('Show less'), findsOneWidget);
      await tester.tap(find.text('Show less'));
      await settle(tester);
      expect(find.textContaining('Skipped task'), findsNWidgets(4));
      expect(tester.takeException(), isNull);

      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await settle(tester);
      await finish(tester, container);
    },
  );
}

bool _isAncestor(Element ancestor, Element descendant) {
  var found = false;
  descendant.visitAncestorElements((e) {
    if (e == ancestor) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}
