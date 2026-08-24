import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/timeline/domain/snap_to_grid.dart';

void main() {
  group('snapToGrid', () {
    test('snaps to nearest 60-minute boundary', () {
      final t = DateTime(2026, 7, 23, 10, 47);
      expect(snapToGrid(t, 60), DateTime(2026, 7, 23, 11, 0));
    });

    test('rounds down when closer to previous boundary', () {
      final t = DateTime(2026, 7, 23, 10, 14);
      expect(snapToGrid(t, 60), DateTime(2026, 7, 23, 10, 0));
    });

    test('supports 30-minute grids', () {
      expect(
        snapToGrid(DateTime(2026, 7, 23, 10, 20), 30),
        DateTime(2026, 7, 23, 10, 30),
      );
    });

    test('supports 15-minute grids', () {
      expect(
        snapToGrid(DateTime(2026, 7, 23, 10, 22), 15),
        DateTime(2026, 7, 23, 10, 15),
      );
    });

    test('drops seconds and milliseconds', () {
      final t = DateTime(2026, 7, 23, 10, 0, 33, 500);
      expect(snapToGrid(t, 60).second, 0);
      expect(snapToGrid(t, 60).millisecond, 0);
    });

    test('never crosses midnight (rounding up at 23:50)', () {
      expect(snapToGrid(DateTime(2026, 7, 23, 23, 50), 60).day, 23);
      expect(snapToGrid(DateTime(2026, 7, 23, 23, 50), 60).hour, 23);
    });
  });

  group('snapSlotStart', () {
    test('clamps into [0, 1440 - grid]', () {
      expect(snapSlotStart(-100, 60), 0);
      expect(snapSlotStart(1439, 60), 1440 - 60);
      expect(snapSlotStart(1439, 15), 1425);
    });
  });

  group('snapDuration', () {
    test('enforces one grid slot minimum', () {
      expect(snapDuration(-10, 30), 30);
      expect(snapDuration(10, 30), 30);
      expect(snapDuration(31, 30), 30);
    });
    test('rounds to whole slots', () {
      expect(snapDuration(75, 30), 90);
      expect(snapDuration(120, 60), 120);
    });
  });
}
