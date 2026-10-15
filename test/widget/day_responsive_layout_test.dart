import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';
import 'package:personal_planner/features/timeline/presentation/screens/day_view_screen.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/attention/attention_groups.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/attention/day_attention_section.dart';

import '../helpers/day_responsive_fixture.dart';
import '../helpers/test_container.dart';

void main() {
  const timeline = ValueKey('timeline-gestures');

  Finder byKey(String key) => find.byKey(ValueKey(key));

  group('Day layout per size class', () {
    for (final (w, h) in [
      (360, 800),
      (800, 1280),
      (1000, 800),
      (1280, 800),
      (1920, 1080),
    ]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('${w}x$h at text scale $scale', (tester) async {
          final container = await pumpResponsiveDay(
            tester,
            size: Size(w.toDouble(), h.toDouble()),
            textScale: scale,
            blocks: !(w < 600 && scale > 1),
          );
          expect(tester.takeException(), isNull);

          final compact = w < 600;
          expect(
            find.byType(NavigationBar),
            compact ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(NavigationRail),
            compact ? findsNothing : findsOneWidget,
          );
          expect(
            byKey('day-new-task'),
            compact ? findsNothing : findsOneWidget,
          );
          expect(
            byKey('day-new-task-fab'),
            compact ? findsOneWidget : findsNothing,
          );
          expect(
            byKey('day-side-panel'),
            w >= 840 ? findsOneWidget : findsNothing,
          );

          final timelineSize = tester.getSize(find.byKey(timeline));
          expect(timelineSize.width, greaterThan(0));
          expect(timelineSize.width, lessThanOrEqualTo(840));

          if (w == 1920) {
            // The actions stay next to the title instead of being pushed to
            // the far edge of the window.
            final title = tester.getTopLeft(byKey('day-date-button')).dx;
            final lastAction = tester.getTopRight(byKey('day-overflow')).dx;
            expect(lastAction - title, lessThanOrEqualTo(1400));
          }
          if (w >= 1200) {
            // The panel is 360 wide at the large class, 320 at expanded.
            expect(tester.getSize(byKey('day-side-panel')).width, 360);
          } else if (w >= 840) {
            expect(tester.getSize(byKey('day-side-panel')).width, 320);
          }
          await finish(tester, container);
        });
      }
    }
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('320x700 at text scale $scale: top bar has no overflow', (
      tester,
    ) async {
      // Ahem is far wider than a real font, so this is the worst case for the
      // compact top bar's date and Today fitting.
      final container = await pumpResponsiveDay(
        tester,
        size: const Size(320, 700),
        textScale: scale,
        blocks: false,
      );
      expect(tester.takeException(), isNull);
      expect(byKey('day-date-button'), findsOneWidget);
      expect(byKey('day-today'), findsOneWidget);
      expect(
        tester.getSize(byKey('day-today')).width,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getRect(byKey('day-today')).right,
        lessThanOrEqualTo(tester.getRect(byKey('day-overflow')).left),
      );
      await finish(tester, container);
    });
  }

  testWidgets('13 overdue items do not shrink the timeline at 1280x800', (
    tester,
  ) async {
    final container = await pumpResponsiveDay(
      tester,
      size: const Size(1280, 800),
    );
    final body = tester.getSize(find.byType(DayViewScreen)).height;
    final viewport = tester.getSize(find.byKey(timeline)).height;
    expect(viewport, greaterThanOrEqualTo(body * 0.7));
    // The list is in the side panel, not above the timeline.
    final panel = byKey('day-side-panel');
    expect(
      find.descendant(of: panel, matching: byKey('day-needs-attention')),
      findsOneWidget,
    );
    expect(
      tester.getRect(byKey('day-needs-attention')).right,
      lessThanOrEqualTo(tester.getRect(panel).right),
    );
    await finish(tester, container);
  });

  testWidgets('medium strip: collapsed by default, expanded stays under 35%', (
    tester,
  ) async {
    final container = await pumpResponsiveDay(
      tester,
      size: const Size(800, 1280),
    );
    final items = container.read(dayAttentionProvider).requireValue;
    expect(items, hasLength(14));
    final strip = byKey('day-needs-attention');
    final body = tester.getSize(find.byType(DayViewScreen)).height;

    // More than three items: header only until expanded.
    expect(find.text('Needs attention · 14'), findsOneWidget);
    expect(
      find.byKey(ValueKey('day-attention-${items.first.task.id}')),
      findsNothing,
    );
    expect(tester.getSize(strip).height, lessThan(body * 0.1));

    await tester.tap(byKey('day-attention-toggle'));
    await settle(tester);
    expect(container.read(dayAttentionExpandedProvider), isTrue);
    expect(
      find.byKey(ValueKey('day-attention-${items.first.task.id}')),
      findsOneWidget,
    );
    expect(tester.getSize(strip).height, lessThanOrEqualTo(body * 0.35));
    expect(tester.getSize(strip).height, greaterThan(body * 0.2));

    // The rows scroll inside the strip.
    final scrollable = find.descendant(
      of: strip,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable.first).position;
    expect(position.maxScrollExtent, greaterThan(0));
    final before = position.pixels;
    // Mouse wheel: the existing InboxTaskTile rows are immediate Draggables,
    // so a touch drag that starts on a row begins a drag instead of a scroll
    // (the Inbox rework, Phase 4, moves dragging to a handle).
    final wheel = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(wheel.hover(tester.getCenter(strip)));
    await tester.sendEventToBinding(wheel.scroll(const Offset(0, 150)));
    await settle(tester);
    expect(position.pixels, greaterThan(before));
    expect(tester.takeException(), isNull);
    await finish(tester, container);
  });

  testWidgets('compact banner counts and opens a sheet with every row', (
    tester,
  ) async {
    final container = await pumpResponsiveDay(
      tester,
      size: const Size(360, 800),
    );
    final items = container.read(dayAttentionProvider).requireValue;
    expect(items, hasLength(14));

    final banner = byKey('day-attention-banner');
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: banner, matching: find.textContaining('13 overdue')),
      findsOneWidget,
    );
    expect(find.textContaining('1 due today'), findsOneWidget);
    expect(tester.getSize(banner).height, greaterThanOrEqualTo(48));

    await tester.tap(banner);
    await settle(tester);
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    final list = byKey('day-attention-sheet-list');
    expect(list, findsOneWidget);

    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    // Scroll down through the rows in the order the sheet shows them.
    final shown = [
      for (final group in groupAttention(items, responsiveNow)) ...group.items,
    ];
    expect(shown, hasLength(items.length));
    for (final item in shown) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('day-attention-${item.task.id}')),
        120,
        scrollable: scrollable,
      );
    }
    expect(
      find.byKey(ValueKey('day-attention-${shown.last.task.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await finish(tester, container);
  });

  testWidgets('compact: the New task FAB opens quick create', (tester) async {
    final container = await pumpResponsiveDay(
      tester,
      size: const Size(360, 800),
    );
    await tester.tap(byKey('day-new-task-fab'));
    await settle(tester);
    expect(find.text('Create scheduled task'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester, container);
  });
}
