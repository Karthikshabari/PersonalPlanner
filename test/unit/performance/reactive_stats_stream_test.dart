import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/reactive_stats_stream.dart';

import '../../helpers/sqlite_setup.dart';

void main() {
  setupSqliteForTests();

  test(
    'serializes recalculation bursts and runs the latest request after it',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      var calls = 0;
      var running = 0;
      var maximumRunning = 0;

      final stream = watchReactiveStats<int>(db, () async {
        calls++;
        running++;
        maximumRunning = maximumRunning < running ? running : maximumRunning;
        if (calls == 1) {
          firstStarted.complete();
          await releaseFirst.future;
        }
        running--;
        return calls;
      });
      final subscription = stream.listen((_) {});
      try {
        await firstStarted.future;
        for (var i = 0; i < 3; i++) {
          await db
              .into(db.tasks)
              .insert(
                TasksCompanion.insert(
                  id: 'burst-$i',
                  title: 'Burst $i',
                  createdAt: DateTime.utc(2026, 8, 24),
                  updatedAt: DateTime.utc(2026, 8, 24),
                ),
              );
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(maximumRunning, 1);

        releaseFirst.complete();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        expect(calls, 2);
        expect(maximumRunning, 1);
      } finally {
        await subscription.cancel();
        await db.close();
      }
    },
  );
}
