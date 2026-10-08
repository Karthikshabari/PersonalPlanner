import 'package:personal_planner/core/models/weekly_review.dart';
import 'package:personal_planner/features/review/domain/review_plan_change.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';
import 'package:personal_planner/features/review/domain/weekly_review_history.dart';
import 'package:personal_planner/features/review/domain/weekly_review_numbers.dart';

/// Port of the Weekly Review prototype's `DAYS`, `SC`, `PREV`, `LAST` and
/// `BEST` (docs/weekly_review/Weekly Review Prototype.html). The week is
/// Mon Sep 28 – Sun Oct 4, 2026.
class FixtureTask {
  const FixtureTask(this.title, this.notDone, this.reason, {this.planChange});

  final String title;

  /// Outcome when the task is not among the day's done tasks.
  final TaskOutcome notDone;
  final String? reason;
  final ReviewPlanChange? planChange;
}

class FixtureDay {
  const FixtureDay(
    this.day,
    this.context,
    this.mood,
    this.reviewed,
    this.tasks,
  );

  /// Day of month in Sep/Oct 2026 (Mon Sep 28 = index 0).
  final int day;
  final String? context;
  final int? mood;
  final bool reviewed;
  final List<FixtureTask> tasks;
}

const fixtureDays = <FixtureDay>[
  FixtureDay(28, 'Office', 1, true, [
    FixtureTask('Stand-up notes', TaskOutcome.skipped, 'Lower priority'),
    FixtureTask(
      'Fix login redirect',
      TaskOutcome.notStarted,
      'Ran out of time',
    ),
    FixtureTask('Draft API doc', TaskOutcome.rescheduled, 'Blocked'),
    FixtureTask('Review pull requests', TaskOutcome.partlyDone, 'Interrupted'),
  ]),
  FixtureDay(29, 'Office', 2, true, [
    FixtureTask('Reply to recruiter', TaskOutcome.skipped, 'Lower priority'),
    FixtureTask('Backup check', TaskOutcome.notStarted, 'Ran out of time'),
    FixtureTask(
      'Update onboarding doc',
      TaskOutcome.rescheduled,
      'Interrupted',
    ),
  ]),
  FixtureDay(30, 'Office', 3, true, [
    FixtureTask('Read Drift docs', TaskOutcome.notStarted, 'Low energy'),
    FixtureTask('Walk, 30 min', TaskOutcome.skipped, 'Low energy'),
    FixtureTask('Gym session', TaskOutcome.skipped, 'Low energy'),
  ]),
  FixtureDay(1, 'Leave', 1, true, [
    FixtureTask('Weekly groceries', TaskOutcome.notStarted, 'Blocked'),
    FixtureTask(
      'Refactor sync tests',
      TaskOutcome.rescheduled,
      'Low energy',
      planChange: ReviewPlanChange(
        kind: ReviewPlanChangeKind.title,
        oldValue: 'Refactor tests',
        newValue: 'Refactor sync tests',
        reason: 'Scope grew',
      ),
    ),
  ]),
  FixtureDay(2, 'Leave', null, false, [
    FixtureTask('Pay electricity bill', TaskOutcome.notStarted, null),
    FixtureTask('Plan next sprint', TaskOutcome.notStarted, null),
  ]),
  FixtureDay(3, null, null, false, []),
  FixtureDay(4, null, null, false, []),
];

/// Tasks done per day (Mon..Sun): the first N tasks of each day are done.
const fixtureScenarios = <String, List<int>>{
  'good': [1, 1, 1, 1, 1, 0, 0],
  'great': [2, 2, 1, 1, 1, 0, 0],
  'excellent': [3, 3, 2, 1, 1, 0, 0],
  'legendary': [4, 3, 3, 2, 1, 0, 0],
};

DateTime fixtureDate(int index) => DateTime(2026, 9, 28 + index);

List<WeeklyDayInput> fixtureWeek(String scenario) {
  final done = fixtureScenarios[scenario]!;
  return [
    for (var i = 0; i < fixtureDays.length; i++)
      WeeklyDayInput(
        date: fixtureDate(i),
        reviewed: fixtureDays[i].reviewed,
        mood: fixtureDays[i].mood,
        contextLabel: fixtureDays[i].context,
        tasks: [
          for (var j = 0; j < fixtureDays[i].tasks.length; j++)
            WeeklyTaskInput(
              taskId: 'task-$i-$j',
              title: fixtureDays[i].tasks[j].title,
              outcome: j < done[i]
                  ? TaskOutcome.completed
                  : fixtureDays[i].tasks[j].notDone,
              reason: fixtureDays[i].tasks[j].reason,
              planChange: fixtureDays[i].tasks[j].planChange,
            ),
        ],
      ),
  ];
}

/// The seven weeks before the fixture week (oldest first). `LAST` = 45 and
/// `BEST` = 82. Aug 31–Sep 6 has no saved review (a gap week).
List<WeeklyHistoryWeek> fixtureHistory() {
  WeeklyHistoryWeek week(DateTime start, int? percent, int? mood) {
    final reviewed = percent != null;
    return WeeklyHistoryWeek(
      weekStart: start,
      totalTasks: 100,
      completedTasks: percent ?? 0,
      review: reviewed
          ? WeeklyReview(
              id: 'weekly-${start.month}-${start.day}',
              weekStartDate: start,
              mood: mood,
              createdAt: start,
              updatedAt: start,
            )
          : null,
    );
  }

  return [
    week(DateTime(2026, 8, 10), 52, 2),
    week(DateTime(2026, 8, 17), 64, 3),
    week(DateTime(2026, 8, 24), 71, 3),
    week(DateTime(2026, 8, 31), null, null),
    week(DateTime(2026, 9, 7), 57, 2),
    week(DateTime(2026, 9, 14), 82, 4),
    week(DateTime(2026, 9, 21), 45, 1),
  ];
}
