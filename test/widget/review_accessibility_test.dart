import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/theme/app_theme_tokens.dart';
import 'package:personal_planner/core/theme/theme_mode_provider.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/day_context/providers/day_context_providers.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../helpers/test_container.dart';

void main() {
  DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  String longTitle(int i) =>
      'Task $i ${'long title words ' * 4}'.substring(0, 60);

  /// Four tasks with 60-character titles: one with a plan change and one with
  /// tracked time. Starts 06:00-09:00 so they sit in the past or the future
  /// without mattering to the Daily list.
  Future<void> seedTasks(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final repo = container.read(taskRepositoryProvider);
    final day = today();
    for (var i = 0; i < 4; i++) {
      final start = DateTime(day.year, day.month, day.day, 6 + i * 2);
      await runDb(
        tester,
        () => repo.insertTask(
          Task(
            id: '',
            title: longTitle(i),
            startTime: start,
            endTime: start.add(const Duration(hours: 1)),
            actualDurationMin: i == 3 ? 25 : null,
            manualDurationAdjustmentMin: i == 3 ? 25 : 0,
            manualActualSet: i == 3,
            createdAt: start,
            updatedAt: start,
          ),
        ),
      );
    }
    final rows = await runDb(
      tester,
      () => container
          .read(appDatabaseProvider)
          .taskDao
          .getTasksBetween(day, addDays(day, 1)),
    );
    final first = rows.firstWhere((r) => r.title == longTitle(0));
    final event = PlanTitleChange(
      id: '00000000-0000-7000-8000-0000000003f2',
      previousTitle: 'Older version of the first long task title',
      newTitle: first.title,
      changedAt: DateTime.now().toUtc(),
    );
    final current = await runDb(tester, () => repo.getTaskById(first.id));
    await runDb(
      tester,
      () => repo.updateTask(
        current!.copyWith(
          planTitleHistory: [event],
          displayPlanChangeId: event.id,
        ),
      ),
    );
  }

  Future<ProviderContainer> pumpAt(
    WidgetTester tester,
    String path,
    Size surface, {
    double textScale = 1.0,
    bool seed = true,
  }) async {
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    final container = await buildTestContainer(tester);
    if (seed) await seedTasks(tester, container);
    appRouter.go(path);
    await pumpApp(tester, container, surface: surface);
    return container;
  }

  // Disposing a reactive-stats provider mid-test starts an async onCancel in
  // the FakeAsync zone; give it real time so database.close() in finish() does
  // not hang.
  Future<void> drainDisposedStreams(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
  }

  /// Scrolls the first list through its full extent, asserting after every
  /// pump that layout threw nothing (an overflow is a reported exception).
  Future<void> scrollThrough(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 8; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: 'after scroll step $i');
    }
  }

  for (final (name, surface) in [
    ('360 dp', const Size(360, 800)),
    ('1920 px', const Size(1920, 1080)),
    ('760 dp (two columns)', const Size(760, 900)),
    ('759 dp (one column)', const Size(759, 900)),
  ]) {
    testWidgets('daily tab has no overflow at $name and text scale 1.3', (
      tester,
    ) async {
      final container = await pumpAt(
        tester,
        '/review',
        surface,
        textScale: 1.3,
      );
      expect(find.text('Task outcomes'), findsOneWidget);

      await scrollThrough(tester);
      await finish(tester, container);
    });
  }

  testWidgets('overview has no overflow at 360 dp and text scale 1.3', (
    tester,
  ) async {
    final container = await pumpAt(
      tester,
      '/review/overview',
      const Size(360, 800),
      textScale: 1.3,
    );
    final day = today();
    await runDb(
      tester,
      () => container
          .read(dayContextRepositoryProvider)
          .save(isoDateString(day), DayContextKind.travel, null),
    );
    await settle(tester);

    expect(find.byKey(const ValueKey('overview-strip')), findsOneWidget);
    expect(find.text('Not reviewed'), findsWidgets);
    expect(find.text('Travel'), findsWidgets);
    expect(tester.takeException(), isNull);
    await scrollThrough(tester);
    await finish(tester, container);
  });

  for (final (name, surface) in [
    ('360 dp', const Size(360, 800)),
    ('760 dp (two columns)', const Size(760, 900)),
  ]) {
    testWidgets('weekly tab has no overflow at $name and text scale 1.3', (
      tester,
    ) async {
      final container = await pumpAt(
        tester,
        '/review/weekly',
        surface,
        textScale: 1.3,
      );
      expect(find.text('Week at a glance'), findsOneWidget);
      await scrollThrough(tester);

      // Back to the top, where the sub-tabs are.
      await tester.drag(find.byType(ListView).first, const Offset(0, 4000));
      await tester.pump(const Duration(milliseconds: 400));
      // The wide test font makes this tab wider than the phone; tap its start.
      await tester.tapAt(
        tester.getTopLeft(find.text('Next week (optional)')) +
            const Offset(8, 8),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('A note for next week'), findsOneWidget);
      await drainDisposedStreams(tester);
      await finish(tester, container);
    });
  }

  testWidgets('mood options expose radio semantics and are at least 44x44', (
    tester,
  ) async {
    final container = await pumpAt(tester, '/review', const Size(1400, 1400));
    final handle = tester.ensureSemantics();

    final option = find.byKey(const ValueKey('review-mood-1'));
    expect(
      tester.getSemantics(option),
      isSemantics(
        label: 'Good',
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
        isButton: true,
      ),
    );
    for (var level = 1; level <= 4; level++) {
      final size = tester.getSize(find.byKey(ValueKey('review-mood-$level')));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    handle.dispose();
    await finish(tester, container);
  });

  testWidgets('keyboard focus is visible on mood options', (tester) async {
    final container = await pumpAt(tester, '/review', const Size(1400, 1400));

    double? focusedBorderWidth() {
      for (var level = 1; level <= 4; level++) {
        final decoration = tester
            .widget<AnimatedContainer>(
              find.descendant(
                of: find.byKey(ValueKey('review-mood-$level')),
                matching: find.byType(AnimatedContainer),
              ),
            )
            .decoration;
        final border = (decoration as BoxDecoration).border! as Border;
        if (border.top.width == 2) return border.top.width;
      }
      return null;
    }

    expect(focusedBorderWidth(), isNull);
    double? width;
    for (var i = 0; i < 120 && width == null; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump(const Duration(milliseconds: 200));
      width = focusedBorderWidth();
    }
    expect(width, 2, reason: 'Tab never reached a mood option');
    await finish(tester, container);
  });

  testWidgets('missing reasons and Not reviewed use no warning/error colour', (
    tester,
  ) async {
    final container = await pumpAt(tester, '/review', const Size(1400, 1400));

    final forbidden = {
      AppThemeTokens.dark().error,
      AppThemeTokens.dark().warning,
      AppThemeTokens.light().error,
      AppThemeTokens.light().warning,
    };
    final counter = tester.widget<Text>(
      find.byKey(const ValueKey('review-reason-counter')),
    );
    expect(counter.data, contains('without a reason'));
    expect(forbidden, isNot(contains(counter.style?.color)));

    final chipText = tester.widget<Text>(find.text('Not reviewed').first);
    expect(chipText.style?.color, isNotNull);
    expect(forbidden, isNot(contains(chipText.style?.color)));
    await finish(tester, container);
  });

  testWidgets('light theme renders the Daily tab and Overview', (tester) async {
    final container = await pumpAt(tester, '/review', const Size(1400, 1400));
    await runDb(
      tester,
      () => container.read(themeModeProvider.notifier).setMode(ThemeMode.light),
    );
    await settle(tester);
    expect(
      Theme.of(tester.element(find.text('Task outcomes'))).brightness,
      Brightness.light,
    );
    expect(tester.takeException(), isNull);
    await scrollThrough(tester);

    container.read(selectedReviewDateProvider.notifier).state = today();
    appRouter.go('/review/overview');
    await settle(tester);
    expect(find.byKey(const ValueKey('overview-strip')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });
}
