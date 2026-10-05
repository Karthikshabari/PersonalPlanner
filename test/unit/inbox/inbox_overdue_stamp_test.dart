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
}
