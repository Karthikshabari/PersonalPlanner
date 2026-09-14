import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/category.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/analytics/domain/analytics_models.dart';
import 'package:personal_planner/features/analytics/domain/analytics_service.dart';

void main() {
  PlannerTimeZone.initialize(identifier: 'UTC');
  final monday = PlannerTimeZone.calendarDate(2026, 8, 24);
  final work = _category('work', 'Work', '#4285F4');
  final learning = _category('learning', 'Learning', '#FBBC04');

  test('consistency calendar window is a rolling year ending today', () {
    final now = PlannerTimeZone.calendarDate(2026, 9, 14);
    final desktop = consistencyCalendarRange(now);
    final mobile = consistencyCalendarRange(now, compact: true);

    expect(isoDateString(desktop.start), '2025-09-15');
    expect(isoDateString(desktop.endExclusive), '2026-09-15');
    expect(desktop.dayCount, 365);
    expect(mobile.start, desktop.start);
    expect(mobile.endExclusive, desktop.endExclusive);
  });

  test('rolling year includes every date and no future date', () {
    final now = PlannerTimeZone.calendarDate(2026, 9, 14);
    final range = consistencyCalendarRange(now);
    final dates = <DateTime>[];
    for (
      var date = range.start;
      date.isBefore(range.endExclusive);
      date = addDays(date, 1)
    ) {
      dates.add(date);
    }

    expect(dates, hasLength(365));
    expect(dates.first, range.start);
    expect(isoDateString(dates.last), isoDateString(now));
    expect(dates.any((date) => date.isAfter(now)), isFalse);
  });

  test('calculator emits one canonical model for each visible date', () {
    final start = PlannerTimeZone.calendarDate(2025, 9, 15);
    final now = PlannerTimeZone.calendarDate(2026, 9, 14);
    final snapshot = _calculate(monday: start, now: now);

    expect(snapshot.consistencyDays, hasLength(365));
    expect(isoDateString(snapshot.consistencyDays.first.date), '2025-09-15');
    expect(isoDateString(snapshot.consistencyDays.last.date), '2026-09-14');
    expect(
      snapshot.consistencyDays.any((day) => day.date.isAfter(now)),
      isFalse,
    );
  });

  group('duration-weighted follow-through', () {
    test('weights planned minutes instead of task count', () {
      final snapshot = _calculate(
        monday: monday,
        tasks: [
          _task('short', monday, 15, status: TaskStatus.completed),
          _task('long', monday, 180),
        ],
      );
      final day = snapshot.consistencyDays.first;

      expect(day.plannedMinutes, 195);
      expect(day.completedPlannedMinutes, 15);
      expect(day.followThrough, closeTo(15 / 195, 0.0001));
      expect(day.intensity, ConsistencyIntensity.low);
    });

    test('handles 0%, partial, 100%, and zero planned duration', () {
      final zero = _calculate(
        monday: monday,
        tasks: [_task('zero', monday, 60)],
      ).consistencyDays.first;
      final partial = _calculate(
        monday: monday,
        tasks: [
          _task('done', monday, 30, status: TaskStatus.completed),
          _task('open', monday, 30),
        ],
      ).consistencyDays.first;
      final complete = _calculate(
        monday: monday,
        tasks: [_task('done', monday, 60, status: TaskStatus.completed)],
      ).consistencyDays.first;
      final noPlan = _calculate(monday: monday).consistencyDays.first;

      expect(zero.followThroughPercent, 0);
      expect(partial.followThroughPercent, 50);
      expect(complete.followThroughPercent, 100);
      expect(noPlan.followThrough, isNull);
      expect(noPlan.isNeutral, isTrue);
    });

    test('maps active percentages to the four heatmap intensity levels', () {
      ConsistencyIntensity intensity(int completed) => ConsistencyDay(
        date: monday,
        plannedMinutes: 100,
        completedPlannedMinutes: completed,
        actualMinutes: 0,
        isFuture: false,
      ).intensity;

      expect(intensity(10), ConsistencyIntensity.low);
      expect(intensity(30), ConsistencyIntensity.medium);
      expect(intensity(60), ConsistencyIntensity.high);
      expect(intensity(80), ConsistencyIntensity.strong);
    });

    test('slices a completed cross-midnight plan onto each date once', () {
      final sunday = monday.subtract(const Duration(days: 1));
      final overnight = Task(
        id: 'overnight',
        title: 'Overnight',
        startTime: sunday.add(const Duration(hours: 23)),
        endTime: monday.add(const Duration(hours: 1)),
        status: TaskStatus.completed,
        createdAt: sunday,
        updatedAt: sunday,
      );
      final snapshot = _calculate(monday: monday, tasks: [overnight]);

      expect(snapshot.consistencyDays.first.plannedMinutes, 60);
      expect(snapshot.consistencyDays.first.completedPlannedMinutes, 60);
      expect(snapshot.plannedMinutes, 60);
    });

    test('weekly follow-through uses planned duration weighting', () {
      final snapshot = _calculate(
        monday: monday,
        tasks: [
          _task('completed', monday, 60, status: TaskStatus.completed),
          _task('incomplete', monday, 180),
        ],
      );

      expect(snapshot.plannedMinutes, 240);
      expect(snapshot.completedPlannedMinutes, 60);
      expect(snapshot.weeklyFollowThrough, closeTo(0.25, 0.0001));
      expect(snapshot.weeklyFollowThroughPercent, 25);
    });
  });

  group('neutral days', () {
    test('Holiday and Leave are neutral even with plans', () {
      for (final kind in [DayContextKind.holiday, DayContextKind.leave]) {
        final snapshot = _calculate(
          monday: monday,
          tasks: [_task('planned-${kind.name}', monday, 60)],
          contexts: [_context(monday, kind)],
        );
        expect(snapshot.consistencyDays.first.isNeutral, isTrue);
        expect(snapshot.consistencyDays.first.followThrough, isNull);
      }
    });

    test('Travel is eligible with plans and neutral without plans', () {
      final planned = _calculate(
        monday: monday,
        tasks: [_task('travel-plan', monday, 60)],
        contexts: [_context(monday, DayContextKind.travel)],
      ).consistencyDays.first;
      final empty = _calculate(
        monday: monday,
        contexts: [_context(monday, DayContextKind.travel)],
      ).consistencyDays.first;

      expect(planned.isNeutral, isFalse);
      expect(planned.followThroughPercent, 0);
      expect(empty.isNeutral, isTrue);
    });
  });

  group('streaks', () {
    ConsistencyDay day(
      int offset,
      int completed, {
      int planned = 100,
      DayContextKind? context,
      bool future = false,
    }) => ConsistencyDay(
      date: monday.add(Duration(days: offset)),
      plannedMinutes: planned,
      completedPlannedMinutes: completed,
      actualMinutes: 0,
      context: context,
      isFuture: future,
    );

    test('successes continue and an eligible failure breaks the streak', () {
      final streaks = InsightsCalculator.calculateStreaks([
        day(0, 80),
        day(1, 100),
        day(2, 50),
        day(3, 75),
      ]);
      expect(streaks.current, 1);
      expect(streaks.best, 2);
    });

    test('neutral days do not break and future days are ignored', () {
      final streaks = InsightsCalculator.calculateStreaks([
        day(0, 80),
        day(1, 0, context: DayContextKind.holiday),
        day(2, 0, planned: 0),
        day(3, 90),
        day(4, 100, future: true),
      ]);
      expect(streaks.current, 2);
      expect(streaks.best, 2);
    });

    test(
      'snapshot streaks use the same daily follow-through models as cells',
      () {
        final snapshot = _calculate(
          monday: monday,
          now: monday.add(const Duration(days: 2, hours: 12)),
          tasks: [
            _task('success-one', monday, 100, status: TaskStatus.completed),
            _task(
              'success-two',
              monday.add(const Duration(days: 1)),
              100,
              status: TaskStatus.completed,
            ),
            _task('failure', monday.add(const Duration(days: 2)), 100),
          ],
        );

        expect(snapshot.consistencyDays.map((day) => day.isSuccessful), [
          true,
          true,
          false,
        ]);
        expect(snapshot.streaks.current, 0);
        expect(snapshot.streaks.best, 2);
      },
    );
  });

  group('actual time categories', () {
    test('aggregates actual minutes, sorts descending, and omits zero', () {
      final taskA = _task('a', monday, 60, categoryId: work.id);
      final taskB = _task('b', monday, 60, categoryId: learning.id);
      final snapshot = _calculate(
        monday: monday,
        tasks: [taskA, taskB],
        actualTasks: [taskA, taskB],
        categories: [work, learning],
        slices: [
          _slice('a', monday, 80),
          _slice('a', monday, 20),
          _slice('b', monday, 30),
          _slice('b', monday, 0),
        ],
      );

      expect(snapshot.actualMinutes, 130);
      expect(snapshot.categories.map((item) => item.name), [
        'Work',
        'Learning',
      ]);
      expect(snapshot.categories.map((item) => item.actualMinutes), [100, 30]);
    });

    test(
      'keeps four named categories, combines the rest, and keeps uncategorized',
      () {
        final categories = List.generate(
          6,
          (index) => _category('c$index', 'Category $index', '#4285F4'),
        );
        final tasks = [
          for (var index = 0; index < 6; index++)
            _task('t$index', monday, 10, categoryId: categories[index].id),
          _task('uncategorized', monday, 10),
        ];
        final snapshot = _calculate(
          monday: monday,
          tasks: tasks,
          actualTasks: tasks,
          categories: categories,
          slices: [
            for (var index = 0; index < 6; index++)
              _slice('t$index', monday, 100 - index * 10),
            _slice('uncategorized', monday, 75),
          ],
        );

        expect(
          snapshot.categories.where((item) => item.name.startsWith('Category')),
          hasLength(4),
        );
        expect(snapshot.categories.first.name, 'Other');
        expect(
          snapshot.categories
              .singleWhere((item) => item.name == 'Other')
              .actualMinutes,
          110,
        );
        expect(
          snapshot.categories
              .singleWhere((item) => item.name == 'Uncategorized')
              .actualMinutes,
          75,
        );
      },
    );
  });

  group('deterministic notable observations', () {
    test('insufficient comparable history produces nothing', () {
      final tasks = [
        _task('current', monday, 300, categoryId: work.id),
        _task(
          'previous',
          monday.subtract(const Duration(days: 7)),
          300,
          categoryId: work.id,
        ),
      ];
      final snapshot = _calculate(
        monday: monday,
        now: monday.add(const Duration(days: 10)),
        tasks: tasks,
        actualTasks: tasks,
        categories: [work],
        slices: [
          _slice('current', monday, 100),
          _slice('previous', monday.subtract(const Duration(days: 7)), 100),
        ],
      );
      expect(snapshot.notable, isEmpty);
    });

    test('category change below either threshold produces nothing', () {
      final fixture = _categoryFixture(
        monday,
        current: 150,
        prior: [100, 100],
        category: work,
      );
      final snapshot = _calculate(
        monday: monday,
        now: monday.add(const Duration(days: 10)),
        tasks: fixture.tasks,
        actualTasks: fixture.tasks,
        categories: [work],
        slices: fixture.slices,
      );
      expect(snapshot.notable, isEmpty);
    });

    test(
      'reports the strongest valid category increase and decrease factually',
      () {
        final increase = _categoryFixture(
          monday,
          current: 240,
          prior: [100, 100],
          category: learning,
        );
        final increaseSnapshot = _calculate(
          monday: monday,
          now: monday.add(const Duration(days: 10)),
          tasks: increase.tasks,
          actualTasks: increase.tasks,
          categories: [learning],
          slices: increase.slices,
        );
        expect(
          increaseSnapshot.notable.first.message,
          'Learning was 2h 20m above your recent average.',
        );

        final decrease = _categoryFixture(
          monday,
          current: 60,
          prior: [180, 180],
          category: work,
        );
        final decreaseSnapshot = _calculate(
          monday: monday,
          now: monday.add(const Duration(days: 10)),
          tasks: decrease.tasks,
          actualTasks: decrease.tasks,
          categories: [work],
          slices: decrease.slices,
        );
        expect(
          decreaseSnapshot.notable.first.message,
          'Work was 2h below your recent average.',
        );
      },
    );

    test('current partial week compares only the same elapsed weekdays', () {
      final previousMonday = monday.subtract(const Duration(days: 7));
      final earlierMonday = monday.subtract(const Duration(days: 14));
      final tasks = [
        _task('current', monday, 300, categoryId: learning.id),
        _task('prior-1', previousMonday, 300, categoryId: learning.id),
        _task('prior-2', earlierMonday, 300, categoryId: learning.id),
      ];
      final snapshot = _calculate(
        monday: monday,
        now: monday.add(const Duration(days: 2, hours: 12)),
        tasks: tasks,
        actualTasks: tasks,
        categories: [learning],
        slices: [
          _slice('current', monday.add(const Duration(days: 2)), 200),
          _slice('prior-1', previousMonday.add(const Duration(days: 1)), 100),
          _slice('prior-2', earlierMonday.add(const Duration(days: 1)), 100),
          _slice('prior-1', previousMonday.add(const Duration(days: 4)), 1000),
          _slice('prior-2', earlierMonday.add(const Duration(days: 4)), 1000),
        ],
      );
      expect(
        snapshot.notable.first.message,
        'Learning was 1h 40m above your recent average.',
      );
    });

    test('reports plan/actual gap improvement and worsening', () {
      InsightsSnapshot gapSnapshot({
        required int current,
        required int previous,
      }) {
        final previousMonday = monday.subtract(const Duration(days: 7));
        final tasks = [
          _task('current', monday, 500),
          _task('previous', previousMonday, 500),
        ];
        return _calculate(
          monday: monday,
          now: monday.add(const Duration(days: 10)),
          tasks: tasks,
          actualTasks: tasks,
          slices: [
            _slice('current', monday, current),
            _slice('previous', previousMonday, previous),
          ],
        );
      }

      expect(
        gapSnapshot(current: 450, previous: 300).notable.single.message,
        'Planned and actual time were closer than last week.',
      );
      expect(
        gapSnapshot(current: 200, previous: 450).notable.single.message,
        'The gap between planned and actual time was larger than last week.',
      );
    });

    test('returns no more than category then gap observations', () {
      final fixture = _categoryFixture(
        monday,
        current: 450,
        prior: [200, 200],
        category: learning,
        plannedMinutes: 600,
      );
      final snapshot = _calculate(
        monday: monday,
        now: monday.add(const Duration(days: 10)),
        tasks: fixture.tasks,
        actualTasks: fixture.tasks,
        categories: [learning],
        slices: fixture.slices,
      );
      expect(snapshot.notable, hasLength(2));
      expect(snapshot.notable.first.kind, NotableInsightKind.categoryChange);
      expect(snapshot.notable.last.kind, NotableInsightKind.planningGap);
    });
  });
}

