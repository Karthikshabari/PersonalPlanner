import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/providers/database_provider.dart';

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
  runApp(UncontrolledProviderScope(
    container: container,
    child: const PersonalPlannerApp(),
  ));
}
