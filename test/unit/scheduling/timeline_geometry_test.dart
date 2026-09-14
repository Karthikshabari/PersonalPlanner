import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/constants/app_constants.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/planner_day_axis.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/timeline/domain/conflict_detector.dart';
import 'package:personal_planner/features/timeline/domain/timeline_geometry.dart';

Task makeTask(
  String id, {
  required DateTime start,
  required DateTime end,
  int? actualMinutes,
  TaskStatus status = TaskStatus.planned,
}) => Task(
  id: id,
  title: 'Task $id',
  startTime: start,
  endTime: end,
  actualDurationMin: actualMinutes,
  status: status,
  createdAt: start,
  updatedAt: start,
);

void main() {
  setUp(() => PlannerTimeZone.initialize(identifier: 'UTC'));

  test('keeps gaps, endpoints and adjacent intervals on the shared axis', () {
    final day = PlannerTimeZone.calendarDate(2026, 7, 23);
    final first = makeTask(
      'first',
      start: day.add(const Duration(hours: 9)),
      end: day.add(const Duration(hours: 10)),
    );
    final second = makeTask(
      'second',
      start: day.add(const Duration(hours: 11)),
      end: day.add(const Duration(hours: 11, minutes: 30)),
    );
    final adjacent = makeTask(
      'adjacent',
      start: day.add(const Duration(hours: 10)),
      end: day.add(const Duration(hours: 11)),
    );
    final geometries = TimelineGeometry.layoutForDay(
      tasks: [first, second, adjacent],
      date: day,
    );
    final byId = {
      for (final geometry in geometries) geometry.task.id: geometry,
    };

    expect(byId['first']!.topPx, closeTo(9 * 64, 0.001));
    expect(byId['first']!.heightPx, closeTo(64, 0.001));
    expect(byId['second']!.topPx, closeTo(11 * 64, 0.001));
    expect(byId['second']!.heightPx, closeTo(32, 0.001));
    expect(byId['first']!.laneCount, 1);
    expect(byId['adjacent']!.hasOverlap, isFalse);
  });

  test('overlap geometry assigns distinct side-by-side lanes', () {
    final day = PlannerTimeZone.calendarDate(2026, 7, 23);
    final outer = makeTask(
      'outer',
      start: day.add(const Duration(hours: 9)),
      end: day.add(const Duration(hours: 11)),
    );
    final overlapping = makeTask(
      'overlap',
      start: day.add(const Duration(hours: 9, minutes: 30)),
      end: day.add(const Duration(hours: 10, minutes: 30)),
    );
    final geometries = TimelineGeometry.layoutForDay(
      tasks: [outer, overlapping],
      date: day,
    );

    expect(geometries, hasLength(2));
    expect(geometries[0].laneCount, 2);
    expect(geometries[1].laneCount, 2);
    expect(geometries[0].laneIndex, isNot(geometries[1].laneIndex));
    expect(geometries.every((geometry) => geometry.hasOverlap), isTrue);
    expect(
      geometries.first.componentTaskIds,
      containsAll(<String>['outer', 'overlap']),
    );
  });

  test(
    'cross-midnight tasks retain identity and project coverage per segment',
    () {
      final firstDay = PlannerTimeZone.calendarDate(2026, 7, 23);
      final secondDay = PlannerTimeZone.calendarDate(2026, 7, 24);
      final task = makeTask(
        'overnight',
        start: firstDay.add(const Duration(hours: 23, minutes: 30)),
        end: secondDay.add(const Duration(minutes: 30)),
        actualMinutes: 45,
      );
      final first = TimelineGeometry.layoutForDay(
        tasks: [task],
        date: firstDay,
      ).single;
      final second = TimelineGeometry.layoutForDay(
        tasks: [task],
        date: secondDay,
      ).single;

      expect(first.task.id, task.id);
      expect(second.task.id, task.id);
      expect(first.continuesBefore, isFalse);
      expect(first.continuesAfter, isTrue);
      expect(second.continuesBefore, isTrue);
      expect(second.continuesAfter, isFalse);
      expect(first.visibleDuration, const Duration(minutes: 30));
      expect(second.visibleDuration, const Duration(minutes: 30));
      expect(first.actualCoveredDuration, const Duration(minutes: 30));
      expect(second.actualCoveredDuration, const Duration(minutes: 15));
      expect(second.plannedRemainingDuration, const Duration(minutes: 15));
    },
  );

  test(
    'overtime changes semantic status without changing scheduled geometry',
    () {
      final day = PlannerTimeZone.calendarDate(2026, 7, 23);
      final normal = makeTask(
        'normal',
        start: day.add(const Duration(hours: 16)),
        end: day.add(const Duration(hours: 17)),
        actualMinutes: 60,
      );
      final overtime = normal.copyWith(id: 'overtime', actualDurationMin: 75);
      final normalGeometry = TimelineGeometry.layoutForDay(
        tasks: [normal],
        date: day,
      ).single;
      final overtimeGeometry = TimelineGeometry.layoutForDay(
        tasks: [overtime],
        date: day,
      ).single;

      expect(overtimeGeometry.topPx, normalGeometry.topPx);
      expect(overtimeGeometry.heightPx, normalGeometry.heightPx);
      expect(overtimeGeometry.overtimeDuration, const Duration(minutes: 15));
      expect(overtimeGeometry.actualCoverageFraction, 1);
    },
  );

  test(
    'cross-midnight overtime is marked only on the scheduled-end segment',
    () {
      final firstDay = PlannerTimeZone.calendarDate(2026, 7, 23);
      final task = makeTask(
        'overnight-overtime',
        start: firstDay.add(const Duration(hours: 23, minutes: 30)),
        end: PlannerTimeZone.calendarDate(2026, 7, 24, hour: 0, minute: 30),
        actualMinutes: 75,
      );
      final first = TimelineGeometry.layoutForDay(
        tasks: [task],
        date: firstDay,
      ).single;
      final second = TimelineGeometry.layoutForDay(
        tasks: [task],
        date: PlannerTimeZone.calendarDate(2026, 7, 24),
      ).single;

      expect(first.overtimeDuration, const Duration(minutes: 15));
      expect(second.overtimeDuration, const Duration(minutes: 15));
      expect(first.isScheduledEndSegment, isFalse);
      expect(second.isScheduledEndSegment, isTrue);
    },
  );

  test('retains seconds and uses real elapsed time on DST days', () {
    final day = PlannerTimeZone.calendarDate(2026, 7, 23);
    final tiny = makeTask(
      'tiny',
      start: day.add(const Duration(hours: 9, seconds: 30)),
      end: day.add(const Duration(hours: 9, minutes: 1)),
    );
    final tinyGeometry = TimelineGeometry.layoutForDay(
      tasks: [tiny],
      date: day,
    ).single;
    expect(tinyGeometry.heightPx, closeTo(0.533333, 0.001));

    PlannerTimeZone.initialize(identifier: 'America/New_York');
    final springDay = PlannerTimeZone.calendarDate(2026, 3, 8);
    final axis = PlannerDayAxis(springDay);
    final dstTask = makeTask(
      'dst',
      start: PlannerTimeZone.calendarDate(2026, 3, 8, hour: 1, minute: 30),
      end: PlannerTimeZone.calendarDate(2026, 3, 8, hour: 3, minute: 30),
    );
    final geometry = TimelineGeometry.layoutForDay(
      tasks: [dstTask],
      date: springDay,
    ).single;
    expect(axis.durationMinutes, 23 * 60);
    expect(geometry.heightPx, closeTo(AppConstants.hourRowHeight, 0.001));
  });

  test(
    'historical inactive rows occupy visual lanes without becoming conflicts',
    () {
      final day = PlannerTimeZone.calendarDate(2026, 7, 23);
      final active = makeTask(
        'active',
        start: day.add(const Duration(hours: 9)),
        end: day.add(const Duration(hours: 10)),
      );
      final cancelled = makeTask(
        'cancelled',
        start: day.add(const Duration(hours: 9, minutes: 15)),
        end: day.add(const Duration(hours: 9, minutes: 45)),
        status: TaskStatus.cancelled,
      );
      final metadata = ConflictDetector.componentLaneMetadata([
        active,
        cancelled,
      ]);
      expect(metadata['active']!.hasOverlap, isTrue);
      expect(metadata['cancelled']!.hasOverlap, isTrue);
      expect(ConflictDetector.overlaps(active, cancelled), isFalse);
      final geometries = TimelineGeometry.layoutForDay(
        tasks: [active, cancelled],
        date: day,
      );
      expect(
        geometries.map((geometry) => geometry.task.id),
        containsAll(<String>['active', 'cancelled']),
      );
    },
  );

  test('supports more than ten lanes without negative geometry', () {
    final day = PlannerTimeZone.calendarDate(2026, 7, 23);
    final tasks = [
      for (var index = 0; index < 12; index++)
        makeTask(
          'lane-$index',
          start: day.add(const Duration(hours: 9)),
          end: day.add(const Duration(hours: 10)),
        ),
    ];
    final geometries = TimelineGeometry.layoutForDay(tasks: tasks, date: day);
    expect(geometries.every((geometry) => geometry.laneCount == 12), isTrue);
    expect(
      geometries.map((geometry) => geometry.laneIndex).toSet(),
      hasLength(12),
    );
    expect(geometries.every((geometry) => geometry.heightPx > 0), isTrue);
  });
}
