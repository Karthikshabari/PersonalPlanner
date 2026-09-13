import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/models/timer_session.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late TimerService timer;
  late TaskRepository tasks;
  late DateTime now;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 1, 1, 9);
    timer = TimerService(db, clock: () => now);
    tasks = TaskRepository(db);
    await CategoryRepository(db).seedDefaultsIfEmpty();
  });

  tearDown(() => db.close());

  Future<Task> seedTask(
    String title, {
    TaskStatus status = TaskStatus.planned,
  }) => tasks.insertTask(
    Task(id: '', title: title, status: status, createdAt: now, updatedAt: now),
  );

  test(
    'start creates one owned running session and sets In Progress',
    () async {
      final task = await seedTask('Alpha');
      final result = await timer.start(task.id);

      expect(result.didChange, isTrue);
      expect(result.session?.state, TimerSessionState.running);
      expect(result.session?.runningSince?.toUtc(), now);
      final reloaded = await tasks.getTaskById(task.id);
      expect(reloaded?.status, TaskStatus.inProgress);

      final repeated = await timer.start(task.id);
      expect(repeated.didChange, isFalse);
      expect(await db.timerDao.getSessionsForTask(task.id), hasLength(1));
    },
  );

  test(
    'pause/resume retains one ID and excludes pauses from Actual Duration',
    () async {
      final task = await seedTask('Alpha');
      await timer.setManualActual(task.id, 10);
      final started = await timer.start(task.id);
      final id = started.session!.id;

      now = now.add(const Duration(minutes: 10));
      final firstPause = await timer.pause();
      expect(firstPause.session?.id, id);
      expect(firstPause.session?.state, TimerSessionState.paused);
      expect(
        firstPause.session?.durationSec,
        const Duration(minutes: 10).inSeconds,
      );
      expect((await tasks.getTaskById(task.id))?.actualDurationMin, 10);

      now = now.add(const Duration(minutes: 30));
      final resumed = await timer.resume(task.id);
      expect(resumed.session?.id, id);
      expect(resumed.session?.state, TimerSessionState.running);

      now = now.add(const Duration(minutes: 20));
      await timer.pause();
      now = now.add(const Duration(minutes: 10));
      await timer.resume(task.id);
      now = now.add(const Duration(minutes: 5));
      final stopped = await timer.stop();

      expect(stopped.didFinish, isTrue);
      expect(stopped.session?.id, id);
      expect(stopped.session?.state, TimerSessionState.finished);
      expect(
        stopped.session?.durationSec,
        const Duration(minutes: 35).inSeconds,
      );
      expect(stopped.session?.workIntervals, hasLength(3));
      expect(await db.timerDao.getSessionsForTask(task.id), hasLength(1));
      expect((await tasks.getTaskById(task.id))?.actualDurationMin, 45);
    },
  );

  test('Stop while paused commits exactly the closed duration once', () async {
    final task = await seedTask('Paused stop');
    final started = await timer.start(task.id);
    now = now.add(const Duration(seconds: 95));
    await timer.pause();
    now = now.add(const Duration(minutes: 10));

    final first = await timer.stopSession(started.session!.id);
    final second = await timer.stopSession(started.session!.id);
    expect(first.didFinish, isTrue);
    expect(second.didFinish, isFalse);
    expect(first.session?.durationSec, 95);
    expect((await tasks.getTaskById(task.id))?.actualDurationMin, 1);
  });

  test(
    'twenty paused minutes remain excluded until the same session stops',
    () async {
      final task = await seedTask('Paused source');
      final started = await timer.start(task.id);
      now = now.add(const Duration(minutes: 20));
      await timer.pauseSession(started.session!.id);

      expect((await tasks.getTaskById(task.id))?.actualDurationMin, isNull);
      final stopped = await timer.stopSession(started.session!.id);
      expect(stopped.didFinish, isTrue);
      expect((await tasks.getTaskById(task.id))?.actualDurationMin, 20);
    },
  );

  test(
    'a delayed native Stop retry commits its original action timestamp',
    () async {
      final task = await seedTask('Native action timestamp');
      final started = await timer.start(task.id);
      final actionAt = now.add(const Duration(seconds: 95));
      // The retry is handled much later, but the durable envelope carries the
      // first button-press time and must be the measured segment boundary.
      now = now.add(const Duration(minutes: 10));

      final stopped = await timer.stopSession(
        started.session!.id,
        occurredAt: actionAt,
        expectedRunningSince: started.session!.runningSince,
      );
      expect(stopped.didFinish, isTrue);
      expect(stopped.session?.endedAt, actionAt);
      expect(stopped.session?.durationSec, 95);
    },
  );

  test('starting B pauses A without finishing or counting A', () async {
    final a = await seedTask('A');
    final b = await seedTask('B');
    await timer.start(a.id);
    now = now.add(const Duration(minutes: 2));
    await timer.start(b.id);

    final aSession = (await db.timerDao.getSessionsForTask(a.id)).single;
    expect(aSession.state, TimerSessionState.paused.dbValue);
    expect(aSession.endedAt, isNull);
    expect(aSession.durationSec, const Duration(minutes: 2).inSeconds);
    expect((await tasks.getTaskById(a.id))?.actualDurationMin, isNull);
    final bSession = (await db.timerDao.getSessionsForTask(b.id)).single;
    expect(bSession.state, TimerSessionState.running.dbValue);
  });

  test(
    'manual desired totals are signed corrections over finished sources',
    () async {
      final task = await seedTask('Manual');
      await db
          .into(db.timerSessions)
          .insert(
            TimerSessionsCompanion.insert(
              id: 'finished-source',
              taskId: task.id,
              startedAt: now,
              endedAt: Value(now.add(const Duration(minutes: 20))),
              durationSec: const Value(20 * 60),
              state: const Value('finished'),
              workIntervalsJson: const Value('[]'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await timer.syncActualDuration(task.id);
      await timer.setManualActual(task.id, 5);
      var reloaded = await tasks.getTaskById(task.id);
      expect(reloaded?.manualDurationAdjustmentMin, -15);
      expect(reloaded?.manualActualSet, isTrue);
      expect(reloaded?.actualDurationMin, 5);

      await db
          .into(db.timerSessions)
          .insert(
            TimerSessionsCompanion.insert(
              id: 'second-source',
              taskId: task.id,
              startedAt: now,
              endedAt: Value(now.add(const Duration(minutes: 10))),
              durationSec: const Value(10 * 60),
              state: const Value('finished'),
              workIntervalsJson: const Value('[]'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await timer.syncActualDuration(task.id);
      reloaded = await tasks.getTaskById(task.id);
      expect(reloaded?.actualDurationMin, 15);
    },
  );

  test('ownerless imported work requires Recover and retains its session ID', () async {
    final task = await seedTask('Imported');
    const id = '11111111-1111-4111-8111-111111111111';
    final startedAt = now.subtract(const Duration(minutes: 5));
    await db
        .into(db.timerSessions)
        .insert(
          TimerSessionsCompanion.insert(
            id: id,
            taskId: task.id,
            startedAt: startedAt,
            durationSec: const Value(120),
            state: const Value('paused'),
            workIntervalsJson: Value(
              '[{"start_at":"${startedAt.toIso8601String()}",'
              '"end_at":"${startedAt.add(const Duration(minutes: 2)).toIso8601String()}",'
              '"duration_sec":120}]',
            ),
            createdAt: startedAt,
            updatedAt: now,
          ),
        );

    await expectLater(timer.start(task.id), throwsStateError);
    final recovered = await timer.recoverSession(id);
    expect(recovered.didChange, isTrue);
    expect(recovered.session?.id, id);
    expect(recovered.session?.state, TimerSessionState.paused);
    expect(recovered.session?.ownerDeviceId, isNotNull);

    final resumed = await timer.resume(task.id);
    expect(resumed.session?.id, id);
    expect(resumed.session?.state, TimerSessionState.running);
  });

  test(
    'foreign sessions cannot be started, paused, or stopped locally',
    () async {
      final task = await seedTask('Foreign');
      const id = '22222222-2222-4222-8222-222222222222';
      await db
          .into(db.timerSessions)
          .insert(
            TimerSessionsCompanion.insert(
              id: id,
              taskId: task.id,
              startedAt: now,
              durationSec: const Value(0),
              state: const Value('running'),
              runningSince: Value(now),
              workIntervalsJson: const Value('[]'),
              ownerDeviceId: const Value(
                '33333333-3333-4333-8333-333333333333',
              ),
              createdAt: now,
              updatedAt: now,
            ),
          );

      await expectLater(timer.start(task.id), throwsStateError);
      expect((await timer.pauseSession(id)).didChange, isFalse);
      expect((await timer.stopSession(id)).didFinish, isFalse);
      expect((await db.timerDao.getSessionById(id))?.state, 'running');
    },
  );

  test(
    'paused session resumes with the same ID after a database reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp('planner_timer_');
      final file = File('${directory.path}/planner.sqlite');
      AppDatabase? first;
      AppDatabase? reopened;
      try {
        final startedAt = DateTime.utc(2026, 2, 1, 9);
        var clock = startedAt;
        first = AppDatabase(NativeDatabase(file));
        final firstTasks = TaskRepository(first);
        final task = await firstTasks.insertTask(
          Task(
            id: '',
            title: 'Persistent pause',
            createdAt: startedAt,
            updatedAt: startedAt,
          ),
        );
        final firstTimer = TimerService(first, clock: () => clock);
        final started = await firstTimer.start(task.id);
        clock = clock.add(const Duration(minutes: 3));
        await firstTimer.pause();
        await first.close();
        first = null;

        reopened = AppDatabase(NativeDatabase(file));
        final resumed = await TimerService(
          reopened,
          clock: () => clock,
        ).resume(task.id);
        expect(resumed.session?.id, started.session?.id);
        expect(resumed.session?.state, TimerSessionState.running);
        expect(
          resumed.session?.durationSec,
          const Duration(minutes: 3).inSeconds,
        );
      } finally {
        await first?.close();
        await reopened?.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'running work survives abrupt reopen and derives real elapsed time',
    () async {
      final directory = await Directory.systemTemp.createTemp('planner_timer_');
      final file = File('${directory.path}/planner.sqlite');
      AppDatabase? first;
      AppDatabase? reopened;
      try {
        final startedAt = DateTime.utc(2026, 2, 2, 9);
        var clock = startedAt;
        first = AppDatabase(NativeDatabase(file));
        final task = await TaskRepository(first).insertTask(
          Task(
            id: '',
            title: 'Persistent running',
            createdAt: startedAt,
            updatedAt: startedAt,
          ),
        );
        final started = await TimerService(
          first,
          clock: () => clock,
        ).start(task.id);
        await first.close();
        first = null;

        clock = clock.add(const Duration(minutes: 20));
        reopened = AppDatabase(NativeDatabase(file));
        final row = await reopened.timerDao.getSessionById(started.session!.id);
        expect(row?.state, TimerSessionState.running.dbValue);
        expect(
          row!.durationSec + clock.difference(row.runningSince!).inSeconds,
          const Duration(minutes: 20).inSeconds,
        );
        final resumed = await TimerService(
          reopened,
          clock: () => clock,
        ).resume(task.id);
        expect(resumed.didChange, isFalse);
        expect(resumed.session?.id, started.session?.id);
      } finally {
        await first?.close();
        await reopened?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
