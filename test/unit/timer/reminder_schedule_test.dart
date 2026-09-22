import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/settings/providers/notification_settings_providers.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/domain/notification_coordinator.dart';
import 'package:personal_planner/features/timer/domain/notification_service.dart';
import 'package:personal_planner/features/timer/domain/planner_notification.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  group('nextOccurrence', () {
    test('returns today when the time is still ahead', () {
      final now = DateTime(2026, 8, 25, 10);
      expect(
        NotificationService.nextOccurrence(now, 21, 0),
        DateTime(2026, 8, 25, 21),
      );
    });

    test('rolls over to tomorrow once the time has passed', () {
      final now = DateTime(2026, 8, 25, 22, 30);
      expect(
        NotificationService.nextOccurrence(now, 21, 0),
        DateTime(2026, 8, 26, 21),
      );
    });

    test('exact match rolls over (must be strictly in the future)', () {
      final now = DateTime(2026, 8, 25, 21);
      expect(
        NotificationService.nextOccurrence(now, 21, 0),
        DateTime(2026, 8, 26, 21),
      );
    });
  });

  group('reminder settings persistence', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() async {
      await db.close();
    });

    Future<String?> setting(String key) async {
      final row = await (db.select(
        db.appSettings,
      )..where((s) => s.key.equals(key))).getSingleOrNull();
      return row?.value;
    }

    test('defaults are enabled at 21:00', () async {
      expect(
        await container.read(reviewReminderEnabledProvider.future),
        isTrue,
      );
      expect(
        await container.read(reviewReminderMinutesProvider.future),
        defaultReminderMinutes,
      );
    });

    test('toggle persists to app_settings', () async {
      await container
          .read(reviewReminderEnabledProvider.notifier)
          .setEnabled(false);
      expect(await setting(reminderEnabledKey), 'false');

      await container
          .read(reviewReminderEnabledProvider.notifier)
          .setEnabled(true);
      expect(await setting(reminderEnabledKey), 'true');
    });

    test('time persists and re-reads', () async {
      await container
          .read(reviewReminderMinutesProvider.notifier)
          .setMinutes(8 * 60 + 35);
      expect(await setting(reminderTimeKey), '515');
      expect(await container.read(reviewReminderMinutesProvider.future), 515);
    });

    test('invalid stored time falls back to the default', () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(key: reminderTimeKey, value: '99999'),
          );
      expect(
        await container.read(reviewReminderMinutesProvider.future),
        defaultReminderMinutes,
      );
    });
  });

  group('planned task reminders', () {
    late AppDatabase db;
    late TaskRepository tasks;
    late _FakeNotifications notifications;
    late PlannerNotificationCoordinator coordinator;
    late DateTime now;

    setUp(() async {
      now = DateTime.utc(2026, 9, 21, 9);
      db = AppDatabase(NativeDatabase.memory());
      tasks = TaskRepository(db, clock: () => now);
      notifications = _FakeNotifications();
      coordinator = PlannerNotificationCoordinator(
        database: db,
        notifications: notifications,
        accountId: null,
        clock: () => now,
      );
      await coordinator.start();
    });

    tearDown(() async {
      await coordinator.dispose();
      await db.close();
    });

    Future<Task> insertPlanned({
      String id = '11111111-1111-4111-8111-111111111111',
    }) => tasks.insertTask(
      Task(
        id: id,
        title: 'Planned task',
        startTime: now.add(const Duration(hours: 1)),
        endTime: now.add(const Duration(hours: 2)),
        createdAt: now,
        updatedAt: now,
      ),
    );

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('planned task schedules for start plus five minutes', () async {
      final task = await insertPlanned();
      await settle();
      final reminder = notifications.scheduled[task.id];
      expect(
        reminder?.remindAt.millisecondsSinceEpoch,
        task.startTime!.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      );
    });

    test('start, completion and deletion cancel a pending reminder', () async {
      final startedTask = await insertPlanned();
      await settle();
      await TimerService(db, clock: () => now).start(startedTask.id);
      await settle();
      expect(notifications.scheduled, isNot(contains(startedTask.id)));

      final completed = await insertPlanned(
        id: '22222222-2222-4222-8222-222222222222',
      );
      await settle();
      await tasks.updateTask(completed.copyWith(status: TaskStatus.completed));
      await settle();
      expect(notifications.scheduled, isNot(contains(completed.id)));

      final deleted = await insertPlanned(
        id: '33333333-3333-4333-8333-333333333333',
      );
      await settle();
      await tasks.deleteTask(deleted.id);
      await settle();
      expect(notifications.scheduled, isNot(contains(deleted.id)));
    });

    test('reschedule replaces the original reminder', () async {
      final task = await insertPlanned();
      await settle();
      final moved = task.copyWith(
        startTime: task.startTime!.add(const Duration(hours: 3)),
        endTime: task.endTime!.add(const Duration(hours: 3)),
      );
      await tasks.updateTask(moved);
      await settle();
      expect(notifications.cancelled, contains(task.id));
      expect(
        notifications.scheduled[task.id]?.plannedStart.millisecondsSinceEpoch,
        moved.startTime?.millisecondsSinceEpoch,
      );
    });

    test('stale reminder does not display or start after reschedule', () async {
      final task = await insertPlanned();
      final stale = TaskReminderSnapshot(
        accountId: null,
        taskId: task.id,
        taskTitle: task.title,
        plannedStart: task.startTime!,
      );
      await tasks.updateTask(
        task.copyWith(
          startTime: task.startTime!.add(const Duration(hours: 1)),
          endTime: task.endTime!.add(const Duration(hours: 1)),
        ),
      );
      expect(
        await reminderStillApplies(
          db,
          await db.taskDao.getTaskById(task.id),
          stale.plannedStart,
        ),
        isFalse,
      );
      final changed = await PlannerNotificationActionDispatcher(
        database: db,
        notifications: notifications,
        accountId: null,
        clock: () => now,
      ).dispatch(PlannerNotificationAction.startNow, stale.payload);
      expect(changed, isFalse);
      expect((await tasks.getTaskById(task.id))?.status, TaskStatus.planned);
    });

    test(
      'Start now uses TimerService and Dismiss changes no task data',
      () async {
        final task = await insertPlanned();
        final reminder = TaskReminderSnapshot(
          accountId: null,
          taskId: task.id,
          taskTitle: task.title,
          plannedStart: task.startTime!,
        );
        final dispatcher = PlannerNotificationActionDispatcher(
          database: db,
          notifications: notifications,
          accountId: null,
          clock: () => now,
        );
        expect(
          await dispatcher.dispatch(
            PlannerNotificationAction.dismiss,
            reminder.payload,
          ),
          isTrue,
        );
        expect((await tasks.getTaskById(task.id))?.status, TaskStatus.planned);
        expect(await db.timerDao.getSessionsForTask(task.id), isEmpty);

        expect(
          await dispatcher.dispatch(
            PlannerNotificationAction.startNow,
            reminder.payload,
          ),
          isTrue,
        );
        expect(
          (await tasks.getTaskById(task.id))?.status,
          TaskStatus.inProgress,
        );
        expect(
          (await db.timerDao.getSessionsForTask(task.id)).single.state,
          'running',
        );
        expect(notifications.timerSnapshots, isNotEmpty);
        expect(
          notifications.timerSnapshots.last.sessionId,
          (await db.timerDao.getSessionsForTask(task.id)).single.id,
        );
      },
    );
  });
}

class _FakeNotifications implements PlannerNotificationGateway {
  final Map<String, TaskReminderSnapshot> scheduled = {};
  final List<String> cancelled = [];
  final List<TimerNotificationSnapshot> timerSnapshots = [];

  @override
  Future<void> cancelTaskReminder(String taskId) async {
    cancelled.add(taskId);
    scheduled.remove(taskId);
  }

  @override
  Future<void> cancelTimer() async {}

  @override
  Future<void> scheduleTaskReminder(TaskReminderSnapshot snapshot) async {
    scheduled[snapshot.taskId] = snapshot;
  }

  @override
  Future<void> showTaskReminder(TaskReminderSnapshot snapshot) async {}

  @override
  Future<void> showTimer(TimerNotificationSnapshot snapshot) async {
    timerSnapshots.add(snapshot);
  }
}
