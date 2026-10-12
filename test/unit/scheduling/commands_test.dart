import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timeline/domain/commands/batch_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/create_task_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/delete_task_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/duplicate_task_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/move_task_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/resize_task_command.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';
import 'package:personal_planner/features/inbox/data/inbox_repository.dart';
import 'package:personal_planner/features/inbox/domain/inbox_commands.dart';

import '../../helpers/sqlite_setup.dart' as sqlite_setup;

void main() {
  sqlite_setup.setupSqliteForTests();
  late AppDatabase db;
  late TaskRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = TaskRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  final day = DateTime(2026, 7, 23);

  Task newTask(String title, DateTime start, DateTime end, {String id = ''}) =>
      Task(
        id: id,
        title: title,
        startTime: start,
        endTime: end,
        createdAt: DateTime(2026, 7, 1),
        updatedAt: DateTime(2026, 7, 1),
      );

  group('CreateTaskCommand', () {
    test(
      'execute inserts; undo tombstones so redo restores the aggregate',
      () async {
        final command = CreateTaskCommand(
          repo,
          newTask(
            'Created',
            day.add(const Duration(hours: 9)),
            day.add(const Duration(hours: 10)),
            id: 'create-test-id',
          ),
        );
        await command.execute();
        var fetched = await repo.getTaskById('create-test-id');
        expect(fetched, isNotNull);
        expect(fetched!.title, 'Created');

        await command.undo();
        fetched = await repo.getTaskById('create-test-id');
        expect(fetched, isNotNull);
        expect(fetched!.deletedAt, isNotNull);

        // Redo restores the same id without a conflict.
        await command.execute();
        fetched = await repo.getTaskById('create-test-id');
        expect(fetched!.title, 'Created');
        expect(fetched.deletedAt, isNull);
      },
    );

    test(
      'creation derives exact planned duration from both endpoints',
      () async {
        final scheduled =
            newTask(
              'Proposal',
              day.add(const Duration(hours: 16)),
              day.add(const Duration(hours: 17, minutes: 30)),
              id: 'proposal-task',
            ).copyWith(
              description: 'Details\n\n  with indentation',
              estimatedDurationMin: 16,
            );
        await CreateTaskCommand(repo, scheduled).execute();

        final fetched = await repo.getTaskById(scheduled.id);
        expect(fetched?.description, 'Details\n\n  with indentation');
        expect(fetched?.estimatedDurationMin, 90);

        final overnight = newTask(
          'Overnight',
          day.add(const Duration(hours: 23, minutes: 30)),
          day.add(const Duration(days: 1, minutes: 30)),
          id: 'overnight-task',
        );
        await CreateTaskCommand(repo, overnight).execute();
        expect(
          (await repo.getTaskById(overnight.id))?.estimatedDurationMin,
          60,
        );
      },
    );
  });

  test(
    'DeleteTaskCommand closes an active session before tombstoning',
    () async {
      final task = await repo.insertTask(
        newTask(
          'Timing delete',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 9)),
        ),
      );
      await TimerService(db).start(task.id);

      await DeleteTaskCommand(repository: repo, original: task).execute();

      expect(await db.timerDao.getActiveTimerForTask(task.id), isNull);
      expect(
        (await db.timerDao.getSessionsForTask(task.id)).single.endedAt,
        isNotNull,
      );
      expect((await repo.getTaskById(task.id))!.deletedAt, isNotNull);
    },
  );

  group('MoveTaskCommand', () {
    test('execute moves to new slot; undo restores original', () async {
      final inserted = await repo.insertTask(
        newTask(
          'Movable',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 9)),
        ),
      );
      final newStart = day.add(const Duration(hours: 14));
      final newEnd = day.add(const Duration(hours: 15));
      final command = MoveTaskCommand(
        repository: repo,
        original: inserted,
        newStart: newStart,
        newEnd: newEnd,
      );

      await command.execute();
      var fetched = await repo.getTaskById(inserted.id);
      expect(fetched!.startTime, newStart);
      expect(fetched.endTime, newEnd);
      expect(
        fetched.updatedAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(inserted.updatedAt.millisecondsSinceEpoch),
      );

      await command.undo();
      fetched = await repo.getTaskById(inserted.id);
      expect(fetched!.startTime, inserted.startTime);
      expect(fetched.endTime, inserted.endTime);
      expect(fetched.deletedAt, isNull);
    });

    test('does not overwrite a concurrent schedule edit', () async {
      final inserted = await repo.insertTask(
        newTask(
          'Concurrent move',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 9)),
        ),
      );
      final command = MoveTaskCommand(
        repository: repo,
        original: inserted,
        newStart: day.add(const Duration(hours: 12)),
        newEnd: day.add(const Duration(hours: 13)),
      );
      await repo.updateTask(
        inserted.copyWith(
          startTime: day.add(const Duration(hours: 10)),
          endTime: day.add(const Duration(hours: 11)),
        ),
      );

      await expectLater(command.execute(), throwsStateError);
      final current = await repo.getTaskById(inserted.id);
      expect(current!.startTime, day.add(const Duration(hours: 10)));
      expect(current.endTime, day.add(const Duration(hours: 11)));
    });
  });

  group('ResizeTaskCommand', () {
    test('execute extends end_time; undo restores it', () async {
      final inserted = await repo.insertTask(
        newTask(
          'Resizable',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 9)),
        ),
      );
      final newEnd = day.add(const Duration(hours: 11));
      final command = ResizeTaskCommand(
        repository: repo,
        original: inserted,
        newEnd: newEnd,
      );

      await command.execute();
      var fetched = await repo.getTaskById(inserted.id);
      expect(fetched!.endTime, newEnd);
      expect(fetched.startTime, inserted.startTime); // start untouched
      expect(fetched.estimatedDurationMin, 180);

      await command.undo();
      fetched = await repo.getTaskById(inserted.id);
      expect(fetched!.endTime, inserted.endTime);
      expect(fetched.estimatedDurationMin, 60);
    });

    test('does not overwrite a concurrent move before resizing', () async {
      final inserted = await repo.insertTask(
        newTask(
          'Concurrent resize',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 9)),
        ),
      );
      final command = ResizeTaskCommand(
        repository: repo,
        original: inserted,
        newEnd: day.add(const Duration(hours: 10)),
      );
      await repo.updateTask(
        inserted.copyWith(
          startTime: day.add(const Duration(hours: 11)),
          endTime: day.add(const Duration(hours: 12)),
        ),
      );

      await expectLater(command.execute(), throwsStateError);
      final current = await repo.getTaskById(inserted.id);
      expect(current!.startTime, day.add(const Duration(hours: 11)));
      expect(current.endTime, day.add(const Duration(hours: 12)));
    });
  });

  group('DeleteTaskCommand', () {
    test('execute soft-deletes; undo restores from snapshot', () async {
      final inserted = await repo.insertTask(
        newTask(
          'Deletable',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 9)),
        ),
      );
      final command = DeleteTaskCommand(repository: repo, original: inserted);

      await command.execute();
      var inDay = await repo.watchTasksForDay(day).first;
      expect(inDay, isEmpty);
      var fetched = await repo.getTaskById(inserted.id);
      expect(fetched!.deletedAt, isNotNull);

      await command.undo();
      inDay = await repo.watchTasksForDay(day).first;
      expect(inDay, hasLength(1));
      fetched = await repo.getTaskById(inserted.id);
      expect(fetched!.deletedAt, isNull);
      expect(fetched.title, 'Deletable');
    });
  });

  test('repository rejects illegal status transitions', () async {
    final inserted = await repo.insertTask(
      newTask('Terminal status', day, day.add(const Duration(hours: 1))),
    );
    await repo.updateTask(inserted.copyWith(status: TaskStatus.completed));

    await expectLater(
      repo.updateTask(
        (await repo.getTaskById(inserted.id))!
            .copyWith(status: TaskStatus.inProgress),
      ),
      throwsStateError,
    );
  });

  group('BatchCommand with real commands', () {
    test('move + shift batch undoes everything in reverse', () async {
      final a = await repo.insertTask(
        newTask(
          'A',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 9)),
        ),
      );
      final b = await repo.insertTask(
        newTask(
          'B',
          day.add(const Duration(hours: 9)),
          day.add(const Duration(hours: 10)),
        ),
      );

      // Move A onto B's slot and shift B one hour later.
      final moveA = MoveTaskCommand(
        repository: repo,
        original: a,
        newStart: day.add(const Duration(hours: 9)),
        newEnd: day.add(const Duration(hours: 10)),
      );
      final shiftB = MoveTaskCommand(
        repository: repo,
        original: b,
        newStart: day.add(const Duration(hours: 10)),
        newEnd: day.add(const Duration(hours: 11)),
      );
      final batch = BatchCommand([moveA, shiftB]);

      await batch.execute();
      var fa = await repo.getTaskById(a.id);
      var fb = await repo.getTaskById(b.id);
      expect(fa!.startTime, day.add(const Duration(hours: 9)));
      expect(fb!.startTime, day.add(const Duration(hours: 10)));

      await batch.undo(); // reverse: B first, then A
      fa = await repo.getTaskById(a.id);
      fb = await repo.getTaskById(b.id);
      expect(fa!.startTime, a.startTime);
      expect(fb!.startTime, b.startTime);
    });
  });

  group('Inbox scheduling commands', () {
    test('creates a session, keeps the idea, and guarded undo/redo preserve unrelated work', () async {
      final inbox = InboxRepository(db);
      final capture = await inbox.addToInbox(
        '  Raw capture\n\nwith indentation  ',
        dueDate: '2026-07-30',
      );
      final start = day.add(const Duration(hours: 16));
      final end = day.add(const Duration(hours: 17, minutes: 30));
      final command = ScheduleInboxItemCommand(
        repository: inbox,
        itemId: capture.id,
        start: start,
        end: end,
        title: 'Prepare proposal',
        description: 'with indentation',
      );

      await command.execute();
      final session = await repo.getTaskById(command.sessionId);
      expect(session!.isInbox, isFalse);
      expect(session.inboxItemId, capture.id);
      expect(session.title, 'Prepare proposal');
      expect(session.description, 'with indentation');
      expect(session.scheduledDuration, const Duration(minutes: 90));
      expect(session.status, TaskStatus.planned);
      // The idea is not converted; only its legacy due date is cleared.
      var idea = await repo.getTaskById(capture.id);
      expect(idea!.isInbox, isTrue);
      expect(idea.title, 'Inbox capture');
      expect(idea.description, capture.description);
      expect(idea.startTime, isNull);
      expect(idea.dueDate, isNull);

      // Manual Actual is an owned timer/accounting source, not an ordinary
      // task field, so it is independent of the guarded undo.
      await TimerService(db).setManualActual(command.sessionId, 10);
      await command.undo();
      final undone = await repo.getTaskById(command.sessionId);
      expect(undone!.deletedAt, isNotNull);
      expect(undone.manualDurationAdjustmentMin, 10);
      // Undo leaves the idea as it was before the command, due date too.
      idea = await repo.getTaskById(capture.id);
      expect(idea!.isInbox, isTrue);
      expect(idea.deletedAt, isNull);
      expect(idea.dueDate, '2026-07-30');

      await command.execute();
      final redone = await repo.getTaskById(command.sessionId);
      expect(redone!.deletedAt, isNull);
      expect(redone.inboxItemId, capture.id);
      expect(redone.title, 'Prepare proposal');
      expect((await repo.getTaskById(capture.id))!.dueDate, isNull);
    });

    test('the session title and description default from the idea', () async {
      final inbox = InboxRepository(db);
      final capture = await inbox.addToInbox('First line\nsecond\nthird');
      final command = ScheduleInboxItemCommand(
        repository: inbox,
        itemId: capture.id,
        start: day.add(const Duration(hours: 11)),
        end: day.add(const Duration(hours: 12)),
      );
      await command.execute();
      final session = await repo.getTaskById(command.sessionId);
      expect(session!.title, 'First line');
      expect(session.description, 'second\nthird');
    });

    test('guarded undo refuses completed, timed or edited sessions', () async {
      final inbox = InboxRepository(db);
      final capture = await inbox.addToInbox('Retry me');
      final command = ScheduleInboxItemCommand(
        repository: inbox,
        itemId: capture.id,
        start: day.add(const Duration(hours: 11)),
        end: day.add(const Duration(hours: 12)),
        title: 'Retried task',
      );
      await command.execute();
      expect(command.didMutate, isTrue);

      final created = (await repo.getTaskById(command.sessionId))!;
      await repo.updateTask(created.copyWith(title: 'Renamed in Day'));
      await expectLater(command.undo(), throwsStateError);
      await repo.updateTask(
        (await repo.getTaskById(command.sessionId))!
            .copyWith(title: 'Retried task', status: TaskStatus.completed),
      );
      await expectLater(command.undo(), throwsStateError);
      expect((await repo.getTaskById(command.sessionId))!.deletedAt, isNull);
      expect((await repo.getTaskById(capture.id))!.isInbox, isTrue);
    });

    test('an idea that was closed in the meantime is refused', () async {
      final inbox = InboxRepository(db);
      final capture = await inbox.addToInbox('Closed before the drop');
      await inbox.closeItem(
        capture.id,
        'Not needed',
        DateTime.utc(2026, 7, 23),
      );
      final command = ScheduleInboxItemCommand(
        repository: inbox,
        itemId: capture.id,
        start: day.add(const Duration(hours: 11)),
        end: day.add(const Duration(hours: 12)),
      );
      await expectLater(command.execute(), throwsStateError);
      expect(await repo.getTaskById(command.sessionId), isNull);
    });
  });

  test(
    'DuplicateTaskCommand clears an Inbox due date on the new plan',
    () async {
      final source = await repo.insertTask(
        newTask(
          'Duplicate source',
          day.add(const Duration(hours: 8)),
          day.add(const Duration(hours: 9)),
        ).copyWith(dueDate: '2026-07-30'),
      );
      final command = DuplicateTaskCommand(
        repository: repo,
        source: source,
        newStart: day.add(const Duration(hours: 10)),
        newEnd: day.add(const Duration(hours: 11)),
      );
      await command.execute();

      final all = await db.taskDao.getTasksForDay(day);
      final copy = all.singleWhere((row) => row.id != source.id);
      expect(copy.dueDate, isNull);
    },
  );
}
