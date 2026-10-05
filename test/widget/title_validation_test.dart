import 'package:drift/drift.dart' show InvalidDataException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/core/theme/app_theme.dart';
import 'package:personal_planner/features/timeline/domain/scheduled_task_draft.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';
import 'package:personal_planner/features/timeline/presentation/widgets/task_quick_create.dart';

import '../helpers/test_container.dart';

/// UAT F-002: over-long titles get a friendly, blocking message (never a raw
/// Drift exception) in both the quick-create dialog and the full editor.
void main() {
  setUp(() => appRouter.go('/day'));

  const tooLong = 'Title must be 500 characters or fewer';
  final overLimit = 'F002-${'0123456789' * 59}END!'; // 600 chars

  Future<List<Task>> tasksToday(
    WidgetTester tester,
    ProviderContainer container,
  ) => runDb(
    tester,
    () => container
        .read(taskRepositoryProvider)
        .watchTasksForDay(DateTime.now())
        .first,
  );

  Future<void> openQuickCreate(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    await doubleTap(tester, find.byKey(const ValueKey('timeline-gestures')));
    await settle(tester);
    expect(find.text('Create scheduled task'), findsOneWidget);
  }

  /// The quick-create Title field's own error line (InputDecoration
  /// errorText), as opposed to the schedule or form-level error lines.
  Finder titleFieldError(String message) => find.descendant(
    of: find.byKey(const ValueKey('quick-create-input')),
    matching: find.text(message),
  );

  Future<void> pumpStandalone(
    WidgetTester tester, {
    DateTime? start,
    DateTime? end,
    Future<bool> Function(ScheduledTaskDraft draft)? onSubmit,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: TaskQuickCreate(
          taskId: 'draft-1',
          initialStart: start,
          initialEnd: end,
          onSubmit: onSubmit ?? (_) async => true,
          onCancel: () {},
        ),
      ),
    ),
  );

  Future<void> submitQuickCreate(WidgetTester tester, String title) async {
    await tester.enterText(
      find.byKey(const ValueKey('quick-create-input')),
      title,
    );
    await tester.tap(find.byKey(const ValueKey('quick-create-submit')));
    await settle(tester);
  }

  testWidgets('quick create blocks a 600-char title with a friendly message', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await openQuickCreate(tester, container);

    await submitQuickCreate(tester, overLimit);

    expect(find.text('Create scheduled task'), findsOneWidget);
    // F-003: shown once, on the Title field itself.
    expect(find.text(tooLong), findsOneWidget);
    expect(titleFieldError(tooLong), findsOneWidget);
    expect(find.textContaining('InvalidDataException'), findsNothing);
    expect(find.textContaining('TasksCompanion'), findsNothing);
    expect(await tasksToday(tester, container), isEmpty);
    await teardownApp(tester, container);
  });

  testWidgets('quick create saves a title of exactly 500 characters', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await openQuickCreate(tester, container);

    await submitQuickCreate(tester, 'y' * 500);

    expect(find.text('Create scheduled task'), findsNothing);
    final tasks = await tasksToday(tester, container);
    expect(tasks.single.title, 'y' * 500);
    await teardownApp(tester, container);
  });

  testWidgets('quick create never shows a raw database exception', (
    tester,
  ) async {
    await pumpStandalone(
      tester,
      start: DateTime.utc(2026, 10, 8, 9),
      end: DateTime.utc(2026, 10, 8, 10),
      onSubmit: (_) async => throw InvalidDataException(
        'Sorry, TasksCompanion(id: Value(draft-1), title: Value(x)) '
        'cannot be used for that because: title too long',
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('quick-create-input')),
      'Valid title',
    );
    await tester.tap(find.byKey(const ValueKey('quick-create-submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('TasksCompanion'), findsNothing);
    expect(
      find.text(
        'Something went wrong. Your local data was not discarded; please retry.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('quick-create-error')), findsOneWidget);
  });

  // UAT F-003: every validation message is rendered exactly once.
  testWidgets('blank title error is shown once, on the Title field', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await openQuickCreate(tester, container);

    await submitQuickCreate(tester, '     ');

    expect(find.text('Title must not be blank'), findsOneWidget);
    expect(titleFieldError('Title must not be blank'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-create-error')), findsNothing);
    expect(await tasksToday(tester, container), isEmpty);
    await teardownApp(tester, container);
  });

  testWidgets('schedule errors are shown once, under the schedule fields', (
    tester,
  ) async {
    var submitted = false;
    Future<void> submitWith(DateTime? start, DateTime? end) async {
      await pumpStandalone(
        tester,
        start: start,
        end: end,
        onSubmit: (_) async => submitted = true,
      );
      await tester.enterText(
        find.byKey(const ValueKey('quick-create-input')),
        'Valid title',
      );
      await tester.tap(find.byKey(const ValueKey('quick-create-submit')));
      await tester.pumpAndSettle();
    }

    final nine = DateTime.utc(2026, 10, 8, 9);
    await submitWith(nine, nine.subtract(const Duration(hours: 1)));
    expect(find.text('End must be later than start'), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-fields-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-create-error')), findsNothing);

    // Unmount so the next form gets fresh State (initial times are read once).
    await tester.pumpWidget(const SizedBox.shrink());
    await submitWith(null, nine);
    expect(find.text('Start date and time are required'), findsOneWidget);
    expect(find.byKey(const ValueKey('quick-create-error')), findsNothing);
    expect(submitted, isFalse);
  });

  testWidgets('blank title and a bad interval are each shown once', (
    tester,
  ) async {
    final nine = DateTime.utc(2026, 10, 8, 9);
    await pumpStandalone(
      tester,
      start: nine,
      end: nine.subtract(const Duration(minutes: 30)),
    );
    await tester.tap(find.byKey(const ValueKey('quick-create-submit')));
    await tester.pumpAndSettle();

    expect(titleFieldError('Title must not be blank'), findsOneWidget);
    expect(find.text('Title must not be blank'), findsOneWidget);
    expect(find.text('End must be later than start'), findsOneWidget);
  });

  testWidgets('editor Save blocks a 600-char title and writes nothing', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final start = DateTime(2027, 3, 15, 9);
    final task = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Original',
              startTime: start,
              endTime: start.add(const Duration(hours: 1)),
              estimatedDurationMin: 60,
              createdAt: start,
              updatedAt: start,
            ),
          ),
    );
    container.read(selectedDateProvider.notifier).state = DateTime(2027, 3, 15);
    await pumpApp(tester, container, surface: const Size(1400, 1000));
    container.read(selectedTaskIdProvider.notifier).state = task.id;
    container.read(taskEditorOpenProvider.notifier).state = true;
    await settle(tester);
    expect(find.text('Edit Task'), findsOneWidget);

    final title = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Title',
    );
    await tester.enterText(title, overLimit);
    await tester.tap(find.byKey(const ValueKey('save-task-button')));
    await settle(tester);

    expect(find.text(tooLong), findsWidgets); // inline + editor snackbar
    expect(find.textContaining('Something went wrong'), findsNothing);
    final stored = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskWithRevision(task.id),
    );
    expect(stored!.$1.title, 'Original');
    await finish(tester, container);
  });
}
