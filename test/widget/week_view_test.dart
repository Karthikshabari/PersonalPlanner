import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/theme/app_colors.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';

import '../helpers/test_container.dart';

void main() {
  Future<ProviderContainer> pumpDay(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final container = await buildTestContainer(tester);
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    return container;
  }

  DateTime monday() => startOfWeek(DateTime.now());

  Future<void> seedWeekTasks(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final categories = await runDb(
      tester,
      () =>
          container.read(appDatabaseProvider).categoryDao.getActiveCategories(),
    );
    final work = categories.firstWhere((c) => c.name == 'Work');
    final tasks = container.read(taskRepositoryProvider);
    final mon = monday();

    Future<void> insert(
      int dayOffset,
      int hour,
      String title,
      TaskStatus status,
    ) async {
      final start = DateTime(mon.year, mon.month, mon.day + dayOffset, hour);
      await runDb(
        tester,
        () => tasks.insertTask(
          Task(
            id: '',
            title: title,
            startTime: start,
            endTime: start.add(const Duration(hours: 1)),
            status: status,
            categoryId: work.id,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        ),
      );
    }

    // Monday has two blocks (one completed → "1/2"), Tuesday one.
    await insert(0, 9, 'Alpha', TaskStatus.completed);
    await insert(0, 10, 'Beta', TaskStatus.planned);
    await insert(1, 14, 'Gamma', TaskStatus.planned);
  }

  Future<void> openWeekView(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await settle(tester);
  }

  Finder weekColumn(String iso) => find.byKey(ValueKey('week-column-$iso'));

  testWidgets('W opens the Week View with seven day columns', (tester) async {
    final container = await pumpDay(tester);
    await seedWeekTasks(tester, container);
    await openWeekView(tester);

    expect(find.text('This Week'), findsOneWidget);
    for (var i = 0; i < 7; i++) {
      expect(
        weekColumn(isoDateString(monday().add(Duration(days: i)))),
        findsOneWidget,
      );
    }
    // Today's column is highlighted exactly once.
    expect(find.byKey(const ValueKey('week-today-marker')), findsOneWidget);

    // Compact blocks render title-only.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);

    // Completion counts in headers ("Mon d • done/total").
    expect(
      find.byKey(ValueKey('day-count-${isoDateString(monday())}')),
      findsOneWidget,
    );
    expect(find.text('1/2'), findsOneWidget);
    expect(
      find.byKey(
        ValueKey(
          'day-count-${isoDateString(monday().add(const Duration(days: 1)))}',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('0/1'), findsOneWidget);

    // Blocks are color-coded by category (Work #4285F4 left border).
    final blockFinder = find.ancestor(
      of: find.text('Alpha'),
      matching: find.byWidgetPredicate((w) => w is Container),
    );
    final decoration =
        tester.widget<Container>(blockFinder.first).decoration as BoxDecoration;
    expect(decoration.border, isA<Border>());
    expect(
      (decoration.border as Border).left.color,
      AppColors.parseHex('#4285F4'),
    );
    await finish(tester, container);
  });

  testWidgets('Day to Week keeps the selected day in view', (tester) async {
    final container = await pumpDay(tester);
    final selected = addDays(monday(), 4);
    container.read(selectedDateProvider.notifier).state = selected;
    await settle(tester);

    await openWeekView(tester);

    expect(container.read(selectedWeekStartProvider), monday());
    expect(find.text('This Week'), findsOneWidget);
    expect(
      find.byKey(ValueKey('week-column-${isoDateString(selected)}')),
      findsOneWidget,
    );
    await finish(tester, container);
  });

  testWidgets('tapping a day column navigates to its Day View', (tester) async {
    final container = await pumpDay(tester);
    await seedWeekTasks(tester, container);
    await openWeekView(tester);

    final tuesday = monday().add(const Duration(days: 1));
    await tester.tap(weekColumn(isoDateString(tuesday)));
    await settle(tester);

    expect(
      find.text(DateFormat('MMM d, yyyy').format(tuesday)),
      findsOneWidget,
    );
    expect(isSameDay(container.read(selectedDateProvider), tuesday), isTrue);
    await finish(tester, container);
  });

  testWidgets('W toggles back to Day View and week navigation works', (
    tester,
  ) async {
    final container = await pumpDay(tester);
    await openWeekView(tester);
    expect(find.text('This Week'), findsOneWidget);

    // W toggles back to Day.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await settle(tester);
    expect(find.text('This Week'), findsNothing);

    // Back to week; navigate weeks and return with This Week.
    await openWeekView(tester);
    final current = container.read(selectedWeekStartProvider);
    await tester.tap(find.byKey(const ValueKey('weekview-next')));
    await settle(tester);
    expect(
      container.read(selectedWeekStartProvider),
      current.add(const Duration(days: 7)),
    );
    await tester.tap(find.byKey(const ValueKey('weekview-prev')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('weekview-this-week')));
    await settle(tester);
    expect(container.read(selectedWeekStartProvider), monday());
    await finish(tester, container);
  });

  testWidgets('Ctrl+R opens the Daily Review from the Day View', (
    tester,
  ) async {
    final container = await pumpDay(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
    await settle(tester);

    expect(find.text('Daily Review'), findsOneWidget);
    await finish(tester, container);
  });
}
