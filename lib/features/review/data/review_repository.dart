import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/review_dao.dart';
import '../../../core/models/daily_review.dart';
import '../../../core/models/weekly_review.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/json_list_utils.dart';
import '../../../core/utils/uuid.dart';

/// CRUD for daily and weekly reviews (planner.md Chunk 5 #4).
class ReviewRepository {
  final AppDatabase _db;

  ReviewRepository(this._db);

  ReviewDao get _dao => _db.reviewDao;

  // ---------------------------------------------------------------
  // Daily reviews
  // ---------------------------------------------------------------

  /// Inserts or updates the review for [review.date] (one row per date).
  /// Ratings are clamped to the 1–5 range the schema allows.
  Future<DailyReview> saveDailyReview(DailyReview review) async {
    final dateIso = isoDateString(startOfDay(review.date));
    final existing = await _dao.getAnyDailyReviewByDate(dateIso);
    final now = DateTime.now();
    final effective = review.copyWith(
      id:
          existing?.id ??
          (review.id.isEmpty
              ? generateDeterministicUuid('daily-review:$dateIso')
              : review.id),
      date: startOfDay(review.date),
      energyLevel: _clampRating(review.energyLevel),
      productivityRating: _clampRating(review.productivityRating),
      planningAccuracyRating: _clampRating(review.planningAccuracyRating),
      updatedAt: now,
      createdAt: existing?.createdAt ?? now,
      deletedAt: null,
    );
    await _db.transaction(() async {
      if (existing == null) {
        await _dao.insertDailyReview(_toCompanion(effective));
      } else {
        await _dao.updateDailyReview(
          _toRow(effective, syncStatus: 1, revision: existing.revision + 1),
        );
      }
      await _db.statsDao.invalidateForDate(dateIso);
    });
    return effective;
  }

  Stream<DailyReview?> watchReviewForDate(DateTime date) => _dao
      .watchReviewForDate(isoDateString(startOfDay(date)))
      .map((row) => row == null ? null : fromRow(row));

  Future<DailyReview?> getReviewForDate(DateTime date) async {
    final row = await _dao.getDailyReviewByDate(
      isoDateString(startOfDay(date)),
    );
    return row == null ? null : fromRow(row);
  }

  Future<List<DailyReview>> getDailyReviewsBetween(
    DateTime start,
    DateTime end,
  ) async {
    final rows = await _dao.getDailyReviewsBetween(
      isoDateString(startOfDay(start)),
      isoDateString(startOfDay(end)),
    );
    return rows.map(ReviewRepository.fromRow).toList(growable: false);
  }

  Future<void> deleteDailyReview(String id) async {
    final current = await _dao.getDailyReviewById(id);
    await _db.transaction(() async {
      await _dao.softDeleteDailyReview(id, DateTime.now());
      if (current != null) {
        await _db.statsDao.invalidateForDate(current.date);
      }
    });
  }

  // ---------------------------------------------------------------
  // Weekly reviews
  // ---------------------------------------------------------------

  /// Inserts or updates the review for the Mon–Sun week starting at
  /// [review.weekStartDate] (one row per week).
  Future<WeeklyReview> saveWeeklyReview(WeeklyReview review) async {
    final weekIso = isoDateString(startOfWeek(review.weekStartDate));
    final existing = await _dao.getAnyWeeklyReviewByWeekStart(weekIso);
    final now = DateTime.now();
    final effective = review.copyWith(
      id:
          existing?.id ??
          (review.id.isEmpty
              ? generateDeterministicUuid('weekly-review:$weekIso')
              : review.id),
      weekStartDate: startOfWeek(review.weekStartDate),
      overallRating: _clampRating(review.overallRating),
      updatedAt: now,
      createdAt: existing?.createdAt ?? now,
      deletedAt: null,
    );
    if (existing == null) {
      await _dao.insertWeeklyReview(_toWeeklyCompanion(effective));
    } else {
      await _dao.updateWeeklyReview(
        _toWeeklyRow(effective, syncStatus: 1, revision: existing.revision + 1),
      );
    }
    return effective;
  }

  Stream<WeeklyReview?> watchWeeklyReviewForWeek(DateTime weekStart) => _dao
      .watchWeeklyReviewForWeek(isoDateString(startOfWeek(weekStart)))
      .map((row) => row == null ? null : fromWeeklyRow(row));

  Future<WeeklyReview?> getWeeklyReviewForWeek(DateTime weekStart) async {
    final row = await _dao.getWeeklyReviewByWeekStart(
      isoDateString(startOfWeek(weekStart)),
    );
    return row == null ? null : fromWeeklyRow(row);
  }

