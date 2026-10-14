import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/inbox/providers/inbox_provider.dart';

import '../helpers/test_container.dart';

/// UAT-009: a dialog opened from a Day "Needs attention" row must still save
/// after the minute clock ticks, even when the tick removes the row (a legacy
/// capture due "today" leaves the panel at midnight) and so unmounts the
/// widget that opened the dialog.
void main() {
  late StreamController<DateTime> clock;
  final firstMinute = DateTime.utc(2026, 9, 16, 6, 30);

  Future<(ProviderContainer, String)> pumpDay(WidgetTester tester) async {
    clock = StreamController<DateTime>.broadcast();
    final container = await buildTestContainer(
      tester,
      minuteClockFactory: () async* {
        yield firstMinute;
        yield* clock.stream;
      },
    );
    final capture = await runDb(
      tester,
      () => container
          .read(inboxRepositoryProvider)
          .addToInbox('Tick capture', dueDate: '2026-09-16'),
    );
    appRouter.go('/day');
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    await settle(tester);
    return (container, capture.id);
  }

  /// A tick into the next day: the capture is no longer due today.
  Future<void> tickPastMidnight(WidgetTester tester) async {
    clock.add(DateTime.utc(2026, 9, 17, 6, 30));
    await settle(tester);
  }

  void expectNoRawError(WidgetTester tester) {
    expect(find.textContaining('"ref"'), findsNothing);
    expect(find.textContaining('unmounted'), findsNothing);
  }

  testWidgets('Edit saves after the minute clock ticks with the dialog open', (
    tester,
  ) async {
    final (container, id) = await pumpDay(tester);
    expect(find.byKey(ValueKey('day-attention-$id')), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('day-attention-menu-$id')));
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    expect(find.text('Edit Inbox capture'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('inbox-capture-content')),
      'Tick capture, edited',
    );

    await tickPastMidnight(tester);
    expect(find.byKey(ValueKey('day-attention-$id')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('inbox-capture-submit')));
    await settle(tester);

    expectNoRawError(tester);
    expect(find.byKey(const ValueKey('inbox-capture-error')), findsNothing);
    expect(find.text('Edit Inbox capture'), findsNothing);
    final saved = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(id),
    );
    expect(saved?.description, 'Tick capture, edited');
    await finish(tester, container);
    await clock.close();
  });

  testWidgets(
    'Schedule saves after the minute clock ticks with the form open',
    (tester) async {
      final (container, id) = await pumpDay(tester);

      await tester.tap(find.byKey(ValueKey('day-attention-menu-$id')));
      await settle(tester);
      await tester.tap(find.text('Schedule'));
      await settle(tester);
      // The scheduling form opens directly (it has the date and time fields).
      expect(find.text('Schedule Inbox capture'), findsOneWidget);

      await tickPastMidnight(tester);
      expect(find.byKey(ValueKey('day-attention-$id')), findsNothing);
      expect(find.text('Schedule Inbox capture'), findsOneWidget);

      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('Save')),
      );
      await settle(tester);

      expectNoRawError(tester);
      expect(find.text('Schedule Inbox capture'), findsNothing);
      final sessions = await runDb(
        tester,
        () => container
            .read(appDatabaseProvider)
            .customSelect(
              'SELECT id FROM tasks WHERE inbox_item_id = ? AND deleted_at IS NULL',
              variables: [Variable.withString(id)],
            )
            .get(),
      );
      expect(sessions, hasLength(1));
      await finish(tester, container);
      await clock.close();
    },
  );
}
