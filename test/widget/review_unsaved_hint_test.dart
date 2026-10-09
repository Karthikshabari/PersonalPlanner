import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../helpers/test_container.dart';

/// B5: the "Not saved yet" hint must be visible whenever mood, note or a
/// reason differs from what is saved, in the wide and the narrow layout, also
/// while a reason far from the Save button is still being typed. It lives in
/// the always-visible bottom save bar, so it is on screen wherever the page
/// is scrolled.
void main() {
  final hint = find.byKey(const ValueKey('review-unsaved-hint'));
  final save = find.byKey(const ValueKey('review-save'));

  Future<(ProviderContainer, List<Finder>)> pumpToday(
    WidgetTester tester,
    Size surface, {
    int tasks = 8,
  }) async {
    final container = await buildTestContainer(tester);
    final now = DateTime.now();
    for (var i = 0; i < tasks; i++) {
      final start = DateTime(now.year, now.month, now.day, 6 + i);
      await runDb(
        tester,
        () => container
            .read(taskRepositoryProvider)
            .insertTask(
              Task(
                id: '',
                title: 'Task $i',
                startTime: start,
                endTime: start.add(const Duration(minutes: 50)),
                createdAt: now,
                updatedAt: now,
              ),
            ),
      );
    }
    final rows = await runDb(
      tester,
      () => container
          .read(appDatabaseProvider)
          .taskDao
          .getTasksBetween(
            DateTime(now.year, now.month, now.day),
            DateTime(now.year, now.month, now.day + 1),
          ),
    );
    appRouter.go('/review');
    await pumpApp(tester, container, surface: surface);
    return (
      container,
      [
        for (final row in rows)
          find.byKey(
            ValueKey('review-reason-${TaskRepository.fromRow(row).id}'),
          ),
      ],
    );
  }

  void expectOnScreen(WidgetTester tester, Finder f, Size surface) {
    final rect = tester.getRect(f);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(surface.height));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(surface.width));
  }

  for (final (name, surface) in [
    ('wide', const Size(1400, 700)),
    ('narrow', const Size(420, 800)),
  ]) {
    group('$name layout', () {
      testWidgets('typing a reason shows the hint while still focused', (
        tester,
      ) async {
        final (container, fields) = await pumpToday(tester, surface, tasks: 1);
        expect(hint, findsNothing);

        await tester.ensureVisible(fields.single);
        await tester.tap(fields.single);
        await tester.enterText(fields.single, 'Meeting ran long');
        await settle(tester);

        expect(hint, findsOneWidget);
        expect(find.text('Save review'), findsOneWidget);
        expect(find.text('Saved'), findsNothing);
        await finish(tester, container);
      });

      testWidgets('the hint is on screen while typing the last of 8 tasks', (
        tester,
      ) async {
        final (container, fields) = await pumpToday(tester, surface);
        await tester.ensureVisible(fields.last);
        await settle(tester);
        await tester.enterText(fields.last, 'Late reason');
        await settle(tester);

        expectOnScreen(tester, fields.last, surface);
        expectOnScreen(tester, hint, surface);
        expect(find.text('Save review'), findsOneWidget);
        await finish(tester, container);
      });

      testWidgets('a restored draft shows the hint when you come back', (
        tester,
      ) async {
        final (container, fields) = await pumpToday(tester, surface, tasks: 2);
        await tester.enterText(fields.first, 'Early reason');
        await settle(tester);

        appRouter.go('/review/weekly');
        await settle(tester);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await settle(tester);
        appRouter.go('/review');
        await settle(tester);

        expect(hint, findsOneWidget);
        expectOnScreen(tester, hint, surface);
        expect(find.text('Save review'), findsOneWidget);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await finish(tester, container);
      });

      testWidgets('mood or note changes show it too', (tester) async {
        final (container, _) = await pumpToday(tester, surface, tasks: 1);
        await tester.ensureVisible(find.byKey(const ValueKey('review-mood-3')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('review-mood-3')));
        await settle(tester);
        expect(hint, findsOneWidget);

        await tester.ensureVisible(find.byKey(const ValueKey('review-mood-1')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('review-mood-1')));
        await settle(tester);
        expect(hint, findsNothing);

        await tester.enterText(find.byKey(const ValueKey('review-note')), 'x');
        await settle(tester);
        expect(hint, findsOneWidget);
        await finish(tester, container);
      });

      testWidgets('reverting the reason removes the hint', (tester) async {
        final (container, fields) = await pumpToday(tester, surface, tasks: 1);
        await tester.ensureVisible(fields.single);
        await tester.enterText(fields.single, 'Meeting ran long');
        await settle(tester);
        expect(hint, findsOneWidget);

        await tester.enterText(fields.single, '');
        await settle(tester);
        expect(hint, findsNothing);
        await finish(tester, container);
      });

      testWidgets('the hint disappears after a successful save', (
        tester,
      ) async {
        final (container, fields) = await pumpToday(tester, surface, tasks: 1);
        await tester.ensureVisible(fields.single);
        await tester.enterText(fields.single, 'Meeting ran long');
        await settle(tester);
        expect(hint, findsOneWidget);

        await tester.ensureVisible(save);
        await tester.pump();
        // Clear the bottom navigation bar of the narrow layout.
        await tester.drag(find.byType(ListView).first, const Offset(0, -150));
        await tester.pump();
        await tester.tap(save);
        await settle(tester);

        expect(hint, findsNothing);
        expect(find.text('Saved'), findsOneWidget);
        await finish(tester, container);
      });
    });
  }

  testWidgets('the hint does not collide with the Ctrl + Enter hint', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final (container, fields) = await pumpToday(
      tester,
      const Size(1100, 900),
      tasks: 1,
    );
    await tester.enterText(fields.single, 'Meeting ran long');
    await settle(tester);

    expect(find.text('Ctrl + Enter'), findsOneWidget);
    expect(
      tester.getRect(hint).overlaps(tester.getRect(find.text('Ctrl + Enter'))),
      isFalse,
    );
    await finish(tester, container);
  });

  testWidgets('the bar hint is neutral and ignores pointers', (
    tester,
  ) async {
    final (container, fields) = await pumpToday(
      tester,
      const Size(1400, 900),
      tasks: 1,
    );
    await tester.enterText(fields.single, 'Meeting ran long');
    await settle(tester);

    final text = tester.widget<Text>(
      find.descendant(of: hint, matching: find.text('Not saved yet')),
    );
    final theme = Theme.of(tester.element(hint));
    expect(text.style?.color, isNot(theme.colorScheme.error));
    expect(
      find.descendant(of: hint, matching: find.byType(IgnorePointer)),
      findsWidgets,
    );
    await finish(tester, container);
  });
}
