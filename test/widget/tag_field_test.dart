import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_planner/core/models/recurring_rule.dart';
import 'package:personal_planner/core/models/task.dart';
import 'package:personal_planner/core/providers/database_provider.dart';
import 'package:personal_planner/core/router/app_router.dart';
import 'package:personal_planner/features/experiments/providers/experiment_providers.dart';
import 'package:personal_planner/features/recurring/providers/recurring_providers.dart';
import 'package:personal_planner/features/task_editor/presentation/widgets/tag_field.dart';
import 'package:personal_planner/features/task_editor/providers/tag_providers.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_date_provider.dart';
import 'package:personal_planner/features/timeline/presentation/providers/selected_task_provider.dart';

import '../helpers/test_container.dart';

void main() {
  const desktop = Size(1400, 900);
  final viewDay = DateTime(2027, 3, 15);

  const fieldKey = ValueKey('task-tag-field');
  const saveKey = ValueKey('save-task-button');

  Future<Task> insertBlock(
    WidgetTester tester,
    ProviderContainer container, {
    String title = 'Block',
    String? tagId,
    bool inbox = false,
  }) => runDb(
    tester,
    () => container
        .read(taskRepositoryProvider)
        .insertTask(
          Task(
            id: '',
            title: title,
            isInbox: inbox,
            inboxContentVersion: inbox ? 1 : 0,
            description: inbox ? title : null,
            startTime: inbox ? null : viewDay.add(const Duration(hours: 9)),
            endTime: inbox ? null : viewDay.add(const Duration(hours: 10)),
            tagId: tagId,
            createdAt: viewDay,
            updatedAt: viewDay,
          ),
        ),
  );

  Future<void> openEditor(
    WidgetTester tester,
    ProviderContainer container,
    Task task,
  ) async {
    container.read(selectedDateProvider.notifier).state = viewDay;
    container.read(selectedTaskIdProvider.notifier).state = task.id;
    container.read(taskEditorOpenProvider.notifier).state = true;
    appRouter.go('/day');
    await pumpApp(tester, container, surface: desktop);
  }

  Future<void> scrollToField(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(fieldKey));
    await tester.pump();
  }

  Future<void> typeTag(WidgetTester tester, String text) async {
    await scrollToField(tester);
    await tester.tap(find.byKey(fieldKey));
    await tester.pump();
    await tester.enterText(find.byKey(fieldKey), text);
    await tester.pump();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.byKey(saveKey));
    await settle(tester);
  }

  Future<List<String>> tagNames(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    final tags = await runDb(
      tester,
      () => container.read(appDatabaseProvider).tagDao.getActiveTags(),
    );
    return [for (final t in tags) t.name];
  }

  Future<Task> reload(
    WidgetTester tester,
    ProviderContainer container,
    Task task,
  ) async {
    final loaded = await runDb(
      tester,
      () => container.read(taskRepositoryProvider).getTaskById(task.id),
    );
    return loaded!;
  }

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.linux);

  testWidgets('the Tag field sits directly below Category', (tester) async {
    final container = await buildTestContainer(tester);
    final task = await insertBlock(tester, container);
    await openEditor(tester, container, task);

    expect(find.byKey(fieldKey), findsOneWidget);
    expect(find.text('Tag'), findsOneWidget);
    final category = tester.getTopLeft(find.text('Category').first);
    final tag = tester.getTopLeft(find.byKey(fieldKey));
    final status = tester.getTopLeft(find.text('Status').first);
    expect(tag.dy, greaterThan(category.dy));
    expect(tag.dy, lessThan(status.dy));
    expect(tester.takeException(), isNull);
    await finish(tester, container);
  });

  testWidgets('pick an existing tag and save', (tester) async {
    final container = await buildTestContainer(tester);
    final learn = await runDb(
      tester,
      () => container.read(tagRepositoryProvider).getOrCreateByName('Learn C'),
    );
    final task = await insertBlock(tester, container);
    await openEditor(tester, container, task);

    await typeTag(tester, 'lea');
    expect(find.byKey(ValueKey('tag-option-${learn.id}')), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('tag-option-${learn.id}')));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byKey(fieldKey)).controller!.text,
      'Learn C',
    );
    await tapSave(tester);

    expect((await reload(tester, container, task)).tagId, learn.id);
    expect(await tagNames(tester, container), ['Learn C']);
    await finish(tester, container);
  });

  testWidgets('type a new name, choose Create, save: tag created and used', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await insertBlock(tester, container);
    await openEditor(tester, container, task);

    await typeTag(tester, 'Learn C');
    expect(find.text('Create tag "Learn C"'), findsOneWidget);
    expect(find.text('A new tag is created when you save.'), findsOneWidget);
    // Nothing is created before Save (ED16).
    expect(await tagNames(tester, container), isEmpty);
    await tester.tap(find.byKey(const ValueKey('tag-option-create')));
    await tester.pump();
    expect(await tagNames(tester, container), isEmpty);
    await tapSave(tester);

    final saved = await reload(tester, container, task);
    final tags = await runDb(
      tester,
      () => container.read(appDatabaseProvider).tagDao.getActiveTags(),
    );
    expect(tags.map((t) => t.name), ['Learn C']);
    expect(saved.tagId, tags.single.id);
    // After saving, the field shows the stored name and no helper text.
    expect(find.text('A new tag is created when you save.'), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(fieldKey)).controller!.text,
      'Learn C',
    );
    await finish(tester, container);
  });

  testWidgets('a name that differs only by case selects the existing tag', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final learn = await runDb(
      tester,
      () => container.read(tagRepositoryProvider).getOrCreateByName('Learn C'),
    );
    final task = await insertBlock(tester, container);
    await openEditor(tester, container, task);

    await typeTag(tester, 'learn c');
    expect(find.byKey(const ValueKey('tag-option-create')), findsNothing);
    expect(find.text('A new tag is created when you save.'), findsNothing);
    await tapSave(tester);

    expect((await reload(tester, container, task)).tagId, learn.id);
    expect(await tagNames(tester, container), ['Learn C']);
    await finish(tester, container);
  });

  testWidgets('two inner spaces and outer spaces still find the tag', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final learn = await runDb(
      tester,
      () => container.read(tagRepositoryProvider).getOrCreateByName('Learn C'),
    );
    final task = await insertBlock(tester, container);
    await openEditor(tester, container, task);

    await typeTag(tester, '  Learn  C  ');
    expect(find.byKey(const ValueKey('tag-option-create')), findsNothing);
    await tapSave(tester);

    expect((await reload(tester, container, task)).tagId, learn.id);
    expect(await tagNames(tester, container), ['Learn C']);
    await finish(tester, container);
  });

  testWidgets('a typed value is saved without leaving the field', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final task = await insertBlock(tester, container);
    await openEditor(tester, container, task);

    await typeTag(tester, 'Sketching');
    // The field still has focus and no option was chosen.
    expect(
      tester.widget<TextField>(find.byKey(fieldKey)).focusNode!.hasFocus,
      isTrue,
    );
    await tapSave(tester);

    final saved = await reload(tester, container, task);
    expect(saved.tagId, isNotNull);
    expect(await tagNames(tester, container), ['Sketching']);
    await finish(tester, container);
  });

  testWidgets('clear and save removes the tag but keeps the tag row', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final learn = await runDb(
      tester,
      () => container.read(tagRepositoryProvider).getOrCreateByName('Learn C'),
    );
    final task = await insertBlock(tester, container, tagId: learn.id);
    await openEditor(tester, container, task);

    await scrollToField(tester);
    expect(
      tester.widget<TextField>(find.byKey(fieldKey)).controller!.text,
      'Learn C',
    );
    await tester.tap(find.byKey(const ValueKey('task-tag-clear')));
    await tester.pump();
    expect(find.byKey(const ValueKey('task-tag-clear')), findsNothing);
    await tapSave(tester);

    expect((await reload(tester, container, task)).tagId, isNull);
    expect(await tagNames(tester, container), ['Learn C']);
    await finish(tester, container);
  });

  testWidgets('emptying the text clears the tag too', (tester) async {
    final container = await buildTestContainer(tester);
    final learn = await runDb(
      tester,
      () => container.read(tagRepositoryProvider).getOrCreateByName('Learn C'),
    );
    final task = await insertBlock(tester, container, tagId: learn.id);
    await openEditor(tester, container, task);

    await typeTag(tester, '');
    await tapSave(tester);
    expect((await reload(tester, container, task)).tagId, isNull);
    await finish(tester, container);
  });

  testWidgets('choosing another tag replaces the current one', (tester) async {
    final container = await buildTestContainer(tester);
    final repo = container.read(tagRepositoryProvider);
    final a = await runDb(tester, () => repo.getOrCreateByName('Alpha'));
    final b = await runDb(tester, () => repo.getOrCreateByName('Beta'));
    final task = await insertBlock(tester, container, tagId: a.id);
    await openEditor(tester, container, task);

    await typeTag(tester, 'Bet');
    await tester.tap(find.byKey(ValueKey('tag-option-${b.id}')));
    await tester.pump();
    await tapSave(tester);

    expect((await reload(tester, container, task)).tagId, b.id);
    await finish(tester, container);
  });

  testWidgets('a tag that belongs to an experiment shows the marker', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    await runDb(
      tester,
      () => container
          .read(experimentRepositoryProvider)
          .createExperiment(
            name: 'Learn C',
            startDate: '2027-03-01',
            endDate: '2027-03-30',
            weekdayTargetMin: 60,
            weekendTargetMin: 90,
            checkInEveryDays: 7,
          ),
    );
    final plain = await runDb(
      tester,
      () => container.read(tagRepositoryProvider).getOrCreateByName('Plain'),
    );
    final task = await insertBlock(tester, container);
    await openEditor(tester, container, task);

    await scrollToField(tester);
    await tester.tap(find.byKey(fieldKey));
    await settle(tester);
    expect(find.text('Experiment'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('tag-option-${plain.id}')),
        matching: find.text('Experiment'),
      ),
      findsNothing,
    );
    expect(find.byIcon(Icons.science_outlined), findsOneWidget);
    await finish(tester, container);
  });

  testWidgets('the field is hidden for an Inbox capture', (tester) async {
    final container = await buildTestContainer(tester);
    final item = await insertBlock(tester, container, inbox: true);
    await openEditor(tester, container, item);

    expect(find.byKey(saveKey), findsOneWidget);
    expect(find.byKey(fieldKey), findsNothing);
    await finish(tester, container);
  });

  testWidgets('saving a block without touching the field changes no tag', (
    tester,
  ) async {
    final container = await buildTestContainer(tester);
    final learn = await runDb(
      tester,
      () => container.read(tagRepositoryProvider).getOrCreateByName('Learn C'),
    );
    final tagged = await insertBlock(tester, container, tagId: learn.id);
    await openEditor(tester, container, tagged);

    Future<int> revisionOf() async => (await runDb(
      tester,
      () =>
          container.read(taskRepositoryProvider).getTaskWithRevision(tagged.id),
    ))!.$2;
    final revisionBefore = await revisionOf();

    // Untouched editor: Save has nothing to do.
    await tapSave(tester);
    expect(find.text('No changes to save'), findsOneWidget);
    expect((await reload(tester, container, tagged)).tagId, learn.id);
    expect(await revisionOf(), revisionBefore);

    // Another field changes: the tag is neither created nor changed.
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Renamed notes',
    );
    await tester.pump();
    await tapSave(tester);
    final saved = await reload(tester, container, tagged);
    expect(saved.description, 'Renamed notes');
    expect(saved.tagId, learn.id);
    expect(await tagNames(tester, container), ['Learn C']);
    await finish(tester, container);
  });

  testWidgets('saving an untagged block without touching the field adds no '
      'tag', (tester) async {
    final container = await buildTestContainer(tester);
    final task = await insertBlock(tester, container);
    await openEditor(tester, container, task);

    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Other',
    );
    await tester.pump();
    await tapSave(tester);

    final saved = await reload(tester, container, task);
    expect(saved.description, 'Other');
    expect(saved.tagId, isNull);
    expect(await tagNames(tester, container), isEmpty);
    await finish(tester, container);
  });

  testWidgets('typing 101 UTF-16 code units keeps 100 and never splits an '
      'emoji', (tester) async {
    final container = await buildTestContainer(tester);
    final task = await insertBlock(tester, container);
    await openEditor(tester, container, task);

    await typeTag(tester, 'a' * 101);
    var text = tester.widget<TextField>(find.byKey(fieldKey)).controller!.text;
    expect(text.length, 100);

    // 99 letters and an emoji (two code units) would be 101 units: the emoji
    // is dropped whole instead of leaving half of it behind.
    await tester.enterText(find.byKey(fieldKey), '${'b' * 99}😀');
    await tester.pump();
    text = tester.widget<TextField>(find.byKey(fieldKey)).controller!.text;
    expect(text, 'b' * 99);

    // 50 emoji are exactly 100 code units and are all kept.
    await tester.enterText(find.byKey(fieldKey), '😀' * 51);
    await tester.pump();
    text = tester.widget<TextField>(find.byKey(fieldKey)).controller!.text;
    expect(text, '😀' * 50);
    expect(text.length, 100);
    await finish(tester, container);
  });

  testWidgets('a recurring block saves the tag on the edited block only '
      '(ED13)', (tester) async {
    final container = await buildTestContainer(tester);
    final now = DateTime.now();
    final hour = now.hour >= 21 ? 19 : now.hour;
    DateTime at(int dayOffset) =>
        DateTime(now.year, now.month, now.day + dayOffset, hour);
    final rules = container.read(recurringRepositoryProvider);
    final first = await runDb(
      tester,
      () => container
          .read(taskRepositoryProvider)
          .insertTask(
            Task(
              id: '',
              title: 'Series',
              startTime: at(0),
              endTime: at(0).add(const Duration(hours: 1)),
              estimatedDurationMin: 60,
              createdAt: now,
              updatedAt: now,
            ),
          ),
    );
    await runDb(
      tester,
      () => rules.createRule(
        RecurringRule(
          id: '',
          rrule: 'FREQ=DAILY',
          taskTitle: 'Series',
          durationMin: 60,
          startTimeOfDay: '${hour.toString().padLeft(2, '0')}:00',
          startDate: DateTime(now.year, now.month, now.day),
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
    final rule = (await runDb(tester, () => rules.getActiveRules())).single;
    final repo = container.read(taskRepositoryProvider);
    await runDb(
      tester,
      () => repo.updateTask(first.copyWith(recurringRuleId: rule.id)),
    );
    final later = await runDb(
      tester,
      () => repo.insertTask(
        Task(
          id: '',
          title: 'Series',
          startTime: at(1),
          endTime: at(1).add(const Duration(hours: 1)),
          estimatedDurationMin: 60,
          recurringRuleId: rule.id,
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );
    await pumpApp(tester, container, surface: desktop);
    await tester.tap(find.byKey(ValueKey('task-block-${first.id}')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('selected-task-edit-${first.id}')));
    await settle(tester);

    await typeTag(tester, 'Learn C');
    await tester.tap(find.byKey(const ValueKey('tag-option-create')));
    await tester.pump();
    await tapSave(tester);
    // The tag does not exist while the scope dialog is still open (ED16).
    expect(find.text('This and all future'), findsOneWidget);
    expect(await tagNames(tester, container), isEmpty);
    await tester.tap(find.byKey(const ValueKey('scope-all-future')));
    await settle(tester);

    final tags = await runDb(
      tester,
      () => container.read(appDatabaseProvider).tagDao.getActiveTags(),
    );
    expect(tags.map((t) => t.name), ['Learn C']);
    expect((await reload(tester, container, first)).tagId, tags.single.id);
    expect((await reload(tester, container, later)).tagId, isNull);
    final storedRule = await runDb(tester, () => rules.getRuleById(rule.id));
    expect(storedRule!.tags, isEmpty);
    await finish(tester, container);
  });

  test('the formatter keeps whole grapheme clusters', () {
    const formatter = Utf16LengthLimitingTextInputFormatter(5);
    TextEditingValue run(String text) => formatter.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: text),
    );
    expect(run('abcdef').text, 'abcde');
    expect(run('abcd😀').text, 'abcd');
    expect(run('abc😀').text, 'abc😀');
    // A family emoji is one cluster of 11 code units: dropped, not cut.
    expect(run('a👨‍👩‍👧').text, 'a');
    expect(run('abc').text, 'abc');
  });
}
