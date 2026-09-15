import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_planner/core/models/enums/priority.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/widgets/task_block_widget.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/task_editor/presentation/widgets/category_dropdown.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/timeline/domain/timeline_geometry.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';

import '../helpers/test_container.dart';

Task _task({
  String id = 'task',
  String title = 'A compact task',
  int durationMinutes = 60,
  DateTime? start,
}) {
  final taskStart = start ?? DateTime(2027, 3, 15, 10);
  return Task(
    id: id,
    title: title,
    startTime: taskStart,
    endTime: taskStart.add(Duration(minutes: durationMinutes)),
    createdAt: taskStart,
    updatedAt: taskStart,
  );
}

Widget _card(Task task, {double height = 80, String? subtaskCount}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 260,
            height: height,
            child: TaskBlockWidget(
              key: ValueKey(task.id),
              task: task,
              groupedSubtaskCount: subtaskCount,
              onTap: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('legacy task metadata still decodes safely', () {
    final json = _task(id: 'legacy').copyWith().toJson()
      ..['priority'] = 'high'
      ..['tags'] = ['legacy-tag'];

    final decoded = Task.fromJson(json);

    expect(decoded.title, 'A compact task');
    expect(decoded.priority.name, 'high');
  });

  test('adjacent short cards receive temporary visual lanes', () {
    final day = PlannerTimeZone.calendarDate(2027, 3, 15);
    final firstStart = PlannerTimeZone.calendarDate(2027, 3, 15, hour: 10);
    final first = _task(
      id: 'first-short',
      durationMinutes: 1,
      start: firstStart,
    );
    final second = _task(
      id: 'second-short',
      durationMinutes: 1,
      start: firstStart.add(const Duration(minutes: 1)),
    );
    final geometries = TimelineGeometry.layoutForDay(
      tasks: [first, second],
      date: day,
    );
    final lanes = TimelineGeometry.visualLanesForMinimumHeight(
      geometries: geometries,
      thresholdPx: TaskBlockWidget.compactHeightThreshold,
      minimumHeightPx: TaskBlockWidget.compactMinHeight,
    );
    expect(lanes['first-short']?.count, 2);
    expect(lanes['second-short']?.count, 2);
    expect(lanes['first-short']?.index, isNot(lanes['second-short']?.index));
  });

  testWidgets('normal cards separate subtask count and duration', (
    tester,
  ) async {
    await tester.pumpWidget(_card(_task(id: 'normal'), subtaskCount: '2/4'));

    final subtaskRect = tester.getRect(
      find.byKey(const ValueKey('subtask-count')),
    );
    final durationRect = tester.getRect(
      find.byKey(const ValueKey('task-duration-label')),
    );
    expect(subtaskRect.bottom, lessThanOrEqualTo(durationRect.top));
    expect(find.text('A compact task'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short cards keep one-line titles and compact subtask counts', (
    tester,
  ) async {
    for (final minutes in [60, 15, 5, 1]) {
      final task = _task(
        id: 'duration-$minutes',
        title: 'Task $minutes minutes',
        durationMinutes: minutes,
      );
      await tester.pumpWidget(
        _card(task, height: minutes == 60 ? 80 : 28, subtaskCount: '1/2'),
      );

      expect(find.text('Task $minutes minutes'), findsOneWidget);
      final title = tester.widget<Text>(find.text('Task $minutes minutes'));
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(find.byKey(const ValueKey('subtask-count')), findsOneWidget);
      if (minutes == 60) {
        expect(
          find.byKey(const ValueKey('task-duration-label')),
          findsOneWidget,
        );
      } else {
        expect(find.byKey(const ValueKey('task-duration-label')), findsNothing);
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('compact cards keep the existing tap callback', (tester) async {
    var taps = 0;
    final task = _task(id: 'tap-task', durationMinutes: 1);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 28,
              child: TaskBlockWidget(
                key: const ValueKey('compact-tap-card'),
                task: task,
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('compact-tap-card')));
    expect(taps, 1);
  });

  testWidgets(
    'editor keeps category and status while hiding retired metadata',
    (tester) async {
      final container = await buildTestContainer(tester);
      final day = DateTime(2027, 3, 15);
      final task = await runDb(
        tester,
        () => container
            .read(taskRepositoryProvider)
            .insertTask(
              _task(
                id: 'editor-task',
                title: 'Editable task',
                start: day.add(const Duration(hours: 9)),
              ).copyWith(priority: Priority.high),
            ),
      );
      container.read(selectedDateProvider.notifier).state = day;
      container.read(selectedTaskIdProvider.notifier).state = task.id;
      container.read(taskEditorOpenProvider.notifier).state = true;
      appRouter.go('/day');
      await pumpApp(tester, container, surface: const Size(1400, 1000));

      expect(find.byType(CategoryDropdown), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField &&
              widget.decoration.labelText == 'Status',
        ),
        findsOneWidget,
      );
      expect(find.text('Priority'), findsNothing);
      expect(find.text('Tags'), findsNothing);

      final description = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Description',
      );
      await tester.enterText(description, 'Saved description');
      await tester.tap(find.byKey(const ValueKey('save-task-button')));
      await settle(tester);

      final saved = await runDb(
        tester,
        () => container.read(taskRepositoryProvider).getTaskById(task.id),
      );
      expect(saved?.description, 'Saved description');
      expect(saved?.priority, Priority.high);
      await finish(tester, container);
    },
  );
}
