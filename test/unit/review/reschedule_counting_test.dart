import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/domain/analytics_models.dart';
import 'package:personal_planner/features/analytics/domain/analytics_service.dart';
import 'package:personal_planner/features/review/domain/daily_stats_service.dart';
import 'package:personal_planner/features/review/domain/review_overview.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';
import 'package:personal_planner/features/review/domain/weekly_review_history.dart';
import 'package:personal_planner/features/review/domain/weekly_review_numbers.dart';
import 'package:personal_planner/features/review/domain/weekly_review_service.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

/// QA fix phase 1: one counting rule (`plan_counting.dart`) for planned
/// minutes and task counts across Review, Insights and the Weekly numbers.
void main() {
  setupSqliteForTests();
  PlannerTimeZone.initialize(identifier: 'UTC');

  late AppDatabase db;
  late TaskRepository tasks;
  final monday = PlannerTimeZone.calendarDate(2026, 9, 7);
  final tuesday = addDays(monday, 1);
  final wednesday = addDays(monday, 2);
  final now = PlannerTimeZone.calendarDate(2026, 9, 14, hour: 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
  });

  tearDown(() => db.close());

  Future<Task> block(
    String title,
    DateTime day,
    int hour,
    int minutes, {
    int minute = 0,
    TaskStatus status = TaskStatus.planned,
    String? from,
  }) {
    final start = PlannerTimeZone.calendarDate(
      day.year,
      day.month,
      day.day,
      hour: hour,
      minute: minute,
    );
    return tasks.insertTask(
      Task(
        id: '',
        title: title,
        startTime: start,
        endTime: start.add(Duration(minutes: minutes)),
        status: status,
        rescheduledFromId: from,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Moves [original] to a new block (as Needs attention does) and returns
  /// the new block with [status].
  Future<Task> reschedule(
    Task original,
    DateTime day,
    int hour, {
    TaskStatus status = TaskStatus.completed,
  }) async {
    final next = await block(original.title, day, hour, 60, from: original.id);
    await tasks.markRescheduled(original.id, next.id);
    if (status == TaskStatus.planned) return next;
    return tasks.updateTask(next.copyWith(status: status));
  }

  Future<ConsistencyDay> insightsDay(DateTime day) async {
    final snapshot = await InsightsService(db)
        .compute(weekStart: monday, now: now);
    return snapshot.consistencyDays.firstWhere(
      (entry) => isoDateString(entry.date) == isoDateString(day),
    );
  }

  group('planned minutes', () {
    test('same-day reschedule counts only the new block', () async {
      final original = await block('UAT-R', monday, 9, 60);
      await reschedule(original, monday, 14);

      final stats = await DailyStatsService(db).computeForDate(monday);
      expect(stats.plannedDurationMin, 60);
      final day = await insightsDay(monday);
      expect(day.plannedMinutes, 60);
      expect(day.completedPlannedMinutes, 60);
      expect(day.followThroughPercent, 100);
      expect(classifyDay(day, target: 0.6), DayResult.success);
    });

    test('a reschedule to another day leaves the original day Empty', () async {
      final original = await block('UAT-R', monday, 9, 60);
      await reschedule(original, tuesday, 14);

      final mon = await insightsDay(monday);
      expect(mon.plannedMinutes, 0);
      expect(classifyDay(mon, target: 0.6), DayResult.empty);
      final tue = await insightsDay(tuesday);
      expect(classifyDay(tue, target: 0.6), DayResult.success);
      expect(
        (await DailyStatsService(db).computeForDate(monday)).plannedDurationMin,
        0,
      );
    });

    test('Cancelled adds no minutes, also inside a union', () async {
      await block('A', wednesday, 9, 90, status: TaskStatus.completed);
      await block('C', wednesday, 11, 60, status: TaskStatus.cancelled);
      await block(
        'Inside',
        wednesday,
        9,
        30,
        minute: 30,
        status: TaskStatus.cancelled,
      );

      final stats = await DailyStatsService(db).computeForDate(wednesday);
      expect(stats.plannedDurationMin, 90);
      expect(stats.plannedOverlapMin, 0);
      final day = await insightsDay(wednesday);
      expect(day.plannedMinutes, 90);
      expect(day.followThroughPercent, 100);
      expect(classifyDay(day, target: 0.6), DayResult.success);
    });

    test('Skipped still counts as planned time', () async {
      await block('A', wednesday, 9, 60, status: TaskStatus.completed);
      await block('B', wednesday, 11, 60, status: TaskStatus.skipped);

      expect(
        (await DailyStatsService(db).computeForDate(wednesday))
            .plannedDurationMin,
        120,
      );
      expect((await insightsDay(wednesday)).followThroughPercent, 50);
    });

    test(
      'a rescheduled block whose new block was deleted counts again',
      () async {
        final original = await block('UAT-R', monday, 9, 60);
        final next = await reschedule(
          original,
          tuesday,
          14,
          status: TaskStatus.planned,
        );
        await tasks.deleteTask(next.id);

        expect(
          (await DailyStatsService(db).computeForDate(monday))
              .plannedDurationMin,
          60,
        );
        expect((await insightsDay(monday)).plannedMinutes, 60);
      },
    );
  });

  group('task counts', () {
    Future<WeeklyNumbers> week() async => computeWeeklyNumbers(
      await WeeklyReviewService(db).loadWeek(monday),
      now: now,
    );

    test('same-day reschedule is 1 of 1 with one Rescheduled row', () async {
      final original = await block('UAT-R', monday, 9, 60);
      await reschedule(original, monday, 14);

      final stats = await DailyStatsService(db).computeForDate(monday);
      expect(stats.totalTasks, 1);
      expect(stats.completedTasks, 1);
      expect(stats.rescheduledTasks, 1);

      final numbers = await week();
      expect(numbers.total, 1);
      expect(numbers.completed, 1);
      expect(numbers.rescheduled, 1);
      expect(numbers.days.first.total, 1);
      expect(numbers.outcomeRows.single.outcome, TaskOutcome.rescheduled);
      expect(numbers.outcomeRows.single.taskId, original.id);

      final overview = await ReviewOverviewService(db)
          .window(today: addDays(monday, 6), dayCount: 7);
      expect(overview.last.totalTasks, 1);
      expect(overview.last.completedTasks, 1);

      final history = await WeeklyReviewHistoryService(db)
          .load(addDays(monday, 7), weekCount: 1);
      expect(history.single.totalTasks, 1);
      expect(history.single.completedTasks, 1);
    });

    test('Cancelled still counts as a task: 1 of 2', () async {
      await block('A', wednesday, 9, 90, status: TaskStatus.completed);
      await block('C', wednesday, 11, 60, status: TaskStatus.cancelled);

      final stats = await DailyStatsService(db).computeForDate(wednesday);
      expect(stats.totalTasks, 2);
      expect(stats.completedTasks, 1);
      final numbers = await week();
      expect(numbers.total, 2);
      expect(numbers.completed, 1);
    });

    test('the active day hides a replaced block, not a dangling one', () async {
      final original = await block('UAT-R', monday, 9, 60);
      final next = await reschedule(
        original,
        monday,
        14,
        status: TaskStatus.planned,
      );
      List<String> ids(List<Task> list) => [for (final t in list) t.id];

      expect(ids(await tasks.watchActiveTasksForDay(monday).first), [next.id]);
      // A tombstoned new block: the old one is active again (healed or not).
      await (db.update(db.tasks)..where((t) => t.id.equals(next.id))).write(
        TasksCompanion(deletedAt: Value(now)),
      );
      expect(ids(await tasks.watchActiveTasksForDay(monday).first), [
        original.id,
      ]);
      expect((await week()).total, 1);
      expect(
        (await DailyStatsService(db).computeForDate(monday)).totalTasks,
        1,
      );
    });
  });
}
