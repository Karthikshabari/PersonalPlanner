import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/domain/task_actual_duration_service.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late TaskRepository tasks;
  late TaskActualDurationService actuals;
  final start = DateTime.utc(2026, 3, 1, 23, 59, 15);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
    actuals = TaskActualDurationService(db);
    await CategoryRepository(db).seedDefaultsIfEmpty();
  });

  tearDown(() => db.close());

  Future<Task> task({DateTime? startTime}) => tasks.insertTask(
    Task(
      id: '',
      title: 'Tracked',
      startTime: startTime,
      endTime: startTime?.add(const Duration(hours: 1)),
      createdAt: start,
      updatedAt: start,
    ),
  );

  Future<void> finished(
    String id,
    String taskId,
    int seconds, {
    String intervals = '[]',
  }) => db
      .into(db.timerSessions)
      .insert(
        TimerSessionsCompanion.insert(
          id: id,
          taskId: taskId,
          startedAt: start,
          endedAt: Value(start.add(Duration(seconds: seconds))),
          durationSec: Value(seconds),
          state: const Value('finished'),
          workIntervalsJson: Value(intervals),
          createdAt: start,
          updatedAt: start,
        ),
      );

  test(
    'null and explicit zero retain distinct manual source semantics',
    () async {
      final untouched = await task();
      await actuals.recomputeTask(untouched.id);
      expect(
        (await tasks.getTaskById(untouched.id))?.actualDurationMin,
        isNull,
      );

      await actuals.setDisplayedTotal(untouched.id, 0);
      final explicit = await tasks.getTaskById(untouched.id);
      expect(explicit?.manualActualSet, isTrue);
      expect(explicit?.actualDurationMin, 0);
    },
  );

  test(
    'finished IDs are counted once and signed adjustment survives recompute',
    () async {
      final tracked = await task();
      await finished('one-session', tracked.id, 20 * 60);
      await actuals.setDisplayedTotal(tracked.id, 5);
      await actuals.recomputeTasks({tracked.id, tracked.id});
      var reloaded = await tasks.getTaskById(tracked.id);
      expect(reloaded?.manualDurationAdjustmentMin, -15);
      expect(reloaded?.actualDurationMin, 5);

      await finished('second-session', tracked.id, 10 * 60);
      await actuals.recomputeTask(tracked.id);
      reloaded = await tasks.getTaskById(tracked.id);
      expect(reloaded?.actualDurationMin, 15);
    },
  );

  test('distinct completed IDs add while replaying one ID leaves its total unchanged', () async {
    final tracked = await task();
    await finished('first-source', tracked.id, 20 * 60);
    await actuals.setDisplayedTotal(tracked.id, 30);
    await actuals.recomputeTask(tracked.id);
    expect((await tasks.getTaskById(tracked.id))?.actualDurationMin, 30);

    // A sync replay replaces the one source row; it must never create a
    // second contribution merely because the same ID was observed again.
    final first = await db.timerDao.getSessionById('first-source');
    await db.timerDao.updateSession(first!);
    await actuals.recomputeTask(tracked.id);
    expect((await tasks.getTaskById(tracked.id))?.actualDurationMin, 30);

    await finished('second-source', tracked.id, 20 * 60);
    await actuals.recomputeTask(tracked.id);
    expect((await tasks.getTaskById(tracked.id))?.actualDurationMin, 50);
  });

  test(
    'derived cache refresh leaves semantic revision and outbox untouched',
    () async {
      final tracked = await task();
      await actuals.setDisplayedTotal(tracked.id, 5);
      await db.syncDao.runWithoutOutbound(() async {
        await (db.update(db.tasks)..where((row) => row.id.equals(tracked.id)))
            .write(const TasksCompanion(actualDurationMin: Value(99)));
      });
      await db.customStatement('DELETE FROM sync_log');
      final before = await db.taskDao.getTaskById(tracked.id);

      await actuals.recomputeTask(tracked.id);

      final after = await db.taskDao.getTaskById(tracked.id);
      expect(after?.actualDurationMin, 5);
      expect(after?.revision, before?.revision);
      expect(after?.updatedAt, before?.updatedAt);
      expect(await db.syncDao.pendingCount(), 0);
    },
  );

  test('cross-midnight interval allocation preserves the authoritative total', () async {
    final tracked = await task(startTime: DateTime.utc(2026, 3, 1, 9));
    const intervalJson =
        '[{"start_at":"2026-03-01T18:29:15.000Z","end_at":"2026-03-01T18:30:45.000Z","duration_sec":90}]';
    await finished('cross-midnight', tracked.id, 90, intervals: intervalJson);
    await actuals.recomputeTask(tracked.id);
    final row = await db.taskDao.getTaskById(tracked.id);
    final history = await db.timerDao.getFinishedSessionsForTask(tracked.id);
    final allocation = TaskActualDurationService.allocateActualByDate(
      row!,
      history,
    );
    expect(allocation.values.fold(0, (sum, value) => sum + value), 1);
    // The two 45-second weights tie for one minute, so the stable ascending
    // planner-date tie break gives it to the first date.
    expect(allocation['2026-03-01'], 1);
    expect(allocation['2026-03-02'], 0);
  });
}