InsightsSnapshot _calculate({
  required DateTime monday,
  DateTime? now,
  List<Task> tasks = const [],
  List<Task>? actualTasks,
  List<ActualTimeSlice> slices = const [],
  List<Category> categories = const [],
  List<DayContext> contexts = const [],
}) => InsightsCalculator.calculate(
  source: InsightsSourceData(
    plannedTasks: tasks,
    actualTasks: actualTasks ?? tasks,
    actualSlices: slices,
    categories: categories,
    dayContexts: contexts,
  ),
  now: now ?? monday.add(const Duration(hours: 12)),
  selectedWeekStart: monday,
  consistencyStart: monday,
);

Task _task(
  String id,
  DateTime date,
  int minutes, {
  TaskStatus status = TaskStatus.planned,
  String? categoryId,
}) => Task(
  id: id,
  title: id,
  startTime: date.add(const Duration(hours: 9)),
  endTime: date.add(Duration(hours: 9, minutes: minutes)),
  categoryId: categoryId,
  status: status,
  createdAt: date,
  updatedAt: date,
);

Category _category(String id, String name, String color) => Category(
  id: id,
  name: name,
  colorHex: color,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

DayContext _context(DateTime date, DayContextKind kind) => DayContext(
  id: 'context-${kind.name}',
  date: _iso(date),
  kind: kind,
  createdAt: date,
  updatedAt: date,
);

ActualTimeSlice _slice(String taskId, DateTime date, int minutes) =>
    ActualTimeSlice(taskId: taskId, date: date, minutes: minutes);

({List<Task> tasks, List<ActualTimeSlice> slices}) _categoryFixture(
  DateTime monday, {
  required int current,
  required List<int> prior,
  required Category category,
  int plannedMinutes = 300,
}) {
  final tasks = <Task>[
    _task('current', monday, plannedMinutes, categoryId: category.id),
  ];
  final slices = <ActualTimeSlice>[_slice('current', monday, current)];
  for (var index = 0; index < prior.length; index++) {
    final date = monday.subtract(Duration(days: 7 * (index + 1)));
    final id = 'prior-$index';
    tasks.add(_task(id, date, plannedMinutes, categoryId: category.id));
    slices.add(_slice(id, date, prior[index]));
  }
  return (tasks: tasks, slices: slices);
}

String _iso(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';
