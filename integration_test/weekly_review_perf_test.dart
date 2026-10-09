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

/// Frame timings of the Weekly Review tab: scroll, rating taps, chip taps,
/// typing in the note and opening / closing "Edit presets".
///
///   flutter drive --profile -d linux \
///     --driver=test_driver/integration_test.dart \
///     --target=integration_test/weekly_review_perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('weekly review frame timings', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    await CategoryRepository(database).seedDefaultsIfEmpty();
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    appRouter.go('/review/weekly');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PersonalPlannerApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 300));

    await binding.traceAction(() async {
      final list = find.byType(ListView).first;
      await tester.fling(list, const Offset(0, -600), 1500);
      await tester.pumpAndSettle();
      await tester.fling(list, const Offset(0, 600), 1500);
      await tester.pumpAndSettle();
      for (var level = 1; level <= 4; level++) {
        await tester.tap(find.byKey(ValueKey('weekly-mood-$level')));
        await tester.pumpAndSettle();
      }
      for (final word in ['Focused', 'Calm', 'Tired', 'Proud']) {
        final chip = find.byKey(ValueKey('weekly-feeling-word-$word'));
        await tester.ensureVisible(chip);
        await tester.pumpAndSettle();
        await tester.tap(chip);
        await tester.pumpAndSettle();
      }
      final field = find.byKey(const ValueKey('weekly-feeling'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'A steady week');
      await tester.pumpAndSettle();
      final edit = find.byKey(const ValueKey('weekly-feeling-edit-presets'));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    }, reportKey: 'weekly_review_timeline');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      container.dispose();
      await database.close();
    });
  });
}
