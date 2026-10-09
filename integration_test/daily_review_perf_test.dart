import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_planner/app.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';

/// Frame timings of the Daily Review tab with a busy day (fifteen tasks, most
/// of them skipped): scroll, rating taps, preset chips, typing in a reason and
/// in the note, and opening / closing "Edit presets".
///
///   flutter drive --profile -d linux \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/daily_review_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('daily review frame timings', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await CategoryRepository(database).seedDefaultsIfEmpty();
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    final repo = container.read(taskRepositoryProvider);
    final now = DateTime.now();
    for (var i = 0; i < 15; i++) {
      final start = DateTime(now.year, now.month, now.day, 5).add(
        Duration(minutes: 40 * i),
      );
      await repo.insertTask(
        Task(
          id: '',
          title: 'Task ${i + 1} with a reasonably long descriptive title',
          startTime: start,
          endTime: start.add(const Duration(minutes: 30)),
          status: i % 4 == 3 ? TaskStatus.completed : TaskStatus.skipped,
          createdAt: start,
          updatedAt: start,
        ),
      );
    }
    appRouter.go('/review');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PersonalPlannerApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    await binding.traceAction(() async {
      final list = find.byType(ListView).first;
      await tester.fling(list, const Offset(0, -900), 1500);
      await tester.pumpAndSettle();
      await tester.fling(list, const Offset(0, 900), 1500);
      await tester.pumpAndSettle();
      for (var level = 1; level <= 4; level++) {
        await tester.tap(find.byKey(ValueKey('review-mood-$level')));
        await tester.pumpAndSettle();
      }
      final chip = find.widgetWithText(ActionChip, 'Blocked').first;
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pumpAndSettle();
      final reason = find.byType(TextField).at(1);
      await tester.ensureVisible(reason);
      await tester.enterText(reason, 'The meeting ran long');
      await tester.pumpAndSettle();
      final note = find.byKey(const ValueKey('review-note'));
      await tester.ensureVisible(note);
      await tester.enterText(note, 'A steady day');
      await tester.pumpAndSettle();
      final edit = find.byKey(const ValueKey('review-edit-presets'));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }, reportKey: 'daily_review_timeline');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      container.dispose();
      await database.close();
    });
  });
}
