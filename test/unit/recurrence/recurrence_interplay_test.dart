import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/inbox/data/inbox_repository.dart';
import 'package:personal_planner/features/recurring/domain/recurrence_service.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

/// Cross-chunk verification (Chunk 4 x Chunk 3): how recurring instances
/// interact with the inbox-reschedule flow.
void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late TaskRepository tasks;
  late InboxRepository inbox;
  late RecurrenceService recurrence;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
    inbox = InboxRepository(db);
    recurrence = RecurrenceService(db);
  });

  tearDown(() => db.close());

  test(
      'rescheduling a recurring instance to tomorrow does not duplicate '
      'that day', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));

    await db.into(db.recurringRules).insert(RecurringRulesCompanion.insert(
          id: 'rule-1',
          rrule: 'FREQ=DAILY',
          taskTitle: 'Daily standup',
          durationMin: 60,
          startTimeOfDay: '09:00',
          startDate: isoDateString(yesterday),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
    // A daily rule anchored yesterday whose instance was already
    // materialized (now overdue → surfaces in the inbox).
    final original = await tasks.insertTask(Task(
      id: '',
      title: 'Daily standup',
      startTime: DateTime(yesterday.year, yesterday.month, yesterday.day, 9),
      endTime: DateTime(yesterday.year, yesterday.month, yesterday.day, 10),
      status: TaskStatus.planned,
      recurringRuleId: 'rule-1',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));

    // Drag it from the inbox onto tomorrow's timeline (Chunk 3 flow).
    final copy = await inbox.rescheduleOverdue(
      original.id,
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 14),
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15),
    );

    expect(copy.rescheduledFromId, original.id);
    final rereadOriginal = await tasks.getTaskById(original.id);
    expect(rereadOriginal!.status, TaskStatus.rescheduled);

    // Materializing tomorrow must NOT create a second block for the rule:
    // the rescheduled copy already occupies that rule's dedupe slot.
    expect(await recurrence.materializeForDate(tomorrow), 0);
    final dayTasks = await tasks.watchTasksForDay(tomorrow).first;
    expect(dayTasks, hasLength(1));
    expect(dayTasks.single.id, copy.id);

    // The series itself is alive and well: today gets its own fresh
    // instance (the daily rule continues independently of the move).
    await recurrence.materializeForDate(today);
    final todayTasks = await tasks.watchTasksForDay(today).first;
    expect(todayTasks, hasLength(1));
    expect(todayTasks.single.status, TaskStatus.planned);
    expect(todayTasks.single.startTime!.day, today.day);

    // And yesterday keeps the rescheduled original visible.
    final yesterdayTasks = await tasks.watchTasksForDay(yesterday).first;
    expect(yesterdayTasks.single.id, original.id);
    expect(yesterdayTasks.single.status, TaskStatus.rescheduled);
  });
}
