import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/providers/database_provider.dart';
import 'features/recurring/providers/recurring_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();
  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
  );
  try {
    await container.read(categoryRepositoryProvider).seedDefaultsIfEmpty();
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  // Materialize recurring tasks for today + tomorrow on app start
  // (planner.md Chunk 4 #3).
  try {
    final recurrence = container.read(recurrenceServiceProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await recurrence.materializeForDate(today);
    await recurrence.materializeForDate(today.add(const Duration(days: 1)));
  } catch (err, stack) {
    FlutterError.reportError(FlutterErrorDetails(exception: err, stack: stack));
  }
  runApp(UncontrolledProviderScope(
    container: container,
    child: const PersonalPlannerApp(),
  ));
}
