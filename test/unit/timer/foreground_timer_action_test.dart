import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/models/timer_session.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/domain/notification_coordinator.dart';
import 'package:personal_planner/features/timer/domain/planner_notification.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase database;
  late _FakeNotifications notifications;
  late DateTime now;
  late Task task;
  late TimerNotificationSnapshot running;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    notifications = _FakeNotifications();
    now = DateTime.utc(2026, 9, 21, 9);
    task = await TaskRepository(database, clock: () => now).insertTask(
      Task(
        id: '11111111-1111-4111-8111-111111111111',
        title: 'Notification task',
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    final started = await TimerService(
      database,
      clock: () => now,
    ).start(task.id);
    final row = await database.timerDao.getSessionById(started.session!.id);
    running = TimerNotificationSnapshot(
      accountId: null,
      taskTitle: task.title,
      sessionId: row!.id,
      taskId: row.taskId,
      ownerDeviceId: row.ownerDeviceId!,
      state: TimerSessionState.running,
      runningSince: row.runningSince,
      durationSec: row.durationSec,
      revision: row.revision,
    );
  });

  tearDown(() => database.close());

  PlannerNotificationActionDispatcher dispatcher() =>
      PlannerNotificationActionDispatcher(
        database: database,
        notifications: notifications,
        accountId: null,
        clock: () => now,
      );

  test('payload round-trips exact persisted timer identity', () {
    final decoded = PlannerNotificationPayload.tryDecode(
      running.payload.encode(),
    );
    expect(decoded?.sessionId, running.sessionId);
    expect(decoded?.taskId, running.taskId);
    expect(decoded?.ownerDeviceId, running.ownerDeviceId);
    expect(
      decoded?.expectedRunningSince?.millisecondsSinceEpoch,
      running.runningSince?.millisecondsSinceEpoch,
    );
    expect(decoded?.expectedDurationSec, running.durationSec);
    expect(decoded?.expectedRevision, running.revision);
  });

  test(
    'Pause and Resume use the persisted TimerService state machine',
    () async {
      now = now.add(const Duration(minutes: 7));
      expect(
        await dispatcher().dispatch(
          PlannerNotificationAction.pause,
          running.payload,
        ),
        isTrue,
      );
      final paused = await database.timerDao.getSessionById(running.sessionId);
      expect(paused?.state, 'paused');
      expect(paused?.durationSec, 7 * 60);
      expect(
        notifications.timerSnapshots.single.state,
        TimerSessionState.paused,
      );

      final pausedPayload = notifications.timerSnapshots.single.payload;
      now = now.add(const Duration(minutes: 3));
      expect(
        await dispatcher().dispatch(
          PlannerNotificationAction.resume,
          pausedPayload,
        ),
        isTrue,
      );
      final resumed = await database.timerDao.getSessionById(running.sessionId);
      expect(resumed?.state, 'running');
      expect(resumed?.durationSec, 7 * 60);
      expect(
        resumed?.runningSince?.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
    },
  );

  test('Stop computes Actual Duration exactly like in-app Stop', () async {
    now = now.add(const Duration(minutes: 12, seconds: 40));
    expect(
      await dispatcher().dispatch(
        PlannerNotificationAction.stop,
        running.payload,
      ),
      isTrue,
    );
    final stopped = await database.timerDao.getSessionById(running.sessionId);
    final updatedTask = await database.taskDao.getTaskById(task.id);
    expect(stopped?.state, 'finished');
    expect(stopped?.durationSec, 12 * 60 + 40);
    expect(updatedTask?.actualDurationMin, 12);
    expect(notifications.timerCancelCount, 1);
  });

  test('stale action cannot mutate a newer running segment', () async {
    now = now.add(const Duration(minutes: 2));
    await TimerService(
      database,
      clock: () => now,
    ).pauseSession(running.sessionId);
    now = now.add(const Duration(minutes: 1));
    await TimerService(
      database,
      clock: () => now,
    ).resumeSession(running.sessionId);

    expect(
      await dispatcher().dispatch(
        PlannerNotificationAction.stop,
        running.payload,
      ),
      isFalse,
    );
    final current = await database.timerDao.getSessionById(running.sessionId);
    expect(current?.state, 'running');
    expect(
      current?.runningSince?.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
  });

  test(
    'startup reconciliation restores and later removes one notification',
    () async {
      final coordinator = PlannerNotificationCoordinator(
        database: database,
        notifications: notifications,
        accountId: null,
        clock: () => now,
      );
      await coordinator.start();
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(notifications.timerSnapshots, hasLength(1));
      expect(notifications.timerSnapshots.single.sessionId, running.sessionId);
      expect(await database.timerDao.getSessionsForTask(task.id), hasLength(1));

      now = now.add(const Duration(minutes: 1));
      await TimerService(
        database,
        clock: () => now,
      ).stopSession(running.sessionId);
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(notifications.timerCancelCount, greaterThanOrEqualTo(1));
      expect(await database.timerDao.getSessionsForTask(task.id), hasLength(1));
      await coordinator.dispose();
    },
  );
}

class _FakeNotifications implements PlannerNotificationGateway {
  final List<TimerNotificationSnapshot> timerSnapshots = [];
  int timerCancelCount = 0;

  @override
  Future<void> cancelTaskReminder(String taskId) async {}

  @override
  Future<void> cancelTimer() async => timerCancelCount++;

  @override
  Future<void> scheduleTaskReminder(TaskReminderSnapshot snapshot) async {}

  @override
  Future<void> showTaskReminder(TaskReminderSnapshot snapshot) async {}

  @override
  Future<void> showTimer(TimerNotificationSnapshot snapshot) async {
    timerSnapshots.add(snapshot);
  }
}
