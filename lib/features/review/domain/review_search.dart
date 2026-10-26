import '../../../core/database/app_database.dart';
import '../../../core/models/enums/task_status.dart';
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

/// Everything Review search can find: days up to today (Daily) and weeks up to
/// and including this week, all seven days of it (Weekly).
class ReviewSearchIndex {
  const ReviewSearchIndex({
    required this.today,
    required this.days,
    required this.weekReviews,
  });

  /// The day the index was built for; Daily search stops here.
  final DateTime today;

  /// Newest first; only days with at least one non-blank text. It reaches to
  /// the end of this week, so use [today] to tell past days from later ones.
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

/// The first matching text of each day up to and including today, newest day
/// first. [needle] comes from [pageSearchNeedle]; a blank needle matches
/// nothing.
List<ReviewSearchHit> searchReviewDays(ReviewSearchIndex index, String needle) {
  if (needle.isEmpty) return const [];
  return [
    for (final day in index.days)
      if (!day.date.isAfter(index.today))
        ?_firstHit(day.date, day.texts, needle),
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

/// Reads the saved texts of every day up to today and every week up to this
/// one, for Review search.
///
/// Three range reads, none of them per day: titles come from a two-column
/// projection, since the typed full-row read costs about 100 ms per 5 800 rows.
class ReviewSearchIndexLoader {
  ReviewSearchIndexLoader(this._db);

  final AppDatabase _db;

  Future<ReviewSearchIndex> load({required DateTime today}) async {
    final from = DateTime.utc(1970);
    final day = startOfDay(today);
    final tomorrow = addDays(day, 1);
    final nextWeek = addDays(startOfWeek(today), 7);
    final repository = ReviewRepository(_db);
    // Tasks reach to the end of this week, as the Weekly page lists them.
    // Reviews only exist for days that have begun.
    final tasks = await _db.taskDao.getStartAndTitleBetween(from, nextWeek);
    final dailies = await repository.getDailyReviewsBetween(from, tomorrow);
    final weeklies = await repository.getWeeklyReviewsBetween(from, nextWeek);

    // The same rule as the Daily Review: a task belongs to the day it starts.
    final byDay =
        <
          DateTime,
          List<({String id, DateTime start, String title, String status})>
        >{};
    for (final row in tasks) {
      if (!row.start.isBefore(nextWeek)) continue;
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
      final dayTasks = [...?byDay[date]]
        ..sort((a, b) => a.start.compareTo(b.start));
      for (final row in dayTasks) {
        final title = row.title.trim();
        if (title.isEmpty) continue;
        texts.add(ReviewSearchText(title, ReviewSearchSource.task));
      }
      // The pages show a reason only beside its task, so a reason whose task
      // is gone, starts on another day, or was completed since (the page
      // hides it then) is not searchable either.
      final taskIds = {
        for (final row in dayTasks)
          if (row.status != TaskStatus.completed.dbValue) row.id,
      };
      for (final entry
          in review?.taskReasons.entries ??
              const <MapEntry<String, String>>[]) {
        if (!taskIds.contains(entry.key)) continue;
        final trimmed = entry.value.trim();
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
    return ReviewSearchIndex(today: day, days: days, weekReviews: weekReviews);
  }
}
