import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/features/timeline/domain/conflict_detector.dart';
import 'package:personal_planner/features/timeline/domain/conflict_resolver.dart';

Task task(
  String id,
  int startMinutes,
  int endMinutes, {
  DateTime? onDay,
}) {
  final day = onDay ?? DateTime(2026, 7, 23);
  return Task(
    id: id,
    title: 'Task $id',
    startTime: day.add(Duration(minutes: startMinutes)),
    endTime: day.add(Duration(minutes: endMinutes)),
    createdAt: day,
    updatedAt: day,
  );
}

Task move(Task t, int deltaMinutes) => t.copyWith(
      startTime: t.startTime!.add(Duration(minutes: deltaMinutes)),
      endTime: t.endTime!.add(Duration(minutes: deltaMinutes)),
    );

void main() {
  final day = DateTime(2026, 7, 23);

  group('planShiftAllFollowing', () {
    test('shifts every task starting at/after first conflict by overlap', () {
      // Moved task dropped at 9:00–10:30.
      final moved = task('m', 540, 630);
      final b = task('b', 540, 600); // 9:00–10:00 (first conflict)
      final c = task('c', 600, 660); // 10:00–11:00
      final d = task('d', 660, 720); // 11:00–12:00
      final before = task('e', 480, 540); // 8:00–9:00 (not following)

      final plan = ConflictResolver.planShiftAllFollowing(
        moved: moved,
        dayTasks: [before, b, c, d],
      );

      expect(plan.keepOverlapIds, isEmpty);
      final shiftById = {for (final s in plan.shifts) s.taskId: s};
      // Overlap duration = 10:30 − 9:00 = 90 min.
      final bs = shiftById['b']!;
      expect(bs.newStart, DateTime(2026, 7, 23).add(const Duration(minutes: 630)));
      expect(bs.newEnd, day.add(const Duration(minutes: 690)));
      final cs = shiftById['c']!;
      expect(cs.newStart, day.add(const Duration(minutes: 690)));
      final ds = shiftById['d']!;
      expect(ds.newStart, day.add(const Duration(minutes: 750)));
      expect(shiftById.containsKey('e'), isFalse);
    });

    test('no conflicts → empty plan', () {
      final moved = task('m', 300, 360);
      final other = task('b', 600, 660);
      final plan = ConflictResolver.planShiftAllFollowing(
        moved: moved,
        dayTasks: [other],
      );
      expect(plan.isEmpty, isTrue);
    });
  });

  group('planShiftOnlyOverlapping (cascade)', () {
    test('cascade pushes subsequent blocks until conflict-free', () {
      // Dropped block overlaps A by 30 min; A then overlaps B; B then C.
      final moved = task('m', 540, 600); // 9:00–10:00
      final a = task('a', 550, 620); // 9:10–10:20 → +50 → 10:00–10:70?? no:
      // a shifted by (moved.end 10:00 − a.start 9:10) = 50min → 10:00–11:10
      final b = task('b', 630, 660); // 10:30–11:00 → conflicts with new a
      // b shifted by (a.end 11:10 − b.start 10:30) = 40min → 11:10–11:40
      final c = task('c', 700, 720); // 11:40–12:00 → adjacent, no conflict

      final plan = ConflictResolver.planShiftOnlyOverlapping(
        moved: moved,
        dayTasks: [moved, a, b, c],
      );

      final shiftById = {for (final s in plan.shifts) s.taskId: s};
      expect(shiftById.keys, containsAll(['a', 'b']));
      expect(plan.keepOverlapIds, isEmpty);

      final as = shiftById['a']!;
      expect(as.newStart, day.add(const Duration(minutes: 600)));
      expect(as.newEnd, day.add(const Duration(minutes: 670)));
      final bs = shiftById['b']!;
      expect(bs.newStart, day.add(const Duration(minutes: 670)));
      expect(bs.newEnd, day.add(const Duration(minutes: 700)));
      expect(shiftById.containsKey('c'), isFalse);
    });

    test('cascade depth limit falls back to keep-overlap', () {
      // Dense chain of 60-minute blocks staggered by 30 minutes: resolving
      // the drop needs cascading pushes. Capping the depth at 1 must fall
      // back to keep-overlap for whatever remains unresolved (including
      // flagging the moved block itself).
      final tasks = <Task>[];
      const n = 15;
      for (var i = 0; i < n; i++) {
        tasks.add(task('t$i', 540 + i * 30, 540 + i * 30 + 60));
      }
      final moved = task('m', 540, 610);

      final plan = ConflictResolver.planShiftOnlyOverlapping(
        moved: moved,
        dayTasks: [...tasks, moved],
        maxCascadeDepth: 1,
      );

      expect(plan.keepOverlapIds, isNotEmpty);
      // Fallback flags the moved block too.
      expect(plan.keepOverlapIds, contains('m'));
    });

    test('default cascade resolves a moderate chain conflict-free', () {
      // A -> B -> C chain, each 60-min block pushed onto the next.
      final moved = task('m', 545, 605); // overlaps A by 55min
      final a = task('a', 550, 610);
      final b = task('b', 615, 675);
      final plan = ConflictResolver.planShiftOnlyOverlapping(
        moved: moved,
        dayTasks: [moved, a, b],
        maxCascadeDepth: 10,
      );
      expect(plan.shifts, hasLength(2));
      expect(plan.keepOverlapIds, isEmpty);
    });
  });

  group('findNextAvailableSlot', () {
    test('returns original end when free', () {
      final a = task('a', 540, 600);
      final slot = ConflictResolver.findNextAvailableSlot(
        durationMinutes: 60,
        dayTasks: [a],
        searchFromMinutes: 600,
      );
      expect(slot, 600);
    });

    test('skips past an occupied block', () {
      final a = task('a', 540, 660); // 9:00–11:00
      final b = task('b', 660, 720); // 11:00–12:00
      final slot = ConflictResolver.findNextAvailableSlot(
        durationMinutes: 60,
        dayTasks: [a, b],
        searchFromMinutes: 600,
      );
      expect(slot, 720); // after b
    });

    test('fits into a gap between blocks', () {
      final a = task('a', 540, 660);
      final b = task('b', 720, 780);
      final slot = ConflictResolver.findNextAvailableSlot(
        durationMinutes: 45,
        dayTasks: [a, b],
        searchFromMinutes: 600,
      );
      expect(slot, 660);
    });

    test('returns null when nothing fits before midnight', () {
      final a = task('a', 1380, 1440);
      final slot = ConflictResolver.findNextAvailableSlot(
        durationMinutes: 60,
        dayTasks: [a],
        searchFromMinutes: 1400,
      );
      expect(slot, isNull);
    });
  });

  group('detector interplay', () {
    test('moved hypothetical against original list finds targets', () {
      final a = task('a', 540, 600);
      final movedOriginal = task('x', 480, 540);
      final hypothetical =
          move(movedOriginal, 90); // now 9:30–10:00 overlapping a
      expect(ConflictDetector.detect(hypothetical, [a]), [a]);
    });
  });
}
