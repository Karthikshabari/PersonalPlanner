import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/models/timer_session.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/domain/notification_coordinator.dart';
import 'package:personal_planner/features/timer/domain/notification_service.dart';
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
    // Production DateTime.now() carries sub-millisecond precision. Keep it in
    // the fixture so notification serialization cannot silently truncate the
    // running-segment identity while zero-microsecond test clocks still pass.
    now = DateTime.utc(2026, 9, 21, 9, 0, 0, 123, 456);
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

  Future<bool?> routeForegroundAction(
    String actionId,
    PlannerNotificationPayload payload,
  ) async {
    bool? result;
    await NotificationService.routeForegroundResponse(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: actionId,
        payload: payload.encode(),
      ),
      onSelect: (_) {},
      clock: () => now,
      onPlannerAction: (action, decodedPayload, occurredAt) async {
        result = await PlannerNotificationActionDispatcher(
          database: database,
          notifications: notifications,
          accountId: null,
          clock: () => occurredAt,
        ).dispatch(action, decodedPayload);
      },
    );
    return result;
  }

  Future<void> settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

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
    expect(
      decoded?.expectedRunningSince?.microsecondsSinceEpoch,
      running.runningSince?.microsecondsSinceEpoch,
    );
    expect(running.runningSince?.isUtc, isFalse);
    expect(decoded?.expectedRunningSince?.isUtc, isTrue);
    expect(decoded?.expectedRunningSince, isNot(running.runningSince));
    expect(
      decoded?.expectedRunningSince?.isAtSameMomentAs(running.runningSince!),
      isTrue,
    );
    expect(decoded?.expectedDurationSec, running.durationSec);
    expect(decoded?.expectedRevision, running.revision);
  });

  test('Linux foreground Pause and Resume use the persisted TimerService state machine', () async {
    now = now.add(const Duration(minutes: 7));
    expect(
      await routeForegroundAction(
        NotificationService.timerPauseActionId,
        running.payload,
      ),
      isTrue,
    );
    final paused = await database.timerDao.getSessionById(running.sessionId);
    expect(paused?.state, 'paused');
    expect(paused?.durationSec, 7 * 60);
    expect(notifications.timerSnapshots.single.state, TimerSessionState.paused);

    final pausedPayload = notifications.timerSnapshots.single.payload;
    now = now.add(const Duration(minutes: 3));
    expect(
      await routeForegroundAction(
        NotificationService.timerResumeActionId,
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
  });

  test(
    'Linux foreground Stop computes Actual Duration like in-app Stop',
    () async {
      now = now.add(const Duration(minutes: 12, seconds: 40));
      expect(
        await routeForegroundAction(
          NotificationService.timerStopActionId,
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
    },
  );

  test('paused notification Stop remains supported', () async {
    now = now.add(const Duration(minutes: 4));
    expect(
      await routeForegroundAction(
        NotificationService.timerPauseActionId,
        running.payload,
      ),
      isTrue,
    );
    final pausedPayload = notifications.timerSnapshots.single.payload;

    now = now.add(const Duration(minutes: 2));
    expect(
      await routeForegroundAction(
        NotificationService.timerStopActionId,
        pausedPayload,
      ),
      isTrue,
    );
    final stopped = await database.timerDao.getSessionById(running.sessionId);
    expect(stopped?.state, 'finished');
    expect(stopped?.durationSec, 4 * 60);
    expect((await database.taskDao.getTaskById(task.id))?.actualDurationMin, 4);
  });

  test('unknown foreground action does not mutate timer state', () async {
    expect(
      await routeForegroundAction('unknown_action', running.payload),
      equals(null),
    );
    final current = await database.timerDao.getSessionById(running.sessionId);
    expect(current?.state, 'running');
    expect(current?.revision, running.revision);
    expect(notifications.timerSnapshots, isEmpty);
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

  test('running action with a different actual instant is rejected', () async {
    final stale = PlannerNotificationPayload(
      kind: PlannerNotificationKind.timer,
      accountId: running.accountId,
      taskId: running.taskId,
      sessionId: running.sessionId,
      ownerDeviceId: running.ownerDeviceId,
      expectedState: running.state,
      expectedRunningSince: running.runningSince!.add(
        const Duration(microseconds: 1),
      ),
      expectedDurationSec: running.durationSec,
      expectedRevision: running.revision,
    );

    expect(
      await routeForegroundAction(
        NotificationService.timerPauseActionId,
        stale,
      ),
      isFalse,
    );
    final current = await database.timerDao.getSessionById(running.sessionId);
    expect(current?.state, 'running');
    expect(current?.runningSince, running.runningSince);
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

  test(
    'same-clock A to B switch always presents and controls running B',
    () async {
      final taskB = await TaskRepository(database, clock: () => now).insertTask(
        Task(
          id: '22222222-2222-4222-8222-222222222222',
          title: 'Second task',
          startTime: now,
          endTime: now.add(const Duration(hours: 1)),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final startedB = await TimerService(
        database,
        clock: () => now,
      ).start(taskB.id);
      final sessionA = await database.timerDao.getSessionById(
        running.sessionId,
      );
      final sessionB = await database.timerDao.getSessionById(
        startedB.session!.id,
      );
      expect(sessionA?.state, 'paused');
      expect(sessionB?.state, 'running');
      expect(sessionA?.updatedAt, sessionB?.updatedAt);

      final coordinator = PlannerNotificationCoordinator(
        database: database,
        notifications: notifications,
        accountId: null,
        clock: () => now,
      );
      await coordinator.start();
      await settle();
      final selected = notifications.timerSnapshots.last;
      expect(selected.sessionId, sessionB?.id);

      expect(
        await routeForegroundAction(
          NotificationService.timerPauseActionId,
          selected.payload,
        ),
        isTrue,
      );
      expect(
        (await database.timerDao.getSessionById(sessionB!.id))?.state,
        'paused',
      );
      expect(
        (await database.timerDao.getSessionById(sessionA!.id))?.state,
        'paused',
      );

      final pausedB = notifications.timerSnapshots.last;
      expect(pausedB.sessionId, sessionB.id);
      expect(
        await routeForegroundAction(
          NotificationService.timerResumeActionId,
          pausedB.payload,
        ),
        isTrue,
      );
      final resumedB = notifications.timerSnapshots.last;
      expect(resumedB.sessionId, sessionB.id);
      expect(resumedB.state, TimerSessionState.running);
      expect(
        await routeForegroundAction(
          NotificationService.timerStopActionId,
          resumedB.payload,
        ),
        isTrue,
      );
      expect(
        (await database.timerDao.getSessionById(sessionB.id))?.state,
        'finished',
      );
      expect(
        (await database.timerDao.getSessionById(sessionA.id))?.state,
        'paused',
      );
      await coordinator.dispose();
    },
  );

  test(
    'paused fallback is used only when no local running session exists',
    () async {
      now = now.add(const Duration(minutes: 1));
      await TimerService(database, clock: () => now).pause();
      final coordinator = PlannerNotificationCoordinator(
        database: database,
        notifications: notifications,
        accountId: null,
        clock: () => now,
      );
      await coordinator.start();
      await settle();
      expect(notifications.timerSnapshots.last.sessionId, running.sessionId);
      expect(notifications.timerSnapshots.last.state, TimerSessionState.paused);
      await coordinator.dispose();
    },
  );

  test(
    'foreign running session cannot displace local running session',
    () async {
      final taskB = await TaskRepository(database, clock: () => now).insertTask(
        Task(
          id: '33333333-3333-4333-8333-333333333333',
          title: 'Foreign task',
          startTime: now,
          endTime: now.add(const Duration(hours: 1)),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final later = now.add(const Duration(hours: 1));
      await database.timerDao.insertSession(
        TimerSessionsCompanion.insert(
          id: '44444444-4444-4444-8444-444444444444',
          taskId: taskB.id,
          startedAt: later,
          state: const Value('running'),
          runningSince: Value(later),
          ownerDeviceId: const Value('foreign-device'),
          createdAt: later,
          updatedAt: later,
        ),
      );
      final coordinator = PlannerNotificationCoordinator(
        database: database,
        notifications: notifications,
        accountId: null,
        clock: () => now,
      );
      await coordinator.start();
      await settle();
      expect(notifications.timerSnapshots.last.sessionId, running.sessionId);
      await coordinator.dispose();
    },
  );

  test('notification presentation failure leaves timer state intact', () async {
    notifications.failTimerPresentation = true;
    final coordinator = PlannerNotificationCoordinator(
      database: database,
      notifications: notifications,
      accountId: null,
      clock: () => now,
    );
    await coordinator.start();
    await settle();

    final current = await database.timerDao.getSessionById(running.sessionId);
    expect(current?.state, 'running');
    expect(current?.revision, running.revision);
    await coordinator.dispose();
  });
}

class _FakeNotifications implements PlannerNotificationGateway {
  final List<TimerNotificationSnapshot> timerSnapshots = [];
  int timerCancelCount = 0;
  bool failTimerPresentation = false;

  @override
  Future<bool> cancelTaskReminder(TaskReminderIdentity identity) async => true;

  @override
  Future<void> cancelTimer() async => timerCancelCount++;

  @override
  Future<bool> scheduleTaskReminder(TaskReminderSnapshot snapshot) async =>
      true;

  @override
  Future<void> showTaskReminder(TaskReminderSnapshot snapshot) async {}

  @override
  Future<void> showTimer(TimerNotificationSnapshot snapshot) async {
    if (failTimerPresentation) throw StateError('presentation failed');
    timerSnapshots.add(snapshot);
  }
}
