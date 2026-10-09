import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/daily_review.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/date_utils.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../helpers/test_container.dart';

void main() {
  DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Finder card(DateTime date) =>
      find.byKey(ValueKey('overview-day-${isoDateString(date)}'));

  final strip = find.byKey(const ValueKey('overview-strip'));
  final switcher = find.byKey(const ValueKey('review-mode-switcher'));

  Future<ProviderContainer> pumpAt(
    WidgetTester tester,
    String path, {
    Size surface = const Size(1400, 1000),
  }) async {
    final container = await buildTestContainer(tester);
    appRouter.go(path);
    await pumpApp(tester, container, surface: surface);
    return container;
  }

  // Disposing a reactive-stats provider mid-test starts an async onCancel in
  // the FakeAsync zone; give it real time to finish so database.close() in
  // finish() does not wait on it forever.
  Future<void> drainDisposedStreams(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await settle(tester);
  }

  Future<void> openOverview(WidgetTester tester) async {
    await tester.tap(
      find.descendant(of: switcher, matching: find.text('Overview')),
    );
    await settle(tester);
  }

  testWidgets('switcher shows three segments and opens Overview', (
    tester,
  ) async {
    final container = await pumpAt(tester, '/review');
    for (final label in ['Daily', 'Weekly', 'Overview']) {
      expect(
        find.descendant(of: switcher, matching: find.text(label)),
        findsOneWidget,
      );
    }

    await openOverview(tester);

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Overview')),
      findsOneWidget,
    );
    expect(strip, findsOneWidget);
    expect(
      find.descendant(of: strip, matching: find.text('Today')),
      findsOneWidget,
    );
    await finish(tester, container);
  });

  testWidgets(
    'selecting a card updates the detail line and Open this day switches to Daily',
    (tester) async {
      final container = await pumpAt(tester, '/review');
      final date = addDays(today(), -3);
      await runDb(
        tester,
        () => container
            .read(taskRepositoryProvider)
            .insertTask(
              Task(
                id: '',
                title: 'Old task',
                startTime: DateTime(date.year, date.month, date.day, 9),
                endTime: DateTime(date.year, date.month, date.day, 10),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ),
      );
      await runDb(
        tester,
        () => container
            .read(reviewRepositoryProvider)
            .saveDailyReview(
              DailyReview(
                id: '',
                date: date,
                mood: 2,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ),
      );
      await openOverview(tester);

      await tester.tap(card(date));
      await settle(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('overview-detail'))).data,
        contains('Great'),
      );

      await tester.tap(find.byKey(const ValueKey('overview-open-day')));
      await settle(tester);
      await drainDisposedStreams(tester);
      expect(find.text('Daily Review'), findsOneWidget);
      expect(
        isSameDay(container.read(selectedReviewDateProvider), date),
        isTrue,
      );
      await finish(tester, container);
    },
  );

  testWidgets('weekly sub-tab shows the week strip', (tester) async {
    final container = await pumpAt(tester, '/review/overview');

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('overview-subtabs')),
        matching: find.text('Weekly'),
      ),
    );
    await settle(tester);

    expect(
      find.text('Weekly overview comes in the weekly round.'),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('overview-week-strip')), findsOneWidget);
    expect(strip, findsNothing);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });

  testWidgets('arrows hidden below 520 dp', (tester) async {
    final container = await pumpAt(
      tester,
      '/review/overview',
      surface: const Size(390, 844),
    );
    expect(find.byKey(const ValueKey('overview-older')), findsNothing);
    expect(find.byKey(const ValueKey('overview-newer')), findsNothing);

    await pumpApp(tester, container, surface: const Size(1400, 1000));
    expect(find.byKey(const ValueKey('overview-older')), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-newer')), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('scrolling to the older end loads 30 more days', (tester) async {
    final container = await pumpAt(tester, '/review/overview');
    final target = card(addDays(today(), -40));
    expect(target, findsNothing);

    await tester.dragUntilVisible(target, strip, const Offset(300, 0));
    await settle(tester);

    expect(target, findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('saving a review updates the overview', (tester) async {
    final container = await pumpAt(tester, '/review');
    await tester.tap(find.byKey(const ValueKey('review-mood-4')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('review-save')));
    await settle(tester);

    final handle = tester.ensureSemantics();
    await openOverview(tester);

    expect(tester.getSemantics(card(today())).label, contains('Legendary'));
    handle.dispose();
    await finish(tester, container);
  });

  testWidgets('no future days', (tester) async {
    final container = await pumpAt(tester, '/review/overview');

    expect(card(today()), findsOneWidget);
    expect(card(addDays(today(), 1)), findsNothing);
    await finish(tester, container);
  });

  testWidgets('weekly review still opens and shows its content', (
    tester,
  ) async {
    final container = await pumpAt(tester, '/review/overview');

    await tester.tap(
      find.descendant(of: switcher, matching: find.text('Weekly')),
    );
    await settle(tester);

    expect(find.text('Weekly Review'), findsOneWidget);
    await drainDisposedStreams(tester);
    await finish(tester, container);
  });
}
