import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/daily_review.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late ReviewRepository reviews;
  final date = DateTime(2026, 9, 14);
  final stamp = DateTime.utc(2026, 9, 14, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    reviews = ReviewRepository(db);
  });

  tearDown(() => db.close());

  test(
    'saveReviewDraft stores mood, note and reasons and preserves legacy fields',
    () async {
      await reviews.saveDailyReview(
        DailyReview(
          id: '',
          date: date,
          energyLevel: 4,
          wins: const ['w'],
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );

      await reviews.saveReviewDraft(
        date: date,
        mood: 3,
        note: '  Hi ',
        taskReasons: const {'t1': 'Blocked'},
      );

      final saved = (await reviews.getReviewForDate(date))!;
      expect(saved.mood, 3);
      expect(saved.reflection, 'Hi');
      expect(saved.taskReasons, {'t1': 'Blocked'});
      expect(saved.energyLevel, 4);
      expect(saved.wins, ['w']);
    },
  );

  test('saveDailyReview rejects blank reason text', () async {
    await expectLater(
      reviews.saveDailyReview(
        DailyReview(
          id: '',
          date: date,
          taskReasons: const {'t1': '  '},
          createdAt: stamp,
          updatedAt: stamp,
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await reviews.getReviewForDate(date), isNull);
  });
}
