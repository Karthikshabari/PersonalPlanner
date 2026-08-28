// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'review_dao.dart';

// ignore_for_file: type=lint
mixin _$ReviewDaoMixin on DatabaseAccessor<AppDatabase> {
  $DailyReviewsTable get dailyReviews => attachedDatabase.dailyReviews;
  $WeeklyReviewsTable get weeklyReviews => attachedDatabase.weeklyReviews;
  ReviewDaoManager get managers => ReviewDaoManager(this);
}

class ReviewDaoManager {
  final _$ReviewDaoMixin _db;
  ReviewDaoManager(this._db);
  $$DailyReviewsTableTableManager get dailyReviews =>
      $$DailyReviewsTableTableManager(_db.attachedDatabase, _db.dailyReviews);
  $$WeeklyReviewsTableTableManager get weeklyReviews =>
      $$WeeklyReviewsTableTableManager(_db.attachedDatabase, _db.weeklyReviews);
}