  Future<void> deleteWeeklyReview(String id) =>
      _dao.softDeleteWeeklyReview(id, DateTime.now());

  static int? _clampRating(int? value) {
    if (value == null) return null;
    return value.clamp(1, 5);
  }

  // ---------------------------------------------------------------
  // Row mapping
  // ---------------------------------------------------------------

  static DailyReview fromRow(DailyReviewRow row) => DailyReview(
    id: row.id,
    date: parseIsoDate(row.date),
    reflection: row.reflection,
    energyLevel: row.energyLevel,
    productivityRating: row.productivityRating,
    planningAccuracyRating: row.planningAccuracyRating,
    wins: JsonListUtils.decode(row.winsJson),
    improvements: JsonListUtils.decode(row.improvementsJson),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );

  static DailyReviewsCompanion _toCompanion(DailyReview r) =>
      DailyReviewsCompanion.insert(
        id: r.id,
        date: isoDateString(r.date),
        reflection: Value(r.reflection),
        energyLevel: Value(r.energyLevel),
        productivityRating: Value(r.productivityRating),
        planningAccuracyRating: Value(r.planningAccuracyRating),
        winsJson: Value(r.wins.isEmpty ? null : JsonListUtils.encode(r.wins)),
        improvementsJson: Value(
          r.improvements.isEmpty ? null : JsonListUtils.encode(r.improvements),
        ),
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        deletedAt: Value(r.deletedAt),
        syncStatus: const Value(1),
        revision: const Value(1),
      );

  static DailyReviewRow _toRow(
    DailyReview r, {
    required int syncStatus,
    required int revision,
  }) => DailyReviewRow(
    id: r.id,
    date: isoDateString(r.date),
    reflection: r.reflection,
    energyLevel: r.energyLevel,
    productivityRating: r.productivityRating,
    planningAccuracyRating: r.planningAccuracyRating,
    winsJson: r.wins.isEmpty ? null : JsonListUtils.encode(r.wins),
    improvementsJson: r.improvements.isEmpty
        ? null
        : JsonListUtils.encode(r.improvements),
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
    deletedAt: r.deletedAt,
    syncStatus: syncStatus,
    revision: revision,
  );

  static WeeklyReview fromWeeklyRow(WeeklyReviewRow row) => WeeklyReview(
    id: row.id,
    weekStartDate: parseIsoDate(row.weekStartDate),
    reflection: row.reflection,
    overallRating: row.overallRating,
    goalsMet: JsonListUtils.decode(row.goalsMetJson),
    goalsMissed: JsonListUtils.decode(row.goalsMissedJson),
    nextWeekFocus: JsonListUtils.decode(row.nextWeekFocusJson),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );

  static WeeklyReviewsCompanion _toWeeklyCompanion(WeeklyReview r) =>
      WeeklyReviewsCompanion.insert(
        id: r.id,
        weekStartDate: isoDateString(r.weekStartDate),
        reflection: Value(r.reflection),
        overallRating: Value(r.overallRating),
        goalsMetJson: Value(
          r.goalsMet.isEmpty ? null : JsonListUtils.encode(r.goalsMet),
        ),
        goalsMissedJson: Value(
          r.goalsMissed.isEmpty ? null : JsonListUtils.encode(r.goalsMissed),
        ),
        nextWeekFocusJson: Value(
          r.nextWeekFocus.isEmpty
              ? null
              : JsonListUtils.encode(r.nextWeekFocus),
        ),
        createdAt: r.createdAt,
        updatedAt: r.updatedAt,
        deletedAt: Value(r.deletedAt),
        syncStatus: const Value(1),
        revision: const Value(1),
      );

  static WeeklyReviewRow _toWeeklyRow(
    WeeklyReview r, {
    required int syncStatus,
    required int revision,
  }) => WeeklyReviewRow(
    id: r.id,
    weekStartDate: isoDateString(r.weekStartDate),
    reflection: r.reflection,
    overallRating: r.overallRating,
    goalsMetJson: r.goalsMet.isEmpty ? null : JsonListUtils.encode(r.goalsMet),
    goalsMissedJson: r.goalsMissed.isEmpty
        ? null
        : JsonListUtils.encode(r.goalsMissed),
    nextWeekFocusJson: r.nextWeekFocus.isEmpty
        ? null
        : JsonListUtils.encode(r.nextWeekFocus),
    createdAt: r.createdAt,
    updatedAt: r.updatedAt,
    deletedAt: r.deletedAt,
    syncStatus: syncStatus,
    revision: revision,
  );
}
