import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/daily_review.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/day_context/data/day_context_repository.dart';
import 'package:personal_planner/features/review/data/review_repository.dart';
import 'package:personal_planner/features/review/domain/review_overview.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('window returns newest-first days with counts, mood and context', () async {
    final today = startOfDay(DateTime.now());
    final twoAgo = addDays(today, -2);
    final tasks = TaskRepository(db);
    var n = 0;
    Future<void> add(DateTime day, TaskStatus status) => tasks.insertTask(
      Task(
        id: '00000000-0000-7000-8000-0000000004${(n++).toString().padLeft(2, '0')}',
        title: 'T$n',
        startTime: day.add(const Duration(hours: 9)),
        endTime: day.add(const Duration(hours: 10)),
        status: status,
        createdAt: day,
        updatedAt: day,
      ),
    );
    await add(today, TaskStatus.completed);
    await add(today, TaskStatus.planned);
    await add(twoAgo, TaskStatus.completed);
    await add(twoAgo, TaskStatus.completed);
    await ReviewRepository(db).saveDailyReview(
      DailyReview(
        id: '',
        date: twoAgo,
        mood: 3,
        createdAt: twoAgo,
        updatedAt: twoAgo,
      ),
    );
    await DayContextRepository(db).save(
      isoDateString(twoAgo),
      DayContextKind.office,
      null,
    );

    final days = await ReviewOverviewService(db).window(today: today, dayCount: 3);

    expect(days.map((d) => d.date), [today, addDays(today, -1), twoAgo]);
    expect([days[0].totalTasks, days[0].completedTasks], [2, 1]);
    expect(days[0].reviewed, isFalse);
    expect([days[1].totalTasks, days[1].completedTasks], [0, 0]);
    expect(days[1].percent, isNull);
    expect([days[2].totalTasks, days[2].completedTasks], [2, 2]);
    expect(days[2].mood, 3);
    expect(days[2].reviewed, isTrue);
    expect(days[2].dayContext?.kind, DayContextKind.office);
  });

  test('overviewDetailLine', () {
    final date = DateTime(2026, 10, 7);
    final stamp = DateTime.utc(2026, 10, 7);
    final withAll = ReviewOverviewDay(
      date: date,
      totalTasks: 5,
      completedTasks: 1,
      review: DailyReview(
        id: 'r',
        date: date,
        mood: 2,
        createdAt: stamp,
        updatedAt: stamp,
      ),
      dayContext: DayContext(
        id: 'c',
        date: '2026-10-07',
        kind: DayContextKind.office,
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
    expect(
      overviewDetailLine(withAll),
      'Wed Oct 7 · Office · Great · 20% done (1 / 5)',
    );
    final bare = ReviewOverviewDay(date: date, totalTasks: 0, completedTasks: 0);
    expect(overviewDetailLine(bare), 'Wed Oct 7 · no mood saved · No tasks');
  });
}
