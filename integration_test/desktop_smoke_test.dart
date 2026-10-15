import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:personal_planner/app.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/analytics/presentation/screens/analytics_screen.dart';
import 'package:personal_planner/features/categories/data/category_repository.dart';
import 'package:personal_planner/features/inbox/presentation/screens/inbox_screen.dart';
import 'package:personal_planner/features/review/presentation/screens/daily_review_screen.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';
import 'package:personal_planner/features/timeline/presentation/screens/day_view_screen.dart';
import 'package:personal_planner/features/timer/domain/notification_service.dart'
    show initializeTimezone;
import 'package:sqlite3/sqlite3.dart' show sqlite3;

/// Desktop release-readiness smoke test (Linux, Windows, macOS).
///
/// Runs the real widget tree on the real OS with an in-memory database and no
/// network or sign-in: native SQLite and plugin loading, a database round
/// trip, and every main tab rendering without a framework error.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app starts, persists a row and renders every main tab', (
    tester,
  ) async {
    final errors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    try {
      // Native plugins used before the first frame in production.
      await initializeTimezone();
      expect((await getApplicationSupportDirectory()).path, isNotEmpty);
      debugPrint('SQLite ${sqlite3.version.libVersion}');

      final database = AppDatabase(NativeDatabase.memory());
      await CategoryRepository(database).seedDefaultsIfEmpty();
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          container.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await database.close();
        });
      });

      final now = DateTime.now();
      final written = await TaskRepository(database).insertTask(
        Task(
          id: '00000000-0000-7000-8000-00000000d001',
          title: 'Desktop smoke task',
          startTime: startOfDay(now).add(const Duration(hours: 9)),
          endTime: startOfDay(now).add(const Duration(hours: 10)),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final read = await TaskRepository(database).getTaskById(written.id);
      expect(read?.title, 'Desktop smoke task');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PersonalPlannerApp(),
        ),
      );

      const tabs = <(String, Type)>[
        ('/day', DayViewScreen),
        ('/review', DailyReviewScreen),
        ('/analytics', AnalyticsScreen),
        ('/inbox', InboxScreen),
      ];
      for (final (path, screen) in tabs) {
        appRouter.go(path);
        await _pumpUntilFound(tester, find.byType(screen), path);
        // Let streams deliver and the screen lay out its loaded content.
        await _pumpFor(tester, const Duration(seconds: 1));
        expect(find.byType(screen), findsOneWidget, reason: path);
      }
      appRouter.go('/day');
      await _pumpFor(tester, const Duration(milliseconds: 500));
    } finally {
      FlutterError.onError = originalOnError;
    }
    expect(
      errors.map((details) => details.toString()).toList(),
      isEmpty,
      reason: 'Flutter reported errors while rendering',
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder,
  String path,
) async {
  final end = DateTime.now().add(const Duration(seconds: 20));
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) fail('$path did not open');
    await tester.pump(const Duration(milliseconds: 50));
  }
}
