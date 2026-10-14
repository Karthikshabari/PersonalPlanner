import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/features/inbox/data/inbox_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test('stampOverdue writes the planned end minute', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await db
          .into(db.tasks)
          .insert(
            TasksCompanion.insert(
              id: 'overdue-task',
              title: 'Overdue',
              startTime: Value(DateTime.utc(2026, 1, 1, 9)),
              endTime: Value(DateTime.utc(2026, 1, 1, 9, 30)),
              createdAt: DateTime.utc(2026, 1, 1, 8),
              updatedAt: DateTime.utc(2026, 1, 1, 8),
            ),
          );

      final stamped = await InboxRepository(db)
          .stampOverdue(DateTime.utc(2026, 1, 1, 11, 47));

      expect(stamped, 1);
      final row = (await db.taskDao.getTaskById('overdue-task'))!;
      expect(row.missedAt, '2026-01-01T09:30');
    } finally {
      await db.close();
    }
  });

  // C-002: the minute stamp must not wake every task stream when it changes
  // nothing.
  test(
    'stampOverdue notifies the tasks table only when it stamps a row',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final repository = InboxRepository(db);
        var notifications = 0;
        final subscription = db
            .tableUpdates(TableUpdateQuery.onTable(db.tasks))
            .listen((_) => notifications++);
        Future<void> flush() =>
            Future<void>.delayed(const Duration(milliseconds: 20));

        await db
            .into(db.tasks)
            .insert(
              TasksCompanion.insert(
                id: 'future-task',
                title: 'Not yet',
                startTime: Value(DateTime.utc(2026, 1, 1, 12)),
                endTime: Value(DateTime.utc(2026, 1, 1, 13)),
                createdAt: DateTime.utc(2026, 1, 1, 8),
                updatedAt: DateTime.utc(2026, 1, 1, 8),
              ),
            );
        await flush();
        notifications = 0;

        // Nothing is overdue: no rows change, no notification.
        expect(await repository.stampOverdue(DateTime.utc(2026, 1, 1, 11)), 0);
        await flush();
        expect(notifications, 0);

        // One block ends: one stamp, exactly one notification.
        expect(
          await repository.stampOverdue(DateTime.utc(2026, 1, 1, 13, 5)),
          1,
        );
        await flush();
        expect(notifications, 1);
        final row = (await db.taskDao.getTaskById('future-task'))!;
        expect(row.missedAt, '2026-01-01T13:00');

        // The next minute finds it already stamped.
        expect(
          await repository.stampOverdue(DateTime.utc(2026, 1, 1, 13, 6)),
          0,
        );
        await flush();
        expect(notifications, 1);
        await subscription.cancel();
      } finally {
        await db.close();
      }
    },
  );
}
