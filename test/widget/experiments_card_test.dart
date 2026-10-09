import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/database/app_database.dart';
import 'package:personal_planner/core/models/day_context.dart';
import 'package:personal_planner/core/models/enums/task_status.dart';
import 'package:personal_planner/core/models/experiment.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/day_context/data/day_context_repository.dart';
import 'package:personal_planner/features/experiments/data/experiment_repository.dart';
import 'package:personal_planner/features/experiments/presentation/widgets/experiment_chart.dart';
import 'package:personal_planner/features/task_editor/data/tag_repository.dart';

import '../helpers/test_container.dart';

void main() {
  const desktop = Size(1400, 1000);
  const phone = Size(360, 800);

  // Wednesday Oct 7 2026, midday planner time.
  final now = PlannerTimeZone.calendarDate(2026, 10, 7, hour: 12);
  DateTime clock() => now;

  DateTime at(int day, int hour, [int minute = 0]) =>
      PlannerTimeZone.calendarDate(2026, 10, day, hour: hour, minute: minute);

  Future<ProviderContainer> open(
    WidgetTester tester, {
    Size surface = desktop,
  }) async {
    final container = await buildTestContainer(
      tester,
      insightsNowFactory: clock,
    );
    appRouter.go('/analytics');
    await pumpApp(tester, container, surface: surface);
    return container;
  }

  AppDatabase dbOf(ProviderContainer c) => c.read(appDatabaseProvider);

  Future<Experiment> createExperiment(
    WidgetTester tester,
    ProviderContainer container, {
    String name = 'Learn C',
    String start = '2026-10-05',
    String end = '2026-10-11',
  }) => runDb(
    tester,
    () => ExperimentRepository(dbOf(container)).createExperiment(
      name: name,
      startDate: start,
      endDate: end,
      weekdayTargetMin: 60,
      weekendTargetMin: 90,
      checkInEveryDays: 1,
    ),
  );

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
            tagId: tagId,
            createdAt: start,
            updatedAt: start,
          ),
        ),
  );

  Finder inCard(Finder finder) => find.descendant(
    of: find.byKey(const ValueKey('experiments-section')),
    matching: finder,
  );

  /// The worked example of the plan, built for real.
  Future<Experiment> workedExample(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final e = await createExperiment(tester, container);
    await runDb(
      tester,
      () =>
          DayContextRepository(dbOf(container))
              .save('2026-10-06', DayContextKind.leave, null),
    );
    await addBlock(
      tester,
      container,
      tagId: e.tagId,
      start: at(5, 9),
      end: at(5, 10),
      actual: 50,
    );
    await addBlock(
      tester,
      container,
      tagId: e.tagId,
      start: at(6, 9),
      end: at(6, 10),
      actual: 30,
    );
    await addBlock(
      tester,
      container,
      tagId: e.tagId,
      start: at(7, 9),
      end: at(7, 10),
      actual: 40,
    );
    await addBlock(
      tester,
      container,
      tagId: e.tagId,
      start: at(7, 14),
      end: at(7, 14, 30),
      status: TaskStatus.planned,
    );
    return e;
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await tester.pump();
  }

  Future<void> goTo(WidgetTester tester, String path) async {
    appRouter.go(path);
    await settle(tester);
  }

  testWidgets('shows Consistency, then an empty Experiments card', (
    tester,
  ) async {
    final container = await open(tester);

    expect(find.byKey(const ValueKey('consistency-section')), findsOneWidget);
    expect(find.byKey(const ValueKey('this-week-section')), findsNothing);
    expect(find.text('This Week'), findsNothing);
    expect(inCard(find.text('Experiments')), findsOneWidget);
    expect(inCard(find.text('Start an experiment')), findsOneWidget);
    expect(
      inCard(
        find.text(
          'No experiments yet. Start one to follow how it is going here.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('experiments-counts')), findsNothing);
    final consistency = tester.getTopLeft(
      find.byKey(const ValueKey('consistency-section')),
    );
    final experiments = tester.getTopLeft(
      find.byKey(const ValueKey('experiments-section')),
    );
    expect(experiments.dy, greaterThan(consistency.dy));

    await teardownApp(tester, container);
  });

  testWidgets('the worked example shows the hand-calculated numbers', (
    tester,
  ) async {
    final container = await open(tester);
    final e = await workedExample(tester, container);
    await settle(tester);

    expect(find.byKey(const ValueKey('experiments-counts')), findsOneWidget);
    expect(find.text('1 running · 0 concluded'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('experiment-headline-${e.id}')))
          .data,
      'Done 2h of 1h 40m expected so far',
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('experiment-pace-${e.id}')),
        matching: find.text('20m ahead'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('experiment-days-at-target-${e.id}')),
        matching: find.text('0 of 1'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('experiment-today-${e.id}')))
          .data,
      'Today: 40m done · 30m still planned · target 1h',
    );
    expect(find.text('Running · Day 3 of 7'), findsOneWidget);
    expect(
      find.text(
        'Oct 5 to Oct 11 · 60 min weekdays · 90 min weekends · '
        'every day check-in',
      ),
      findsOneWidget,
    );
    expect(find.text('Pace'), findsOneWidget);
    expect(find.text('Days at your target'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Expected by now'), findsOneWidget);
    expect(find.text('Full bar = the whole window, 7h'), findsOneWidget);
    expect(
      find.text("Today's target only counts against you once the day is over."),
      findsOneWidget,
    );

    await teardownApp(tester, container);
  });

  testWidgets('completing a tagged block while Insights is shown updates the '
      'headline', (tester) async {
    final container = await open(tester);
    final e = await workedExample(tester, container);
    await settle(tester);
    Text headline() => tester.widget<Text>(
      find.byKey(ValueKey('experiment-headline-${e.id}')),
    );
    expect(headline().data, 'Done 2h of 1h 40m expected so far');

    await addBlock(
      tester,
      container,
      tagId: e.tagId,
      start: at(5, 15),
      end: at(5, 16),
      actual: 20,
    );
    await settle(tester);

    expect(headline().data, 'Done 2h 20m of 1h 40m expected so far');
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await teardownApp(tester, container);
  });

  testWidgets('leaving to Day and back shows the numbers in the first frame '
      'with no spinner (F4)', (tester) async {
    final container = await open(tester);
    final e = await workedExample(tester, container);
    await settle(tester);
    final headlineKey = ValueKey('experiment-headline-${e.id}');
    final cached = tester.widget<Text>(find.byKey(headlineKey)).data;
    expect(cached, 'Done 2h of 1h 40m expected so far');

    await goTo(tester, '/day');
    expect(find.byKey(const ValueKey('experiments-section')), findsNothing);

    appRouter.go('/analytics');
    var sawConsistency = false;
    for (var frame = 0; frame < 40 && !sawConsistency; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find
          .byKey(const ValueKey('consistency-section'))
          .evaluate()
          .isEmpty) {
        continue;
      }
      sawConsistency = true;
      expect(
        find.byKey(headlineKey),
        findsOneWidget,
        reason: 'the headline must be there in the first frame of the content',
      );
      expect(tester.widget<Text>(find.byKey(headlineKey)).data, cached);
      expect(inCard(find.byType(CircularProgressIndicator)), findsNothing);
      expect(
        find.byKey(const ValueKey('experiments-placeholder')),
        findsNothing,
      );
    }
    expect(sawConsistency, isTrue);

    await teardownApp(tester, container);
  });

  testWidgets('a block completed on Day shows on return without a spinner', (
    tester,
  ) async {
    final container = await open(tester);
    final e = await workedExample(tester, container);
    await settle(tester);
    await goTo(tester, '/day');

    await addBlock(
      tester,
      container,
      tagId: e.tagId,
      start: at(5, 15),
      end: at(5, 16),
      actual: 20,
    );
    await settle(tester);
    await goTo(tester, '/analytics');

    expect(
      tester
          .widget<Text>(find.byKey(ValueKey('experiment-headline-${e.id}')))
          .data,
      'Done 2h 20m of 1h 40m expected so far',
    );
    expect(inCard(find.byType(CircularProgressIndicator)), findsNothing);

    await teardownApp(tester, container);
  });

  group('start form', () {
    Future<void> openForm(WidgetTester tester) async {
      await tapKey(tester, 'experiments-start');
      await settle(tester);
    }

    FilledButton submit(WidgetTester tester) => tester.widget<FilledButton>(
      find.byKey(const ValueKey('experiment-start-submit')),
    );

    testWidgets('has the planned defaults and validates', (tester) async {
      final container = await open(tester);
      await openForm(tester);

      expect(find.text('New experiment'), findsOneWidget);
      expect(find.text('Name (this becomes the tag)'), findsOneWidget);
      expect(find.text('Weekday target (min)'), findsOneWidget);
      expect(find.text('Weekend target (min)'), findsOneWidget);
      expect(
        find.text(
          'How often do you want to write a check-in about how it is going?',
        ),
        findsOneWidget,
      );
      expect(find.text('Wed, Oct 7, 2026'), findsOneWidget);
      expect(find.text('Thu, Nov 5, 2026'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('experiment-weekday-target')),
            )
            .controller!
            .text,
        '60',
      );
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('experiment-weekend-target')),
            )
            .controller!
            .text,
        '90',
      );
      expect(
        tester
            .widget<ChoiceChip>(
              find.byKey(const ValueKey('experiment-frequency-1')),
            )
            .selected,
        isTrue,
      );
      for (final label in [
        'Every day',
        'Every 3 days',
        'Every week',
        'Every 10 days',
        'Every 15 days',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(submit(tester).onPressed, isNull, reason: 'name is empty');

      await tester.enterText(
        find.byKey(const ValueKey('experiment-weekday-target')),
        '',
      );
      await tester.pump();
      expect(find.text('Targets must be numbers, 0 or more.'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('experiment-name')),
        'Sketching',
      );
      await tester.pump();
      expect(submit(tester).onPressed, isNull, reason: 'targets error shows');
      await tester.enterText(
        find.byKey(const ValueKey('experiment-weekday-target')),
        '30',
      );
      await tester.pump();
      expect(submit(tester).onPressed, isNotNull);

      await tapKey(tester, 'experiment-start-cancel');
      await settle(tester);
      expect(find.text('New experiment'), findsNothing);
      await teardownApp(tester, container);
    });

    testWidgets('creates an experiment with a new tag', (tester) async {
      final container = await open(tester);
      await openForm(tester);

      await tester.enterText(
        find.byKey(const ValueKey('experiment-name')),
        'Sketching',
      );
      await tester.pump();
      expect(
        find.text('A new tag called "Sketching" will be created.'),
        findsOneWidget,
      );
      await tapKey(tester, 'experiment-frequency-7');
      await settle(tester);
      await tapKey(tester, 'experiment-start-submit');
      await settle(tester);
      await settle(tester);

      expect(find.text('New experiment'), findsNothing);
      expect(find.text('1 running · 0 concluded'), findsOneWidget);
      expect(find.text('Sketching'), findsOneWidget);
      expect(find.textContaining('every week check-in'), findsOneWidget);
      expect(find.text('Running · Day 1 of 30'), findsOneWidget);
      final tag = await runDb(
        tester,
        () =>
            TagRepository(dbOf(container)).findByNameIgnoringCase('sketching'),
      );
      expect(tag?.name, 'Sketching');

      await teardownApp(tester, container);
    });

    testWidgets('uses an existing tag, shows its blocks and the first date, '
        'and refuses a tag already in use', (tester) async {
      final container = await open(tester);
      final tag = await runDb(
        tester,
        () => TagRepository(dbOf(container)).getOrCreateForName('Learn C'),
      );
      await addBlock(
        tester,
        container,
        tagId: tag.id,
        start: at(1, 9),
        end: at(1, 10),
        actual: 10,
      );
      await openForm(tester);

      await tester.enterText(
        find.byKey(const ValueKey('experiment-name')),
        'learn c',
      );
      await settle(tester);
      expect(
        find.text(
          'The tag "Learn C" already exists with 1 block. Blocks inside your '
          'dates count straight away.',
        ),
        findsOneWidget,
      );
      final useFirst = find.byKey(const ValueKey('experiment-use-first-date'));
      expect(useFirst, findsOneWidget);
      expect(
        find.text('Use the first tagged block date (Thu, Oct 1, 2026)'),
        findsOneWidget,
      );
      await tester.ensureVisible(useFirst);
      await tester.tap(useFirst);
      await tester.pump();
      expect(find.text('Thu, Oct 1, 2026'), findsOneWidget);
      // The end date did not move.
      expect(find.text('Thu, Nov 5, 2026'), findsOneWidget);

      await tapKey(tester, 'experiment-start-submit');
      await settle(tester);
      await settle(tester);
      expect(find.text('1 running · 0 concluded'), findsOneWidget);
      // The block of Oct 1 is inside the window and counts straight away.
      expect(find.text('Running · Day 7 of 36'), findsOneWidget);

      await openForm(tester);
      await tester.enterText(
        find.byKey(const ValueKey('experiment-name')),
        'Learn C',
      );
      await settle(tester);
      expect(
        find.text(
          'An experiment already uses the tag "Learn C". Pick a different name.',
        ),
        findsOneWidget,
      );
      expect(submit(tester).onPressed, isNull);

      await teardownApp(tester, container);
    });
  });

  group('chart', () {
    testWidgets('is one CustomPaint with the experiment painter and no '
        'per-bar widgets (R18)', (tester) async {
      final container = await open(tester);
      final e = await workedExample(tester, container);
      await settle(tester);

      final chart = find.byKey(ValueKey('experiment-chart-${e.id}'));
      expect(chart, findsOneWidget);
      // The key sits on the one CustomPaint of the chart.
      final paint = tester.widget<CustomPaint>(chart);
      expect(paint.painter, isA<ExperimentChartPainter>());
      expect((paint.painter! as ExperimentChartPainter).buckets, hasLength(7));
      // Nothing inside it is a second CustomPaint (no widget per bar).
      expect(
        find.descendant(of: chart, matching: find.byType(CustomPaint)),
        findsNothing,
      );
      // And the whole row holds exactly one chart painter.
      expect(
        find.descendant(
          of: find.byKey(ValueKey('experiment-${e.id}')),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.painter is ExperimentChartPainter,
          ),
        ),
        findsOneWidget,
      );

      await teardownApp(tester, container);
    });

    testWidgets('tap and hover show the line of the nearest bar', (
      tester,
    ) async {
      final container = await open(tester);
      final e = await workedExample(tester, container);
      await settle(tester);

      final chart = find.byKey(ValueKey('experiment-chart-${e.id}'));
      final line = find.byKey(ValueKey('experiment-chart-line-${e.id}'));
      expect(tester.widget<Text>(line).data, ' ');

      final box = tester.getRect(chart);
      final slot = box.width / 7;
      // Monday is the first slot; tap just beside the bar, still in the slot.
      await tester.tapAt(Offset(box.left + slot * 0.1, box.center.dy));
      await tester.pump();
      expect(tester.widget<Text>(line).data, 'Mon Oct 5: 50m of 1h target');

      // Tuesday is a Leave day.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(Offset(box.left + slot * 1.5, box.center.dy));
      await tester.pump();
      expect(tester.widget<Text>(line).data, 'Tue Oct 6: Leave');
      await mouse.moveTo(const Offset(1, 1));
      await tester.pump();
      expect(
        tester.widget<Text>(line).data,
        'Mon Oct 5: 50m of 1h target',
        reason: 'hover cleared, the tapped bar is still selected',
      );

      // Tapping the selected bar again clears it.
      await tester.tapAt(Offset(box.left + slot * 0.1, box.center.dy));
      await tester.pump();
      expect(tester.widget<Text>(line).data, ' ');
      await mouse.removePointer();

      await teardownApp(tester, container);
    });

    testWidgets('regroups into days, weeks and months by width', (
      tester,
    ) async {
      final container = await open(tester, surface: phone);
      // Consistency keeps its horizontal scroller at phone width (this
      // assertion used to live in the removed This Week phone-layout test).
      expect(
        find.byKey(const ValueKey('consistency-grid-scroll')),
        findsOneWidget,
      );
      final days = await createExperiment(
        tester,
        container,
        name: 'Thirty',
        start: '2026-10-01',
        end: '2026-10-30',
      );
      final weeks = await createExperiment(
        tester,
        container,
        name: 'Sixty',
        start: '2026-09-20',
        end: '2026-11-18',
      );
      final months = await createExperiment(
        tester,
        container,
        name: 'Long',
        start: '2026-09-01',
        end: '2027-10-05',
      );
      await settle(tester);

      ExperimentChartPainter painterOf(Experiment e) =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(ValueKey('experiment-chart-${e.id}')),
                  )
                  .painter!
              as ExperimentChartPainter;
      for (final e in [days, weeks, months]) {
        await tester.ensureVisible(
          find.byKey(ValueKey('experiment-chart-${e.id}')),
        );
      }
      await tester.pump();

      expect(painterOf(days).buckets, hasLength(30));
      expect(painterOf(weeks).buckets.length, lessThan(60));
      expect(
        find.text("Showing weeks because 60 days don't fit on this screen."),
        findsOneWidget,
      );
      expect(painterOf(months).buckets.length, lessThan(20));
      expect(
        find.textContaining('Showing months because 400 days'),
        findsOneWidget,
      );
      expect(
        find.text("Minutes per day. The dashed outline is that day's target."),
        findsOneWidget,
      );

      // A wide surface fits the 60 days.
      tester.view.physicalSize = desktop;
      await tester.pump();
      await settle(tester);
      expect(painterOf(weeks).buckets, hasLength(60));

      await teardownApp(tester, container);
    });

    testWidgets('screen readers get the summary and one label per bar '
        '(F10 a)', (tester) async {
      final handle = tester.ensureSemantics();
      final container = await open(tester);
      final e = await workedExample(tester, container);
      await settle(tester);

      expect(
        find.bySemanticsLabel(
          "Minutes per day. The dashed outline is that day's target. "
          'Oct 5 to Oct 11.',
        ),
        findsOneWidget,
      );
      final chart = find.byKey(ValueKey('experiment-chart-${e.id}'));
      final labels = <String>[];
      void collect(SemanticsNode node) {
        node.visitChildren((child) {
          final label = child.getSemanticsData().label;
          if (label.isNotEmpty) labels.add(label);
          collect(child);
          return true;
        });
      }

      collect(tester.getSemantics(chart));
      final painter =
          tester.widget<CustomPaint>(chart).painter! as ExperimentChartPainter;
      expect(painter.buckets, hasLength(7));
      for (final bucket in painter.buckets) {
        expect(labels, contains(bucket.tapLine));
      }
      expect(labels, contains('Mon Oct 5: 50m of 1h target'));
      expect(labels, contains('Tue Oct 6: Leave'));

      handle.dispose();
      await teardownApp(tester, container);
    });
  });

  testWidgets('large text on a phone does not overflow, card or form '
      '(F10 d)', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final container = await open(tester, surface: phone);
    final e = await workedExample(tester, container);
    await settle(tester);
    await tester.ensureVisible(
      find.byKey(ValueKey('experiment-chart-${e.id}')),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tapKey(tester, 'experiments-start');
    await settle(tester);
    expect(find.text('New experiment'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('experiment-name')),
      'Learn C',
    );
    await settle(tester);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byType(SingleChildScrollView).last,
      const Offset(0, -600),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tapKey(tester, 'experiment-start-cancel');
    await settle(tester);
    await teardownApp(tester, container);
  });
}
