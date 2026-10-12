// Day's drag path for an Inbox idea: the idea is not converted, a linked
// session is created through the conflict-aware command path.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/app.dart';
import 'package:personal_planner/core/models/inbox_item.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/day_view_controller.dart';
import 'package:personal_planner/features/timeline/presentation/providers/overlap_flags_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart'
    as date_provider;
import 'package:personal_planner/features/timeline/presentation/providers/undo_stack_provider.dart';

import '../helpers/test_container.dart';

final DateTime viewDay = DateTime(2027, 3, 15);

void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester) async {
    container = await buildTestContainer(tester);
    container.read(date_provider.selectedDateProvider.notifier).state = viewDay;
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
  }

  BuildContext appContext(WidgetTester tester) =>
      tester.element(find.byType(Scaffold).first);

  WidgetRef appRef(WidgetTester tester) =>
      tester.element(find.byType(PersonalPlannerApp)) as WidgetRef;

  Future<Task> taskById(WidgetTester tester, String id) => runDb(
    tester,
    () async => (await container.read(taskRepositoryProvider).getTaskById(id))!,
  );

  Future<List<Task>> sessionsOf(WidgetTester tester, String ideaId) =>
      runDb(tester, () async {
        final db = container.read(appDatabaseProvider);
        final rows = await (db.select(
          db.tasks,
        )..where((t) => t.inboxItemId.equals(ideaId))).get();
        return [
          for (final row in rows)
            (await container.read(taskRepositoryProvider).getTaskById(row.id))!,
        ];
      });

  Future<Task> idea(WidgetTester tester, String text) => runDb(
    tester,
    () => container.read(inboxRepositoryProvider).addToInbox(text),
  );

  testWidgets('dropping an idea creates a linked session and undo removes it', (
    tester,
  ) async {
    await pump(tester);
    final item = await idea(tester, 'Buy a lamp\nfor the desk');
    final start = DateTime(2027, 3, 15, 10);
    final committed = await runDb(
      tester,
      () => TimelineActions.scheduleInboxItem(
        appContext(tester),
        appRef(tester),
        InboxItem.explicit(item),
        start,
        start.add(const Duration(hours: 1)),
      ),
    );
    expect(committed, isTrue);
    await settle(tester);

    final sessions = await sessionsOf(tester, item.id);
    expect(sessions, hasLength(1));
    final session = sessions.single;
    expect(session.isInbox, isFalse);
    expect(session.inboxItemId, item.id);
    expect(session.title, 'Buy a lamp');
    expect(session.description, 'for the desk');
    expect((await taskById(tester, item.id)).isInbox, isTrue);

    await runDb(tester, () async {
      await container.read(undoStackProvider.notifier).undo();
    });
    expect((await taskById(tester, session.id)).deletedAt, isNotNull);
    expect((await taskById(tester, item.id)).isInbox, isTrue);
    await finish(tester, container);
  });

  testWidgets('overlap highlighting points at the new session, not the idea', (
    tester,
  ) async {
    await pump(tester);
    final item = await idea(tester, 'Overlapping errand');
    final existing = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Gym',
              startTime: DateTime(2027, 3, 15, 10),
              endTime: DateTime(2027, 3, 15, 11),
              createdAt: DateTime(2027, 3, 1),
              updatedAt: DateTime(2027, 3, 1),
            ),
          ),
    );

    final result = TimelineActions.scheduleInboxItem(
      appContext(tester),
      appRef(tester),
      InboxItem.explicit(item),
      DateTime(2027, 3, 15, 10, 30),
      DateTime(2027, 3, 15, 11, 30),
    );
    for (
      var i = 0;
      i < 40 && find.text('Resolve conflict').evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(find.text('Resolve conflict'), findsOneWidget);
    await tester.tap(find.text('Keep Overlap'));
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(await result, isTrue);

    final sessions = await sessionsOf(tester, item.id);
    expect(sessions, hasLength(1));
    final keep = container.read(keepOverlapIdsProvider);
    expect(keep, {sessions.single.id, existing.id});
    expect(keep, isNot(contains(item.id)));
    await finish(tester, container);
  });

  testWidgets('the scheduling form starts from the idea text', (tester) async {
    await pump(tester);
    final item = await idea(tester, 'First line title\nsecond line\nthird');
    final saved = TimelineActions.showInboxSchedulingForm(
      appContext(tester),
      appRef(tester),
      InboxItem.explicit(item),
      DateTime(2027, 3, 15, 14),
      DateTime(2027, 3, 15, 15),
    );
    await settle(tester);

    final title = tester.widget<TextField>(
      find.byKey(const ValueKey('quick-create-input')),
    );
    final description = tester.widget<TextField>(
      find.byKey(const ValueKey('quick-create-description')),
    );
    expect(title.controller!.text, 'First line title');
    expect(description.controller!.text, 'second line\nthird');

    await tester.tap(find.byKey(const ValueKey('quick-create-submit')));
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
    }
    expect(await saved, isTrue);
    final sessions = await sessionsOf(tester, item.id);
    expect(sessions, hasLength(1));
    expect(sessions.single.title, 'First line title');
    expect(sessions.single.description, 'second line\nthird');
    expect((await taskById(tester, item.id)).isInbox, isTrue);
    await finish(tester, container);
  });
}
