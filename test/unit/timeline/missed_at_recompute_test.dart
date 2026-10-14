import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/inbox/data/inbox_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

/// UAT-007: `missed_at` is the planned end minute. A new end time clears it in
/// the same write, so the next stamp recomputes it; an unchanged end keeps it.
void main() {
  setupSqliteForTests();
  PlannerTimeZone.initialize(identifier: 'UTC');

  late AppDatabase db;
  late TaskRepository tasks;
  late InboxRepository inbox;
  final start = DateTime.utc(2026, 9, 22, 9);
  final later = DateTime.utc(2026, 9, 23, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
    inbox = InboxRepository(db);
  });

  tearDown(() => db.close());

  /// A 09:00-10:00 block, already stamped missed ("2026-09-22T10:00").
  Future<Task> missedBlock() async {
    final created = await tasks.insertTask(
      Task(
        id: '',
        title: 'Past block',
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
        createdAt: start,
        updatedAt: start,
      ),
    );
    await inbox.stampOverdue(later);
    final stamped = (await tasks.getTaskById(created.id))!;
    expect(stamped.missedAt, '2026-09-22T10:00');
    return stamped;
  }

  test(
    'changing the end time clears missed_at; the next stamp recomputes it',
    () async {
      final block = await missedBlock();

      final lengthened = await tasks.updateTask(
        block.copyWith(endTime: start.add(const Duration(hours: 3))),
      );
      expect(lengthened.missedAt, isNull);

      expect(await inbox.stampOverdue(later), 1);
      final restamped = (await tasks.getTaskById(block.id))!;
      expect(restamped.missedAt, '2026-09-22T12:00');
      expect(restamped.missedAt, isNot(block.missedAt));
    },
  );

  test('changing only the title keeps missed_at', () async {
    final block = await missedBlock();

    final renamed = await tasks.updateTask(block.copyWith(title: 'Renamed'));
    expect(renamed.missedAt, '2026-09-22T10:00');
    expect(await inbox.stampOverdue(later), 0);
    expect((await tasks.getTaskById(block.id))!.missedAt, '2026-09-22T10:00');
  });

  test('a block moved to the future is no longer missed', () async {
    final block = await missedBlock();
    final future = DateTime.utc(2026, 9, 25, 9);

    final moved = await tasks.updateTask(
      block.copyWith(
        startTime: future,
        endTime: future.add(const Duration(hours: 1)),
      ),
    );
    expect(moved.missedAt, isNull);
    expect(await inbox.stampOverdue(later), 0);
    expect((await tasks.getTaskById(block.id))!.missedAt, isNull);
  });
}
