import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/models/experiment_check_in.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/providers/analytics_providers.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/providers/experiment_providers.dart';

import '../helpers/sqlite_setup.dart';
import '../helpers/test_container.dart';

/// A repository that can be told to fail every write, to see the toasts.
class _SwitchableRepository extends ExperimentRepository {
  _SwitchableRepository(super.db);

  bool failing = false;

  @override
  Future<Experiment> extendExperiment(
    String experimentId, {
    required int days,
    required String reason,
    required String today,
    required int expectedRevision,
  }) {
    if (failing) return Future.error(StateError('write failed'));
    return super.extendExperiment(
      experimentId,
      days: days,
      reason: reason,
      today: today,
      expectedRevision: expectedRevision,
    );
  }

  @override
  Future<Experiment> concludeExperiment(
    String experimentId, {
    required ExperimentOutcome outcome,
    String? note,
    required String today,
    required int expectedRevision,
  }) {
    if (failing) return Future.error(StateError('write failed'));
    return super.concludeExperiment(
      experimentId,
      outcome: outcome,
      note: note,
      today: today,
      expectedRevision: expectedRevision,
    );
  }

  @override
  Future<ExperimentCheckIn> saveCheckIn({
    required String experimentId,
    required String slotDate,
    required String note,
    required String today,
  }) {
    if (failing) return Future.error(StateError('write failed'));
    return super.saveCheckIn(
      experimentId: experimentId,
      slotDate: slotDate,
      note: note,
      today: today,
    );
  }
}

