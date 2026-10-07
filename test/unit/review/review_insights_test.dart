import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/domain/review_insights.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late TaskRepository tasks;
  late DateTime day;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
    day = startOfDay(DateTime.now().subtract(const Duration(days: 1)));
  });

  tearDown(() => db.close());

  test('derives final meaningful changes and next-day carryover', () async {
    final originalId = '00000000-0000-7000-8000-000000000201';
    final targetId = '00000000-0000-7000-8000-000000000202';
    await tasks.insertTask(
      Task(
        id: targetId,
        title: 'Backend development',
        startTime: addDays(day, 1).add(const Duration(hours: 10)),
        endTime: addDays(day, 1).add(const Duration(hours: 11)),
        createdAt: day,
        updatedAt: day,
      ),
    );
    await tasks.insertTask(
      Task(
        id: originalId,
        title: 'Backend development',
        startTime: day.add(const Duration(hours: 9)),
        endTime: day.add(const Duration(hours: 10)),
        status: TaskStatus.rescheduled,
        rescheduledToId: targetId,
        createdAt: day.subtract(const Duration(days: 2)),
        updatedAt: day,
      ),
    );
    final target = await db.taskDao.getTaskById(targetId);
    await tasks.updateTask(
      TaskRepository.fromRow(target!).copyWith(rescheduledFromId: originalId),
      allowRescheduledTransition: true,
    );
    await tasks.insertTask(
      Task(
        id: '00000000-0000-7000-8000-000000000203',
        title: 'Documentation',
        startTime: day.add(const Duration(hours: 13)),
        endTime: day.add(const Duration(hours: 14)),
        status: TaskStatus.completed,
        actualDurationMin: 90,
        manualActualSet: true,
        manualDurationAdjustmentMin: 90,
        createdAt: day.add(const Duration(hours: 2)),
        updatedAt: day,
      ),
    );

    final insights = await ReviewInsightsService(db).forDay(day);

    expect(
      insights.changes.map((change) => change.detail),
      containsAll(<String>[
        'Moved → Tomorrow · 10:00 AM',
        '1h planned → 1h 30m tracked',
      ]),
    );
    expect(
      insights.changes.map((c) => c.detail),
      isNot(contains('Added during the day')),
    );
    expect(
      insights.changes.where((change) => change.kind == ReviewChangeKind.moved),
      hasLength(1),
    );
    expect(insights.carryover, hasLength(1));
    expect(insights.carryover.single.title, 'Backend development');
  });

  Future<Task> insertSample6(String id) async {
    await tasks.insertTask(
      Task(
        id: id,
        title: 'sample 6',
        startTime: day.add(const Duration(hours: 14)),
        endTime: day.add(const Duration(hours: 15)),
        createdAt: day.add(const Duration(hours: 1)),
        updatedAt: day.add(const Duration(hours: 1)),
      ),
    );
    return TaskRepository.fromRow((await db.taskDao.getTaskById(id))!);
  }

  test(
    'a preserved title change is reported as a plan change, not as added',
    () async {
      const id = '00000000-0000-7000-8000-0000000002a0';
      final current = await insertSample6(id);
      final event = PlanTitleChange(
        id: '00000000-0000-7000-8000-0000000002a1',
        previousTitle: 'sample 6',
        newTitle: 'sample 06',
        changedAt: DateTime.now().toUtc(),
      );
      await tasks.updateTask(
        current.copyWith(
          title: 'sample 06',
          planTitleHistory: [event],
          displayPlanChangeId: event.id,
        ),
      );

      final insights = await ReviewInsightsService(db).forDay(day);

      expect(insights.changes, hasLength(1));
      final change = insights.changes.single;
      expect(change.kind, ReviewChangeKind.planChanged);
      expect(change.taskTitle, 'sample 06');
      expect(change.detail, 'Plan changed from “sample 6”');
      expect(
        insights.changes.map((c) => c.detail),
        isNot(contains('Added during the day')),
      );
    },
  );

  test('a replaced title change is not reported', () async {
    const id = '00000000-0000-7000-8000-0000000002a0';
    final current = await insertSample6(id);
    await tasks.updateTask(
      current.copyWith(
        title: 'sample 06',
        planTitleHistory: const [],
        displayPlanChangeId: null,
      ),
    );

    final insights = await ReviewInsightsService(db).forDay(day);

    expect(
      insights.changes.where((c) => c.kind == ReviewChangeKind.planChanged),
      isEmpty,
    );
  });

  group('weekly changes', () {
    late DateTime week;

    DateTime at(int dayOffset, int hour) =>
        addDays(week, dayOffset).add(Duration(hours: hour));

    Future<void> seedSixTasks() async {
      week = addDays(startOfWeek(DateTime.now()), -7);
      const reportId = '00000000-0000-7000-8000-0000000003a1';
      const gymId = '00000000-0000-7000-8000-0000000003a2';
      const originalId = '00000000-0000-7000-8000-0000000003a3';
      const successorId = '00000000-0000-7000-8000-0000000003a4';
      const docsId = '00000000-0000-7000-8000-0000000003a5';
      const sprintId = '00000000-0000-7000-8000-0000000003a6';
      Task task(
        String id,
        String title,
        int dayOffset, {
        TaskStatus status = TaskStatus.planned,
      }) => Task(
        id: id,
        title: title,
        startTime: at(dayOffset, 9),
        endTime: at(dayOffset, 10),
        status: status,
        createdAt: at(dayOffset, 1),
        updatedAt: at(dayOffset, 1),
      );

      await tasks.insertTask(
        task(reportId, 'Write report', 0, status: TaskStatus.completed),
      );
      await tasks.insertTask(
        task(gymId, 'Gym session', 1, status: TaskStatus.skipped),
      );
      await tasks.insertTask(task(successorId, 'Refactor sync tests', 3));
      final event = PlanTitleChange(
        id: '00000000-0000-7000-8000-0000000003b1',
        previousTitle: 'Refactor tests',
        newTitle: 'Refactor sync tests',
        changedAt: at(2, 2).toUtc(),
      );
      await tasks.insertTask(
        task(
          originalId,
          'Refactor sync tests',
          2,
          status: TaskStatus.rescheduled,
        ).copyWith(
          rescheduledToId: successorId,
          planTitleHistory: [event],
          displayPlanChangeId: event.id,
        ),
      );
      final successor = await db.taskDao.getTaskById(successorId);
      await tasks.updateTask(
        TaskRepository.fromRow(successor!)
            .copyWith(rescheduledFromId: originalId),
        allowRescheduledTransition: true,
      );
      await tasks.insertTask(task(docsId, 'Read docs', 4));
      await tasks.insertTask(task(sprintId, 'Plan sprint', 5));
    }

    test('six tasks give one row per changed task, with the plan change and '
        'no "Added during the week" (was 8 rows before the fix)', () async {
      await seedSixTasks();

      final insights = await ReviewInsightsService(db).forWeek(week);
      final titles = insights.changes.map((c) => c.taskTitle).toList();

      expect(insights.changes, hasLength(2));
      expect(titles.toSet(), hasLength(titles.length));
      expect(titles, ['Gym session', 'Refactor sync tests']);
      expect(insights.changes.first.detail, 'Skipped');
      final refactor = insights.changes.last;
      expect(refactor.kind, ReviewChangeKind.moved);
      expect(refactor.detail, startsWith('Moved → '));
      expect(
        refactor.detail,
        endsWith(' · Plan changed from “Refactor tests”'),
      );
      expect(
        insights.changes.map((c) => c.detail).join('\n'),
        isNot(contains('Added during the week')),
      );
    });
  });

  test('returns no changes for an unchanged empty day', () async {
    final insights = await ReviewInsightsService(db).forDay(day);
    expect(insights.changes, isEmpty);
    expect(insights.carryover, isEmpty);
  });
}
