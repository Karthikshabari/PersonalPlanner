import 'dart:async';

import '../database/app_database.dart';

/// Shared invalidation owner for derived review/analytics calculations.
///
/// Multiple table emissions in one event turn are coalesced. A slow
/// calculation is allowed to finish before the next invalidated calculation
/// starts, so a burst of writes cannot create an unbounded stack of duplicate
/// database reads. Only the newest generation is allowed to emit.
Stream<T> watchReactiveStats<T>(
  AppDatabase database,
  Future<T> Function() calculate,
) {
  return Stream<T>.multi((controller) {
    var disposed = false;
    var generation = 0;
    var calculationRunning = false;
    var rerunRequested = false;
    Timer? pending;
    final subscriptions = <StreamSubscription<dynamic>>[];

    void schedule([Object? _]) {
      if (disposed) return;
      if (calculationRunning) {
        rerunRequested = true;
        return;
      }
      pending?.cancel();
      pending = Timer(Duration.zero, () {
        if (disposed) return;
        final currentGeneration = ++generation;
        calculationRunning = true;
        unawaited(() async {
          try {
            final value = await calculate();
            if (!disposed && currentGeneration == generation) {
              controller.add(value);
            }
          } catch (error, stack) {
            if (!disposed && currentGeneration == generation) {
              controller.addError(error, stack);
            }
          } finally {
            calculationRunning = false;
            if (!disposed && rerunRequested) {
              rerunRequested = false;
              schedule();
            }
          }
        }());
      });
    }

    subscriptions.add(database.select(database.tasks).watch().listen(schedule));
    subscriptions.add(
      database.select(database.categories).watch().listen(schedule),
    );
    subscriptions.add(
      database.select(database.timerSessions).watch().listen(schedule),
    );
    subscriptions.add(
      database.select(database.dailyReviews).watch().listen(schedule),
    );
    subscriptions.add(
      database.select(database.weeklyReviews).watch().listen(schedule),
    );
    schedule();

    controller.onCancel = () async {
      disposed = true;
      generation++;
      rerunRequested = false;
      pending?.cancel();
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
  });
}
