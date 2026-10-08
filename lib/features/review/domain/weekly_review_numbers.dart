import 'package:intl/intl.dart';

import 'review_mood.dart';
import 'review_plan_change.dart';
import 'task_outcome.dart';
import 'weekly_review_history.dart';

/// One task that starts in the reviewed week (start-day rule D1).
class WeeklyTaskInput {
  const WeeklyTaskInput({
    required this.taskId,
    required this.title,
    required this.outcome,
    this.reason,
    this.planChange,
  });

  final String taskId;
  final String title;
  final TaskOutcome outcome;

  /// Trimmed reason saved in that day's review; null when none.
  final String? reason;
  final ReviewPlanChange? planChange;
}

/// One calendar day of the reviewed week, with its tasks in start order.
class WeeklyDayInput {
  const WeeklyDayInput({
    required this.date,
    required this.tasks,
    required this.reviewed,
    this.mood,
    this.contextLabel,
  });

  final DateTime date;
  final List<WeeklyTaskInput> tasks;

  /// A saved daily review exists for the day.
  final bool reviewed;

  /// Daily mood 1..4; null when not reviewed or saved without a mood.
  final int? mood;

  /// Day context short label (`Office`, `Leave`, a custom label), or null.
  final String? contextLabel;
}

class WeeklyDayStats {
  const WeeklyDayStats({
    required this.date,
    required this.total,
    required this.completed,
    required this.reviewed,
    this.mood,
    this.contextLabel,
  });

  final DateTime date;
  final int total;
  final int completed;
  final bool reviewed;
  final int? mood;
  final String? contextLabel;

  int? get percent => completionPercent(completed, total);
}

/// A Skipped or Rescheduled task of the week (WD5). Its plan change, if any,
/// is part of the same row.
class WeeklyOutcomeRow {
  const WeeklyOutcomeRow({
    required this.date,
    required this.taskId,
    required this.title,
    required this.outcome,
    required this.dayReviewed,
    this.reason,
    this.planChange,
  });

  final DateTime date;
  final String taskId;
  final String title;
  final TaskOutcome outcome;
  final bool dayReviewed;
  final String? reason;
  final ReviewPlanChange? planChange;
}

class WeeklyReasonCount {
  const WeeklyReasonCount({required this.reason, required this.count});

  final String reason;
  final int count;
}

class WeeklyDayType {
  const WeeklyDayType({
    required this.label,
    required this.days,
    required this.completed,
    required this.total,
  });

  final String label;
  final int days;
  final int completed;
  final int total;
}

/// Everything the Weekly review shows about the week's tasks.
class WeeklyNumbers {
  const WeeklyNumbers({
    required this.days,
    required this.total,
    required this.completed,
    required this.skipped,
    required this.rescheduled,
    required this.planChanged,
    required this.outcomeRows,
    required this.reasonCounts,
    required this.noReasonCount,
    required this.dayTypes,
    required this.highlights,
  });

  final List<WeeklyDayStats> days;
  final int total;
  final int completed;
  final int skipped;
  final int rescheduled;
  final int planChanged;
  final List<WeeklyOutcomeRow> outcomeRows;

  /// Most frequent first; ties keep the order the reasons first appear.
  final List<WeeklyReasonCount> reasonCounts;

  /// Not-completed tasks without a reason (any day).
  final int noReasonCount;
  final List<WeeklyDayType> dayTypes;

  /// At most three, in priority order (spec 3.9).
  final List<String> highlights;

  /// Whole-number completion; null when the week has no tasks.
  int? get percent => completionPercent(completed, total);

  /// Days with a saved daily review.
  int get reviewedDays => days.where((day) => day.reviewed).length;

  /// Tasks that are not completed (any outcome but Completed).
  bool get hasMissedTasks => reasonCounts.isNotEmpty || noReasonCount > 0;

  /// `7 of 14 tasks · 2 skipped · 3 rescheduled · 1 plan changed`.
  String get glanceSubline => [
    '$completed of $total tasks',
    if (skipped > 0) '$skipped skipped',
    if (rescheduled > 0) '$rescheduled rescheduled',
    if (planChanged > 0) '$planChanged plan changed',
  ].join(' · ');

