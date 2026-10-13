// Daily Review adds " · From Inbox" to the caption of a session planned from an
// Inbox idea, and only to those. Caption text only: no other change.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';
import 'package:personal_planner/features/review/providers/review_providers.dart';

import '../helpers/test_container.dart';

void main() {
  testWidgets('only a session of an Inbox idea says "From Inbox"', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day - 1);
    final start = DateTime(day.year, day.month, day.day, 9);
    final idea = await runDb(
      tester,
      () =>
          container.read(inboxRepositoryProvider).addToInbox('Sort the garage'),
    );
    Task block(String title, DateTime at, {String? ideaId}) => Task(
      id: '',
      title: title,
      startTime: at,
      endTime: at.add(const Duration(hours: 1)),
      inboxItemId: ideaId,
      createdAt: now,
      updatedAt: now,
    );
    final tasks = container.read(taskRepositoryProvider);
    await runDb(tester, () async {
      await tasks.insertTask(block('Garage session', start, ideaId: idea.id));
      await tasks.insertTask(
        block('Plain block', start.add(const Duration(hours: 2))),
      );
    });
    container.read(selectedReviewDateProvider.notifier).state = day;
    appRouter.go('/review');
    await pumpApp(tester, container, surface: const Size(1400, 1000));

    expect(find.text('1h planned · From Inbox'), findsOneWidget);
    expect(find.text('1h planned'), findsOneWidget);
    expect(find.text('Garage session'), findsOneWidget);
    expect(find.text('Plain block'), findsOneWidget);
    await finish(tester, container);
  });
}
