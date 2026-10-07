import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';
import 'package:personal_planner/features/review/domain/task_outcome_service.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late TaskRepository tasks;
  late DateTime day;

  String id(int n) => '00000000-0000-7000-8000-0000000003${n.toString().padLeft(2, '0')}';

  Task make(
    int n,
    String title,
    int hour, {
    TaskStatus status = TaskStatus.planned,
    int? actual,
    String? rescheduledToId,
    DateTime? start,
    DateTime? end,
  }) => Task(
    id: id(n),
    title: title,
    startTime: start ?? day.add(Duration(hours: hour)),
    endTime: end ?? day.add(Duration(hours: hour + 1)),
    status: status,
    actualDurationMin: actual,
    manualActualSet: actual != null,
    manualDurationAdjustmentMin: actual ?? 0,
    rescheduledToId: rescheduledToId,
    createdAt: day,
    updatedAt: day,
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
    day = startOfDay(DateTime.now().subtract(const Duration(days: 1)));
  });

  tearDown(() => db.close());

  test('builds one ordered row per task starting on the day', () async {
    final targetId = id(50);
    await tasks.insertTask(
      make(
        50,
        'Moved target',
        10,
        start: addDays(day, 1).add(const Duration(hours: 10)),
        end: addDays(day, 1).add(const Duration(hours: 11)),
      ),
    );
    await tasks.insertTask(make(1, 'A done', 8, status: TaskStatus.completed));
    await tasks.insertTask(make(2, 'B partly', 9, actual: 45));
    await tasks.insertTask(make(3, 'C skipped', 10, status: TaskStatus.skipped));
    await tasks.insertTask(
      make(
        4,
        'D moved',
        11,
        status: TaskStatus.rescheduled,
        rescheduledToId: targetId,
      ),
    );
    await tasks.insertTask(make(5, 'E planned', 12));
    // Starts the previous evening and ends on the day: excluded.
    await tasks.insertTask(
      make(
        6,
        'Overnight',
        0,
        start: day.subtract(const Duration(hours: 1)),
        end: day.add(const Duration(hours: 1)),
      ),
    );
    // Soft-deleted: excluded.
    await tasks.insertTask(make(7, 'Deleted', 13));
    final deleted = TaskRepository.fromRow((await db.taskDao.getTaskById(id(7)))!);
    await tasks.updateTask(
      deleted.copyWith(deletedAt: DateTime.now()),
      allowStatusTransition: true,
    );
    // Inbox: excluded.
    await tasks.insertTask(
      Task(
        id: id(8),
        title: 'Inbox item',
        isInbox: true,
        createdAt: day,
        updatedAt: day,
      ),
    );

    final rows = await TaskOutcomeService(db).forDay(day);

    expect(rows.map((r) => r.title), [
      'A done',
      'B partly',
      'C skipped',
      'D moved',
      'E planned',
    ]);
    expect(rows.map((r) => r.outcome), [
      TaskOutcome.completed,
      TaskOutcome.partlyDone,
      TaskOutcome.skipped,
      TaskOutcome.rescheduled,
      TaskOutcome.notStarted,
    ]);
    expect(rows[1].trackedMinutes, 45);
    expect(rows[1].plannedMinutes, 60);
  });

  test('carries the selected plan change', () async {
    await tasks.insertTask(make(1, 'sample 6', 14));
    final current = TaskRepository.fromRow((await db.taskDao.getTaskById(id(1)))!);
    final event = PlanTitleChange(
      id: '00000000-0000-7000-8000-0000000003f1',
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

    final rows = await TaskOutcomeService(db).forDay(day);

    expect(rows, hasLength(1));
    expect(rows.single.planChange?.oldValue, 'sample 6');
    expect(rows.single.planChange?.newValue, 'sample 06');
  });
}
