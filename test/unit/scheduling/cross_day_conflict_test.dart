import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timeline/domain/conflict_detector.dart';
import 'package:personal_planner/features/timeline/domain/scheduling_conflict_service.dart';
import 'package:personal_planner/features/timeline/domain/timeline_geometry.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();
  setUp(() => PlannerTimeZone.initialize(identifier: 'UTC'));

  test(
    'scheduling conflict query includes tasks on the next calendar day',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final repository = TaskRepository(db);
        final now = DateTime.utc(2026, 1, 1, 9);
        final nextDay = DateTime.utc(2026, 1, 2, 0, 30);
        await repository.insertTask(
          Task(
            id: 'next-day-task',
            title: 'Next day',
            startTime: nextDay,
            endTime: nextDay.add(const Duration(minutes: 30)),
            createdAt: now,
            updatedAt: now,
          ),
        );
        final proposed = Task(
          id: 'resized-task',
          title: 'Resized',
          startTime: DateTime.utc(2026, 1, 1, 23, 30),
          endTime: DateTime.utc(2026, 1, 2, 1),
          createdAt: now,
          updatedAt: now,
        );

        final candidates = await SchedulingConflictService.loadCandidates(
          repository,
          proposed,
          anchorDate: proposed.startTime,
        );
        expect(
          ConflictDetector.detect(proposed, candidates).map((task) => task.id),
          contains('next-day-task'),
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    'shared policy treats touching half-open intervals as non-conflicting',
    () {
      final first = Task(
        id: 'first',
        title: 'First',
        startTime: DateTime.utc(2026, 1, 1, 9),
        endTime: DateTime.utc(2026, 1, 1, 10),
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final second = first.copyWith(
        id: 'second',
        startTime: first.endTime,
        endTime: DateTime.utc(2026, 1, 1, 11),
      );
      expect(SchedulingConflictService.conflicts(second, [first]), isEmpty);
    },
  );

  test(
    'cross-midnight geometry clips each day without changing task identity',
    () {
      final start = DateTime.utc(2026, 1, 1, 23, 30);
      final task = Task(
        id: 'overnight-geometry',
        title: 'Overnight',
        startTime: start,
        endTime: DateTime.utc(2026, 1, 2, 1),
        actualDurationMin: 45,
        createdAt: start,
        updatedAt: start,
      );
      final firstSegment = TimelineGeometry.layoutForDay(
        tasks: [task],
        date: DateTime.utc(2026, 1, 1),
      ).single;
      final secondSegment = TimelineGeometry.layoutForDay(
        tasks: [task],
        date: DateTime.utc(2026, 1, 2),
      ).single;

      expect(firstSegment.task.id, secondSegment.task.id);
      expect(firstSegment.heightPx, closeTo(32, 0.001));
      expect(secondSegment.heightPx, closeTo(64, 0.001));
      expect(firstSegment.actualCoveredDuration, const Duration(minutes: 30));
      expect(secondSegment.actualCoveredDuration, const Duration(minutes: 15));
    },
  );
}
