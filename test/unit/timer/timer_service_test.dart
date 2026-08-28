import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late TimerService timer;
  late TaskRepository tasks;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    timer = TimerService(db);
    tasks = TaskRepository(db);
    await CategoryRepository(db).seedDefaultsIfEmpty();
  });

  tearDown(() async {
    await db.close();
  });

  Future<Task> seedTask(String title,
      {TaskStatus status = TaskStatus.planned}) =>
      tasks.insertTask(Task(
        id: '',
        title: title,
        status: status,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

  test('start creates one running session and auto-sets In Progress',
      () async {
    final task = await seedTask('Alpha');
    await timer.start(task.id);

    final running = await db.timerDao.getActiveTimerForTask(task.id);
    expect(running, isNotNull);
    expect(running!.endedAt, isNull);

    final reloaded = await tasks.getTaskById(task.id);
    expect(reloaded!.status, TaskStatus.inProgress);
  });

  test('pause finalizes the session; resume creates a NEW session',
      () async {
    final task = await seedTask('Alpha');
    await timer.start(task.id);
    await timer.pause();

    expect(await db.timerDao.getActiveTimerForTask(task.id), isNull);
    var rows = await db.timerDao.getSessionsForTask(task.id);
    expect(rows, hasLength(1));
    expect(rows.single.endedAt, isNotNull);
    expect(rows.single.durationSec, greaterThanOrEqualTo(0));

    // Resume == a brand-new session.
    await timer.resume(task.id);
    rows = await db.timerDao.getSessionsForTask(task.id);
    expect(rows, hasLength(2));
    expect(rows.where((s) => s.endedAt == null), hasLength(1));
  });

  test('starting B auto-pauses A — only one active timer globally', () async {
    final a = await seedTask('A');
    final b = await seedTask('B');
    await timer.start(a.id);
    await timer.start(b.id);

    final aSessions = await db.timerDao.getSessionsForTask(a.id);
    final bRunning = await db.timerDao.getActiveTimerForTask(b.id);
    expect(aSessions.single.endedAt, isNotNull,
        reason: "A's session must be paused when B starts");
    expect(bRunning, isNotNull);

    // No other open session exists.
    final open = await (db.select(db.timerSessions)
          ..where((s) => s.endedAt.isNull()))
        .get();
    expect(open.map((s) => s.taskId), [b.id]);
  });

  test('start is idempotent while already running for the same task',
      () async {
    final task = await seedTask('Alpha');
    await timer.start(task.id);
    await timer.start(task.id);
    expect(await db.timerDao.getSessionsForTask(task.id), hasLength(1));
  });

  test('timer start rejects terminal statuses', () async {
    final task = await seedTask('Done thing', status: TaskStatus.completed);
    await expectLater(timer.start(task.id), throwsStateError);
    final reloaded = await tasks.getTaskById(task.id);
    expect(reloaded!.status, TaskStatus.completed);
    expect(await db.timerDao.getSessionsForTask(task.id), isEmpty);
  });

  test('actual_duration_min recomputes from finished sessions', () async {
    final task = await seedTask('Tracked');
    final now = DateTime.now().toUtc();
    var n = 0;
    Future<void> addSession(int seconds) {
      n++;
      return db.into(db.timerSessions).insert(TimerSessionsCompanion.insert(
            id: 'seed-$n',
            taskId: task.id,
            startedAt: now,
            endedAt: Value(now.add(Duration(seconds: seconds))),
            durationSec: Value(seconds),
            createdAt: now,
            updatedAt: now,
          ));
    }
    await addSession(90); // 1.5 min
    await addSession(60); // 1 min

    expect(await db.timerDao.getTotalDurationSecForTask(task.id), 150);

    await timer.syncActualDuration(task.id);
    final reloaded = await tasks.getTaskById(task.id);
    expect(reloaded!.actualDurationMin, 2); // floor(150 / 60)
  });

  test('manual duration adjustment survives later finished sessions', () async {
    final task = await seedTask('Adjusted');
    final now = DateTime.now().toUtc();
    await db.into(db.timerSessions).insert(TimerSessionsCompanion.insert(
          id: 'first-session',
          taskId: task.id,
          startedAt: now,
          endedAt: Value(now.add(const Duration(seconds: 120))),
          durationSec: const Value(120),
          createdAt: now,
          updatedAt: now,
        ));

    await timer.syncActualDuration(task.id);
    await timer.setManualActual(task.id, 10);
    await db.into(db.timerSessions).insert(TimerSessionsCompanion.insert(
          id: 'second-session',
          taskId: task.id,
          startedAt: now,
          endedAt: Value(now.add(const Duration(minutes: 1))),
          durationSec: const Value(60),
          createdAt: now,
          updatedAt: now,
        ));
    await timer.syncActualDuration(task.id);

    final reloaded = await tasks.getTaskById(task.id);
    expect(reloaded!.manualDurationAdjustmentMin, 8);
    expect(reloaded.actualDurationMin, 11);
  });

  test('watchActiveTimer exposes the running session with its task title',
      () async {
    final task = await seedTask('Watched');
    await timer.start(task.id);

    final active = await db.timerDao.watchActiveTimerWithTask().first;
    expect(active, isNotNull);
    expect(active!.session.taskId, task.id);
    expect(active.taskTitle, 'Watched');

    await timer.pause();
    final afterPause = await db.timerDao.watchActiveTimerWithTask().first;
    expect(afterPause, isNull);
  });
}
