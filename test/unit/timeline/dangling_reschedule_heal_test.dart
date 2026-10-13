import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/recurring_rule.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/core/utils/uuid.dart';
import 'package:personal_planner/features/inbox/data/inbox_repository.dart';
import 'package:personal_planner/features/recurring/data/recurring_repository.dart';
import 'package:personal_planner/features/recurring/domain/recurrence_aggregate_command.dart';
import 'package:personal_planner/features/recurring/domain/recurrence_service.dart';
import 'package:personal_planner/features/review/domain/daily_stats_service.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timeline/domain/commands/delete_task_command.dart';

import '../../helpers/sqlite_setup.dart';

/// UAT-012: a Rescheduled block whose new block was deleted is healed back
/// to Planned (only when the new block's row exists and is deleted), and the
/// Undo of that delete links it again, so one task never shows twice.
void main() {
  setupSqliteForTests();
  PlannerTimeZone.initialize(identifier: 'UTC');

  late AppDatabase db;
  late TaskRepository tasks;
  final monday = PlannerTimeZone.calendarDate(2026, 9, 14);
  final now = PlannerTimeZone.calendarDate(2026, 9, 20, hour: 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
  });

  tearDown(() => db.close());

  Future<Task> block(String title, int hour, {String? from}) {
    final start = PlannerTimeZone.calendarDate(
      monday.year,
      monday.month,
      monday.day,
      hour: hour,
    );
    return tasks.insertTask(
      Task(
        id: '',
        title: title,
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
        rescheduledFromId: from,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// UAT-R: 09:00 rescheduled to a 14:00 block.
  Future<(Task, Task)> rescheduledPair() async {
    final original = await block('UAT-R', 9);
    final next = await block('UAT-R', 14, from: original.id);
    await tasks.markRescheduled(original.id, next.id);
    return (original, next);
  }

  Future<Task> reload(String id) async => (await tasks.getTaskById(id))!;
  Future<int> revision(String id) async =>
      (await db.taskDao.getTaskById(id))!.revision;

  Future<List<String>> activeIds() async => [
    for (final task in await tasks.watchActiveTasksForDay(monday).first)
      task.id,
  ];

  Future<int> outboxRows() async => (await db.select(db.syncLog).get()).length;

  test(
    'deleting the new block heals the original; Undo links it again',
    () async {
      final (original, next) = await rescheduledPair();
      final command = DeleteTaskCommand(repository: tasks, original: next);

      final before = await outboxRows();
      await command.execute();
      final healed = await reload(original.id);
      expect(healed.status, TaskStatus.planned);
      expect(healed.rescheduledToId, isNull);
      expect(await activeIds(), [original.id]);
      // The heal is an ordinary update: the sync trigger queued it.
      final queued = await (db.select(
        db.syncLog,
      )..where((row) => row.recordId.equals(original.id))).get();
      expect(queued, isNotEmpty);
      expect(await outboxRows(), greaterThan(before));

      await command.undo();
      final relinked = await reload(original.id);
      expect(relinked.status, TaskStatus.rescheduled);
      expect(relinked.rescheduledToId, next.id);
      expect(await activeIds(), [next.id]);
      expect(
        (await DailyStatsService(db).computeForDate(monday)).totalTasks,
        1,
      );
    },
  );

  test('a link to a row that does not exist is never written', () async {
    final (original, next) = await rescheduledPair();
    // Simulate a new block that never arrived: foreign keys off, row gone.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement('DELETE FROM tasks WHERE id = ?', [next.id]);
    await db.customStatement('PRAGMA foreign_keys = ON');
    final row = await reload(original.id);
    final rowRevision = await revision(original.id);
    expect(row.rescheduledToId, next.id);

    final before = await outboxRows();
    expect(await tasks.restoreFromMissingSuccessor(original.id), isFalse);
    expect(await tasks.restoreDanglingReschedules(), isEmpty);
    expect(await outboxRows(), before);
    final after = await reload(original.id);
    expect(after.status, TaskStatus.rescheduled);
    expect(await revision(original.id), rowRevision);
    // Display only: it counts as active.
    expect(await activeIds(), [original.id]);
    expect((await DailyStatsService(db).computeForDate(monday)).totalTasks, 1);
  });

  test(
    'restoreDanglingReschedules heals a deleted copy, then writes nothing',
    () async {
      final (original, next) = await rescheduledPair();
      // As a pull delivers it: the new block's tombstone without any heal.
      await db.syncDao.runWithoutOutbound(
        () => db.customStatement(
          'UPDATE tasks SET deleted_at = ? WHERE id = ?',
          [now.toUtc().toIso8601String(), next.id],
        ),
      );
      expect(await tasks.restoreDanglingReschedules(), [original.id]);
      expect((await reload(original.id)).status, TaskStatus.planned);

      final before = await outboxRows();
      expect(await tasks.restoreDanglingReschedules(), isEmpty);
      expect(await outboxRows(), before);
    },
  );

  test('a minute tick (stampOverdue) does not heal', () async {
    final (original, next) = await rescheduledPair();
    await db.syncDao.runWithoutOutbound(
      () => db.customStatement('UPDATE tasks SET deleted_at = ? WHERE id = ?', [
        now.toUtc().toIso8601String(),
        next.id,
      ]),
    );
    final rowRevision = await revision(original.id);
    await InboxRepository(db).stampOverdue(now);
    final after = await reload(original.id);
    expect(after.status, TaskStatus.rescheduled);
    expect(await revision(original.id), rowRevision);
  });

  test('series delete: delete, Undo, Redo, Undo keep one live copy', () async {
    final rules = RecurringRepository(db);
    final recurrence = RecurrenceService(db);
    final rule = await rules.createRule(
      RecurringRule(
        id: 'rule-uat-r',
        rrule: 'FREQ=DAILY',
        taskTitle: 'UAT-R',
        durationMin: 60,
        startTimeOfDay: '14:00',
        startDate: monday,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await recurrence.materializeForDate(monday);
    final occurrenceId = generateDeterministicUuid(
      'recurring-occurrence:${rule.id}:${isoDateString(monday)}',
    );
    final original = await block('UAT-R', 9);
    await tasks.markRescheduled(original.id, occurrenceId);

    // The same mutation as Day > Delete > All future occurrences.
    final command = RecurrenceAggregateCommand(
      database: db,
      ruleId: rule.id,
      description: 'End recurring series',
      mutation: () async {
        await tasks.deleteTask(occurrenceId);
        await rules.setEndDate(rule.id, addDays(monday, -1));
        await rules.deactivateRule(rule.id);
        await recurrence.deleteMaterializedFuture(
          rule.id,
          monday,
          keepTaskId: occurrenceId,
        );
      },
    );

    Future<void> expectDeleted() async {
      final healed = await reload(original.id);
      expect(healed.status, TaskStatus.planned);
      expect(healed.rescheduledToId, isNull);
      expect(await activeIds(), [original.id]);
    }

    Future<void> expectRestored() async {
      final linked = await reload(original.id);
      expect(linked.status, TaskStatus.rescheduled);
      expect(linked.rescheduledToId, occurrenceId);
      expect(await activeIds(), [occurrenceId]);
    }

    await command.execute();
    await expectDeleted();
    final healedRevision = (await revision(original.id));

    await command.undo();
    await expectRestored();
    // An ordinary edit with a new revision, never a rollback.
    expect((await revision(original.id)), greaterThan(healedRevision));

    await command.execute();
    await expectDeleted();
    await command.undo();
    await expectRestored();
  });
}
