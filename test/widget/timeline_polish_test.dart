import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/constants/app_constants.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/core/utils/planner_day_axis.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/core/widgets/status_badge.dart';
import 'package:personal_planner/core/widgets/task_block_widget.dart';
import 'package:personal_planner/features/timeline/domain/timeline_geometry.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/current_time_indicator.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/ghost_preview.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/task_quick_create.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/timeline_overlap_action.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/timeline_widget.dart';

import '../helpers/test_container.dart';

/// A fixed past day: no now-line, and the timeline opens anchored at 07:00.
final DateTime _day = DateTime(2026, 3, 10);

const double _ppm = AppConstants.pixelsPerMinute;
const Size _desktop = Size(1400, 1000);

void main() {
  final timeline = find.byKey(const ValueKey('timeline-gestures'));

  Future<ProviderContainer> pumpDay(
    WidgetTester tester, {
    Size size = _desktop,
    bool fixedDay = true,
    List<Task> tasks = const [],
  }) async {
    final container = await buildTestContainer(tester);
    final repo = container.read(taskRepositoryProvider);
    for (final task in tasks) {
      await runDb(tester, () => repo.insertTask(task));
    }
    if (fixedDay) container.read(selectedDateProvider.notifier).state = _day;
    appRouter.go('/day');
    await pumpApp(tester, container, surface: size);
    if (fixedDay) container.read(selectedDateProvider.notifier).state = _day;
    await settle(tester);
    return container;
  }

  Task block(String title, int startMin, int endMin) => Task(
    id: '',
    title: title,
    startTime: _day.add(Duration(minutes: startMin)),
    endTime: _day.add(Duration(minutes: endMin)),
    createdAt: _day,
    updatedAt: _day,
  );

  double scrollPixels(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: timeline, matching: find.byType(Scrollable)).first,
      )
      .position
      .pixels;

  /// The global point `dx` from the timeline's left edge and `dy` below its
  /// top edge, and the (unclamped) slot start the widget should derive from it.
  Offset point(WidgetTester tester, double dx, double dy) =>
      tester.getTopLeft(timeline) + Offset(dx, dy);

  int expectedSlot(WidgetTester tester, double dy) {
    final contentY = scrollPixels(tester) + dy;
    final axis = PlannerDayAxis(_day);
    return ((contentY / _ppm / AppConstants.defaultGridMinutes).floor() *
            AppConstants.defaultGridMinutes)
        .clamp(0, axis.durationMinutes - AppConstants.defaultGridMinutes);
  }

  String clock(DateTime instant) {
    final local = PlannerTimeZone.toPlannerLocal(instant);
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  testWidgets('a tap on an empty slot opens quick create at that slot', (
    tester,
  ) async {
    final container = await pumpDay(tester);
    // Right of the empty-day card, so only the grid is under the pointer.
    final tapAt = point(tester, 700, 500);
    await tester.tapAt(tapAt);
    await settle(tester);

    expect(find.text('Create scheduled task'), findsOneWidget);
    final form = tester.widget<TaskQuickCreate>(find.byType(TaskQuickCreate));
    final slot = expectedSlot(tester, 500);
    final expected = PlannerDayAxis(_day).instantAt(slot.toDouble());
    expect(form.initialStart, expected);
    expect(
      form.initialEnd,
      expected.add(const Duration(minutes: AppConstants.defaultGridMinutes)),
    );
    await teardownApp(tester, container);
  });

  group('a tap resolves against the row under the finger', () {
    /// A tap `minute` minutes into the day, just right of the 09:00-10:00 block.
    Future<ProviderContainer> tapAtMinute(
      WidgetTester tester,
      int minute,
    ) async {
      final container = await pumpDay(
        tester,
        tasks: [block('Morning task', 9 * 60, 10 * 60)],
      );
      final blockRight = tester.getRect(find.byType(TaskBlockWidget)).right;
      final dy = minute * _ppm - scrollPixels(tester);
      await tester.tapAt(
        Offset(blockRight + 20, tester.getTopLeft(timeline).dy + dy),
      );
      await settle(tester);
      return container;
    }

    testWidgets('the lower half of an occupied row says the slot is taken', (
      tester,
    ) async {
      final container = await tapAtMinute(tester, 9 * 60 + 40);
      expect(find.textContaining('That slot is taken'), findsOneWidget);
      expect(find.text('Create scheduled task'), findsNothing);
      await teardownApp(tester, container);
    });

    testWidgets('the lower half of a free row opens quick create at that row', (
      tester,
    ) async {
      final container = await tapAtMinute(tester, 8 * 60 + 40);
      expect(find.textContaining('That slot is taken'), findsNothing);
      final form = tester.widget<TaskQuickCreate>(find.byType(TaskQuickCreate));
      expect(form.initialStart, PlannerDayAxis(_day).instantAt(8 * 60));
      await teardownApp(tester, container);
    });
  });

  testWidgets('a tap while a task is selected only deselects', (tester) async {
    // 22:00-23:00 is below the viewport (it starts at about 05:30), so the
    // tapped slot is free.
    final container = await pumpDay(
      tester,
      tasks: [block('Late task', 22 * 60, 23 * 60)],
    );
    final tasks = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).watchTasksForDay(_day).first,
    );
    container.read(selectedTaskIdProvider.notifier).state = tasks.single.id;
    await tester.pump();

    await tester.tapAt(point(tester, 700, 300));
    await settle(tester);
    expect(container.read(selectedTaskIdProvider), isNull);
    expect(find.text('Create scheduled task'), findsNothing);

    await tester.tapAt(point(tester, 700, 300));
    await settle(tester);
    expect(find.text('Create scheduled task'), findsOneWidget);
    await teardownApp(tester, container);
  });

  testWidgets(
    'hover shows the slot highlight without rebuilding the timeline',
    (tester) async {
      final container = await pumpDay(
        tester,
        tasks: [block('Late task', 22 * 60, 23 * 60)],
      );
      final highlight = find.byKey(const ValueKey('timeline-hover-slot'));
      expect(highlight, findsNothing);

      var timelineBuilds = 0;
      var hoverBuilderBuilds = 0;
      final previousHook = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        final widget = element.widget;
        if (widget is TimelineWidget) timelineBuilds++;
        if (widget is ValueListenableBuilder<int?>) hoverBuilderBuilds++;
      };
      try {
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: point(tester, 700, 250));
        await tester.pump();
        await mouse.moveTo(point(tester, 700, 300));
        await tester.pump();

        expect(highlight, findsOneWidget);
        final slot = expectedSlot(tester, 300);
        final label =
            '+ ${clock(PlannerDayAxis(_day).instantAt(slot.toDouble()))}';
        expect(
          find.descendant(of: highlight, matching: find.text(label)),
          findsOneWidget,
        );
        // One slot tall, and inside the lane (right of the ruler).
        final box = tester.getRect(highlight);
        expect(
          box.height,
          closeTo(AppConstants.defaultGridMinutes * _ppm, 0.5),
        );
        expect(
          box.left,
          greaterThanOrEqualTo(
            tester.getTopLeft(timeline).dx + AppConstants.hourLabelWidth,
          ),
        );
        expect(
          box.top - tester.getTopLeft(timeline).dy,
          closeTo(slot * _ppm - scrollPixels(tester), 1),
        );

        // Moving inside the same slot does not touch anything; moving to the
        // next slot updates only the overlay builder.
        final buildsBeforeMoves = timelineBuilds;
        final hoverBuildsBefore = hoverBuilderBuilds;
        for (var i = 1; i <= 20; i++) {
          await mouse.moveTo(point(tester, 700, 300 + i * 2.0));
          await tester.pump();
        }
        await mouse.moveTo(
          point(tester, 700, 300 + AppConstants.hourRowHeight),
        );
        await tester.pump();
        expect(
          hoverBuilderBuilds,
          greaterThan(hoverBuildsBefore),
          reason: 'the rebuild hook must be live, and the overlay must update',
        );
        expect(
          timelineBuilds,
          buildsBeforeMoves,
          reason: 'hover must not rebuild TimelineWidget',
        );

        // Leaving the grid clears the highlight.
        await mouse.moveTo(const Offset(5, 5));
        await tester.pump();
        expect(highlight, findsNothing);
        await mouse.removePointer();
      } finally {
        debugOnRebuildDirtyWidget = previousHook;
      }
      await teardownApp(tester, container);
    },
  );

  testWidgets('hovering a task block shows no slot highlight', (tester) async {
    // 09:00-10:00 is inside the viewport (05:30 onwards).
    final container = await pumpDay(
      tester,
      tasks: [block('Morning task', 9 * 60, 10 * 60)],
    );
    final blockFinder = find.textContaining('Morning task').first;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: point(tester, 700, 100));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(blockFinder));
    await tester.pump();
    expect(find.byKey(const ValueKey('timeline-hover-slot')), findsNothing);
    await mouse.removePointer();
    await teardownApp(tester, container);
  });

  testWidgets('the empty-day card sits near the anchor and its buttons work', (
    tester,
  ) async {
    final container = await pumpDay(tester);
    final card = find.byKey(const ValueKey('empty-day-card'));
    expect(card, findsOneWidget);
    expect(find.text('Nothing scheduled.'), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-day-hint')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('empty-day-hint'))).data,
      'Tap a time slot or pull something from Inbox. '
      'Pick a category in the editor.',
    );

    // Other days anchor at 07:00; the card is one hour below that minute and
    // the viewport starts 1.5 hours above it: 2.5 hours = 160 px down.
    final viewport = tester.getRect(timeline);
    final cardRect = tester.getRect(card);
    expect(cardRect.top - viewport.top, closeTo(2.5 * 64, 2));
    expect(cardRect.width, lessThanOrEqualTo(420));
    expect(
      cardRect.left - viewport.left,
      closeTo(AppConstants.hourLabelWidth + 8, 1),
    );
    expect(viewport.contains(cardRect.topLeft), isTrue);
    expect(viewport.contains(cardRect.bottomRight), isTrue);

    // The card only absorbs taps inside its own bounds: beside it the grid
    // still creates a task.
    await tester.tapAt(Offset(cardRect.right + 60, cardRect.center.dy));
    await settle(tester);
    expect(find.text('Create scheduled task'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel quick create'));
    await settle(tester);
    expect(find.text('Create scheduled task'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('empty-day-add')));
    await settle(tester);
    expect(find.text('Create scheduled task'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel quick create'));
    await settle(tester);

    await tester.tap(find.byKey(const ValueKey('empty-day-inbox')));
    await settle(tester);
    expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/inbox');
    await teardownApp(tester, container);
    appRouter.go('/day');
  });

  testWidgets('the empty-day card disappears once the day has a task', (
    tester,
  ) async {
    final container = await pumpDay(
      tester,
      tasks: [block('Only task', 9 * 60, 10 * 60)],
    );
    expect(find.byKey(const ValueKey('empty-day-card')), findsNothing);
    expect(find.byKey(const ValueKey('empty-day-add')), findsNothing);
    await teardownApp(tester, container);
  });

  testWidgets('ruler labels, now pill and block meta text are at least 12sp', (
    tester,
  ) async {
    // Today, so the now-line is painted; the task is a long block so the full
    // layout (duration and subtask count) is used.
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 1);
    final container = await pumpDay(
      tester,
      fixedDay: false,
      tasks: [
        Task(
          id: '',
          title: 'Long block',
          startTime: start,
          endTime: start.add(const Duration(hours: 2)),
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );
    final ruler = RegExp(r'^\d\d:00$');
    final rulerTexts = find.descendant(
      of: timeline,
      matching: find.byWidgetPredicate(
        (w) => w is Text && ruler.hasMatch(w.data ?? ''),
      ),
    );
    expect(rulerTexts, findsWidgets);
    for (final text in tester.widgetList<Text>(rulerTexts)) {
      expect(text.style?.fontSize, greaterThanOrEqualTo(12), reason: text.data);
    }
    final pill = find.descendant(
      of: find.byType(CurrentTimeIndicator),
      matching: find.byType(Text),
    );
    expect(pill, findsOneWidget);
    expect(tester.widget<Text>(pill).style?.fontSize, greaterThanOrEqualTo(12));
    expect(
      tester.widget<Text>(pill).style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
    // Every glyph run painted inside the timeline (ruler, pill, blocks, icons)
    // resolves to 12sp or more, except the shared StatusBadge (10sp, not part
    // of this phase).
    final duration = find.byKey(const ValueKey('task-duration-label'));
    expect(duration, findsOneWidget);
    expect(
      tester.widget<Text>(duration).style?.fontSize,
      greaterThanOrEqualTo(12),
    );
    final badgeRuns = find
        .descendant(
          of: find.byType(StatusBadge),
          matching: find.byType(RichText),
        )
        .evaluate()
        .map((element) => element.widget)
        .toSet();
    final runs = find
        .descendant(of: timeline, matching: find.byType(RichText))
        .evaluate()
        .where((element) => !badgeRuns.contains(element.widget));
    expect(runs, isNotEmpty);
    for (final element in runs) {
      final paragraph = element.renderObject! as RenderParagraph;
      expect(
        paragraph.text.style?.fontSize,
        greaterThanOrEqualTo(12),
        reason: 'text "${paragraph.text.toPlainText()}"',
      );
    }
    await teardownApp(tester, container);

    // The overlap action and the drag ghost are only shown on demand, so build
    // them directly at the smallest box a block gets (28 dp) and at text scale
    // 1.5; the text must be 12sp or more and must fit with no overflow error.
    final at = DateTime.utc(2026, 3, 10, 9);
    final overlapping = [
      for (var i = 0; i < 2; i++)
        Task(
          id: 'overlap-$i',
          title: 'Overlap $i',
          startTime: at,
          endTime: at.add(const Duration(hours: 1)),
          createdAt: at,
          updatedAt: at,
        ),
    ];
    final geometry = TimelineGeometry.layoutForDay(
      tasks: overlapping,
      date: at,
    ).first;
    for (final scale in [1.0, 1.5]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: 120,
                  height: TaskBlockWidget.compactMinHeight,
                  child: TimelineOverlapAction(
                    geometry: geometry,
                    tasks: overlapping,
                    date: at,
                    onOpen: (_) {},
                  ),
                ),
                for (final (i, minutes) in [5, 15, 30, 90].indexed)
                  GhostPreview(
                    key: ValueKey('ghost-$minutes'),
                    title: 'Ghost task',
                    topPx: 60.0 + i * 100,
                    heightPx: minutes * _ppm,
                    left: 0,
                    right: 0,
                    accentColor: Colors.red,
                    durationMinutes: minutes,
                  ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'scale $scale');
      for (final (name, root) in [
        ('overlap action', find.byType(TimelineOverlapAction)),
        ('ghost preview', find.byType(GhostPreview)),
      ]) {
        final runs = find
            .descendant(of: root, matching: find.byType(RichText))
            .evaluate();
        expect(runs, isNotEmpty, reason: name);
        for (final element in runs) {
          final paragraph = element.renderObject! as RenderParagraph;
          expect(
            paragraph.text.style?.fontSize,
            greaterThanOrEqualTo(12),
            reason: '$name text "${paragraph.text.toPlainText()}" at $scale',
          );
        }
      }
      // One line (never scaled down) inside the 28 dp box.
      final label = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(TimelineOverlapAction),
          matching: find.text('2'),
        ),
      );
      expect(label.size.height, lessThanOrEqualTo(28), reason: 'scale $scale');
    }
  });

  testWidgets('the timeline opens at now minus 90 minutes', (tester) async {
    final container = await pumpDay(tester, fixedDay: false);
    final now = DateTime.now();
    final nowMinutes = PlannerDayAxis(now).elapsedMinutes(now);
    final pixels = scrollPixels(tester);
    final maxExtent = tester
        .state<ScrollableState>(
          find
              .descendant(of: timeline, matching: find.byType(Scrollable))
              .first,
        )
        .position
        .maxScrollExtent;
    final unclamped = (nowMinutes - 90) * _ppm - 64 * 1.5;
    expect(pixels, closeTo(unclamped.clamp(0.0, maxExtent), 3));
    if (unclamped >= 0 && unclamped <= maxExtent) {
      // The now-line is 90 minutes plus the 1.5 hour lead below the top edge.
      final line = tester.getTopLeft(find.byType(CurrentTimeIndicator));
      final top = tester.getTopLeft(timeline);
      expect(line.dy - top.dy, closeTo(90 * _ppm + 64 * 1.5, 4));
    }
    await teardownApp(tester, container);
  });

  group('shortcut hints in header tooltips', () {
    testWidgets('medium and up on a desktop platform carry the hints', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      late ProviderContainer container;
      try {
        container = await pumpDay(tester);
        expect(find.byTooltip('Previous day (←)'), findsOneWidget);
        expect(find.byTooltip('Next day (→)'), findsOneWidget);
        expect(find.byTooltip('Today (T)'), findsOneWidget);
        expect(find.byTooltip('New task (N)'), findsOneWidget);
        // Both segments: Day and Week.
        expect(find.byTooltip('Toggle Day/Week (W)'), findsNWidgets(2));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      await teardownApp(tester, container);
    });

    testWidgets('Android medium and up shows no hint (shortcuts are off)', (
      tester,
    ) async {
      final container = await pumpDay(tester);
      expect(find.byTooltip('Previous day'), findsOneWidget);
      expect(find.byTooltip('Today'), findsOneWidget);
      expect(find.byTooltip('New task'), findsOneWidget);
      expect(find.byTooltip('Toggle Day/Week'), findsNWidgets(2));
      await teardownApp(tester, container);
    });

    testWidgets('compact never carries a hint, even on a desktop platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      late ProviderContainer container;
      try {
        container = await pumpDay(tester, size: const Size(390, 844));
        expect(find.byTooltip('Toggle Day/Week'), findsNWidgets(2));
        final hinted = find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').endsWith(')'),
        );
        expect(hinted, findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
      await teardownApp(tester, container);
    });
  });
}
