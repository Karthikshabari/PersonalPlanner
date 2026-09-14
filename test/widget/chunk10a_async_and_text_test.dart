import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/widgets/async_value_view.dart';
import 'package:personal_planner/core/widgets/error_panel.dart';
import 'package:personal_planner/features/recurring/providers/recurring_providers.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/screens/day_view_screen.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';

import '../helpers/test_container.dart';

final _asyncItemsProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return Future.value(const <String>[]);
});

class _AsyncItemsProbe extends ConsumerWidget {
  const _AsyncItemsProbe();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<List<String>>(
      value: ref.watch(_asyncItemsProvider),
      builder: (items) =>
          items.isEmpty ? const Text('EMPTY RESULT') : Text(items.join(',')),
      onRetry: () => ref.invalidate(_asyncItemsProvider),
    );
  }
}

class _TextContractProbe extends StatefulWidget {
  const _TextContractProbe();

  @override
  State<_TextContractProbe> createState() => _TextContractProbeState();
}

class _TextContractProbeState extends State<_TextContractProbe> {
  final title = TextEditingController();
  final description = TextEditingController();
  final review = TextEditingController();
  final tag = TextEditingController();
  var titleSubmits = 0;
  var tagSubmits = 0;

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    review.dispose();
    tag.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    child: ListView(
      children: [
        // Inventory: task title, inbox/quick-create/tag/subtask/template
        // names all use the single-line submit contract; task description,
        // notes and review reflection/list entries use multiline editing.
        TextField(
          key: const ValueKey('contract-single-line'),
          controller: title,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => setState(() => titleSubmits++),
        ),
        TextField(
          key: const ValueKey('contract-multiline-description'),
          controller: description,
          minLines: 2,
          maxLines: null,
          textInputAction: TextInputAction.newline,
        ),
        TextField(
          key: const ValueKey('contract-multiline-review'),
          controller: review,
          minLines: 2,
          maxLines: 4,
          textInputAction: TextInputAction.newline,
        ),
        TextField(
          key: const ValueKey('contract-submit-tag'),
          controller: tag,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => setState(() => tagSubmits++),
        ),
        Text('title submits: $titleSubmits'),
        Text('tag submits: $tagSubmits'),
      ],
    ),
  );
}

void main() {
  testWidgets('provider overrides keep loading, empty, and error distinct', (
    tester,
  ) async {
    Future<void> pumpState(AsyncValue<List<String>> state) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProviderScope(
            overrides: [_asyncItemsProvider.overrideWithValue(state)],
            child: const _AsyncItemsProbe(),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpState(const AsyncValue.loading());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('EMPTY RESULT'), findsNothing);

    await pumpState(const AsyncValue.data(<String>[]));
    expect(find.text('EMPTY RESULT'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ErrorPanel), findsNothing);

    await pumpState(
      AsyncValue.error(StateError('private storage detail'), StackTrace.empty),
    );
    expect(find.byType(ErrorPanel), findsOneWidget);
    expect(find.text('EMPTY RESULT'), findsNothing);
    expect(find.textContaining('private storage detail'), findsNothing);
  });

  testWidgets(
    'day recurrence materialization failure is visible and retryable',
    (tester) async {
      final container = await buildTestContainer(tester);
      final date = DateTime(2027, 3, 15);
      container.read(selectedDateProvider.notifier).state = date;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ProviderScope(
            overrides: [
              dayMaterializationProvider(date).overrideWithValue(
                AsyncValue.error(
                  StateError('materialization failed'),
                  StackTrace.empty,
                ),
              ),
            ],
            child: const MaterialApp(home: DayViewScreen()),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ErrorPanel), findsOneWidget);
      expect(find.textContaining('Something went wrong'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester, container);
    },
  );

  testWidgets(
    'text fields preserve caret, selection, deletion, newline, Unicode, and IME contracts',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _TextContractProbe()));

      final title = find.byKey(const ValueKey('contract-single-line'));
      final description = find.byKey(
        const ValueKey('contract-multiline-description'),
      );
      final review = find.byKey(const ValueKey('contract-multiline-review'));
      final tag = find.byKey(const ValueKey('contract-submit-tag'));

      await tester.tap(title);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'A😀 café',
          selection: TextSelection.collapsed(offset: 8),
        ),
      );
      await tester.pump();
      final titleController = tester.widget<TextField>(title).controller!;
      expect(titleController.text, 'A😀 café');
      expect(
        titleController.selection,
        const TextSelection.collapsed(offset: 8),
      );

      // Replace a middle selection, then exercise both caret boundaries and a
      // rapid repeated-delete sequence through the platform text client.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'A😀 café',
          selection: TextSelection(baseOffset: 3, extentOffset: 5),
        ),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'A😀é',
          selection: TextSelection.collapsed(offset: 3),
        ),
      );
      await tester.pump();
      expect(titleController.text, 'A😀é');
      expect(
        titleController.selection,
        const TextSelection.collapsed(offset: 3),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(titleController.text, isNotEmpty);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'A',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pump();
      expect(titleController.text, 'A');

      await tester.tap(description);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'line one\nline two',
          selection: TextSelection.collapsed(offset: 17),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(description).controller!.text,
        'line one\nline two',
      );

      await tester.tap(review);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'か',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 1),
        ),
      );
      await tester.pump();
      expect(
        tester.widget<TextField>(review).controller!.value.composing,
        const TextRange(start: 0, end: 1),
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '完成 ✅',
          selection: TextSelection.collapsed(offset: 4),
          composing: TextRange.empty,
        ),
      );
      await tester.pump();
      expect(tester.widget<TextField>(review).controller!.text, '完成 ✅');

      await tester.tap(title);
      await tester.showKeyboard(title);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('title submits: 1'), findsOneWidget);
      await tester.tap(tag);
      await tester.showKeyboard(tag);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.text('tag submits: 1'), findsOneWidget);
    },
  );

  testWidgets(
    'focused editor input blocks global navigation and deletion shortcuts',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final container = await buildTestContainer(tester);
      final date = DateTime(2027, 3, 15);
      container.read(selectedDateProvider.notifier).state = date;
      final task = await runDb(
        tester,
        () => container
            .read(taskRepositoryProvider)
            .insertTask(
              Task(
                id: '',
                title: 'Shortcut target',
                startTime: date.add(const Duration(hours: 9)),
                endTime: date.add(const Duration(hours: 10)),
                createdAt: date,
                updatedAt: date,
              ),
            ),
      );
      await pumpApp(tester, container, surface: const Size(1400, 1000));
      await tester.tap(find.byKey(ValueKey('task-block-${task.id}')));
      await settle(tester);
      await tester.tap(find.byKey(ValueKey('selected-task-edit-${task.id}')));
      await settle(tester);
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Title',
      );
      await tester.tap(title);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await settle(tester);

      expect(find.text('Edit Task'), findsOneWidget);
      expect(find.text('Delete task?'), findsNothing);
      expect(appRouter.routerDelegate.currentConfiguration.uri.path, '/day');
      expect(
        (await runDb(
          tester,
          () => container.read(taskRepositoryProvider).getTaskById(task.id),
        ))!.deletedAt,
        isNull,
      );
      await finish(tester, container);
    },
  );
}
