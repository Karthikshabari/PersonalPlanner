import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:personal_planner/app.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';

/// Frame timings of the Review › Overview tab: flinging the strip, the arrows,
/// selecting tiles and switching between Days and Weeks.
///
///   flutter drive --profile -d linux \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/overview_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('overview frame timings', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await CategoryRepository(database).seedDefaultsIfEmpty();
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    appRouter.go('/review/overview');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PersonalPlannerApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    await binding.traceAction(() async {
      final days = find.byKey(const ValueKey('overview-strip'));
      await tester.fling(days, const Offset(600, 0), 1500);
      await tester.pumpAndSettle();
      await tester.fling(days, const Offset(-600, 0), 1500);
      await tester.pumpAndSettle();
      for (final key in [
        'overview-older',
        'overview-older',
        'overview-newer',
        'overview-newer',
      ]) {
        final arrow = find.byKey(ValueKey(key));
        if (arrow.evaluate().isEmpty) continue;
        await tester.tap(arrow);
        await tester.pumpAndSettle();
      }
      // Select a few visible tiles.
      final tiles = find.descendant(
        of: days,
        matching: find.byWidgetPredicate(
          (w) => w.key.toString().contains('overview-day-'),
        ),
      );
      final count = tiles.evaluate().length;
      for (var i = 0; i < count && i < 4; i++) {
        await tester.tap(tiles.at(i));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Weeks'));
      await tester.pumpAndSettle();
      final weeks = find.byKey(const ValueKey('overview-week-strip'));
      await tester.fling(weeks, const Offset(600, 0), 1500);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Days'));
      await tester.pumpAndSettle();
    }, reportKey: 'overview_timeline');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      container.dispose();
      await database.close();
    });
  });
}
