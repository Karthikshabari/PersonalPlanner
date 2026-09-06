import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/daily_review.dart';
import 'package:personal_planner/core/models/daily_stats.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/models/timer_session.dart';
import 'package:personal_planner/core/models/weekly_review.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/review/domain/daily_stats_service.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timer/data/timer_repository.dart';
import 'package:personal_planner/core/utils/uuid.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late ReviewRepository reviews;
  late DailyStatsService statsService;
  late TaskRepository tasks;
  late CategoryRepository categories;

  // Yesterday: every seeded end time is guaranteed to be in the past, so the
  // "missed" classification is deterministic regardless of wall-clock time.
  late DateTime day;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    reviews = ReviewRepository(db);
    statsService = DailyStatsService(db);
    tasks = TaskRepository(db);
    categories = CategoryRepository(db);
    await categories.seedDefaultsIfEmpty();
    final now = DateTime.now();
    day = DateTime(now.year, now.month, now.day - 1);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> workCategoryId() async {
    final all = await db.categoryDao.getActiveCategories();
    return all.firstWhere((c) => c.name == 'Work').id;
  }

  /// Marks Work (the first category) as a focus category.
  Future<void> markWorkFocus() async {
    final all = await db.categoryDao.getActiveCategories();
    final work = all.firstWhere((c) => c.name == 'Work');
    await (db.update(db.categories)..where((c) => c.id.equals(work.id))).write(
      CategoriesCompanion(isFocus: const Value(true)),
    );
  }

  group('ReviewRepository daily', () {
    test('save inserts then updates the same row per date', () async {
      final saved = await reviews.saveDailyReview(
        DailyReview(
          id: '',
          date: day,
          reflection: 'First pass',
          energyLevel: 3,
          wins: ['Shipped chunk'],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final loaded = await reviews.getReviewForDate(day);
      expect(loaded!.id, saved.id);
      expect(
        saved.id,
        generateDeterministicUuid('daily-review:${isoDateString(day)}'),
      );
      expect(loaded.reflection, 'First pass');
      expect(loaded.wins, ['Shipped chunk']);
      expect(loaded.createdAt, saved.createdAt);

      final updated = await reviews.saveDailyReview(
        saved.copyWith(reflection: 'Edited', improvements: ['Sleep more']),
      );
      expect(updated.id, saved.id);
      final reloaded = await reviews.getReviewForDate(day);
      expect(reloaded!.reflection, 'Edited');
      expect(reloaded.improvements, ['Sleep more']);
      expect(reloaded.createdAt, saved.createdAt);
    });

    test('ratings are clamped to 1-5 and null passes through', () async {
      await reviews.saveDailyReview(
        DailyReview(
          id: '',
          date: day,
          energyLevel: 7,
          productivityRating: 0,
          planningAccuracyRating: null,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final loaded = await reviews.getReviewForDate(day);
      expect(loaded!.energyLevel, 5);
      expect(loaded.productivityRating, 1);
      expect(loaded.planningAccuracyRating, isNull);
    });

    test('watch emits the saved review and soft-delete hides it', () async {
      final saved = await reviews.saveDailyReview(
        DailyReview(
          id: '',
          date: day,
          reflection: 'Watched',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await expectLater(
        reviews.watchReviewForDate(day).first,
        completion(predicate<DailyReview?>((r) => r?.id == saved.id)),
      );

      await reviews.deleteDailyReview(saved.id);
      expect(await reviews.getReviewForDate(day), isNull);
      final raw = await (db.select(
        db.dailyReviews,
      )..where((r) => r.id.equals(saved.id))).getSingle();
      expect(raw.deletedAt, isNotNull);
    });
  });

  group('ReviewRepository weekly', () {
    test('save inserts then updates the same row per week', () async {
      final monday = startOfWeek(DateTime.now());
      final saved = await reviews.saveWeeklyReview(
        WeeklyReview(
          id: '',
          weekStartDate: monday,
          reflection: 'Week one',
          overallRating: 4,
          goalsMet: ['Plan daily'],
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final loaded = await reviews.getWeeklyReviewForWeek(monday);
      expect(loaded!.id, saved.id);
      expect(
        saved.id,
        generateDeterministicUuid('weekly-review:${isoDateString(monday)}'),
      );
      expect(loaded.goalsMet, ['Plan daily']);

      final updated = await reviews.saveWeeklyReview(
        saved.copyWith(reflection: 'Revised', nextWeekFocus: ['Timer']),
      );
      expect(updated.id, saved.id);
      final reloaded = await reviews.getWeeklyReviewForWeek(monday);
      expect(reloaded!.reflection, 'Revised');
      expect(reloaded.nextWeekFocus, ['Timer']);
      expect(reloaded.overallRating, 4);
    });
  });

  group('DailyStatsService', () {
    test(
      'computes counts, durations, focus hours and accuracy for a day',
      () async {
        await markWorkFocus();
        final workId = await workCategoryId();

        Future<Task> seed({
          required String title,
          required int startHour,
          required int durationMin,
          TaskStatus status = TaskStatus.planned,
          String? categoryId,
          int? estimated,
          int? actual,
        }) => tasks.insertTask(
          Task(
            id: '',
            title: title,
            startTime: DateTime(day.year, day.month, day.day, startHour),
            endTime: DateTime(
              day.year,
              day.month,
              day.day,
              startHour,
            ).add(Duration(minutes: durationMin)),
            status: status,
            categoryId: categoryId,
            estimatedDurationMin: estimated,
            actualDurationMin: actual,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        // Focus-category completed task with overrun (60 actual vs 90 est).
        await seed(
          title: 'Focus work',
          startHour: 9,
          durationMin: 90,
          status: TaskStatus.completed,
          categoryId: workId,
          estimated: 90,
          actual: 60,
        );
        // Non-focus completed without durations.
        await seed(
          title: 'Chores',
          startHour: 11,
          durationMin: 30,
          status: TaskStatus.completed,
        );
        // Missed: planned and already over.
        await seed(title: 'Missed call', startHour: 13, durationMin: 60);
        // Terminal statuses.
        await seed(
          title: 'Skip it',
          startHour: 15,
          durationMin: 30,
          status: TaskStatus.skipped,
        );
        await seed(
          title: 'Nope',
          startHour: 16,
          durationMin: 30,
          status: TaskStatus.cancelled,
        );
        await seed(
          title: 'Moved',
          startHour: 17,
          durationMin: 30,
          status: TaskStatus.rescheduled,
        );

        final stats = await statsService.computeAndCache(day);

        expect(stats.totalTasks, 6);
        expect(stats.completedTasks, 2);
        expect(stats.missedTasks, 1);
        expect(stats.skippedTasks, 1);
        expect(stats.cancelledTasks, 1);
        expect(stats.rescheduledTasks, 1);
        // 90 + 30 + 60 + 30 + 30 + 30
        expect(stats.plannedDurationMin, 270);
        expect(stats.actualDurationMin, 60);
        // Only the Work (focus) task counts toward focus duration.
        expect(stats.focusDurationMin, 90);
        // avg(actual/estimated) ×100 — only one task has both.
        expect(stats.planningAccuracyPct!, closeTo(66.67, 0.01));
        // completed / (total − cancelled) × 100 = 2 / 5.
        expect(stats.completionRatePct!, closeTo(40, 0.01));

        // Cached snapshot mirrors the computation.
        final cached = await db.statsDao.getStatsForDate(isoDateString(day));
        expect(cached!.totalTasks, 6);
        expect(cached.completedTasks, 2);
        expect(cached.focusDurationMin, 90);
        expect(cached.energyLevel, isNull);
      },
    );

    test('review save trigger refreshes cached review-linked fields', () async {
      await reviews.saveDailyReview(
        DailyReview(
          id: '',
          date: day,
          energyLevel: 4,
          productivityRating: 5,
          planningAccuracyRating: 3,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await statsService.computeAndCache(day);

      final cached = await db.statsDao.getStatsForDate(isoDateString(day));
      expect(cached!.energyLevel, 4);
      expect(cached.productivityRating, 5);
    });

    test('range aggregation sums across days of a week', () async {
      final weekStart = startOfWeek(DateTime.now());
      Future<void> seedOn(DateTime at, int plannedMin) => tasks.insertTask(
        Task(
          id: '',
          title: 'W',
          startTime: at,
          endTime: at.add(Duration(minutes: plannedMin)),
          status: TaskStatus.completed,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await seedOn(
        DateTime(weekStart.year, weekStart.month, weekStart.day, 9),
        30,
      );
      await seedOn(
        DateTime(weekStart.year, weekStart.month, weekStart.day + 1, 10),
        90,
      );

      final totals = await statsService.computeRange(
        weekStart,
        weekStart.add(const Duration(days: 7)),
      );

      expect(totals.totalTasks, 2);
      expect(totals.completedTasks, 2);
      expect(totals.plannedDurationMin, 120);
      expect(totals.completionRatePct!, 100);
    });

    test('getTasksBetween excludes inbox items and deleted rows', () async {
      final weekStart = startOfWeek(DateTime.now());
      final at = DateTime(weekStart.year, weekStart.month, weekStart.day, 8);
      final kept = await tasks.insertTask(
        Task(
          id: '',
          title: 'Kept',
          startTime: at,
          endTime: at.add(const Duration(hours: 1)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await tasks.insertTask(
        Task(
          id: '',
          title: 'Inbox thing',
          isInbox: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final doomed = await tasks.insertTask(
        Task(
          id: '',
          title: 'Doomed',
          startTime: at,
          endTime: at.add(const Duration(hours: 1)),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await tasks.deleteTask(doomed.id);

      final rows = await db.taskDao.getTasksBetween(
        weekStart,
        weekStart.add(const Duration(days: 7)),
      );
      expect(rows.map((t) => t.id), [kept.id]);
    });

    test(
      'cross-midnight tasks are queried and allocated once per day',
      () async {
        final firstDay = DateTime(2026, 8, 10);
        final secondDay = addDays(firstDay, 1);
        final task = await tasks.insertTask(
          Task(
            id: '',
            title: 'Overnight focus',
            startTime: firstDay.add(const Duration(hours: 23)),
            endTime: secondDay.add(const Duration(minutes: 30)),
            estimatedDurationMin: 60,
            actualDurationMin: 90,
            manualDurationAdjustmentMin: 30,
            createdAt: firstDay,
            updatedAt: firstDay,
          ),
        );
        await TimerRepository(db).insertSession(
          TimerSession(
            id: '',
            taskId: task.id,
            startedAt: firstDay.add(const Duration(hours: 23, minutes: 30)),
            endedAt: secondDay.add(const Duration(minutes: 30)),
            durationSec: 3600,
            createdAt: firstDay,
            updatedAt: firstDay,
          ),
        );

        final firstRows = await db.taskDao.getTasksForDay(firstDay);
        final secondRows = await db.taskDao.getTasksForDay(secondDay);
        expect(firstRows.map((row) => row.id), [task.id]);
        expect(secondRows.map((row) => row.id), [task.id]);

        final firstStats = await statsService.computeForDate(firstDay);
        final secondStats = await statsService.computeForDate(secondDay);
        expect(firstStats.totalTasks, 1);
        expect(secondStats.totalTasks, 0);
        expect(firstStats.plannedDurationMin, 60);
        expect(secondStats.plannedDurationMin, 30);
        expect(firstStats.actualDurationMin, 60);
        expect(secondStats.actualDurationMin, 30);
        expect(
          firstStats.actualDurationMin + secondStats.actualDurationMin,
          90,
        );
        expect(
          firstStats.plannedDurationMin + secondStats.plannedDurationMin,
          90,
        );
      },
    );

    test('range actual time rounds each day before summing buckets', () async {
      final firstDay = DateTime(2026, 8, 12);
      final secondDay = addDays(firstDay, 1);
      final task = await tasks.insertTask(
        Task(
          id: '',
          title: 'Subminute overnight work',
          startTime: firstDay.add(const Duration(hours: 23)),
          endTime: secondDay.add(const Duration(hours: 1)),
          createdAt: firstDay,
          updatedAt: firstDay,
        ),
      );
      await TimerRepository(db).insertSession(
        TimerSession(
          id: '',
          taskId: task.id,
          startedAt: firstDay.add(
            const Duration(hours: 23, minutes: 59, seconds: 30),
          ),
          endedAt: secondDay.add(const Duration(seconds: 30)),
          durationSec: 60,
          createdAt: firstDay,
          updatedAt: firstDay,
        ),
      );

      final firstStats = await statsService.computeForDate(firstDay);
      final secondStats = await statsService.computeForDate(secondDay);
      final rangeStats = await statsService.computeRange(
        firstDay,
        addDays(secondDay, 1),
      );

      expect(firstStats.actualDurationMin, 0);
      expect(secondStats.actualDurationMin, 0);
      expect(rangeStats.actualDurationMin, 0);
      expect(
        firstStats.actualDurationMin + secondStats.actualDurationMin,
        rangeStats.actualDurationMin,
      );
    });

    test(
      'completed sessions count even when their task is unscheduled or deleted',
      () async {
        final task = await tasks.insertTask(
          Task(
            id: '',
            title: 'Unscheduled tracked work',
            createdAt: day,
            updatedAt: day,
          ),
        );
        final startedAt = day.add(const Duration(hours: 10));
        await TimerRepository(db).insertSession(
          TimerSession(
            id: '',
            taskId: task.id,
            startedAt: startedAt,
            endedAt: startedAt.add(const Duration(minutes: 30)),
            durationSec: 30 * 60,
            createdAt: day,
            updatedAt: day,
          ),
        );
        await tasks.deleteTask(task.id);

        final stats = await statsService.computeForDate(day);
        expect(stats.totalTasks, 0);
        expect(stats.actualDurationMin, 30);
      },
    );
  });
}
