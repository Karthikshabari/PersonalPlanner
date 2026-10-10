import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_planner/app.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

/// Frame timings of Insights with five kept experiments: opening it, switching
/// the Experiments segments and flinging the page.
///
///   flutter drive --profile -d linux \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/insights_kept_perf_test.dart
///
/// The results are written to `build/integration_response_data.json` under the
/// keys `insights_open`, `segments` and `scroll`.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('insights kept frame timings', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await CategoryRepository(database).seedDefaultsIfEmpty();
    await _seedKeptExperiments(database);
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    appRouter.go('/analytics');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PersonalPlannerApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    await binding.watchPerformance(() async {
      for (var i = 0; i < 10; i++) {
        appRouter.go('/day');
        await tester.pumpAndSettle();
        appRouter.go('/analytics');
        await tester.pumpAndSettle();
      }
    }, reportKey: 'insights_open');

    await binding.watchPerformance(() async {
      for (var i = 0; i < 10; i++) {
        for (final label in ['Concluded (5)', 'Running (0)']) {
          final segment = find.text(label);
          await tester.ensureVisible(segment);
          await tester.pumpAndSettle();
          await tester.tap(segment);
          await tester.pumpAndSettle();
        }
      }
    }, reportKey: 'segments');

    await binding.watchPerformance(() async {
      final list = find.byType(ListView).first;
      for (var i = 0; i < 3; i++) {
        await tester.fling(list, const Offset(0, -1500), 3000);
        await tester.pumpAndSettle();
        await tester.fling(list, const Offset(0, 1500), 3000);
        await tester.pumpAndSettle();
      }
    }, reportKey: 'scroll');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      container.dispose();
      await database.close();
    });
  });
}

/// Five kept experiments, "Kept 1" … "Kept 5", each started 70 days ago and
/// ended 7 days ago, concluded today with Keep it. Each tag has one completed
/// 09:00–10:00 block (actual 60) on every weekday of the last 9 weeks that is
/// not in the future, and one planned block tomorrow when tomorrow is in this
/// week.
Future<void> _seedKeptExperiments(AppDatabase database) async {
  final experiments = ExperimentRepository(database);
  final tasks = TaskRepository(database);
  final today = parseIsoDate(isoDateString(DateTime.now()));
  final todayIso = isoDateString(today);
  final thisWeek = startOfWeek(today);
  final tomorrow = addDays(today, 1);

  Future<void> block(
    DateTime day,
    String tagId,
    TaskStatus status, {
    int? actual,
  }) {
    final start = PlannerTimeZone.calendarDate(
      day.year,
      day.month,
      day.day,
      hour: 9,
    );
    final end = PlannerTimeZone.calendarDate(
      day.year,
      day.month,
      day.day,
      hour: 10,
    );
    return tasks.insertTask(
      Task(
        id: '',
        title: 'Block',
        startTime: start,
        endTime: end,
        status: status,
        actualDurationMin: actual,
        tagId: tagId,
        createdAt: start,
        updatedAt: start,
      ),
    );
  }

  for (var n = 1; n <= 5; n++) {
    final created = await experiments.createExperiment(
      name: 'Kept $n',
      startDate: isoDateString(addDays(today, -70)),
      endDate: isoDateString(addDays(today, -7)),
      weekdayTargetMin: 60,
      weekendTargetMin: 90,
      checkInEveryDays: 7,
    );
    await experiments.concludeExperiment(
      created.id,
      outcome: ExperimentOutcome.keep,
      note: 'Worth keeping.',
      today: todayIso,
      expectedRevision: created.revision,
    );
    for (var week = 8; week >= 0; week--) {
      final monday = addDays(thisWeek, -7 * week);
      for (var d = 0; d < 5; d++) {
        final day = addDays(monday, d);
        if (day.isAfter(today)) continue;
        await block(day, created.tagId, TaskStatus.completed, actual: 60);
      }
    }
    if (tomorrow.isBefore(addDays(thisWeek, 7))) {
      await block(tomorrow, created.tagId, TaskStatus.planned);
    }
  }
}
