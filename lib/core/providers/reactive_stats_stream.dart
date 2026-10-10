import 'dart:async';

import 'package:drift/drift.dart'
    show ResultSetImplementation, TableUpdateQuery;

import '../database/app_database.dart';

/// Shared invalidation owner for derived review/analytics calculations.
///
/// Multiple table emissions in one event turn are coalesced. A slow
/// calculation is allowed to finish before the next invalidated calculation
/// starts, so a burst of writes cannot create an unbounded stack of duplicate
/// database reads. Only the newest generation is allowed to emit.
///
/// By default every table a review or analytics calculation can read is
/// watched; a calculation that reads fewer passes [tables], so a write to an
/// unrelated table does not recompute it. A caller that already holds a value
/// known to be current passes it as [initial]: it is emitted at once and the
/// first calculation is skipped (later writes still recalculate).
///
/// Most writes (a sync acknowledgement, a task on another day) leave the result
/// unchanged. With [isSame] a result equal to the one last emitted is dropped,
/// so listeners are not notified and the screen is not rebuilt for nothing.
/// [isSame] must compare every field a listener can show.
Stream<T> watchReactiveStats<T>(
  AppDatabase database,
  Future<T> Function() calculate, {
  List<ResultSetImplementation<dynamic, dynamic>>? tables,
  T? initial,
  bool Function(T previous, T next)? isSame,
}) {
  return Stream<T>.multi((controller) {
    var disposed = false;
    var generation = 0;
    var calculationRunning = false;
    var rerunRequested = false;
    Timer? pending;
    T? last;
    var hasLast = false;
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
              if (!hasLast || isSame == null || !isSame(last as T, value)) {
                last = value;
                hasLast = true;
                controller.add(value);
              }
            }
          } catch (error, stack) {
            if (!disposed && currentGeneration == generation) {
              // The next value must replace the error even if it equals the
              // last good one.
              hasLast = false;
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

    // Only the "a table changed" signal is needed. `tableUpdates` delivers it
    // without running (and discarding) a `SELECT *` over each whole table, and
    // without the six extra initial emissions that used to force a second,
    // identical calculation right after the first one.
    subscriptions.add(
      database
          .tableUpdates(
            TableUpdateQuery.onAllTables(
              tables ??
                  [
                    database.tasks,
                    database.categories,
                    database.timerSessions,
                    database.dailyReviews,
                    database.weeklyReviews,
                    database.dayContexts,
                  ],
            ),
          )
          .listen(schedule),
    );
    if (initial != null) {
      last = initial;
      hasLast = true;
      controller.add(initial);
    } else {
      schedule();
    }

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