void main() {
  const desktop = Size(1400, 1000);
  const phone = Size(360, 800);

  // Wednesday Oct 7 2026, midday planner time. Tests move it with `now = ...`
  // followed by an app resume, which re-reads the planner date.
  late DateTime now;
  setUp(() => now = PlannerTimeZone.calendarDate(2026, 10, 7, hour: 12));

  Future<ProviderContainer> open(
    WidgetTester tester, {
    Size surface = desktop,
  }) async {
    final container = await buildTestContainer(
      tester,
      insightsNowFactory: () => now,
    );
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: surface);
    return container;
  }

  AppDatabase dbOf(ProviderContainer c) => c.read(appDatabaseProvider);

  Future<Experiment> create(
    WidgetTester tester,
    ProviderContainer container, {
    String name = 'Learn C',
    String start = '2026-10-01',
    String end = '2026-10-07',
    int every = 7,
  }) => runDb(
    tester,
    () => ExperimentRepository(dbOf(container)).createExperiment(
      name: name,
      startDate: start,
      endDate: end,
      weekdayTargetMin: 60,
      weekendTargetMin: 90,
      checkInEveryDays: every,
    ),
  );

  Finder panel(Experiment e) => find.byKey(ValueKey('end-panel-${e.id}'));

  Future<void> show(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await show(tester, finder);
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> enter(WidgetTester tester, String key, String text) async {
    final finder = find.byKey(ValueKey(key));
    await show(tester, finder);
    await tester.enterText(finder, text);
    await tester.pump();
  }

  /// Moves the planner clock. The rollover timer fires at the next planner
  /// midnight (12 hours after the default start) and reads the new date.
  Future<void> moveClockTo(WidgetTester tester, DateTime to) async {
    now = to;
    await tester.pump(const Duration(hours: 13));
    await settle(tester);
  }

  FilledButton filled(WidgetTester tester, String key) =>
      tester.widget<FilledButton>(find.byKey(ValueKey(key)));

  testWidgets('the panel appears on the end date, not before', (tester) async {
    final container = await open(tester);
    final tomorrow = await create(
      tester,
      container,
      name: 'Tomorrow',
      end: '2026-10-08',
    );
    await settle(tester);
    expect(panel(tomorrow), findsNothing);
    expect(find.text('The end date has arrived'), findsNothing);

    final today = await create(tester, container);
    await settle(tester);
    expect(panel(today), findsOneWidget);
    expect(find.text('The end date has arrived'), findsOneWidget);
    expect(
      find.text(
        'You can extend the experiment, but you have to say why. '
        'Or conclude it and write what you learned.',
      ),
      findsOneWidget,
    );
    expect(find.text('7 more days'), findsOneWidget);
    expect(find.text('14 more days'), findsOneWidget);
    expect(find.text('30 more days'), findsOneWidget);
    expect(find.text('Continue as a habit'), findsOneWidget);
    expect(find.text('Drop it'), findsOneWidget);
    expect(find.text('Why are you extending? (required)'), findsOneWidget);
    expect(find.text('What did you learn?'), findsOneWidget);
    expect(
      find.text('For example: I missed a week while travelling.'),
      findsOneWidget,
    );
    expect(
      find.text('For example: I like how close to the machine it feels.'),
      findsOneWidget,
    );

    await teardownApp(tester, container);
  });

  testWidgets('Extend stays disabled until a reason is written', (
    tester,
  ) async {
    final container = await open(tester);
    final e = await create(tester, container);
    await settle(tester);

    final key = 'extend-submit-${e.id}';
    await show(tester, find.byKey(ValueKey(key)));
    expect(filled(tester, key).onPressed, isNull);
    await enter(tester, 'extend-reason-${e.id}', '   ');
    expect(filled(tester, key).onPressed, isNull);
    await enter(tester, 'extend-reason-${e.id}', 'Travelling');
    expect(filled(tester, key).onPressed, isNotNull);

    await teardownApp(tester, container);
  });

  testWidgets('extending by 14 moves the end date and makes new slots', (
    tester,
  ) async {
    final container = await open(tester);
    final e = await create(tester, container);
    await settle(tester);
    // The one weekly slot (Oct 7) is due today; write it so only the future
    // is left.
    await runDb(
      tester,
      () => ExperimentRepository(dbOf(container)).saveCheckIn(
        experimentId: e.id,
        slotDate: '2026-10-07',
        note: 'Done',
        today: '2026-10-07',
      ),
    );
    await settle(tester);
    expect(
      find.textContaining('Oct 1 – Oct 7 · 60 min weekdays'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('experiment-check-ins-${e.id}')),
        matching: find.text('1 written'),
      ),
      findsOneWidget,
    );

    // 14 more days is the default segment.
    await enter(tester, 'extend-reason-${e.id}', 'I missed a week');
    await tapKey(tester, 'extend-submit-${e.id}');

    expect(find.textContaining('Oct 1 – Oct 21 · 60 min weekdays'), findsOne);
    expect(
      find.text('Extended 1 time. Last reason: I missed a week'),
      findsOneWidget,
    );
    expect(panel(e), findsNothing);
    // New slots exist: Oct 14 and Oct 21 are in the future.
    expect(
      find.descendant(
        of: find.byKey(ValueKey('experiment-check-ins-${e.id}')),
        matching: find.text('1 written · next Oct 14'),
      ),
      findsOneWidget,
    );
    final row = await runDb(
      tester,
      () => dbOf(container).experimentDao.getExperimentById(e.id),
    );
    expect(row!.endDate, '2026-10-21');
    expect(row.revision, e.revision + 1);

    await teardownApp(tester, container);
  });

  testWidgets('extending by 7 or 30 days uses the chosen length', (
    tester,
  ) async {
    final container = await open(tester);
    final a = await create(tester, container, name: 'Seven');
    await settle(tester);
    await tapKey(tester, 'extend-days-7');
    await enter(tester, 'extend-reason-${a.id}', 'A bit more');
    await tapKey(tester, 'extend-submit-${a.id}');
    expect(find.textContaining('Oct 1 – Oct 14 · 60 min weekdays'), findsOne);

    final b = await create(tester, container, name: 'Thirty');
    await settle(tester);
    await tapKey(tester, 'extend-days-30');
    await enter(tester, 'extend-reason-${b.id}', 'Long haul');
    await tapKey(tester, 'extend-submit-${b.id}');
    expect(find.textContaining('Oct 1 – Nov 6 · 60 min weekdays'), findsOne);

    await teardownApp(tester, container);
  });

  testWidgets('extending twice shows "2 times"', (tester) async {
    final container = await open(tester);
    final e = await create(tester, container);
    await settle(tester);
    await enter(tester, 'extend-reason-${e.id}', 'First reason');
    await tapKey(tester, 'extend-submit-${e.id}');
    expect(panel(e), findsNothing);
    expect(
      find.text('Extended 1 time. Last reason: First reason'),
      findsOneWidget,
    );

    // The new end date (Oct 21) arrives.
    await moveClockTo(
      tester,
      PlannerTimeZone.calendarDate(2026, 10, 21, hour: 9),
    );
    expect(panel(e), findsOneWidget);
    await enter(tester, 'extend-reason-${e.id}', 'Second reason');
    await tapKey(tester, 'extend-submit-${e.id}');

    expect(
      find.text('Extended 2 times. Last reason: Second reason'),
      findsOneWidget,
    );
    expect(find.textContaining('Oct 1 – Nov 4 · 60 min weekdays'), findsOne);
    expect(panel(e), findsNothing);

    await teardownApp(tester, container);
  });

  testWidgets('concluding shows the summary and keeps the experiment', (
    tester,
  ) async {
    final container = await open(tester);
    final e = await create(tester, container);
    await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Tagged block',
              startTime: PlannerTimeZone.calendarDate(2026, 10, 3, hour: 9),
              endTime: PlannerTimeZone.calendarDate(2026, 10, 3, hour: 10),
              status: TaskStatus.completed,
              tagId: e.tagId,
              createdAt: now,
              updatedAt: now,
            ),
          ),
    );
    await settle(tester);
    expect(find.text('Running (1)'), findsOneWidget);
    expect(find.text('Concluded (0)'), findsOneWidget);

    await tapKey(tester, 'conclude-outcome-drop');
    await tapKey(tester, 'conclude-submit-${e.id}');

    // The card moved to the Concluded filter.
    expect(find.byKey(ValueKey('experiment-${e.id}')), findsNothing);
    expect(find.text('Running (0)'), findsOneWidget);
    expect(find.text('Concluded (1)'), findsOneWidget);
    await tester.tap(find.text('Concluded (1)'));
    await tester.pump();

    expect(find.byKey(ValueKey('experiment-${e.id}')), findsOneWidget);
    expect(find.text('Concluded Oct 7'), findsOneWidget);
    expect(find.text('Drop it'), findsOneWidget);
    expect(find.text('No note added.'), findsOneWidget);
    expect(panel(e), findsNothing);
    expect(find.byKey(ValueKey('experiment-today-${e.id}')), findsNothing);
    expect(
      find.text("Today's target only counts against you once the day is over."),
      findsNothing,
    );
    // The blocks keep their tag.
    final tasks = await runDb(
      tester,
      () => dbOf(container).select(dbOf(container).tasks).get(),
    );
    expect(tasks.single.tagId, e.tagId);

    await teardownApp(tester, container);
  });

  testWidgets('concluding with a note shows the note', (tester) async {
    final container = await open(tester);
    final e = await create(tester, container);
    await settle(tester);

    await enter(tester, 'conclude-note-${e.id}', '  It stuck.  ');
    await tapKey(tester, 'conclude-submit-${e.id}');

    await tester.tap(find.text('Concluded (1)'));
    await tester.pump();

    expect(find.text('Continue as a habit'), findsOneWidget);
    expect(find.text('It stuck.'), findsOneWidget);
    expect(find.text('No note added.'), findsNothing);

    await teardownApp(tester, container);
  });

  testWidgets('failed writes show the toasts and keep the forms', (
    tester,
  ) async {
    setupSqliteForTests();
    late ProviderContainer container;
    late _SwitchableRepository repository;
    await tester.runAsync(() async {
      final db = AppDatabase(NativeDatabase.memory());
      repository = _SwitchableRepository(db);
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          insightsNowFactoryProvider.overrideWithValue(() => now),
          experimentRepositoryProvider.overrideWithValue(repository),
        ],
      );
    });
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: desktop);
    final e = await create(tester, container, every: 1, start: '2026-10-06');
    await settle(tester);
    repository.failing = true;

    await enter(tester, 'extend-reason-${e.id}', 'Travelling');
    await tapKey(tester, 'extend-submit-${e.id}');
    expect(find.text('That change was not saved. Try again.'), findsOneWidget);
    expect(panel(e), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(ValueKey('extend-reason-${e.id}')))
          .controller!
          .text,
      'Travelling',
      reason: 'the reason is kept so it can be tried again',
    );

    await tapKey(tester, 'conclude-submit-${e.id}');
    expect(find.text('That change was not saved. Try again.'), findsOneWidget);
    expect(find.text('Concluded Oct 7'), findsNothing);

    await enter(tester, 'checkin-note-${e.id}', 'A note');
    await tapKey(tester, 'checkin-save-${e.id}');
    expect(find.text('The check-in was not saved. Try again.'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(ValueKey('checkin-note-${e.id}')))
          .controller!
          .text,
      'A note',
    );

    // The same forms work again once writes succeed.
    repository.failing = false;
    await tapKey(tester, 'checkin-save-${e.id}');
    expect(
      tester
          .widget<TextField>(find.byKey(ValueKey('checkin-note-${e.id}')))
          .controller!
          .text,
      isEmpty,
      reason: 'the note is cleared once the check-in is saved',
    );

    await teardownApp(tester, container);
  });

  testWidgets('large text on a phone does not overflow, panel and box', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = await open(tester, surface: phone);
    // Every day, so the box has several dates, and the end date is today.
    final e = await create(
      tester,
      container,
      start: '2026-10-03',
      end: '2026-10-07',
      every: 1,
    );
    await settle(tester);
    expect(panel(e), findsOneWidget);
    expect(find.byKey(ValueKey('checkin-box-${e.id}')), findsOneWidget);

    for (final key in [
      'checkin-box-${e.id}',
      'checkin-note-${e.id}',
      'checkin-save-${e.id}',
      'end-panel-${e.id}',
      'extend-days-30',
      'extend-reason-${e.id}',
      'extend-submit-${e.id}',
      'conclude-outcome-drop',
      'conclude-note-${e.id}',
      'conclude-submit-${e.id}',
    ]) {
      await show(tester, find.byKey(ValueKey(key)));
      expect(tester.takeException(), isNull, reason: 'overflow near $key');
    }

    // Open the date list: long item text must not overflow either.
    final dropdown = find.byKey(ValueKey('checkin-date-${e.id}'));
    await show(tester, dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sat Oct 3').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await teardownApp(tester, container);
  });
}
