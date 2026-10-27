import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/analytics/providers/analytics_providers.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/presentation/widgets/experiment_row.dart';
import 'package:personal_planner/features/experiments/presentation/widgets/experiment_theme.dart';
import 'package:personal_planner/features/experiments/presentation/widgets/kept_experiment_row.dart';
import 'package:personal_planner/features/experiments/providers/experiment_providers.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';

import '../helpers/sqlite_setup.dart';
import '../helpers/test_container.dart';

/// Counts the SELECT statements that reach the database.
class _SelectCounter extends QueryInterceptor {
  int selects = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    selects++;
    return super.runSelect(executor, statement, args);
  }
}

void main() {
  const desktop = Size(1400, 1000);
  const phone = Size(360, 800);

  // Saturday Oct 10 2026, midday planner time. `now` moves in the rollover
  // case; every other case starts from this value.
  final saturday = PlannerTimeZone.calendarDate(2026, 10, 10, hour: 12);
  var now = saturday;
  setUp(() => now = saturday);

  DateTime at(int month, int day, int hour, [int minute = 0]) =>
      PlannerTimeZone.calendarDate(
        2026,
        month,
        day,
        hour: hour,
        minute: minute,
      );

  /// Like `buildTestContainer`, plus a repository clock that follows `now`
  /// (a retire stamps "Retired Oct 10" whatever the real date is).
  Future<ProviderContainer> build(
    WidgetTester tester, {
    AppDatabase? db,
  }) async {
    setupSqliteForTests();
    late ProviderContainer container;
    await tester.runAsync(() async {
      final database = db ?? AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          insightsNowFactoryProvider.overrideWithValue(() => now),
          experimentRepositoryProvider.overrideWith(
            (ref) => ExperimentRepository(
              ref.watch(appDatabaseProvider),
              clock: () => now,
            ),
          ),
        ],
      );
      await container.read(categoryRepositoryProvider).seedDefaultsIfEmpty();
    });
    return container;
  }

  Future<void> open(
    WidgetTester tester,
    ProviderContainer container, {
    Size surface = desktop,
  }) async {
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: surface);
  }

  AppDatabase dbOf(ProviderContainer c) => c.read(appDatabaseProvider);

  ExperimentRepository repoOf(ProviderContainer c) =>
      c.read(experimentRepositoryProvider);

  Future<Task> addBlock(
    WidgetTester tester,
    ProviderContainer container, {
    required String tagId,
    required DateTime start,
    required DateTime end,
    TaskStatus status = TaskStatus.completed,
    int? actual,
  }) => runDb(
    tester,
    () => container
        .read(taskRepositoryProvider)
        .insertTask(
          Task(
            id: '',
            title: 'Tagged block',
            startTime: start,
            endTime: end,
            status: status,
            actualDurationMin: actual,
            tagId: tagId.isEmpty ? null : tagId,
            createdAt: start,
            updatedAt: start,
          ),
        ),
  );

  /// A concluded Keep it experiment (start 09-04, end 10-03, concluded 10-09).
  Future<Experiment> keepExperiment(
    WidgetTester tester,
    ProviderContainer container,
    String name, {
    int weekday = 60,
    int weekend = 90,
    String? note,
  }) => runDb(tester, () async {
    final repo = repoOf(container);
    final created = await repo.createExperiment(
      name: name,
      startDate: '2026-09-04',
      endDate: '2026-10-03',
      weekdayTargetMin: weekday,
      weekendTargetMin: weekend,
      checkInEveryDays: 7,
    );
    return repo.concludeExperiment(
      created.id,
      outcome: ExperimentOutcome.keep,
      note: note,
      today: '2026-10-09',
      expectedRevision: created.revision,
    );
  });

  Future<Experiment> runningExperiment(
    WidgetTester tester,
    ProviderContainer container,
  ) => runDb(
    tester,
    () => repoOf(container).createExperiment(
      name: 'Sketching',
      startDate: '2026-10-05',
      endDate: '2026-10-11',
      weekdayTargetMin: 60,
      weekendTargetMin: 90,
      checkInEveryDays: 1,
    ),
  );

  /// V1: Morning pages, 60/90. Done 330 (Mon 60, Wed-Fri 90), planned 150
  /// (Sat 60, Sun 90), and 360 in the week of Sep 7.
  Future<Experiment> seedV1(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final e = await keepExperiment(
      tester,
      container,
      'Morning pages',
      note: 'Mornings beat evenings.',
    );
    Future<void> done(DateTime start, DateTime end, int actual) => addBlock(
      tester,
      container,
      tagId: e.tagId,
      start: start,
      end: end,
      actual: actual,
    );
    await done(at(10, 5, 9), at(10, 5, 10), 60);
    await done(at(10, 7, 9), at(10, 7, 10, 30), 90);
    await done(at(10, 8, 9), at(10, 8, 10, 30), 90);
    await done(at(10, 9, 9), at(10, 9, 10, 30), 90);
    await done(at(9, 7, 6), at(9, 7, 12), 360);
    await addBlock(
      tester,
      container,
      tagId: e.tagId,
      start: at(10, 10, 14),
      end: at(10, 10, 15),
      status: TaskStatus.planned,
    );
    await addBlock(
      tester,
      container,
      tagId: e.tagId,
      start: at(10, 11, 10),
      end: at(10, 11, 11, 30),
      status: TaskStatus.planned,
    );
    return e;
  }

  /// V2: Evening walk, 30/30. Done 100 (30, 30, 0, 30, 10), planned 60.
  Future<Experiment> seedV2(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final e = await keepExperiment(
      tester,
      container,
      'Evening walk',
      weekday: 30,
      weekend: 30,
    );
    for (final (day, minutes) in [(5, 30), (6, 30), (8, 30), (9, 10)]) {
      await addBlock(
        tester,
        container,
        tagId: e.tagId,
        start: at(10, day, 19),
        end: at(10, day, 19, minutes),
        actual: minutes,
      );
    }
    await addBlock(
      tester,
      container,
      tagId: e.tagId,
      start: at(10, 11, 19),
      end: at(10, 11, 20),
      status: TaskStatus.planned,
    );
    return e;
  }

  /// V3: Reading, 30/30. Done 250 (50, 40, 45, 60, 55), nothing planned.
  Future<Experiment> seedV3(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final e = await keepExperiment(
      tester,
      container,
      'Reading',
      weekday: 30,
      weekend: 30,
    );
    for (final (day, minutes) in [
      (5, 50),
      (6, 40),
      (7, 45),
      (8, 60),
      (9, 55),
    ]) {
      await addBlock(
        tester,
        container,
        tagId: e.tagId,
        start: at(10, day, 21),
        end: at(10, day, 22),
        actual: minutes,
      );
    }
    return e;
  }

  Future<void> seedAll(WidgetTester tester, ProviderContainer container) async {
    await seedV1(tester, container);
    await seedV2(tester, container);
    await seedV3(tester, container);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    expect(finder, findsOneWidget, reason: key);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final finder = find.text(text);
    expect(finder, findsOneWidget, reason: text);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> showKept(WidgetTester tester, int count) =>
      tapText(tester, 'Kept ($count)');

  String plain(WidgetTester tester, String key) {
    final text = tester.widget<Text>(find.byKey(ValueKey(key)));
    return (text.textSpan ?? TextSpan(text: text.data)).toPlainText(
      includePlaceholders: false,
    );
  }

  Finder within(String key, Finder matching) =>
      find.descendant(of: find.byKey(ValueKey(key)), matching: matching);

  Finder habit() => find.textContaining(
    RegExp('habit', caseSensitive: false),
    findRichText: true,
  );

  Future<List<String>> experimentLog(
    WidgetTester tester,
    ProviderContainer container,
  ) => runDb(tester, () async {
    final db = dbOf(container);
    return [
      for (final r in await db.select(db.syncLog).get())
        if (r.entityTableName == 'experiments') r.operation,
    ];
  });

  testWidgets('shows the three segments with their counts', (tester) async {
    final container = await build(tester);
    await seedAll(tester, container);
    await open(tester, container);

    expect(find.byKey(const ValueKey('experiments-filter')), findsOneWidget);
    expect(find.text('Running (0)'), findsOneWidget);
    expect(find.text('Kept (3)'), findsOneWidget);
    expect(find.text('Concluded (3, 3 also kept)'), findsOneWidget);

    await teardownApp(tester, container);
  });

  testWidgets('shows the empty text when nothing is kept', (tester) async {
    final container = await build(tester);
    await runningExperiment(tester, container);
    await open(tester, container);

    await showKept(tester, 0);
    expect(find.byKey(const ValueKey('kept-empty')), findsOneWidget);
    expect(
      find.text(
        'Nothing kept yet. Conclude an experiment with Keep it and it shows '
        'up here.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('kept-list')), findsNothing);

    await teardownApp(tester, container);
  });

  testWidgets('V1 shows the hand-calculated numbers', (tester) async {
    final container = await build(tester);
    final e = await seedV1(tester, container);
    await open(tester, container);
    await showKept(tester, 1);

    final id = e.id;
    expect(find.byKey(ValueKey('kept-row-$id')), findsOneWidget);
    expect(
      within('kept-title-$id', find.text('Morning pages')),
      findsOneWidget,
    );
    expect(
      within('kept-title-$id', find.text('Kept since Oct 9 · #Morning pages')),
      findsOneWidget,
    );
    expect(within('kept-chip-$id', find.text('30m ahead')), findsOneWidget);
    expect(plain(tester, 'kept-done-$id'), '5h 30mof 8h this week');
    expect(
      plain(tester, 'kept-plan-$id'),
      'Planned: 2h 30m more this week. That reaches the minimum.',
    );
    expect(find.byKey(ValueKey('kept-plan-link-$id')), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('kept-bar-$id-'),
      ),
      findsNWidgets(6),
    );
    expect(
      within('kept-detail-$id', find.text('This week · Oct 5 – 11')),
      findsOneWidget,
    );
    expect(
      within('kept-detail-$id', find.text('5h 30m of 8h · 69% so far')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('kept-planned-segment-$id')), findsOneWidget);
    expect(find.byKey(ValueKey('kept-tick-$id')), findsOneWidget);

    final fill = find.byKey(ValueKey('kept-done-fill-$id'));
    final track = find.ancestor(of: fill, matching: find.byType(ClipRRect));
    final trackWidth = tester.getSize(track.first).width;
    expect(
      tester.getSize(fill).width,
      closeTo(0.6875 * trackWidth, 1),
      reason: 'done fraction 0.6875 of the track',
    );

    await teardownApp(tester, container);
  });

  testWidgets('V2 is behind in caution amber and Plan it in Day opens Day on '
      'today', (tester) async {
    final container = await build(tester);
    final e = await seedV2(tester, container);
    await open(tester, container);
    await showKept(tester, 1);

    final id = e.id;
    final chipText = tester.widget<Text>(
      within('kept-chip-$id', find.text('50m behind')),
    );
    expect(chipText.style!.color, ExperimentColors.dark.caution);
    expect(
      plain(tester, 'kept-plan-$id'),
      'Planned: 1h more this week. 50m short of the minimum.',
    );
    expect(find.byKey(ValueKey('kept-plan-link-$id')), findsOneWidget);
    expect(
      within('kept-plan-link-$id', find.text('Plan it in Day')),
      findsOneWidget,
    );

    await tapKey(tester, 'kept-plan-link-$id');
    await settle(tester);
    expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/day');
    expect(isoDateString(container.read(selectedDateProvider)), '2026-10-10');

    await teardownApp(tester, container);
  });

  testWidgets('V3 is over target with the extra-is-fine strip', (tester) async {
    final container = await build(tester);
    final e = await seedV3(tester, container);
    await open(tester, container);
    await showKept(tester, 1);

    final id = e.id;
    expect(
      within('kept-chip-$id', find.text('40m over target')),
      findsOneWidget,
    );
    expect(
      plain(tester, 'kept-plan-$id'),
      'Target reached for this week. Anything more is extra.',
    );
    expect(find.byKey(ValueKey('kept-plan-link-$id')), findsNothing);
    expect(
      within('kept-detail-$id', find.text('4h 10m of 3h 30m · 119% so far')),
      findsOneWidget,
    );

    await teardownApp(tester, container);
  });

  testWidgets('tapping a bar selects it and runs no query; neither do the '
      'panel, the sheet or the steppers', (tester) async {
    final counter = _SelectCounter();
    final container = await build(
      tester,
      db: AppDatabase(NativeDatabase.memory().interceptWith(counter)),
    );
    final handle = tester.ensureSemantics();
    final e = await seedV1(tester, container);
    await open(tester, container);
    await showKept(tester, 1);
    await settle(tester);

    final id = e.id;
    final current = find.byKey(ValueKey('kept-bar-$id-2026-10-05'));
    final september = find.byKey(ValueKey('kept-bar-$id-2026-09-07'));
    expect(tester.getSemantics(current), isSemantics(isSelected: true));
    expect(tester.getSemantics(september), isSemantics(isSelected: false));

    final before = counter.selects;
    await tapKey(tester, 'kept-bar-$id-2026-09-07');
    await settle(tester);
    expect(tester.getSemantics(september), isSemantics(isSelected: true));
    expect(tester.getSemantics(current), isSemantics(isSelected: false));
    expect(within('kept-detail-$id', find.text('Sep 7 – 13')), findsOneWidget);
    expect(
      within('kept-detail-$id', find.text('6h of 8h · 75%')),
      findsOneWidget,
    );

    await tapKey(tester, 'kept-explain-toggle-$id');
    await settle(tester);
    await tapKey(tester, 'kept-adjust-$id');
    await settle(tester);
    expect(find.byKey(ValueKey('kept-adjust-sheet-$id')), findsOneWidget);
    await tapKey(tester, 'kept-stepper-weekday-$id-plus');
    await tapKey(tester, 'kept-stepper-weekend-$id-minus');
    await tapKey(tester, 'kept-from-this-$id');
    await settle(tester);
    expect(counter.selects, before, reason: 'no query for UI-only state');

    handle.dispose();
    await teardownApp(tester, container);
  });

  testWidgets('How this is counted shows the seven days', (tester) async {
    final container = await build(tester);
    final e = await seedV1(tester, container);
    await open(tester, container);
    await showKept(tester, 1);

    final id = e.id;
    expect(find.byKey(ValueKey('kept-explain-$id')), findsNothing);
    await tapKey(tester, 'kept-explain-toggle-$id');
    await settle(tester);
    expect(find.byKey(ValueKey('kept-explain-$id')), findsOneWidget);
    expect(find.text('Hide how this is counted'), findsOneWidget);

    const labels = {
      '2026-10-05': '60m',
      '2026-10-06': '0m',
      '2026-10-07': '90m',
      '2026-10-08': '90m',
      '2026-10-09': '90m',
      '2026-10-10': 'today',
      '2026-10-11': '–',
    };
    for (final entry in labels.entries) {
      expect(
        within('kept-day-$id-${entry.key}', find.text(entry.value)),
        findsOneWidget,
        reason: entry.key,
      );
    }
    expect(find.text('Weekly minimum · 5 × 60m + 2 × 90m'), findsOneWidget);
    expect(
      find.text('Done · completed blocks tagged #Morning pages'),
      findsOneWidget,
    );
    expect(
      find.text('Planned · scheduled blocks, today onward'),
      findsOneWidget,
    );
    expect(
      find.text('Expected by today · days already finished'),
      findsOneWidget,
    );
    expect(find.text('30m ahead'), findsNWidgets(2), reason: 'chip and pace');

    await tapKey(tester, 'kept-explain-toggle-$id');
    await settle(tester);
    expect(find.byKey(ValueKey('kept-explain-$id')), findsNothing);
    expect(find.text('How this is counted'), findsOneWidget);

    await teardownApp(tester, container);
  });

  group('Adjust target', () {
    Finder stepButton(String id, String part, String side) => find.descendant(
      of: find.byKey(ValueKey('kept-stepper-$part-$id-$side')),
      matching: find.byType(InkWell),
    );

    bool enabled(WidgetTester tester, String id, String part, String side) =>
        tester.widget<InkWell>(stepButton(id, part, side)).onTap != null;

    testWidgets('steppers stop at 15 and 240 and move in steps of 15', (
      tester,
    ) async {
      final container = await build(tester);
      final e = await seedV1(tester, container);
      await open(tester, container);
      await showKept(tester, 1);
      final id = e.id;
      final sheet = find.byKey(ValueKey('kept-adjust-sheet-$id'));

      await tapKey(tester, 'kept-adjust-$id');
      await settle(tester);
      expect(
        find.descendant(of: sheet, matching: find.text('60m')),
        findsOneWidget,
      );
      await tapKey(tester, 'kept-stepper-weekday-$id-plus');
      expect(
        find.descendant(of: sheet, matching: find.text('75m')),
        findsOneWidget,
      );
      expect(
        find.textContaining('5 × 75m + 2 × 90m = 9h 15m', findRichText: true),
        findsOneWidget,
      );
      await tapKey(tester, 'kept-stepper-weekday-$id-plus');
      expect(
        find.descendant(of: sheet, matching: find.text('90m')),
        findsNWidgets(2),
      );

      for (var i = 0; i < 5; i++) {
        await tapKey(tester, 'kept-stepper-weekday-$id-minus');
      }
      expect(enabled(tester, id, 'weekday', 'minus'), isFalse);
      expect(
        find.descendant(of: sheet, matching: find.text('15m')),
        findsOneWidget,
      );
      await tester.tap(stepButton(id, 'weekday', 'minus'));
      await tester.pump();
      expect(
        find.descendant(of: sheet, matching: find.text('15m')),
        findsOneWidget,
        reason: 'minus does nothing at 15',
      );

      for (var i = 0; i < 15; i++) {
        await tapKey(tester, 'kept-stepper-weekday-$id-plus');
      }
      expect(enabled(tester, id, 'weekday', 'plus'), isFalse);
      expect(
        find.descendant(of: sheet, matching: find.text('240m')),
        findsOneWidget,
      );

      await tapKey(tester, 'kept-adjust-cancel-$id');
      await settle(tester);
      expect(sheet, findsNothing);

      await teardownApp(tester, container);
    });

    testWidgets('saving writes one row per change and none when unchanged', (
      tester,
    ) async {
      final container = await build(tester);
      final e = await seedV1(tester, container);
      await open(tester, container);
      await showKept(tester, 1);
      final id = e.id;
      final sheet = find.byKey(ValueKey('kept-adjust-sheet-$id'));
      var rows = (await experimentLog(tester, container)).length;
      Future<int> added() async {
        final now = (await experimentLog(tester, container)).length;
        final delta = now - rows;
        rows = now;
        return delta;
      }

      // 75/90 from next Monday: a pending note, one new row.
      await tapKey(tester, 'kept-adjust-$id');
      await settle(tester);
      expect(find.text('From next Monday, Oct 12'), findsOneWidget);
      await tapKey(tester, 'kept-stepper-weekday-$id-plus');
      await tapKey(tester, 'kept-adjust-save-$id');
      await settle(tester);
      await settle(tester);
      expect(sheet, findsNothing);
      expect(
        plain(tester, 'kept-pending-$id'),
        'From Mon Oct 12 the minimum becomes 9h 15m a week '
        '(5 × 75m + 2 × 90m).',
      );
      expect(plain(tester, 'kept-done-$id'), '5h 30mof 8h this week');
      expect(await added(), 1);

      // Back to 60/90 from next Monday: the pending entry goes, one new row.
      await tapKey(tester, 'kept-adjust-$id');
      await settle(tester);
      await tapKey(tester, 'kept-adjust-save-$id');
      await settle(tester);
      await settle(tester);
      expect(find.byKey(ValueKey('kept-pending-$id')), findsNothing);
      expect(await added(), 1);

      // Same values again: nothing to write.
      await tapKey(tester, 'kept-adjust-$id');
      await settle(tester);
      await tapKey(tester, 'kept-adjust-save-$id');
      await settle(tester);
      await settle(tester);
      expect(sheet, findsNothing);
      expect(await added(), 0);

      // 75/90 from this week: the target changes at once, one new row.
      await tapKey(tester, 'kept-adjust-$id');
      await settle(tester);
      await tapKey(tester, 'kept-stepper-weekday-$id-plus');
      await tapKey(tester, 'kept-from-this-$id');
      await tapKey(tester, 'kept-adjust-save-$id');
      await settle(tester);
      await settle(tester);
      expect(plain(tester, 'kept-done-$id'), '5h 30mof 9h 15m this week');
      expect(find.byKey(ValueKey('kept-pending-$id')), findsNothing);
      expect(await added(), 1);

      await teardownApp(tester, container);
    });

    testWidgets('an untouched target is never rewritten to fit 15 to 240', (
      tester,
    ) async {
      final container = await build(tester);
      final e = await keepExperiment(
        tester,
        container,
        'Long sessions',
        weekday: 600,
      );
      await open(tester, container);
      await showKept(tester, 1);
      final id = e.id;
      final sheet = find.byKey(ValueKey('kept-adjust-sheet-$id'));

      await tapKey(tester, 'kept-adjust-$id');
      await settle(tester);
      expect(
        find.descendant(of: sheet, matching: find.text('600m')),
        findsOneWidget,
      );
      await tapKey(tester, 'kept-stepper-weekend-$id-plus');
      expect(
        tester
            .widget<FilledButton>(find.byKey(ValueKey('kept-adjust-save-$id')))
            .onPressed,
        isNull,
        reason: '600 cannot be stored, so Save waits',
      );
      expect(find.byKey(ValueKey('kept-out-of-range-$id')), findsOneWidget);

      final stored = await runDb(
        tester,
        () => dbOf(container).experimentDao.getExperimentById(id),
      );
      expect(stored!.weekdayTargetMin, 600);
      expect(stored.targetChangesJson, '[]');

      await teardownApp(tester, container);
    });
  });

  testWidgets('Retire shows the one-line message, Undo brings the row back '
      'and Concluded carries the retirement', (tester) async {
    final container = await build(tester);
    final v1 = await seedV1(tester, container);
    await seedV2(tester, container);
    await seedV3(tester, container);
    await open(tester, container);
    await showKept(tester, 3);
    final id = v1.id;
    const retiredLine =
        'Morning pages retired. Note saved. Its record is under Concluded.';

    Future<void> retire() async {
      await tapKey(tester, 'kept-retire-$id');
      await settle(tester);
      expect(find.byKey(ValueKey('kept-retire-sheet-$id')), findsOneWidget);
      expect(find.text('Retire Morning pages?'), findsOneWidget);
      await tester.enterText(
        find.byKey(ValueKey('kept-retire-note-$id')),
        'Learned enough',
      );
      await tester.pump();
      await tapKey(tester, 'kept-retire-submit-$id');
      await settle(tester);
      await settle(tester);
    }

    await retire();
    expect(find.text(retiredLine), findsOneWidget);
    expect(find.byKey(ValueKey('kept-row-$id')), findsNothing);
    expect(find.text('Kept (2)'), findsOneWidget);

    await tapKey(tester, 'kept-undo-$id');
    await settle(tester);
    await settle(tester);
    expect(find.text(retiredLine), findsNothing);
    expect(find.byKey(ValueKey('kept-row-$id')), findsOneWidget);
    expect(find.text('Kept (3)'), findsOneWidget);

    await retire();
    expect(find.text('Kept (2)'), findsOneWidget);
    await tapText(tester, 'Concluded (3, 2 also kept)');
    expect(
      within('experiment-retired-chip-$id', find.text('Retired Oct 10')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('experiment-retire-note-$id')))
          .data,
      'Learned enough',
    );
    expect(find.text('WHEN RETIRED'), findsOneWidget);
    expect(find.byKey(ValueKey('experiment-now-kept-$id')), findsNothing);

    await teardownApp(tester, container);
  });

  testWidgets('a concluded kept row says Now under Kept and See it opens '
      'Kept', (tester) async {
    final container = await build(tester);
    final e = await seedV1(tester, container);
    await open(tester, container);
    await tapText(tester, 'Concluded (1, 1 also kept)');

    final id = e.id;
    expect(
      within('experiment-outcome-$id', find.text('Keep it')),
      findsOneWidget,
    );
    expect(find.text('Now under Kept'), findsOneWidget);
    expect(find.byKey(ValueKey('experiment-now-kept-$id')), findsOneWidget);
    expect(
      within('experiment-see-kept-$id', find.text('See it')),
      findsOneWidget,
    );
    expect(find.byKey(ValueKey('kept-row-$id')), findsNothing);

    await tapKey(tester, 'experiment-see-kept-$id');
    await settle(tester);
    expect(find.byKey(ValueKey('kept-row-$id')), findsOneWidget);
    expect(find.byKey(ValueKey('experiment-$id')), findsNothing);

    await teardownApp(tester, container);
  });

  testWidgets('the word habit appears in no segment', (tester) async {
    final container = await build(tester);
    await seedAll(tester, container);
    final running = await runningExperiment(tester, container);
    await open(tester, container);

    expect(find.text('Running (1)'), findsOneWidget);
    expect(find.byKey(ValueKey('experiment-${running.id}')), findsOneWidget);
    expect(habit(), findsNothing, reason: 'Running');

    await showKept(tester, 3);
    expect(find.byKey(const ValueKey('kept-list')), findsOneWidget);
    expect(habit(), findsNothing, reason: 'Kept');
    final first = (await runDb(
      tester,
      () => repoOf(container).watchExperiments().first,
    )).firstWhere((e) => e.tagName == 'Morning pages');
    await tapKey(tester, 'kept-explain-toggle-${first.id}');
    await tapKey(tester, 'kept-adjust-${first.id}');
    await settle(tester);
    expect(habit(), findsNothing, reason: 'Kept with explain and Adjust open');
    await tapKey(tester, 'kept-retire-${first.id}');
    await settle(tester);
    expect(habit(), findsNothing, reason: 'Kept with Retire open');

    await tapText(tester, 'Concluded (3, 3 also kept)');
    expect(habit(), findsNothing, reason: 'Concluded');

    await teardownApp(tester, container);
  });

  testWidgets('Kept shows no running rows and Running shows no kept rows', (
    tester,
  ) async {
    final container = await build(tester);
    await seedAll(tester, container);
    final running = await runningExperiment(tester, container);
    await open(tester, container);

    expect(find.byType(ExperimentRowView), findsOneWidget);
    expect(find.byKey(ValueKey('experiment-${running.id}')), findsOneWidget);
    expect(find.byType(KeptExperimentRow), findsNothing);

    await showKept(tester, 3);
    expect(find.byType(ExperimentRowView), findsNothing);
    expect(find.byType(KeptExperimentRow), findsNWidgets(3));

    await tapText(tester, 'Running (1)');
    expect(find.byType(KeptExperimentRow), findsNothing);
    expect(find.byType(ExperimentRowView), findsOneWidget);

    await teardownApp(tester, container);
  });

  testWidgets('large text on a phone: the Adjust sheet does not overflow and '
      'the steppers stack', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = await build(tester);
    final e = await seedV1(tester, container);
    await open(tester, container, surface: phone);
    await showKept(tester, 1);
    expect(tester.takeException(), isNull);

    final id = e.id;
    await tapKey(tester, 'kept-explain-toggle-$id');
    await settle(tester);
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'kept-adjust-$id');
    await settle(tester);
    expect(find.byKey(ValueKey('kept-adjust-sheet-$id')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final weekday = tester.getTopLeft(
      find.byKey(ValueKey('kept-stepper-weekday-$id-minus')),
    );
    final weekend = tester.getTopLeft(
      find.byKey(ValueKey('kept-stepper-weekend-$id-minus')),
    );
    expect(weekend.dx, weekday.dx, reason: 'stacked, not side by side');
    expect(weekend.dy, greaterThan(weekday.dy));

    await tapKey(tester, 'kept-adjust-cancel-$id');
    await tapKey(tester, 'kept-retire-$id');
    await settle(tester);
    expect(find.byKey(ValueKey('kept-retire-sheet-$id')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await teardownApp(tester, container);
  });

  testWidgets('a pending target becomes current when the week rolls over', (
    tester,
  ) async {
    now = PlannerTimeZone.calendarDate(
      2026,
      10,
      11,
      hour: 23,
      minute: 59,
      second: 59,
    );
    final container = await build(tester);
    final e = await seedV1(tester, container);
    await runDb(
      tester,
      () => repoOf(container).adjustKeptTarget(
        e.id,
        weekdayTargetMin: 75,
        weekendTargetMin: 90,
        fromNextWeek: true,
        today: '2026-10-11',
        expectedRevision: e.revision,
      ),
    );
    await open(tester, container);
    await showKept(tester, 1);

    final id = e.id;
    expect(isoDateString(container.read(insightsNowProvider)), '2026-10-11');
    expect(find.byKey(ValueKey('kept-pending-$id')), findsOneWidget);
    expect(plain(tester, 'kept-done-$id'), endsWith('of 8h this week'));

    now = PlannerTimeZone.calendarDate(2026, 10, 12, second: 1);
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);

    expect(isoDateString(container.read(insightsNowProvider)), '2026-10-12');
    expect(find.byKey(ValueKey('kept-pending-$id')), findsNothing);
    expect(plain(tester, 'kept-done-$id'), '0mof 9h 15m this week');
    expect(
      within('kept-detail-$id', find.text('This week · Oct 12 – 18')),
      findsOneWidget,
    );

    await teardownApp(tester, container);
  });
}
