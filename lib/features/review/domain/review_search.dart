import '../../../core/database/app_database.dart';
import '../../../core/search/page_search.dart';
import '../../../core/utils/date_utils.dart';
import '../data/review_repository.dart';

/// Where a Review search hit was found.
enum ReviewSearchSource { note, task, reason, feeling, weekNote }

extension ReviewSearchSourceLabel on ReviewSearchSource {
  String get label => switch (this) {
    ReviewSearchSource.note => 'Worth remembering',
    ReviewSearchSource.task => 'Task',
    ReviewSearchSource.reason => 'Reason',
    ReviewSearchSource.feeling => 'How the week felt',
    ReviewSearchSource.weekNote => 'Note for next week',
  };
}

/// One searchable text. [lower] is computed once per load, not per keystroke.
class ReviewSearchText {
  ReviewSearchText(this.text, this.source) : lower = text.toLowerCase();

  final String text;
  final String lower;
  final ReviewSearchSource source;
}

/// The saved texts of one day: its note, the titles of the tasks that start
/// that day and the reasons saved for them.
class ReviewSearchDay {
  const ReviewSearchDay(this.date, this.texts);

  final DateTime date;
  final List<ReviewSearchText> texts;
}

/// The saved texts of one weekly review, which is keyed by [weekKey].
class ReviewSearchWeekReview {
  const ReviewSearchWeekReview(this.weekKey, this.texts);

  final DateTime weekKey;
  final List<ReviewSearchText> texts;
}

/// Everything Review search can find, up to today and this week.
class ReviewSearchIndex {
  const ReviewSearchIndex({required this.days, required this.weekReviews});

  /// Newest first; only days with at least one non-blank text.
  final List<ReviewSearchDay> days;
  final List<ReviewSearchWeekReview> weekReviews;
}

/// A day (Daily) or the start of a week (Weekly) with the text that matched.
typedef ReviewSearchHit = ({
  DateTime date,
  ReviewSearchSource source,
  String snippet,
});

ReviewSearchHit? _firstHit(
  DateTime date,
  Iterable<ReviewSearchText> texts,
  String needle,
) {
  for (final item in texts) {
    if (item.lower.contains(needle)) {
      return (
        date: date,
        source: item.source,
        snippet: pageSearchSnippet(item.text, needle),
      );
    }
  }
  return null;
}

/// The first matching text of each day, newest day first. [needle] comes from
/// [pageSearchNeedle]; a blank needle matches nothing.
List<ReviewSearchHit> searchReviewDays(ReviewSearchIndex index, String needle) {
  if (needle.isEmpty) return const [];
  return [
    for (final day in index.days) ?_firstHit(day.date, day.texts, needle),
  ];
}

/// The first matching text of each week, newest week first.
///
/// A weekly review's own texts win over the tasks and reasons of its days. The
/// Daily note is not shown on the Weekly page, so it is not searched here.
List<ReviewSearchHit> searchReviewWeeks(
  ReviewSearchIndex index,
  String needle,
) {
  if (needle.isEmpty) return const [];
  final reviews = <DateTime, ReviewSearchWeekReview>{
    for (final review in index.weekReviews) startOfWeek(review.weekKey): review,
  };
  final days = <DateTime, List<ReviewSearchDay>>{};
  for (final day in index.days) {
    days.putIfAbsent(startOfWeek(day.date), () => []).add(day);
  }
  final weeks = {...reviews.keys, ...days.keys}.toList()
    ..sort((a, b) => b.compareTo(a));
  final hits = <ReviewSearchHit>[];
  for (final week in weeks) {
    final hit =
        _firstHit(week, reviews[week]?.texts ?? const [], needle) ??
        _firstHit(week, [
          for (final day in days[week] ?? const <ReviewSearchDay>[])
            ...day.texts.where((t) => t.source != ReviewSearchSource.note),
        ], needle);
    if (hit != null) hits.add(hit);
  }
  return hits;
}

/// Reads the saved texts of every day and week up to today, for Review search.
///
/// Three range reads, none of them per day: titles come from a two-column
/// projection, since the typed full-row read costs about 100 ms per 5 800 rows.
class ReviewSearchIndexLoader {
  ReviewSearchIndexLoader(this._db);

  final AppDatabase _db;

  Future<ReviewSearchIndex> load({required DateTime today}) async {
    final from = DateTime.utc(1970);
    final tomorrow = addDays(startOfDay(today), 1);
    final nextWeek = addDays(startOfWeek(today), 7);
    final repository = ReviewRepository(_db);
    final tasks = await _db.taskDao.getStartAndTitleBetween(from, tomorrow);
    final dailies = await repository.getDailyReviewsBetween(from, tomorrow);
    final weeklies = await repository.getWeeklyReviewsBetween(from, nextWeek);

    // The same rule as the Daily Review: a task belongs to the day it starts.
    final byDay = <DateTime, List<({DateTime start, String title})>>{};
    for (final row in tasks) {
      if (!row.start.isBefore(tomorrow)) continue;
      if (row.title.trim().isEmpty) continue;
      byDay.putIfAbsent(startOfDay(row.start), () => []).add(row);
    }
    final reviewByDay = {
      for (final review in dailies) startOfDay(review.date): review,
    };

    final days = <ReviewSearchDay>[];
    for (final date in {...byDay.keys, ...reviewByDay.keys}) {
      final texts = <ReviewSearchText>[];
      final review = reviewByDay[date];
      final note = review?.reflection?.trim();
      if (note != null && note.isNotEmpty) {
        texts.add(ReviewSearchText(note, ReviewSearchSource.note));
      }
      final titles = [...?byDay[date]]
        ..sort((a, b) => a.start.compareTo(b.start));
      for (final row in titles) {
        texts.add(ReviewSearchText(row.title.trim(), ReviewSearchSource.task));
      }
      for (final reason in review?.taskReasons.values ?? const <String>[]) {
        final trimmed = reason.trim();
        if (trimmed.isEmpty) continue;
        texts.add(ReviewSearchText(trimmed, ReviewSearchSource.reason));
      }
      if (texts.isNotEmpty) days.add(ReviewSearchDay(date, texts));
    }
    days.sort((a, b) => b.date.compareTo(a.date));

    final weekReviews = <ReviewSearchWeekReview>[];
    for (final review in weeklies) {
      final texts = <ReviewSearchText>[];
      final feeling = review.feeling?.trim();
      if (feeling != null && feeling.isNotEmpty) {
        texts.add(ReviewSearchText(feeling, ReviewSearchSource.feeling));
      }
      final note = review.reflection?.trim();
      if (note != null && note.isNotEmpty) {
        texts.add(ReviewSearchText(note, ReviewSearchSource.weekNote));
      }
      if (texts.isNotEmpty) {
        weekReviews.add(ReviewSearchWeekReview(review.weekStartDate, texts));
      }
    }
    return ReviewSearchIndex(days: days, weekReviews: weekReviews);
  }
}
