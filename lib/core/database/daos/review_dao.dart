import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/daily_reviews_table.dart';
import '../tables/weekly_reviews_table.dart';

part 'review_dao.g.dart';

@DriftAccessor(tables: [DailyReviews, WeeklyReviews])
class ReviewDao extends DatabaseAccessor<AppDatabase> with _$ReviewDaoMixin {
  ReviewDao(super.db);

  // ---------------------------------------------------------------
  // Daily reviews
  // ---------------------------------------------------------------

  Stream<DailyReviewRow?> watchReviewForDate(String dateIso) {
    return (select(dailyReviews)
          ..where((r) => r.date.equals(dateIso) & r.deletedAt.isNull()))
        .watchSingleOrNull();
  }

  Future<DailyReviewRow?> getDailyReviewByDate(String dateIso) =>
      (select(dailyReviews)
            ..where((r) => r.date.equals(dateIso) & r.deletedAt.isNull()))
          .getSingleOrNull();

  Future<DailyReviewRow?> getAnyDailyReviewByDate(String dateIso) =>
      (select(dailyReviews)
            ..where((r) => r.date.equals(dateIso))
            ..orderBy([(r) => OrderingTerm.asc(r.deletedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<DailyReviewRow?> getDailyReviewById(String id) =>
      (select(dailyReviews)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<List<DailyReviewRow>> getDailyReviewsBetween(
    String startIsoInclusive,
    String endIsoExclusive,
  ) {
    return (select(dailyReviews)
          ..where(
            (r) =>
                r.date.isBiggerOrEqualValue(startIsoInclusive) &
                r.date.isSmallerThanValue(endIsoExclusive) &
                r.deletedAt.isNull(),
          )
          ..orderBy([(r) => OrderingTerm.asc(r.date)]))
        .get();
  }

  Future<void> insertDailyReview(DailyReviewsCompanion entry) =>
      into(dailyReviews).insert(entry);

  Future<bool> updateDailyReview(DailyReviewRow row) async {
    final count =
        await (update(
          dailyReviews,
        )..where((review) => review.id.equals(row.id))).write(
          row.toCompanion(false).copyWith(serverVersion: const Value.absent()),
        );
    return count > 0;
  }

  /// Soft-deletes by id; the row keeps its unique [DailyReviews.date].
  Future<int> softDeleteDailyReview(String id, DateTime deletedAt) =>
      _softDeleteDaily(id, deletedAt);

  Future<int> _softDeleteDaily(String id, DateTime deletedAt) async {
    final current = await getDailyReviewById(id);
    if (current == null || current.deletedAt != null) return 0;
    return (update(dailyReviews)..where((r) => r.id.equals(id))).write(
      DailyReviewsCompanion(
        deletedAt: Value(deletedAt),
        updatedAt: Value(deletedAt),
        syncStatus: const Value(1),
        revision: Value(current.revision + 1),
      ),
    );
  }

  // ---------------------------------------------------------------
  // Weekly reviews
  // ---------------------------------------------------------------

  Stream<WeeklyReviewRow?> watchWeeklyReviewForWeek(String weekStartIso) {
    return (select(weeklyReviews)..where(
          (r) => r.weekStartDate.equals(weekStartIso) & r.deletedAt.isNull(),
        ))
        .watchSingleOrNull();
  }

  Future<WeeklyReviewRow?> getWeeklyReviewByWeekStart(String weekStartIso) =>
      (select(weeklyReviews)..where(
            (r) => r.weekStartDate.equals(weekStartIso) & r.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  Future<WeeklyReviewRow?> getAnyWeeklyReviewByWeekStart(String weekStartIso) =>
      (select(weeklyReviews)
            ..where((r) => r.weekStartDate.equals(weekStartIso))
            ..orderBy([(r) => OrderingTerm.asc(r.deletedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<WeeklyReviewRow?> getWeeklyReviewById(String id) =>
      (select(weeklyReviews)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<void> insertWeeklyReview(WeeklyReviewsCompanion entry) =>
      into(weeklyReviews).insert(entry);

  Future<bool> updateWeeklyReview(WeeklyReviewRow row) async {
    final count =
        await (update(
          weeklyReviews,
        )..where((review) => review.id.equals(row.id))).write(
          row.toCompanion(false).copyWith(serverVersion: const Value.absent()),
        );
    return count > 0;
  }

  Future<int> softDeleteWeeklyReview(String id, DateTime deletedAt) =>
      _softDeleteWeekly(id, deletedAt);

  Future<int> _softDeleteWeekly(String id, DateTime deletedAt) async {
    final current = await getWeeklyReviewById(id);
    if (current == null || current.deletedAt != null) return 0;
    return (update(weeklyReviews)..where((r) => r.id.equals(id))).write(
      WeeklyReviewsCompanion(
        deletedAt: Value(deletedAt),
        updatedAt: Value(deletedAt),
        syncStatus: const Value(1),
        revision: Value(current.revision + 1),
      ),
    );
  }
}
