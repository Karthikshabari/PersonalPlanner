import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/settings/providers/notification_settings_providers.dart';
import 'package:personal_planner/features/sync/data/secure_session_storage.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/domain/notification_coordinator.dart';
import 'package:personal_planner/features/timer/domain/notification_service.dart';
import 'package:personal_planner/features/timer/domain/planner_notification.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();
  // This file deliberately opens independent account databases and, in one
  // race regression, two connections to the same temporary SQLite file.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

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

    test(
      'daily-review preference stays enabled when permission is denied',
      () async {
        final denied = _PermissionNotificationService();
        final store = _MemoryKeyValueStore();
        final isolated = ProviderContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            notificationServiceProvider.overrideWithValue(denied),
            notificationPermissionControllerProvider.overrideWithValue(
              NotificationPermissionController(
                notifications: denied,
                store: store,
                runtimePermissionRequired: () => true,
              ),
            ),
          ],
        );
        addTearDown(isolated.dispose);

        await isolated
            .read(reviewReminderEnabledProvider.notifier)
            .setEnabled(true);

        expect(
          await isolated.read(reviewReminderEnabledProvider.future),
          isTrue,
        );
        expect(await setting(reminderEnabledKey), 'true');
        expect(denied.permissionRequests, 1);
      },
    );
  });

  group('Android notification permission', () {
    test('fresh denial requests once and persists the attempt', () async {
      final gateway = _FakePermissionGateway(grantOnRequest: false);
      final store = _MemoryKeyValueStore();
      final controller = NotificationPermissionController(
        notifications: gateway,
        store: store,
        runtimePermissionRequired: () => true,
      );

      expect(await controller.ensureForFeatureUse(), isFalse);
      expect(await controller.ensureForFeatureUse(), isFalse);
      expect(gateway.requestCount, 1);
      expect(
        await store.containsKey(key: notificationPermissionAttemptedKey),
        isTrue,
      );
    });

    test('already granted and non-Android paths never prompt', () async {
      final granted = _FakePermissionGateway(
        grantOnRequest: false,
        enabled: true,
      );
      final store = _MemoryKeyValueStore();
      expect(
        await NotificationPermissionController(
          notifications: granted,
          store: store,
          runtimePermissionRequired: () => true,
        ).ensureForFeatureUse(),
        isTrue,
      );
      expect(granted.requestCount, 0);

      final nonAndroid = _FakePermissionGateway(grantOnRequest: false);
      expect(
        await NotificationPermissionController(
          notifications: nonAndroid,
          store: store,
          runtimePermissionRequired: () => false,
        ).ensureForFeatureUse(),
        isTrue,
      );
      expect(nonAndroid.enabledChecks, 0);
      expect(nonAndroid.requestCount, 0);
    });

    test('grant reconciles an existing timer and future reminder', () async {
      final now = DateTime.utc(2026, 9, 22, 9);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final tasks = TaskRepository(db, clock: () => now);
      final runningTask = await tasks.insertTask(
        Task(
          id: '10101010-1010-4010-8010-101010101010',
          title: 'Running',
          startTime: now,
          endTime: now.add(const Duration(hours: 1)),
          createdAt: now,
          updatedAt: now,
        ),
      );
      await TimerService(db, clock: () => now).start(runningTask.id);
      final planned = await tasks.insertTask(
        Task(
          id: '20202020-2020-4020-8020-202020202020',
          title: 'Future',
          startTime: now.add(const Duration(hours: 2)),
          endTime: now.add(const Duration(hours: 3)),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final gateway = _FakePermissionGateway(grantOnRequest: true);
      final controller = NotificationPermissionController(
        notifications: gateway,
        store: _MemoryKeyValueStore(),
        runtimePermissionRequired: () => true,
      );
      final notifications = _FakeNotifications();
      final coordinator = PlannerNotificationCoordinator(
        database: db,
        notifications: notifications,
        accountId: null,
        clock: () => now,
        ensureNotificationPermission: controller.ensureForFeatureUse,
      );
      addTearDown(coordinator.dispose);

      await coordinator.start();
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(gateway.requestCount, 1);
      expect(notifications.timerSnapshots.single.taskId, runningTask.id);
      expect(notifications.scheduled, contains(planned.id));
    });

    test(
      'denial leaves timer/task state intact and restart does not prompt',
      () async {
        final now = DateTime.utc(2026, 9, 22, 9);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final tasks = TaskRepository(db, clock: () => now);
        final task = await tasks.insertTask(
          Task(
            id: '30303030-3030-4030-8030-303030303030',
            title: 'Denied notification',
            startTime: now,
            endTime: now.add(const Duration(hours: 1)),
            createdAt: now,
            updatedAt: now,
          ),
        );
        await TimerService(db, clock: () => now).start(task.id);
        final gateway = _FakePermissionGateway(grantOnRequest: false);
        final store = _MemoryKeyValueStore();
        final notifications = _FakeNotifications();

        for (var attempt = 0; attempt < 2; attempt++) {
          final coordinator = PlannerNotificationCoordinator(
            database: db,
            notifications: notifications,
            accountId: null,
            clock: () => now,
            ensureNotificationPermission: NotificationPermissionController(
              notifications: gateway,
              store: store,
              runtimePermissionRequired: () => true,
            ).ensureForFeatureUse,
          );
          await coordinator.start();
          for (var i = 0; i < 8; i++) {
            await Future<void>.delayed(Duration.zero);
          }
          await coordinator.dispose();
        }

        expect(gateway.requestCount, 1);
        expect(notifications.timerSnapshots, isEmpty);
        expect(
          (await tasks.getTaskById(task.id))?.status,
          TaskStatus.inProgress,
        );
        expect(
          (await db.timerDao.getSessionsForTask(task.id)).single.state,
          'running',
        );
      },
    );
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

    test('remote-style completion apply cancels a pending reminder', () async {
      final task = await insertPlanned();
      await settle();
      expect(notifications.scheduled, contains(task.id));
      await db.syncDao.runWithoutOutbound(() async {
        await (db.update(
          db.tasks,
        )..where((row) => row.id.equals(task.id))).write(
          TasksCompanion(
            status: const Value('completed'),
            updatedAt: Value(now.add(const Duration(minutes: 1))),
          ),
        );
      });
      await settle();
      expect(notifications.scheduled, isNot(contains(task.id)));
      expect(notifications.cancelled, contains(task.id));
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

    test('durable ledger cancels an invalid reminder after restart', () async {
      final task = await insertPlanned();
      await settle();
      expect(notifications.scheduled, contains(task.id));
      expect(
        await db.syncDao.getSetting(ReminderPresentationLedger.settingKey),
        isNotNull,
      );

      await coordinator.dispose();
      await tasks.updateTask(task.copyWith(status: TaskStatus.completed));
      coordinator = PlannerNotificationCoordinator(
        database: db,
        notifications: notifications,
        accountId: null,
        clock: () => now,
      );
      await coordinator.start();
      await settle();

      expect(notifications.cancelled, contains(task.id));
      expect(notifications.scheduled, isNot(contains(task.id)));
      expect(
        await db.syncDao.getSetting(ReminderPresentationLedger.settingKey),
        isNull,
      );
    });

    test(
      'restart preserves a still-valid reminder without duplicating it',
      () async {
        final task = await insertPlanned();
        await settle();
        expect(notifications.scheduleAttempts, hasLength(1));

        await coordinator.dispose();
        coordinator = PlannerNotificationCoordinator(
          database: db,
          notifications: notifications,
          accountId: null,
          clock: () => now,
        );
        await coordinator.start();
        await settle();

        expect(notifications.scheduleAttempts, hasLength(1));
        expect(notifications.scheduled, contains(task.id));
      },
    );

    test(
      'restart replaces a rescheduled occurrence and cancels the old one',
      () async {
        final task = await insertPlanned();
        await settle();
        final oldIdentity = notifications.scheduled[task.id]!.identity;
        await coordinator.dispose();
        final moved = task.copyWith(
          startTime: task.startTime!.add(const Duration(hours: 2)),
          endTime: task.endTime!.add(const Duration(hours: 2)),
        );
        await tasks.updateTask(moved);

        coordinator = PlannerNotificationCoordinator(
          database: db,
          notifications: notifications,
          accountId: null,
          clock: () => now,
        );
        await coordinator.start();
        await settle();

        expect(notifications.scheduleAttempts, hasLength(2));
        expect(notifications.cancelledIdentities, contains(oldIdentity));
        expect(
          notifications.scheduled[task.id]?.plannedStart.millisecondsSinceEpoch,
          moved.startTime?.millisecondsSinceEpoch,
        );
      },
    );

    test(
      'restart cancels reminders after a synced tombstone and timer insertion',
      () async {
        final deleted = await insertPlanned();
        final started = await insertPlanned(
          id: '45454545-4545-4545-8545-454545454545',
        );
        await settle();
        expect(
          notifications.scheduled.keys,
          containsAll([deleted.id, started.id]),
        );
        await coordinator.dispose();

        await db.syncDao.runWithoutOutbound(() async {
          await (db.update(db.tasks)..where((row) => row.id.equals(deleted.id)))
              .write(TasksCompanion(deletedAt: Value(now)));
          await db.timerDao.insertSession(
            TimerSessionsCompanion.insert(
              id: '46464646-4646-4646-8646-464646464646',
              taskId: started.id,
              startedAt: now,
              state: const Value('running'),
              runningSince: Value(now),
              ownerDeviceId: const Value('synced-foreign-device'),
              createdAt: now,
              updatedAt: now,
            ),
          );
        });

        coordinator = PlannerNotificationCoordinator(
          database: db,
          notifications: notifications,
          accountId: null,
          clock: () => now,
        );
        await coordinator.start();
        await settle();

        expect(notifications.scheduled, isNot(contains(deleted.id)));
        expect(notifications.scheduled, isNot(contains(started.id)));
        expect(notifications.cancelled, containsAll([deleted.id, started.id]));
      },
    );

    test(
      'failed scheduling is not cached and ordinary restart retries',
      () async {
        notifications.remainingScheduleFailures = 2;
        final task = await insertPlanned();
        await settle();
        expect(notifications.scheduleAttempts, hasLength(2));
        expect(notifications.scheduled, isNot(contains(task.id)));
        expect(
          await db.syncDao.getSetting(ReminderPresentationLedger.settingKey),
          isNull,
        );

        await coordinator.dispose();
        coordinator = PlannerNotificationCoordinator(
          database: db,
          notifications: notifications,
          accountId: null,
          clock: () => now,
        );
        await coordinator.start();
        await settle();

        expect(notifications.scheduleAttempts, hasLength(3));
        expect(notifications.scheduled.keys, [task.id]);
        final ledger = await ReminderPresentationLedger(
          db,
          accountId: null,
        ).read();
        expect(ledger.values.single.taskId, task.id);
      },
    );

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
      'Start now atomically rejects a reschedule after preliminary validation',
      () async {
        final task = await insertPlanned();
        final reminder = TaskReminderSnapshot(
          accountId: null,
          taskId: task.id,
          taskTitle: task.title,
          plannedStart: task.startTime!,
        );
        final changed = await PlannerNotificationActionDispatcher(
          database: db,
          notifications: notifications,
          accountId: null,
          clock: () => now,
          beforeAuthoritativeReminderStart: () async {
            await tasks.updateTask(
              task.copyWith(
                startTime: task.startTime!.add(const Duration(hours: 2)),
                endTime: task.endTime!.add(const Duration(hours: 2)),
              ),
            );
          },
        ).dispatch(PlannerNotificationAction.startNow, reminder.payload);

        expect(changed, isFalse);
        expect(await db.timerDao.getSessionsForTask(task.id), isEmpty);
        expect((await tasks.getTaskById(task.id))?.status, TaskStatus.planned);
      },
    );

    test(
      'Start now atomically rejects completion and deletion races',
      () async {
        final completed = await insertPlanned();
        final completedReminder = TaskReminderSnapshot(
          accountId: null,
          taskId: completed.id,
          taskTitle: completed.title,
          plannedStart: completed.startTime!,
        );
        expect(
          await PlannerNotificationActionDispatcher(
            database: db,
            notifications: notifications,
            accountId: null,
            clock: () => now,
            beforeAuthoritativeReminderStart: () => tasks.updateTask(
              completed.copyWith(status: TaskStatus.completed),
            ),
          ).dispatch(
            PlannerNotificationAction.startNow,
            completedReminder.payload,
          ),
          isFalse,
        );
        expect(await db.timerDao.getSessionsForTask(completed.id), isEmpty);

        final deleted = await insertPlanned(
          id: '55555555-5555-4555-8555-555555555555',
        );
        final deletedReminder = TaskReminderSnapshot(
          accountId: null,
          taskId: deleted.id,
          taskTitle: deleted.title,
          plannedStart: deleted.startTime!,
        );
        expect(
          await PlannerNotificationActionDispatcher(
            database: db,
            notifications: notifications,
            accountId: null,
            clock: () => now,
            beforeAuthoritativeReminderStart: () =>
                tasks.deleteTask(deleted.id),
          ).dispatch(
            PlannerNotificationAction.startNow,
            deletedReminder.payload,
          ),
          isFalse,
        );
        expect(await db.timerDao.getSessionsForTask(deleted.id), isEmpty);
      },
    );

    test(
      'Start now does not duplicate a session won by another actor',
      () async {
        final task = await insertPlanned();
        final reminder = TaskReminderSnapshot(
          accountId: null,
          taskId: task.id,
          taskTitle: task.title,
          plannedStart: task.startTime!,
        );
        expect(
          await PlannerNotificationActionDispatcher(
            database: db,
            notifications: notifications,
            accountId: null,
            clock: () => now,
            beforeAuthoritativeReminderStart: () async {
              await TimerService(db, clock: () => now).start(task.id);
            },
          ).dispatch(PlannerNotificationAction.startNow, reminder.payload),
          isFalse,
        );
        expect(await db.timerDao.getSessionsForTask(task.id), hasLength(1));
      },
    );

    test('valid Start now preserves one-running-session switching', () async {
      final first = await insertPlanned();
      await TimerService(db, clock: () => now).start(first.id);
      final second = await insertPlanned(
        id: '66666666-6666-4666-8666-666666666666',
      );
      final reminder = TaskReminderSnapshot(
        accountId: null,
        taskId: second.id,
        taskTitle: second.title,
        plannedStart: second.startTime!,
      );
      expect(
        await PlannerNotificationActionDispatcher(
          database: db,
          notifications: notifications,
          accountId: null,
          clock: () => now,
        ).dispatch(PlannerNotificationAction.startNow, reminder.payload),
        isTrue,
      );
      expect(
        (await db.timerDao.getSessionsForTask(first.id)).single.state,
        'paused',
      );
      expect(
        (await db.timerDao.getSessionsForTask(second.id)).single.state,
        'running',
      );
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

  test(
    'Linux scheduler delegates the wait to one transient user timer',
    () async {
      final calls = <({String executable, List<String> arguments})>[];
      final scheduler = LinuxReminderScheduler(
        processRunner: (executable, arguments) async {
          calls.add((executable: executable, arguments: arguments));
          return ProcessResult(1, 0, '', '');
        },
      );
      final snapshot = TaskReminderSnapshot(
        accountId: null,
        taskId: '11111111-1111-4111-8111-111111111111',
        taskTitle: 'Planned task',
        plannedStart: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(await scheduler.schedule(snapshot), isTrue);

      expect(calls, hasLength(1));
      expect(calls.last.executable, 'systemd-run');
      expect(calls.last.arguments, contains('--user'));
      expect(calls.last.arguments, contains('--collect'));
      expect(
        calls.last.arguments,
        contains('--timer-property=AccuracySec=1min'),
      );
      expect(calls.last.arguments, contains('--planner-reminder-worker'));
      expect(calls.last.arguments, contains(startsWith('--on-calendar=')));
    },
    skip: !Platform.isLinux,
  );

  test('Linux systemd-run nonzero is a scheduling failure', () async {
    final scheduler = LinuxReminderScheduler(
      processRunner: (executable, arguments) async =>
          ProcessResult(1, 1, '', 'failed'),
    );
    final snapshot = TaskReminderSnapshot(
      accountId: null,
      taskId: '77777777-7777-4777-8777-777777777777',
      taskTitle: 'Planned task',
      plannedStart: DateTime.now().add(const Duration(hours: 1)),
    );
    expect(await scheduler.schedule(snapshot), isFalse);
  }, skip: !Platform.isLinux);

  test('Linux missing unit cancellation is benign', () async {
    final scheduler = LinuxReminderScheduler(
      processRunner: (executable, arguments) async =>
          ProcessResult(1, 5, '', 'Unit could not be found.'),
    );
    final identity = TaskReminderIdentity(
      accountId: null,
      taskId: '88888888-8888-4888-8888-888888888888',
      plannedStart: DateTime.now().add(const Duration(hours: 1)),
    );
    expect(await scheduler.cancel(identity), isTrue);
  }, skip: !Platform.isLinux);

  test('Android scheduling exception is reported as failure', () async {
    final service = NotificationService(
      isAndroid: () => true,
      isLinux: () => false,
      androidTaskReminderScheduler: (_) async => throw StateError('plugin'),
    );
    final snapshot = TaskReminderSnapshot(
      accountId: null,
      taskId: '99999999-9999-4999-8999-999999999999',
      taskTitle: 'Planned task',
      plannedStart: DateTime.now().add(const Duration(hours: 1)),
    );
    expect(await service.scheduleTaskReminder(snapshot), isFalse);
  });

  test(
    'second database connection cannot win the Start now TOCTOU race',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'planner_reminder_race_',
      );
      final file = File('${directory.path}/planner.sqlite');
      AppDatabase? foreground;
      AppDatabase? remote;
      try {
        final now = DateTime.utc(2026, 9, 22, 9);
        foreground = AppDatabase(NativeDatabase(file));
        final foregroundTasks = TaskRepository(foreground, clock: () => now);
        final task = await foregroundTasks.insertTask(
          Task(
            id: '12121212-1212-4212-8212-121212121212',
            title: 'Raced task',
            startTime: now.add(const Duration(hours: 1)),
            endTime: now.add(const Duration(hours: 2)),
            createdAt: now,
            updatedAt: now,
          ),
        );
        remote = AppDatabase(NativeDatabase(file));
        final reminder = TaskReminderSnapshot(
          accountId: null,
          taskId: task.id,
          taskTitle: task.title,
          plannedStart: task.startTime!,
        );
        final notifications = _FakeNotifications();

        expect(
          await PlannerNotificationActionDispatcher(
            database: foreground,
            notifications: notifications,
            accountId: null,
            clock: () => now,
            beforeAuthoritativeReminderStart: () async {
              final repository = TaskRepository(remote!, clock: () => now);
              final current = (await repository.getTaskById(task.id))!;
              await repository.updateTask(
                current.copyWith(
                  startTime: current.startTime!.add(const Duration(hours: 3)),
                  endTime: current.endTime!.add(const Duration(hours: 3)),
                ),
              );
            },
          ).dispatch(PlannerNotificationAction.startNow, reminder.payload),
          isFalse,
        );
        expect(await foreground.timerDao.getSessionsForTask(task.id), isEmpty);
      } finally {
        await remote?.close();
        await foreground?.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('reminder ledger is account scoped even on one storage seam', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final snapshot = TaskReminderSnapshot(
      accountId: 'account-a',
      taskId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      taskTitle: 'A task',
      plannedStart: DateTime.utc(2026, 9, 22, 10),
    );
    await ReminderPresentationLedger(
      db,
      accountId: 'account-a',
    ).write([snapshot]);
    expect(
      (await ReminderPresentationLedger(
        db,
        accountId: 'account-a',
      ).read()).values.single.taskId,
      snapshot.taskId,
    );
    expect(
      await ReminderPresentationLedger(db, accountId: 'account-b').read(),
      isEmpty,
    );
    expect(
      NotificationService.taskReminderPresentationId(snapshot.identity),
      isNot(
        NotificationService.taskReminderPresentationId(
          TaskReminderIdentity(
            accountId: 'account-b',
            taskId: snapshot.taskId,
            plannedStart: snapshot.plannedStart,
          ),
        ),
      ),
    );
  });

  test(
    'account A reconciliation never cancels account B presentation',
    () async {
      final now = DateTime.utc(2026, 9, 22, 9);
      final dbA = AppDatabase(NativeDatabase.memory());
      final dbB = AppDatabase(NativeDatabase.memory());
      addTearDown(dbA.close);
      addTearDown(dbB.close);
      const taskId = 'abababab-abab-4bab-8bab-abababababab';
      Future<Task> insert(AppDatabase db) =>
          TaskRepository(db, clock: () => now).insertTask(
            Task(
              id: taskId,
              title: 'Scoped task',
              startTime: now.add(const Duration(hours: 1)),
              endTime: now.add(const Duration(hours: 2)),
              createdAt: now,
              updatedAt: now,
            ),
          );
      final taskA = await insert(dbA);
      await insert(dbB);
      final notifications = _FakeNotifications();
      final coordinatorA = PlannerNotificationCoordinator(
        database: dbA,
        notifications: notifications,
        accountId: 'account-a',
        clock: () => now,
      );
      final coordinatorB = PlannerNotificationCoordinator(
        database: dbB,
        notifications: notifications,
        accountId: 'account-b',
        clock: () => now,
      );
      addTearDown(coordinatorA.dispose);
      addTearDown(coordinatorB.dispose);
      await coordinatorA.start();
      await coordinatorB.start();
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(notifications.scheduledByIdentity, hasLength(2));

      await TaskRepository(
        dbA,
        clock: () => now,
      ).updateTask(taskA.copyWith(status: TaskStatus.completed));
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(
        notifications.scheduledByIdentity.keys.single.accountId,
        'account-b',
      );
    },
  );
}

class _FakeNotifications implements PlannerNotificationGateway {
  final Map<String, TaskReminderSnapshot> scheduled = {};
  final Map<TaskReminderIdentity, TaskReminderSnapshot> scheduledByIdentity =
      {};
  final List<String> cancelled = [];
  final List<TaskReminderIdentity> cancelledIdentities = [];
  final List<TaskReminderSnapshot> scheduleAttempts = [];
  final List<TimerNotificationSnapshot> timerSnapshots = [];
  int remainingScheduleFailures = 0;

  @override
  Future<bool> cancelTaskReminder(TaskReminderIdentity identity) async {
    cancelled.add(identity.taskId);
    cancelledIdentities.add(identity);
    scheduledByIdentity.remove(identity);
    if (scheduled[identity.taskId]?.identity == identity) {
      scheduled.remove(identity.taskId);
    }
    return true;
  }

  @override
  Future<void> cancelTimer() async {}

  @override
  Future<bool> scheduleTaskReminder(TaskReminderSnapshot snapshot) async {
    scheduleAttempts.add(snapshot);
    if (remainingScheduleFailures > 0) {
      remainingScheduleFailures--;
      return false;
    }
    scheduled[snapshot.taskId] = snapshot;
    scheduledByIdentity[snapshot.identity] = snapshot;
    return true;
  }

  @override
  Future<void> showTaskReminder(TaskReminderSnapshot snapshot) async {}

  @override
  Future<void> showTimer(TimerNotificationSnapshot snapshot) async {
    timerSnapshots.add(snapshot);
  }
}

class _FakePermissionGateway implements NotificationPermissionGateway {
  _FakePermissionGateway({required this.grantOnRequest, this.enabled = false});

  final bool grantOnRequest;
  bool enabled;
  int requestCount = 0;
  int enabledChecks = 0;

  @override
  Future<bool> notificationsEnabled() async {
    enabledChecks++;
    return enabled;
  }

  @override
  Future<bool> requestPermission() async {
    requestCount++;
    if (grantOnRequest) enabled = true;
    return grantOnRequest;
  }
}

class _MemoryKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> _values = {};

  @override
  Future<bool> containsKey({required String key}) async =>
      _values.containsKey(key);

  @override
  Future<void> delete({required String key}) async => _values.remove(key);

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }
}

class _PermissionNotificationService extends NotificationService {
  int permissionRequests = 0;

  @override
  bool get schedulingSupported => true;

  @override
  Future<bool> notificationsEnabled() async => false;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return false;
  }

  @override
  Future<bool> scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async => false;
}
