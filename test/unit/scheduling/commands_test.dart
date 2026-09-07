import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timeline/domain/commands/batch_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/create_task_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/delete_task_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/move_task_command.dart';
import 'package:personal_planner/features/timeline/domain/commands/resize_task_command.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';

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

      await command.undo();
      fetched = await repo.getTaskById(inserted.id);
      expect(fetched!.endTime, inserted.endTime);
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
}
