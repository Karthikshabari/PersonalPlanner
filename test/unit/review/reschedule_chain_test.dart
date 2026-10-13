import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/review/domain/daily_stats_service.dart';
import 'package:personal_planner/features/review/domain/reschedule_chain.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';
import 'package:personal_planner/features/review/domain/task_outcome_service.dart';
import 'package:personal_planner/features/review/domain/weekly_review_numbers.dart';
import 'package:personal_planner/features/review/domain/weekly_review_service.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import '../../helpers/sqlite_setup.dart';

/// QA fix phase 1 item 7: plan history text. Display only.
void main() {
  setupSqliteForTests();
  PlannerTimeZone.initialize(identifier: 'UTC');

  final monday = PlannerTimeZone.calendarDate(2026, 9, 7);

  RescheduleLink link(
    String id,
    int day,
    int hour, {
    String? to,
    bool deleted = false,
  }) {
    final start = addDays(monday, day).add(Duration(hours: hour));
    return (
      id: id,
      start: start,
      end: start.add(const Duration(hours: 1)),
      rescheduledToId: to,
      deleted: deleted,
    );
  }

  Map<String, RescheduleLink> byId(List<RescheduleLink> links) => {
    for (final l in links) l.id: l,
  };

  group('rescheduleMoveOf', () {
    test('no move, one move, two moves', () {
      expect(rescheduleMoveOf('a', byId([link('a', 0, 9)])), isNull);

      final once = rescheduleMoveOf(
        'a',
        byId([link('a', 0, 9, to: 'b'), link('b', 3, 14)]),
      )!;
      expect(once.pushes, 1);
      expect(
        plannedNowText(once),
        'Planned Mon 09:00–10:00 → now Thu 14:00–15:00',
      );
      expect(movedToText(once), 'Moved to Thu Sep 10, 14:00');

      final chain = byId([
        link('a', 0, 9, to: 'b'),
        link('b', 1, 14, to: 'c'),
        link('c', 2, 14),
      ]);
      final first = rescheduleMoveOf('a', chain)!;
      final middle = rescheduleMoveOf('b', chain)!;
      expect(first.pushes, 2);
      expect(middle.pushes, 2);
      expect(
        plannedNowText(first),
        'Planned Mon 09:00–10:00 → now Wed 14:00–15:00 · pushed 2 times',
      );
      expect(
        plannedNowText(middle),
        'Planned Tue 14:00–15:00 → now Wed 14:00–15:00 · pushed 2 times',
      );
    });

    test('a deleted row in the middle is walked through, not counted', () {
      final move = rescheduleMoveOf(
        'a',
        byId([
          link('a', 0, 9, to: 'b'),
          link('b', 1, 14, to: 'c', deleted: true),
          link('c', 2, 14),
        ]),
      )!;
      expect(move.pushes, 1);
      expect(move.toStart, link('c', 2, 14).start);
    });

    test('a cycle terminates; a deleted last block gives no move', () {
      expect(
        () => rescheduleMoveOf(
          'a',
          byId([link('a', 0, 9, to: 'b'), link('b', 1, 9, to: 'a')]),
        ),
        returnsNormally,
      );
      expect(
        rescheduleMoveOf(
          'a',
          byId([link('a', 0, 9, to: 'b'), link('b', 1, 9, deleted: true)]),
        ),
        isNull,
      );
    });
  });

  group('review rows', () {
    late AppDatabase db;
    late TaskRepository tasks;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      tasks = TaskRepository(db);
    });
    tearDown(() => db.close());

    Future<Task> block(int day, int hour, {String? from}) {
      final start = addDays(monday, day).add(Duration(hours: hour));
      return tasks.insertTask(
        Task(
          id: '',
          title: 'Report',
          startTime: start,
          endTime: start.add(const Duration(hours: 1)),
          rescheduledFromId: from,
          createdAt: monday,
          updatedAt: monday,
        ),
      );
    }

    Future<Task> moveTo(Task from, int day, int hour) async {
      final next = await block(day, hour, from: from.id);
      await tasks.markRescheduled(from.id, next.id);
      return next;
    }

    test('Daily and Weekly show the move; counts are unchanged', () async {
      final a = await block(0, 9);
      final b = await moveTo(a, 1, 14);
      await moveTo(b, 2, 14);

      final statsBefore = await DailyStatsService(db).computeForDate(monday);
      final daily = await TaskOutcomeService(db).forDay(monday);
      expect(daily.single.outcome, TaskOutcome.rescheduled);
      expect(movedToText(daily.single.move!), 'Moved to Wed Sep 9, 14:00');
      expect(daily.single.move!.pushes, 2);
      expect(statsBefore.totalTasks, 0);
      expect(statsBefore.plannedDurationMin, 0);

      final numbers = computeWeeklyNumbers(
        await WeeklyReviewService(db).loadWeek(monday),
        now: addDays(monday, 7),
      );
      expect(numbers.total, 1);
      expect(numbers.rescheduled, 2);
      expect(numbers.outcomeRows.map((r) => plannedNowText(r.move!)), [
        'Planned Mon 09:00–10:00 → now Wed 14:00–15:00 · pushed 2 times',
        'Planned Tue 14:00–15:00 → now Wed 14:00–15:00 · pushed 2 times',
      ]);
    });
  });
}
