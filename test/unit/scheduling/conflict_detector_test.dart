import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/timeline/domain/conflict_detector.dart';

Task task(
  String id, {
  required DateTime start,
  required DateTime end,
  TaskStatus status = TaskStatus.planned,
}) =>
    Task(
      id: id,
      title: 'Task $id',
      startTime: start,
      endTime: end,
      status: status,
      createdAt: start,
      updatedAt: start,
    );

final day = DateTime(2026, 7, 23);

void main() {
  group('ConflictDetector.detect', () {
    test('detects interval overlap', () {
      final a = task('a',
          start: day.add(const Duration(hours: 9)),
          end: day.add(const Duration(hours: 10)));
      final b = task('b',
          start: day.add(const Duration(hours: 9, minutes: 30)),
          end: day.add(const Duration(hours: 11)));
      expect(ConflictDetector.detect(a, [b]), [b]);
      expect(ConflictDetector.detect(b, [a]), [a]);
    });

    test('adjacent blocks do not conflict', () {
      final a = task('a',
          start: day.add(const Duration(hours: 9)),
          end: day.add(const Duration(hours: 10)));
      final b = task('b',
          start: day.add(const Duration(hours: 10)),
          end: day.add(const Duration(hours: 11)));
      expect(ConflictDetector.detect(a, [b]), isEmpty);
    });

    test('skips self', () {
      final a = task('a',
          start: day.add(const Duration(hours: 9)),
          end: day.add(const Duration(hours: 10)));
      expect(ConflictDetector.detect(a, [a]), isEmpty);
    });

    test('skips cancelled and rescheduled tasks', () {
      final a = task('a',
          start: day.add(const Duration(hours: 9)),
          end: day.add(const Duration(hours: 10)));
      final cancelled = task('c',
          start: day.add(const Duration(hours: 9, minutes: 30)),
          end: day.add(const Duration(hours: 11)),
          status: TaskStatus.cancelled);
      final rescheduled = task('r',
          start: day.add(const Duration(hours: 9, minutes: 30)),
          end: day.add(const Duration(hours: 11)),
          status: TaskStatus.rescheduled);
      expect(ConflictDetector.detect(a, [cancelled, rescheduled]), isEmpty);
    });

    test('returns conflicts sorted by start time', () {
      final a = task('a',
          start: day.add(const Duration(hours: 9)),
          end: day.add(const Duration(hours: 12)));
      final later = task('l',
          start: day.add(const Duration(hours: 11)),
          end: day.add(const Duration(hours: 12)));
      final earlier = task('e',
          start: day.add(const Duration(hours: 8)),
          end: day.add(const Duration(hours: 10)));
      final result = ConflictDetector.detect(a, [later, earlier]);
      expect(result.map((t) => t.id), ['e', 'l']);
    });

    test('ignores unscheduled (inbox) rows', () {
      final a = task('a',
          start: day.add(const Duration(hours: 9)),
          end: day.add(const Duration(hours: 10)));
      final inbox = Task(
        id: 'i',
        title: 'Inbox',
        isInbox: true,
        createdAt: day,
        updatedAt: day,
      );
      expect(ConflictDetector.detect(a, [inbox]), isEmpty);
    });
  });

  group('ConflictDetector.overlappingIdSet', () {
    test('marks both members of each overlapping pair', () {
      final a = task('a',
          start: day.add(const Duration(hours: 9)),
          end: day.add(const Duration(hours: 10)));
      final b = task('b',
          start: day.add(const Duration(hours: 9, minutes: 30)),
          end: day.add(const Duration(hours: 11)));
      final c = task('c',
          start: day.add(const Duration(hours: 12)),
          end: day.add(const Duration(hours: 13)));
      final ids = ConflictDetector.overlappingIdSet([a, b, c]);
      expect(ids, {'a', 'b'});
    });
  });
}
