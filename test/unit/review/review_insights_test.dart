import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/domain/review_insights.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late TaskRepository tasks;
  late DateTime day;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
    day = startOfDay(DateTime.now().subtract(const Duration(days: 1)));
  });

  tearDown(() => db.close());

  test('derives final meaningful changes and next-day carryover', () async {
    final originalId = '00000000-0000-7000-8000-000000000201';
    final targetId = '00000000-0000-7000-8000-000000000202';
    await tasks.insertTask(
      Task(
        id: targetId,
        title: 'Backend development',
        startTime: addDays(day, 1).add(const Duration(hours: 10)),
        endTime: addDays(day, 1).add(const Duration(hours: 11)),
        createdAt: day,
        updatedAt: day,
      ),
    );
    await tasks.insertTask(
      Task(
        id: originalId,
        title: 'Backend development',
        startTime: day.add(const Duration(hours: 9)),
        endTime: day.add(const Duration(hours: 10)),
        status: TaskStatus.rescheduled,
        rescheduledToId: targetId,
        createdAt: day.subtract(const Duration(days: 2)),
        updatedAt: day,
      ),
    );
    final target = await db.taskDao.getTaskById(targetId);
    await tasks.updateTask(
      TaskRepository.fromRow(target!).copyWith(rescheduledFromId: originalId),
      allowRescheduledTransition: true,
    );
    await tasks.insertTask(
      Task(
        id: '00000000-0000-7000-8000-000000000203',
        title: 'Documentation',
        startTime: day.add(const Duration(hours: 13)),
        endTime: day.add(const Duration(hours: 14)),
        status: TaskStatus.completed,
        actualDurationMin: 90,
        manualActualSet: true,
        manualDurationAdjustmentMin: 90,
        createdAt: day.add(const Duration(hours: 2)),
        updatedAt: day,
      ),
    );

    final insights = await ReviewInsightsService(db).forDay(day);

    expect(
      insights.changes.map((change) => change.detail),
      containsAll(<String>[
        'Moved → Tomorrow · 10:00 AM',
        'Added during the day',
        '1h planned → 1h 30m tracked',
      ]),
    );
    expect(
      insights.changes.where((change) => change.kind == ReviewChangeKind.moved),
      hasLength(1),
    );
    expect(insights.carryover, hasLength(1));
    expect(insights.carryover.single.title, 'Backend development');
  });

  test('returns no changes for an unchanged empty day', () async {
    final insights = await ReviewInsightsService(db).forDay(day);
    expect(insights.changes, isEmpty);
    expect(insights.carryover, isEmpty);
  });
}
