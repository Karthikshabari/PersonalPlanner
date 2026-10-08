import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/plan_title_change.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/day_context/data/day_context_repository.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';
import 'package:personal_planner/features/review/domain/weekly_review_numbers.dart';
import 'package:personal_planner/features/review/domain/weekly_review_service.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late TaskRepository tasks;
  late DateTime week;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tasks = TaskRepository(db);
    week = startOfWeek(DateTime(2026, 9, 30));
  });

  tearDown(() => db.close());

  Future<Task> add(
    String id,
    String title,
    int day,
    int hour, {
    TaskStatus status = TaskStatus.planned,
  }) {
    final start = addDays(week, day).add(Duration(hours: hour));
    return tasks.insertTask(
      Task(
        id: id,
        title: title,
        startTime: start,
        endTime: start.add(const Duration(hours: 1)),
        status: status,
        createdAt: start,
        updatedAt: start,
      ),
    );
  }

  test('loads seven days with outcomes, reasons, moods and contexts', () async {
    await add(
      '00000000-0000-7000-8000-0000000004a1',
      'Done',
      0,
      9,
      status: TaskStatus.completed,
    );
    await add(
      '00000000-0000-7000-8000-0000000004a2',
      'Skipped one',
      0,
      11,
      status: TaskStatus.skipped,
    );
    await add(
      '00000000-0000-7000-8000-0000000004a3',
      'Cancelled one',
      1,
      9,
      status: TaskStatus.cancelled,
    );
    final event = PlanTitleChange(
      id: '00000000-0000-7000-8000-0000000004b1',
      previousTitle: 'Old title',
      newTitle: 'New title',
      changedAt: DateTime.utc(2026, 9, 29, 8),
    );
    final renamed = await add(
      '00000000-0000-7000-8000-0000000004a4',
      'New title',
      1,
      11,
    );
    await tasks.updateTask(
      renamed.copyWith(
        planTitleHistory: [event],
        displayPlanChangeId: event.id,
      ),
    );
    // Starts the evening before the week: belongs to the previous week (D1).
    final before = addDays(week, -1).add(const Duration(hours: 23));
    await tasks.insertTask(
      Task(
        id: '00000000-0000-7000-8000-0000000004a5',
        title: 'Crosses midnight',
        startTime: before,
        endTime: before.add(const Duration(hours: 2)),
        createdAt: before,
        updatedAt: before,
      ),
    );
    await ReviewRepository(db).saveReviewDraft(
      date: week,
      mood: 3,
      note: '',
      taskReasons: {'00000000-0000-7000-8000-0000000004a2': 'Lower priority'},
    );
    await DayContextRepository(db)
        .save(isoDateString(week), DayContextKind.office, null);

    final days = await WeeklyReviewService(db).loadWeek(addDays(week, 3));

    expect(days, hasLength(7));
    expect(days.first.date, week);
    expect(days.first.reviewed, isTrue);
    expect(days.first.mood, 3);
    expect(days.first.contextLabel, 'Office');
    expect(days.first.tasks.map((t) => t.title), ['Done', 'Skipped one']);
    expect(days.first.tasks.last.reason, 'Lower priority');
    expect(days[1].reviewed, isFalse);
    expect(days[1].tasks.first.outcome, TaskOutcome.skipped);
    expect(days[1].tasks.last.planChange!.oldValue, 'Old title');

    final numbers = computeWeeklyNumbers(days);
    expect(numbers.total, 4);
    expect(numbers.completed, 1);
    expect(numbers.outcomeRows.map((r) => r.title), [
      'Skipped one',
      'Cancelled one',
    ]);
    expect(numbers.planChanged, 1);
  });
}
