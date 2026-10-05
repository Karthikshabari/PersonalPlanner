import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/timeline/domain/conflict_detector.dart';
import 'package:personal_planner/features/timeline/domain/conflict_resolver.dart';

Task task(String id, int startMinutes, int endMinutes, {DateTime? onDay}) {
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
      expect(
        bs.newStart,
        DateTime(2026, 7, 23).add(const Duration(minutes: 630)),
      );
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

  group('planShiftOnlyOverlapping stacking (F-005)', () {
    tearDown(() => PlannerTimeZone.initialize(identifier: 'UTC'));

    Task at(String id, DateTime start, DateTime end) => Task(
      id: id,
      title: 'Task $id',
      startTime: start,
      endTime: end,
      createdAt: start,
      updatedAt: start,
    );

    // Applies the plan and asserts that the moved block and every shifted
    // block are pairwise overlap-free.
    void expectNoOverlapAmongResolved(
      Task moved,
      List<Task> dayTasks,
      ResolutionPlan plan,
    ) {
      final shiftById = {for (final s in plan.shifts) s.taskId: s};
      final resolved = [
        moved,
        for (final t in dayTasks)
          if (shiftById.containsKey(t.id))
            t.copyWith(
              startTime: shiftById[t.id]!.newStart,
              endTime: shiftById[t.id]!.newEnd,
            ),
      ];
      for (var i = 0; i < resolved.length; i++) {
        for (var j = i + 1; j < resolved.length; j++) {
          expect(
            ConflictDetector.overlaps(resolved[i], resolved[j]),
            isFalse,
            reason: '${resolved[i].id} overlaps ${resolved[j].id}',
          );
        }
      }
    }

    test('two victims of one pusher stack instead of sharing a slot', () {
      // The exact UAT T-022 scenario, in the tester's timezone.
      PlannerTimeZone.initialize(identifier: 'Asia/Kolkata');
      DateTime ist(int h, int m) =>
          PlannerTimeZone.calendarDate(2026, 10, 5, hour: h, minute: m);
      final t001 = at('t001', ist(12, 0), ist(12, 30));
      final t018 = at('t018', ist(16, 0), ist(16, 30));
      final t022 = at('t022', ist(12, 10), ist(18, 30));

      final plan = ConflictResolver.planShiftOnlyOverlapping(
        moved: t022,
        dayTasks: [t001, t018],
      );

      final shiftById = {for (final s in plan.shifts) s.taskId: s};
      expect(plan.keepOverlapIds, isEmpty);
      expect(shiftById['t001']!.newStart, ist(18, 30));
      expect(shiftById['t001']!.newEnd, ist(19, 0));
      expect(shiftById['t018']!.newStart, ist(19, 0));
      expect(shiftById['t018']!.newEnd, ist(19, 30));
      expectNoOverlapAmongResolved(t022, [t001, t018], plan);
    });

    test('three victims are stacked in original start order', () {
      final d = DateTime.utc(2026, 7, 23);
      DateTime hm(int h, int m) => d.add(Duration(hours: h, minutes: m));
      final moved = at('m', hm(9, 0), hm(12, 0));
      final a = at('a', hm(9, 30), hm(10, 0)); // 30 min
      final b = at('b', hm(10, 30), hm(11, 30)); // 60 min
      final c = at('c', hm(11, 0), hm(11, 15)); // 15 min
      final later = at('z', hm(14, 0), hm(15, 0)); // clear of the stack

      // Input order deliberately differs from start order.
      final dayTasks = [c, later, a, b];
      final plan = ConflictResolver.planShiftOnlyOverlapping(
        moved: moved,
        dayTasks: dayTasks,
      );

      final shiftById = {for (final s in plan.shifts) s.taskId: s};
      expect(plan.keepOverlapIds, isEmpty);
      expect(shiftById.keys, unorderedEquals(['a', 'b', 'c']));
      expect(shiftById['a']!.newStart, hm(12, 0));
      expect(shiftById['a']!.newEnd, hm(12, 30));
      expect(shiftById['b']!.newStart, hm(12, 30));
      expect(shiftById['b']!.newEnd, hm(13, 30));
      expect(shiftById['c']!.newStart, hm(13, 30));
      expect(shiftById['c']!.newEnd, hm(13, 45));
      expectNoOverlapAmongResolved(moved, dayTasks, plan);
    });

    test('cascade through a victim\'s new slot keeps every block apart', () {
      final d = DateTime.utc(2026, 7, 23);
      DateTime hm(int h, int m) => d.add(Duration(hours: h, minutes: m));
      final moved = at('m', hm(9, 0), hm(10, 0));
      final a = at('a', hm(9, 30), hm(10, 30)); // victim -> 10:00-11:00
      final b = at('b', hm(9, 45), hm(10, 15)); // victim, stacks after a
      final x = at('x', hm(10, 45), hm(11, 15)); // hit by a's new slot
      final y = at('y', hm(11, 40), hm(12, 10)); // hit by x's new slot
      final z = at('z', hm(12, 30), hm(13, 0)); // touches y's slot only
      final early = at('w', hm(7, 0), hm(8, 0)); // unrelated

      final dayTasks = [early, a, b, x, y, z];
      final plan = ConflictResolver.planShiftOnlyOverlapping(
        moved: moved,
        dayTasks: dayTasks,
      );

      final shiftById = {for (final s in plan.shifts) s.taskId: s};
      expect(plan.keepOverlapIds, isEmpty);
      expect(shiftById.keys, unorderedEquals(['a', 'b', 'x', 'y']));
      expect(shiftById['a']!.newStart, hm(10, 0));
      expect(shiftById['b']!.newStart, hm(11, 0));
      expect(shiftById['b']!.newEnd, hm(11, 30));
      expect(shiftById['x']!.newStart, hm(11, 30));
      expect(shiftById['x']!.newEnd, hm(12, 0));
      expect(shiftById['y']!.newStart, hm(12, 0));
      expect(shiftById['y']!.newEnd, hm(12, 30));
      expectNoOverlapAmongResolved(moved, dayTasks, plan);
    });

    test('a push past the end of the day leaves that block in place', () {
      PlannerTimeZone.initialize(identifier: 'UTC');
      final d = DateTime.utc(2026, 7, 23);
      DateTime hm(int h, int m) => d.add(Duration(hours: h, minutes: m));
      final moved = at('m', hm(22, 0), hm(23, 30));
      final a = at('a', hm(22, 30), hm(23, 0)); // -> 23:30-24:00, fits
      final b = at('b', hm(23, 0), hm(23, 45)); // would end 00:45 next day

      final plan = ConflictResolver.planShiftOnlyOverlapping(
        moved: moved,
        dayTasks: [a, b],
      );

      final shiftById = {for (final s in plan.shifts) s.taskId: s};
      expect(shiftById.keys, ['a']);
      expect(shiftById['a']!.newStart, hm(23, 30));
      expect(shiftById['a']!.newEnd, DateTime.utc(2026, 7, 24));
      // b is not moved onto the next day; the overlap is reported instead.
      expect(plan.keepOverlapIds, {'b', 'm'});
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
      final hypothetical = move(
        movedOriginal,
        90,
      ); // now 9:30–10:00 overlapping a
      expect(ConflictDetector.detect(hypothetical, [a]), [a]);
    });
  });
}
