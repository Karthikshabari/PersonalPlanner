import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/models/timer_session.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/domain/analytics_service.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/review/domain/daily_stats_service.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/data/timer_repository.dart';
import 'package:personal_planner/features/timer/domain/timer_service.dart';

import '../../helpers/sqlite_setup.dart';

/// F-016: the Insights "This Week" Actual and the Weekly Review "tracked"
/// figure must describe the same tracked time for the same week.
void main() {
  setupSqliteForTests();
  PlannerTimeZone.initialize(identifier: 'UTC');

  late AppDatabase db;
  late TaskRepository tasks;

  final monday = PlannerTimeZone.calendarDate(2026, 9, 21);
  // Wednesday noon: Friday is still in the future for the current week.
  final now = PlannerTimeZone.calendarDate(2026, 9, 23, hour: 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
    await CategoryRepository(db).seedDefaultsIfEmpty();
  });

  tearDown(() => db.close());

  Future<Task> seedTask(
    String title,
    int dayOffset, {
    int hour = 9,
    int? manualActualMin,
  }) {
    final start = addDays(monday, dayOffset).add(Duration(hours: hour));
    return tasks.insertTask(
      Task(
        id: '',
        title: title,
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
        actualDurationMin: manualActualMin,
        createdAt: monday,
        updatedAt: monday,
      ),
    );
  }

  test('Insights week Actual equals Weekly Review tracked time', () async {
    // (a) Soft-deleted task carrying a manual Actual and no timer history.
    final deleted = await seedTask(
      'Deleted with manual',
      0,
      manualActualMin: 25,
    );
    await tasks.deleteTask(deleted.id);

    // (b) Manual Actual on a task dated later in the current week.
    await seedTask('Friday with manual', 4, manualActualMin: 40);

    // (c) Finished timer session: 30 minutes on Tuesday.
    final tracked = await seedTask('Timed', 1);
    final sessionStart = addDays(monday, 1).add(const Duration(hours: 9));
    await TimerRepository(db).insertSession(
      TimerSession(
        id: '',
        taskId: tracked.id,
        startedAt: sessionStart,
        endedAt: sessionStart.add(const Duration(minutes: 30)),
        durationSec: 30 * 60,
        createdAt: sessionStart,
        updatedAt: sessionStart,
      ),
    );

    // (d) Running timer with 20 minutes of closed work before a resume.
    final running = await seedTask('Running', 2, hour: 10);
    var clock = addDays(monday, 2).add(const Duration(hours: 10));
    final timer = TimerService(db, clock: () => clock);
    await timer.start(running.id);
    clock = clock.add(const Duration(minutes: 20));
    await timer.pause();
    clock = clock.add(const Duration(minutes: 10));
    await timer.resume(running.id);
    final runningRow = (await db.timerDao.getSessionsForTask(running.id))
        .single;
    expect(runningRow.state, TimerSessionState.running.dbValue);
    expect(runningRow.durationSec, 20 * 60);

    final weekly = await DailyStatsService(db)
        .computeRange(monday, addDays(monday, 7));
    final insights = await InsightsService(db)
        .compute(weekStart: monday, now: now);

    // 25 (deleted manual) + 40 (later-dated manual) + 30 (finished session);
    // the running session is not counted until it is stopped.
    expect(weekly.actualDurationMin, 95);
    expect(insights.actualMinutes, weekly.actualDurationMin);
    expect(
      insights.categories.fold<int>(0, (sum, c) => sum + c.actualMinutes),
      weekly.actualDurationMin,
    );
  });
}