  /// `Most common blocker this week: Low energy (3 times).`
  String get blockerLine {
    if (reasonCounts.isEmpty) return 'No blockers recorded this week.';
    final top = reasonCounts.first;
    final times = top.count == 1 ? '1 time' : '${top.count} times';
    return 'Most common blocker this week: ${top.reason} ($times).';
  }
}

/// Pure port of the prototype's `compute()` and `highlights()`.
WeeklyNumbers computeWeeklyNumbers(List<WeeklyDayInput> days) {
  final stats = <WeeklyDayStats>[];
  final outcomeRows = <WeeklyOutcomeRow>[];
  final counts = <String, int>{};
  final firstSeen = <String, int>{};
  final dayTypes = <String, WeeklyDayType>{};
  var total = 0;
  var completed = 0;
  var skipped = 0;
  var rescheduled = 0;
  var planChanged = 0;
  var noReason = 0;
  var missedOnReviewedDays = 0;
  var missedOnReviewedDaysWithReason = 0;

  for (final day in days) {
    var dayCompleted = 0;
    for (final task in day.tasks) {
      total++;
      if (task.planChange != null) planChanged++;
      if (task.outcome == TaskOutcome.completed) {
        completed++;
        dayCompleted++;
        continue;
      }
      if (task.outcome == TaskOutcome.skipped) skipped++;
      if (task.outcome == TaskOutcome.rescheduled) rescheduled++;
      final reason = task.reason;
      if (reason == null) {
        noReason++;
      } else {
        firstSeen.putIfAbsent(reason, () => firstSeen.length);
        counts[reason] = (counts[reason] ?? 0) + 1;
      }
      if (day.reviewed) {
        missedOnReviewedDays++;
        if (reason != null) missedOnReviewedDaysWithReason++;
      }
      if (task.outcome == TaskOutcome.skipped ||
          task.outcome == TaskOutcome.rescheduled) {
        outcomeRows.add(
          WeeklyOutcomeRow(
            date: day.date,
            taskId: task.taskId,
            title: task.title,
            outcome: task.outcome,
            dayReviewed: day.reviewed,
            reason: reason,
            planChange: task.planChange,
          ),
        );
      }
    }
    final dayStats = WeeklyDayStats(
      date: day.date,
      total: day.tasks.length,
      completed: dayCompleted,
      reviewed: day.reviewed,
      mood: day.mood,
      contextLabel: day.contextLabel,
    );
    stats.add(dayStats);
    final label = day.contextLabel;
    if (label != null && dayStats.total > 0) {
      final current = dayTypes[label];
      dayTypes[label] = WeeklyDayType(
        label: label,
        days: (current?.days ?? 0) + 1,
        completed: (current?.completed ?? 0) + dayStats.completed,
        total: (current?.total ?? 0) + dayStats.total,
      );
    }
  }

  final reasonCounts = [
    for (final entry in counts.entries)
      WeeklyReasonCount(reason: entry.key, count: entry.value),
  ];
  reasonCounts.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    return firstSeen[a.reason]!.compareTo(firstSeen[b.reason]!);
  });

  final highlights = <String>[];
  final perfectDays = [
    for (final day in stats)
      if (day.total > 0 && day.completed == day.total)
        DateFormat('EEE').format(day.date),
  ];
  if (perfectDays.isNotEmpty) {
    highlights.add('All done on ${perfectDays.take(2).join(' and ')}');
  }
  final aboveSixty = stats
      .where((day) => day.percent != null && day.percent! > 60)
      .length;
  if (aboveSixty >= 3) highlights.add('$aboveSixty days above 60%');
  if (missedOnReviewedDays > 0 &&
      missedOnReviewedDaysWithReason == missedOnReviewedDays) {
    highlights.add('Every missed task has a reason');
  }
  final reviewedDays = stats.where((day) => day.reviewed).length;
  if (reviewedDays >= 3) highlights.add('Reviewed $reviewedDays days');
  if (completed > 0) {
    highlights.add(completed == 1 ? '1 task done' : '$completed tasks done');
  }

  return WeeklyNumbers(
    days: List.unmodifiable(stats),
    total: total,
    completed: completed,
    skipped: skipped,
    rescheduled: rescheduled,
    planChanged: planChanged,
    outcomeRows: List.unmodifiable(outcomeRows),
    reasonCounts: List.unmodifiable(reasonCounts),
    noReasonCount: noReason,
    dayTypes: List.unmodifiable(dayTypes.values),
    highlights: List.unmodifiable(highlights.take(3)),
  );
}

