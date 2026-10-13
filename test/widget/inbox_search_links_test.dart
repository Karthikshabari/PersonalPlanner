// Search results for Inbox ideas open the Inbox with the idea expanded (in
// Dropped for a closed one, Done for a finished one); results for sessions are ordinary tasks and open on
// Day. Fixed clock: Monday 2026-10-12 12:00 in the planner zone.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/utils/planner_time_zone.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';

import '../helpers/inbox_fixtures.dart';
import '../helpers/inbox_screen_harness.dart';
import '../helpers/test_container.dart';

Future<ProviderContainer> searchFor(
  WidgetTester tester,
  String query, {
  required Future<void> Function(InboxHarness h) seed,
}) async {
  final now = PlannerTimeZone.calendarDate(2026, 10, 12, hour: 12);
  final container = await buildTestContainer(
    tester,
    inboxNowFactory: () => now,
  );
  await runDb(
    tester,
    () => seed(InboxHarness(container.read(appDatabaseProvider))),
  );
  appRouter.go('/search');
  await pumpApp(tester, container, surface: const Size(1400, 1800));
  await tester.enterText(find.byKey(const ValueKey('search-input')), query);
  await tester.pump(const Duration(milliseconds: 350));
  await settle(tester);
  return container;
}

String get _path => appRouter.routerDelegate.currentConfiguration.uri.path;

void main() {
  testWidgets('an open idea opens the Inbox with its trail expanded', (
    tester,
  ) async {
    late Task idea;
    late Task other;
    final container = await searchFor(
      tester,
      'zanzibar',
      seed: (h) async {
        other = await h.idea('Something else');
        idea = await h.idea('Plan the zanzibar trip');
      },
    );
    expect(find.byKey(ValueKey('search-result-${idea.id}')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('search-result-${idea.id}')));
    await settle(tester);

    expect(_path, '/inbox');
    expect(container.read(inboxFocusItemProvider), isNull);
    expect(container.read(inboxExpandedItemProvider), idea.id);
    expect(trailOf(idea.id), findsOneWidget);
    expect(trailOf(other.id), findsNothing);
    expect(find.text('Open (2)'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('a closed idea opens the Inbox in Dropped', (tester) async {
    late Task idea;
    final container = await searchFor(
      tester,
      'zanzibar',
      seed: (h) async {
        await h.idea('Another open idea');
        idea = await h.idea('Plan the zanzibar trip');
        await h.inbox.closeItem(idea.id, 'Too far', h.now);
      },
    );
    await tester.tap(find.byKey(ValueKey('search-result-${idea.id}')));
    await settle(tester);

    expect(_path, '/inbox');
    expect(rowOf(idea.id), findsOneWidget);
    expect(trailOf(idea.id), findsOneWidget);
    expect(find.text('Closed Oct 12 · Too far'), findsOneWidget);
    expect(find.text('Another open idea'), findsNothing);
    expect(find.text('Dropped (1)'), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('a session result still opens Day', (tester) async {
    late Task idea;
    late Task session;
    final container = await searchFor(
      tester,
      'zanzibar',
      seed: (h) async {
        idea = await h.idea('Plan the zanzibar trip');
        session = await h.session(
          idea.id,
          start: h.at(2, 9),
          title: 'Zanzibar flights',
        );
      },
    );
    // Both the idea and its session match; the session opens on Day.
    expect(find.byKey(ValueKey('search-result-${idea.id}')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('search-result-${session.id}')));
    await settle(tester);

    expect(_path, '/day');
    expect(container.read(selectedTaskIdProvider), session.id);
    expect(container.read(taskEditorOpenProvider), isTrue);
    expect(container.read(inboxFocusItemProvider), isNull);
    await finish(tester, container);
  });
}
