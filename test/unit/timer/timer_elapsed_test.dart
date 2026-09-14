import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/timer_session.dart';
import 'package:personal_planner/features/timer/providers/timer_providers.dart';

void main() {
  test(
    'elapsed display derives from the current clock after delayed ticks',
    () {
      final started = DateTime.utc(2026, 1, 1, 9);
      expect(
        elapsedSecondsSince(started, started.add(const Duration(seconds: 17))),
        17,
      );
      expect(
        elapsedSecondsSince(started, started.add(const Duration(minutes: 2))),
        120,
      );
    },
  );

  test('manual clock rollback does not produce negative elapsed time', () {
    final started = DateTime.utc(2026, 1, 1, 9);
    expect(
      elapsedSecondsSince(
        started,
        started.subtract(const Duration(seconds: 1)),
      ),
      0,
    );
  });

  test('paused and finished sessions use persisted accumulated seconds', () {
    final start = DateTime.utc(2026, 1, 1, 9);
    final paused = TimerSession(
      id: 'paused',
      taskId: 'task',
      startedAt: start,
      durationSec: 125,
      state: TimerSessionState.paused,
      createdAt: start,
      updatedAt: start,
    );
    final running = paused.copyWith(
      state: TimerSessionState.running,
      runningSince: start.add(const Duration(minutes: 5)),
    );

    expect(
      elapsedSecondsForSession(paused, start.add(const Duration(hours: 1))),
      125,
    );
    expect(
      elapsedSecondsForSession(
        running,
        start.add(const Duration(minutes: 5, seconds: 10)),
      ),
      135,
    );
  });
}
