import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/app.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/features/onboarding/providers/onboarding_provider.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';

import 'sqlite_setup.dart';

Future<ProviderContainer> buildTestContainer(
  WidgetTester tester, {
  AppDatabase? db,
  MinuteClockFactory? minuteClockFactory,
}) async {
  setupSqliteForTests();
  late ProviderContainer container;
  await tester.runAsync(() async {
    final database = db ?? AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        if (minuteClockFactory != null)
          minuteClockProvider.overrideWithValue(minuteClockFactory),
      ],
    );
    await container.read(categoryRepositoryProvider).seedDefaultsIfEmpty();
    await database.syncDao.setSetting(onboardingCompletedKey, 'true');
  });
  return container;
}

Future<void> pumpApp(
  WidgetTester tester,
  ProviderContainer container, {
  Size? surface,
}) async {
  if (surface != null) {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const PersonalPlannerApp(),
    ),
  );
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<T> runDb<T>(WidgetTester tester, Future<T> Function() action) async {
  final result = await tester.runAsync(action);
  return result as T;
}

Future<void> teardownApp(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final database = container.read(appDatabaseProvider);
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  // ProviderContainer.dispose() synchronously marks elements disposed, while
  // Drift stream subscriptions finish cancelling asynchronously. Run both
  // operations in the real async zone, outside Flutter's FakeAsync clock.
  await tester.runAsync(() async {
    container.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await database.close();
  });
}

/// Resets platform overrides, unmounts the widget tree and pumps several
/// frames so Riverpod's ProviderScheduler flushes pending autoDispose
/// disposals — cancelling periodic streams (e.g. timer tickers) before
/// Flutter's pending-timer invariant runs.
Future<void> finish(WidgetTester tester, ProviderContainer container) async {
  debugDefaultTargetPlatformOverride = null;
  await teardownApp(tester, container);
}

Future<void> doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
}
