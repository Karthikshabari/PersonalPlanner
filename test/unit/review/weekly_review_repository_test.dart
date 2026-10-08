import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/models/weekly_review.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/review/domain/weekly_review_history.dart';
import 'package:personal_planner/features/review/domain/weekly_review_text.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late ReviewRepository reviews;
  final week = DateTime(2026, 9, 28);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    reviews = ReviewRepository(db);
  });

  tearDown(() => db.close());

  test('saveWeeklyReviewDraft stores mood, feeling and note and keeps legacy '
      'fields', () async {
    await reviews.saveWeeklyReview(
      WeeklyReview(
        id: '',
        weekStartDate: week,
        overallRating: 4,
        goalsMet: const ['Ship'],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    await reviews.saveWeeklyReviewDraft(
      weekStart: week,
      mood: 3,
      feeling: '  Calm, proud  ',
      note: '  Start with the hardest task  ',
    );

    final saved = (await reviews.getWeeklyReviewForWeek(week))!;
    expect(saved.mood, 3);
    expect(saved.feeling, 'Calm, proud');
    expect(saved.reflection, 'Start with the hardest task');
    expect(saved.overallRating, 4);
    expect(saved.goalsMet, ['Ship']);
  });

  test(
    'mood is clamped and an empty feeling is stored as empty text',
    () async {
      await reviews.saveWeeklyReviewDraft(
        weekStart: week,
        mood: 9,
        feeling: '   ',
        note: '',
      );

      final row = (await db.reviewDao.getWeeklyReviewByWeekStart(
        '2026-09-28',
      ))!;
      expect(row.mood, 4);
      expect(row.feeling, '');
      expect(row.reflection, isNull);
    },
  );

  test('normalizeWeeklyFeeling trims and clips to 200 code points', () {
    expect(normalizeWeeklyFeeling(null), isNull);
    expect(normalizeWeeklyFeeling('  hi  '), 'hi');
    final long = '😀' * 250;
    final clipped = normalizeWeeklyFeeling(long)!;
    expect(clipped.runes.length, maxWeeklyFeelingLength);
  });

  test(
    'history lists 52 weeks oldest first with reviews and completion',
    () async {
      final current = startOfWeek(week);
      final lastWeek = addDays(current, -7);
      await reviews.saveWeeklyReviewDraft(
        weekStart: lastWeek,
        mood: 2,
        feeling: 'Busy',
        note: 'Protect time for deep work',
      );
      final tasks = TaskRepository(db);
      for (var i = 0; i < 4; i++) {
        final start = addDays(lastWeek, i).add(const Duration(hours: 9));
        await tasks.insertTask(
          Task(
            id: '',
            title: 'Task $i',
            startTime: start,
            endTime: start.add(const Duration(hours: 1)),
            status: i < 3 ? TaskStatus.completed : TaskStatus.planned,
            createdAt: start,
            updatedAt: start,
          ),
        );
      }

      final history = await WeeklyReviewHistoryService(db).load(current);

      expect(history, hasLength(52));
      expect(history.first.weekStart, addDays(current, -7 * 52));
      final last = history.last;
      expect(last.weekStart, lastWeek);
      expect(last.reviewed, isTrue);
      expect(last.mood, 2);
      expect(last.feeling, 'Busy');
      expect(last.note, 'Protect time for deep work');
      expect(last.percent, 75);
      expect(history[history.length - 2].reviewed, isFalse);
      expect(history[history.length - 2].percent, isNull);
    },
  );
}