/// `New best week`, `Up N points from last week`, or null. Never negative.
/// [previous] is oldest first; its last entry is the week right before.
String? weeklyDeltaText({
  required int? percent,
  required List<WeeklyHistoryWeek> previous,
}) {
  if (percent == null) return null;
  int? best;
  for (final week in previous) {
    final value = week.percent;
    if (!week.reviewed || value == null) continue;
    if (best == null || value > best) best = value;
  }
  if (best != null && percent > best) return 'New best week';
  final last = previous.isEmpty ? null : previous.last;
  final lastPercent = last?.percent;
  if (last != null &&
      last.reviewed &&
      lastPercent != null &&
      percent > lastPercent) {
    return 'Up ${percent - lastPercent} points from last week';
  }
  return null;
}

enum WeeklyDotKind { gap, reviewed, current }

class WeeklyDot {
  const WeeklyDot({required this.kind, this.mood});

  final WeeklyDotKind kind;

  /// Mood of a reviewed past week; null when it was saved without one.
  final int? mood;
}

/// Eight dots, oldest first: the seven weeks before this one, then this week.
List<WeeklyDot> weeklyDots(List<WeeklyHistoryWeek> previous) {
  final lastSeven = previous.length <= 7
      ? previous
      : previous.sublist(previous.length - 7);
  return [
    for (var i = lastSeven.length; i < 7; i++)
      const WeeklyDot(kind: WeeklyDotKind.gap),
    for (final week in lastSeven)
      week.reviewed
          ? WeeklyDot(kind: WeeklyDotKind.reviewed, mood: week.mood)
          : const WeeklyDot(kind: WeeklyDotKind.gap),
    const WeeklyDot(kind: WeeklyDotKind.current),
  ];
}

/// Reviewed weeks among the eight dots.
int weeklyReviewedDotCount(
  List<WeeklyDot> dots, {
  required bool currentSaved,
}) =>
    dots.where((dot) => dot.kind == WeeklyDotKind.reviewed).length +
    (currentSaved ? 1 : 0);

String weeksReviewedLabel(int count) => '$count of 8 weeks reviewed';

/// `Last week: Great`, or null when last week has no saved mood.
String? lastWeekMoodHint(List<WeeklyHistoryWeek> previous) {
  final mood = previous.isEmpty ? null : previous.last.mood;
  return mood == null ? null : 'Last week: ${reviewMoodLabel(mood)}';
}

/// Last week's note for this week, trimmed; null when there is none.
String? fromLastWeekNote(List<WeeklyHistoryWeek> previous) {
  final note = previous.isEmpty ? null : previous.last.note?.trim();
  return note == null || note.isEmpty ? null : note;
}

String weeklyMoodMessage(int mood) => switch (mood.clamp(1, 4)) {
  1 => 'Steady progress. Showing up counts.',
  2 => 'Solid work this week.',
  3 => 'A strong week. Well done.',
  _ => 'Your best kind of week.',
};

/// `Sep 28–Oct 4`, or `Aug 10–16` inside one month.
String weekRangeLabel(DateTime weekStart, DateTime weekEnd) {
  final start = DateFormat('MMM d').format(weekStart);
  final end = weekStart.month == weekEnd.month
      ? DateFormat('d').format(weekEnd)
      : DateFormat('MMM d').format(weekEnd);
  return '$start–$end';
}
