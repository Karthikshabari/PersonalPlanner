import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/domain/task_outcome.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../../helpers/sqlite_setup.dart';

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

void main() {
  setupSqliteForTests();

  late AppDatabase db;
  late ProviderContainer container;
  final day = startOfDay(DateTime(2026, 10, 6));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<void> addTask(String id) {
    final stamp = DateTime.utc(2026, 1, 1);
    return db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id,
            title: id,
            startTime: Value(DateTime(2026, 10, 6, 9)),
            endTime: Value(DateTime(2026, 10, 6, 10)),
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
  }

  Future<ProviderSubscription<AsyncValue<List<TaskOutcomeRow>>>> listenReady(
    ProviderListenable<AsyncValue<List<TaskOutcomeRow>>> provider,
  ) async {
    final ready = Completer<void>();
    final sub = container.listen<AsyncValue<List<TaskOutcomeRow>>>(provider, (
      _,
      next,
    ) {
      if (next.hasValue && !ready.isCompleted) ready.complete();
    }, fireImmediately: true);
    await ready.future.timeout(const Duration(seconds: 10));
    return sub;
  }

  // A day just left is kept so stepping back shows it at once. A kept value
  // must never be older than the data: any write while nobody listens drops it.
  test(
    'a kept review stream is instant when unchanged and never stale',
    () async {
      final provider = taskOutcomesProvider(day);
      var sub = await listenReady(provider);
      expect(container.read(provider).requireValue, isEmpty);

      // Leave the day, write nothing: the value is still there at once.
      sub.close();
      await _settle();
      expect(container.exists(provider), isTrue);
      sub = container.listen(provider, (_, _) {});
      expect(container.read(provider).hasValue, isTrue);
      expect(container.read(provider).requireValue, isEmpty);

      // Leave again and write a block while away: the kept value is dropped, so
      // coming back can never show the empty list as if it were current.
      sub.close();
      await _settle();
      await addTask('t1');
      await _settle();
      expect(container.exists(provider), isFalse);
      sub = container.listen(provider, (_, _) {});
      final shown = container.read(provider);
      expect(shown.hasValue && shown.requireValue.isEmpty, isFalse);
      await _settle();
      expect(container.read(provider).requireValue.map((r) => r.taskId), [
        't1',
      ]);
      sub.close();
    },
  );
}
