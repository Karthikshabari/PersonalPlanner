import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/widgets/app_surface.dart';
import 'package:personal_planner/features/review/domain/review_reason_presets.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';
import 'package:personal_planner/features/timeline/data/task_repository.dart';

import 'test_container.dart';

/// One task to seed on a Daily review day.
class DailySeed {
  const DailySeed(this.title, {this.status = TaskStatus.planned});

  final String title;
  final TaskStatus status;
}

DateTime dailyToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

/// `n` characters of readable text, no spaces at the cut so it is one long
/// word-ish title (80 characters is a worst case for the row).
String longTitle(int n) =>
    ('Quarterly planning workshop preparation and follow-up notes ' * 4)
        .substring(0, n);

/// Inserts [seeds] on [date], one every 40 minutes from 05:00, and returns the
/// stored ids in the same order.
Future<List<String>> seedDailyTasks(
  WidgetTester tester,
  ProviderContainer container,
  List<DailySeed> seeds, {
  DateTime? date,
}) async {
  final day = date ?? dailyToday();
  final repo = container.read(taskRepositoryProvider);
  for (var i = 0; i < seeds.length; i++) {
    final start = DateTime(
      day.year,
      day.month,
      day.day,
      5,
    ).add(Duration(minutes: 40 * i));
    await runDb(
      tester,
      () => repo.insertTask(
        Task(
          id: '',
          title: seeds[i].title,
          startTime: start,
          endTime: start.add(const Duration(minutes: 30)),
          status: seeds[i].status,
          createdAt: start,
          updatedAt: start,
        ),
      ),
    );
  }
  final rows = await runDb(
    tester,
    () => container
        .read(appDatabaseProvider)
        .taskDao
        .getTasksBetween(day, addDays(day, 1)),
  );
  final byTitle = {
    for (final row in rows) row.title: TaskRepository.fromRow(row).id,
  };
  return [for (final seed in seeds) byTitle[seed.title]!];
}

/// Stores [presets] as the quick reasons (before the app is pumped).
Future<void> seedPresets(
  WidgetTester tester,
  ProviderContainer container,
  List<String> presets,
) => runDb(
  tester,
  () => container
      .read(appDatabaseProvider)
      .syncDao
      .setSetting(
        reviewReasonPresetsSettingKey,
        ReviewReasonPresets.encode(presets),
      ),
);

/// Opens the Daily review in a [surface] at [textScale].
Future<ProviderContainer> pumpDaily(
  WidgetTester tester, {
  required Size surface,
  double textScale = 1.0,
  List<DailySeed> seeds = const [],
  List<String>? presets,
  DateTime? date,
  void Function(List<String> ids)? onSeeded,
}) async {
  if (textScale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final container = await buildTestContainer(tester);
  final ids = await seedDailyTasks(tester, container, seeds, date: date);
  onSeeded?.call(ids);
  if (presets != null) await seedPresets(tester, container, presets);
  if (date != null) {
    container.read(selectedReviewDateProvider.notifier).state = date;
  }
  appRouter.go('/review');
  await pumpApp(tester, container, surface: surface);
  return container;
}

/// The card (an `AppSurface`) that holds [title].
Finder cardOf(String title) => find
    .ancestor(of: find.text(title), matching: find.byType(AppSurface))
    .first;

/// Leaves the Daily tab and gives the disposed streams real time, so closing
/// the database does not hang (as the other Daily tests do).
Future<void> drainStreams(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await settle(tester);
}
